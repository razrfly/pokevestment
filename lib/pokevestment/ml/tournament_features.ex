defmodule Pokevestment.ML.TournamentFeatures do
  @moduledoc """
  Computes tournament-derived features for each card from deck/standing data.
  Returns %{card_id => %{feature_name => value}} for all cards with tournament presence.
  """

  alias Pokevestment.Repo

  @doc """
  Computes all 13 tournament aggregate features via a single CTE query.
  """
  def compute_all do
    %{columns: columns, rows: rows} = Repo.query!(query(), [], timeout: 60_000)
    rows_to_map(columns, rows)
  end

  defp query do
    """
    WITH card_tournament_data AS (
      SELECT
        dc.card_id,
        t.id AS tournament_id,
        t.tournament_date,
        t.player_count,
        ts.placing,
        ts.wins,
        ts.losses,
        ts.deck_archetype_id,
        dc.count
      FROM tournament_deck_cards dc
      JOIN tournament_standings ts ON ts.id = dc.tournament_standing_id
      JOIN tournaments t ON t.id = ts.tournament_id
    ),
    total_inclusions AS (
      SELECT COUNT(*)::float AS total FROM card_tournament_data
    ),
    total_inclusions_30d AS (
      SELECT COUNT(*)::float AS total FROM card_tournament_data
      WHERE tournament_date >= NOW() - INTERVAL '30 days'
    ),
    total_inclusions_90d AS (
      SELECT COUNT(*)::float AS total FROM card_tournament_data
      WHERE tournament_date >= NOW() - INTERVAL '90 days'
    )
    SELECT
      ctd.card_id,
      COUNT(DISTINCT ctd.tournament_id) AS tournament_appearances,
      COUNT(*) AS total_deck_inclusions,
      AVG(ctd.count)::float AS avg_copies_per_deck,
      COUNT(*)::float / NULLIF(ti.total, 0) AS meta_share_total,
      COUNT(*) FILTER (WHERE ctd.tournament_date >= NOW() - INTERVAL '30 days')::float
        / NULLIF(ti30.total, 0) AS meta_share_30d,
      COUNT(*) FILTER (WHERE ctd.tournament_date >= NOW() - INTERVAL '90 days')::float
        / NULLIF(ti90.total, 0) AS meta_share_90d,
      COUNT(DISTINCT ctd.deck_archetype_id) AS archetype_count,
      COUNT(*) FILTER (WHERE ctd.placing <= 8) AS top_8_appearances,
      COUNT(*) FILTER (WHERE ctd.placing <= 8)::float / NULLIF(COUNT(*), 0)::float AS top_8_rate,
      AVG(ctd.placing)::float AS avg_placing,
      AVG(
        CASE WHEN ctd.wins + ctd.losses > 0
          THEN ctd.wins::float / (ctd.wins + ctd.losses)::float
          ELSE NULL
        END
      ) AS avg_win_rate,
      SUM(1.0 / NULLIF(ctd.placing, 0) * LN(GREATEST(ctd.player_count, 1)))::float AS weighted_tournament_score
    FROM card_tournament_data ctd
    CROSS JOIN total_inclusions ti
    CROSS JOIN total_inclusions_30d ti30
    CROSS JOIN total_inclusions_90d ti90
    GROUP BY ctd.card_id, ti.total, ti30.total, ti90.total
    """
  end

  defp rows_to_map(columns, rows) do
    # First column is card_id, rest are feature values
    [_ | feature_names] = columns

    Map.new(rows, fn [card_id | values] ->
      features =
        Enum.zip(feature_names, values)
        |> Map.new(fn {name, val} -> {name, val || 0} end)

      meta_trend =
        (features["meta_share_30d"] || 0) - (features["meta_share_90d"] || 0)

      {card_id, Map.put(features, "meta_trend", meta_trend)}
    end)
  end
end
