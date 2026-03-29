defmodule Pokevestment.Ingestion.TournamentImport do
  @moduledoc """
  Tournament data import orchestrator — fetches tournaments and standings from
  the Limitless TCG API and inserts into the database.

  Idempotent: `on_conflict: :nothing` on external_id means re-running skips
  already-imported tournaments.
  """

  require Logger

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Api.Limitless
  alias Pokevestment.Ingestion.TournamentTransformer
  alias Pokevestment.Cards.{Set, Card}
  alias Pokevestment.Tournaments.{Tournament, TournamentStanding, TournamentDeckCard}

  @doc """
  Run tournament import.

  Options:
    - `:format` - filter by format (e.g. "STANDARD", "EXPANDED"). Default: "STANDARD"
    - `:since` - only import tournaments after this date (Date). Default: nil (all)

  Returns `{:ok, summary}` or `{:error, reason}`.

  Summary keys: `:tournaments`, `:standings`, `:deck_cards`, `:skipped`, `:failed`,
  `:unresolved_codes`, `:elapsed_ms`.
  """
  def run(opts \\ []) do
    start = System.monotonic_time(:millisecond)
    format_filter = Keyword.get(opts, :format, "STANDARD")
    since = Keyword.get(opts, :since)

    Logger.info("TournamentImport: starting (format=#{format_filter || "ALL"})...")

    # Preload lookup maps
    ptcgo_map = load_ptcgo_map()
    Logger.info("TournamentImport: loaded #{map_size(ptcgo_map)} PTCGO code mappings")

    card_ids = load_card_ids()
    Logger.info("TournamentImport: loaded #{MapSet.size(card_ids)} card IDs")

    existing_ids = load_existing_tournament_ids()
    Logger.info("TournamentImport: #{MapSet.size(existing_ids)} tournaments already imported")

    with {:ok, raw_tournaments} <- Limitless.list_tournaments("PTCG") do
      # Filter tournaments and compute actual skipped count
      filtered = filter_tournaments(raw_tournaments, format_filter, since)
      skipped = Enum.count(filtered, fn t -> MapSet.member?(existing_ids, t["id"]) end)

      tournaments_to_import =
        Enum.reject(filtered, fn t -> MapSet.member?(existing_ids, t["id"]) end)

      total = length(tournaments_to_import)

      Logger.info(
        "TournamentImport: #{total} new tournaments to import " <>
          "(#{length(raw_tournaments)} total, #{skipped} skipped)"
      )

      counter = :counters.new(1, [:atomics])
      unresolved_codes = :ets.new(:unresolved_codes, [:set, :public])

      # Limitless API rate limit: 50 requests per 5 minutes.
      # Each tournament needs 1 standings request, so we throttle to stay under.
      # max_concurrency: 2 + 7s sleep = ~17 req/min (well under 10 req/min per worker).
      {tournaments_count, standings_count, deck_cards_count, failed} =
        tournaments_to_import
        |> Task.async_stream(
          fn raw_tournament ->
            Process.sleep(7_000)

            result =
              import_tournament(raw_tournament, ptcgo_map, card_ids, unresolved_codes)

            :counters.add(counter, 1, 1)
            processed = :counters.get(counter, 1)

            if rem(processed, 10) == 0 do
              elapsed = System.monotonic_time(:millisecond) - start
              rate = if elapsed > 0, do: Float.round(processed / (elapsed / 1_000), 1), else: 0.0
              Logger.info("TournamentImport: #{processed}/#{total} (#{rate}/s)")
            end

            {raw_tournament["id"], result}
          end,
          max_concurrency: 2,
          timeout: :infinity,
          ordered: false
        )
        |> Enum.reduce({0, 0, 0, []}, fn
          {:ok, {_id, {:ok, counts}}}, {t, s, d, failed} ->
            {t + 1, s + counts.standings, d + counts.deck_cards, failed}

          {:ok, {id, {:error, reason}}}, {t, s, d, failed} ->
            Logger.warning("TournamentImport: failed tournament #{id}: #{inspect(reason)}")
            {t, s, d, [id | failed]}

          {:exit, reason}, {t, s, d, failed} ->
            Logger.warning("TournamentImport: task crashed: #{inspect(reason)}")
            {t, s, d, failed}
        end)

      unresolved = :ets.tab2list(unresolved_codes) |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      :ets.delete(unresolved_codes)

      elapsed_ms = System.monotonic_time(:millisecond) - start

      Logger.info(
        "TournamentImport: complete in #{format_duration(elapsed_ms)} — " <>
          "#{tournaments_count} tournaments, #{standings_count} standings, " <>
          "#{deck_cards_count} deck cards"
      )

      if unresolved != [] do
        Logger.warning(
          "TournamentImport: #{length(unresolved)} unresolved PTCGO codes: #{inspect(unresolved)}"
        )
      end

      if failed != [] do
        Logger.warning("TournamentImport: #{length(failed)} tournaments failed")
      end

      {:ok,
       %{
         tournaments: tournaments_count,
         standings: standings_count,
         deck_cards: deck_cards_count,
         skipped: skipped,
         failed: failed,
         unresolved_codes: unresolved,
         elapsed_ms: elapsed_ms
       }}
    end
  end

  # --- Private: Single tournament import ---

  defp import_tournament(raw_tournament, ptcgo_map, card_ids, unresolved_codes) do
    tournament_attrs = TournamentTransformer.tournament_attrs(raw_tournament)
    external_id = tournament_attrs.external_id

    case Limitless.get_standings(external_id) do
      {:ok, raw_standings} ->
        result =
          Repo.transaction(fn ->
            # Insert tournament
            {:ok, tournament} =
              %Tournament{}
              |> Tournament.changeset(tournament_attrs)
              |> Repo.insert(on_conflict: :nothing, conflict_target: [:external_id])

            # Skip if tournament already existed (concurrent import race)
            if is_nil(tournament.id) do
              Repo.rollback(:already_exists)
            end

            # Process each standing
            {standings_count, deck_cards_count} =
              Enum.reduce(raw_standings, {0, 0}, fn raw_standing, {s_count, d_count} ->
                standing_attrs =
                  TournamentTransformer.standing_attrs(raw_standing, tournament.id)

                case %TournamentStanding{tournament_id: tournament.id}
                     |> TournamentStanding.changeset(standing_attrs)
                     |> Repo.insert(
                       on_conflict: :nothing,
                       conflict_target: [:tournament_id, :player_handle]
                     ) do
                  {:ok, standing} ->
                    if is_nil(standing.id) do
                      # Standing already exists (concurrent race), skip deck cards
                      {s_count, d_count}
                    else
                      # Build deck card rows
                      decklist = raw_standing["decklist"]

                      deck_card_attrs_list =
                        TournamentTransformer.deck_card_attrs_from_decklist(
                          decklist,
                          standing.id
                        )

                      # Resolve card_ids and prepare for insert_all
                      now = DateTime.utc_now() |> DateTime.truncate(:second)

                      rows =
                        deck_card_attrs_list
                        |> Enum.map(fn attrs ->
                          card_id =
                            TournamentTransformer.resolve_card_id(
                              attrs.set_code,
                              attrs.card_number,
                              ptcgo_map,
                              card_ids
                            )

                          # Track unresolved codes
                          if is_nil(card_id) and not is_nil(attrs.set_code) do
                            :ets.insert(unresolved_codes, {attrs.set_code})
                          end

                          attrs
                          |> Map.put(:card_id, card_id)
                          |> Map.put(:inserted_at, now)
                        end)
                        |> Enum.filter(fn row -> is_integer(row.count) and row.count > 0 end)

                      {inserted, _} = Repo.insert_all(TournamentDeckCard, rows)
                      {s_count + 1, d_count + inserted}
                    end

                  {:error, _changeset} ->
                    # Standing validation failed, skip
                    {s_count, d_count}
                end
              end)

            %{standings: standings_count, deck_cards: deck_cards_count}
          end)

        case result do
          {:ok, counts} -> {:ok, counts}
          {:error, :already_exists} -> {:ok, %{standings: 0, deck_cards: 0}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning(
        "TournamentImport: exception importing #{raw_tournament["id"]}: #{Exception.message(e)}"
      )

      {:error, Exception.message(e)}
  end

  # --- Private: Filtering ---

  defp filter_tournaments(tournaments, nil, since) do
    filter_by_date(tournaments, since)
  end

  defp filter_tournaments(tournaments, format, since) do
    tournaments
    |> Enum.filter(fn t -> t["format"] == format end)
    |> filter_by_date(since)
  end

  defp filter_by_date(tournaments, nil), do: tournaments

  defp filter_by_date(tournaments, since) do
    Enum.filter(tournaments, fn t ->
      case t["date"] do
        nil ->
          false

        date_str ->
          case DateTime.from_iso8601(date_str) do
            {:ok, dt, _} -> Date.compare(DateTime.to_date(dt), since) != :lt
            _ -> false
          end
      end
    end)
  end

  # --- Private: Data loading ---

  defp load_ptcgo_map do
    from(s in Set, where: not is_nil(s.ptcgo_code), select: {s.ptcgo_code, s.id})
    |> Repo.all()
    |> Map.new()
  end

  defp load_card_ids do
    from(c in Card, select: c.id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp load_existing_tournament_ids do
    from(t in Tournament, select: t.external_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # --- Private: Formatting ---

  defp format_duration(ms) when ms < 1_000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"

  defp format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = Float.round(rem(ms, 60_000) / 1_000, 1)
    "#{minutes}m #{seconds}s"
  end
end
