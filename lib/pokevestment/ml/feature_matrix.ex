defmodule Pokevestment.ML.FeatureMatrix do
  @moduledoc """
  Assembles a complete feature matrix from all data sources into an Explorer DataFrame.
  Merges card attributes, set metadata, species data, tournament features, and price features.
  """

  import Ecto.Query
  require Explorer.DataFrame, as: DF

  alias Pokevestment.Repo
  alias Pokevestment.Cards.{Card, CardDexId, CardType, Set}
  alias Pokevestment.Pokemon.Species
  alias Pokevestment.ML.{TournamentFeatures, PriceFeatures}

  @tournament_defaults %{
    tournament_appearances: 0,
    total_deck_inclusions: 0,
    avg_copies_per_deck: 0.0,
    meta_share_total: 0.0,
    meta_share_30d: 0.0,
    meta_share_90d: 0.0,
    archetype_count: 0,
    top_8_appearances: 0,
    top_8_rate: 0.0,
    avg_placing: 0.0,
    avg_win_rate: 0.0,
    meta_trend: 0.0,
    weighted_tournament_score: 0.0
  }

  @doc """
  Assembles the full feature matrix from all data sources.
  Returns `{:ok, %Explorer.DataFrame{}}`.
  """
  def assemble do
    base_cards = base_query()
    species_map = species_query()
    dex_count_map = dex_count_query()
    type_count_map = type_count_query()
    illustrator_map = illustrator_stats()
    tournament_map = TournamentFeatures.compute_all()
    price_map = PriceFeatures.compute_all()

    rows =
      Enum.map(base_cards, fn card ->
        card_id = card.card_id

        card
        |> merge_species(species_map[card_id], dex_count_map[card_id])
        |> merge_type_count(type_count_map[card_id])
        |> merge_illustrator(card.illustrator, illustrator_map)
        |> merge_tournament(tournament_map[card_id])
        |> merge_price(price_map[card_id])
        |> compute_derived()
        |> clean_for_dataframe()
      end)

    df = DF.new(rows)
    {:ok, df}
  end

  # --- Data Queries ---

  defp base_query do
    from(c in Card,
      join: s in Set,
      on: s.id == c.set_id,
      select: %{
        card_id: c.id,
        name: c.name,
        category: c.category,
        rarity: c.rarity,
        hp: c.hp,
        stage: c.stage,
        illustrator: c.illustrator,
        evolves_from: c.evolves_from,
        retreat_cost: c.retreat_cost,
        energy_type: c.energy_type,
        attack_count: c.attack_count,
        total_attack_damage: c.total_attack_damage,
        max_attack_damage: c.max_attack_damage,
        has_ability: c.has_ability,
        ability_count: c.ability_count,
        weakness_count: c.weakness_count,
        resistance_count: c.resistance_count,
        energy_cost_total: c.energy_cost_total,
        art_type: c.art_type,
        is_full_art: c.is_full_art,
        is_alternate_art: c.is_alternate_art,
        is_secret_rare: c.is_secret_rare,
        language_count: c.language_count,
        first_edition: c.first_edition,
        is_shadowless: c.is_shadowless,
        has_first_edition_stamp: c.has_first_edition_stamp,
        legal_standard: c.legal_standard,
        legal_expanded: c.legal_expanded,
        set_id: c.set_id,
        era: s.era,
        release_date: s.release_date,
        set_card_count: s.card_count_official,
        secret_rare_ratio: s.secret_rare_ratio
      }
    )
    |> Repo.all()
  end

  defp species_query do
    # DISTINCT ON card_id, ordered by lowest dex_id for primary species
    from(cd in CardDexId,
      join: sp in Species,
      on: sp.id == cd.dex_id,
      distinct: cd.card_id,
      order_by: [asc: cd.card_id, asc: cd.dex_id],
      select: %{
        card_id: cd.card_id,
        species_generation: sp.generation,
        is_legendary: sp.is_legendary,
        is_mythical: sp.is_mythical,
        is_baby: sp.is_baby,
        capture_rate: sp.capture_rate,
        base_happiness: sp.base_happiness,
        growth_rate: sp.growth_rate
      }
    )
    |> Repo.all()
    |> Map.new(fn row -> {row.card_id, row} end)
  end

  defp dex_count_query do
    from(cd in CardDexId,
      group_by: cd.card_id,
      select: {cd.card_id, count(cd.dex_id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp type_count_query do
    from(ct in CardType,
      group_by: ct.card_id,
      select: {ct.card_id, count(ct.type_name)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp illustrator_stats do
    # Frequency count per illustrator and average price (TCGPlayer-first)
    %{rows: rows} =
      Repo.query!(
        """
        SELECT
          c.illustrator,
          COUNT(*) AS frequency,
          AVG(ps.best_price::float) AS avg_price
        FROM cards c
        LEFT JOIN LATERAL (
          SELECT COALESCE(price_market, price_avg) AS best_price
          FROM price_snapshots
          WHERE card_id = c.id
            AND COALESCE(price_market, price_avg) IS NOT NULL
            AND COALESCE(price_market, price_avg) > 0
          ORDER BY snapshot_date DESC,
            CASE
              WHEN source = 'tcgplayer' AND variant = 'normal' THEN 1
              WHEN source = 'tcgplayer' AND variant = 'holofoil' THEN 2
              WHEN source = 'cardmarket' AND variant = 'normal' THEN 3
              WHEN source = 'cardmarket' AND variant = 'holo' THEN 4
              ELSE 5
            END
          LIMIT 1
        ) ps ON true
        WHERE c.illustrator IS NOT NULL
        GROUP BY c.illustrator
        """,
        [],
        timeout: 60_000
      )

    Map.new(rows, fn [name, freq, avg_price] ->
      {name, %{frequency: freq, avg_price: avg_price || 0.0}}
    end)
  end

  # --- Merge Helpers ---

  defp merge_species(card, nil, dex_count) do
    Map.merge(card, %{
      species_generation: nil,
      is_legendary: false,
      is_mythical: false,
      is_baby: false,
      capture_rate: nil,
      base_happiness: nil,
      growth_rate: nil,
      dex_id_count: dex_count || 0
    })
  end

  defp merge_species(card, species, dex_count) do
    Map.merge(card, %{
      species_generation: species.species_generation,
      is_legendary: species.is_legendary,
      is_mythical: species.is_mythical,
      is_baby: species.is_baby,
      capture_rate: species.capture_rate,
      base_happiness: species.base_happiness,
      growth_rate: species.growth_rate,
      dex_id_count: dex_count || 0
    })
  end

  defp merge_type_count(card, nil), do: Map.put(card, :type_count, 0)
  defp merge_type_count(card, count), do: Map.put(card, :type_count, count)

  defp merge_illustrator(card, nil, _map) do
    Map.merge(card, %{illustrator_frequency: 0, illustrator_avg_price: 0.0})
  end

  defp merge_illustrator(card, illustrator, map) do
    stats = Map.get(map, illustrator, %{frequency: 0, avg_price: 0.0})

    Map.merge(card, %{
      illustrator_frequency: stats.frequency,
      illustrator_avg_price: stats.avg_price
    })
  end

  defp merge_tournament(card, nil) do
    Map.merge(card, @tournament_defaults)
  end

  defp merge_tournament(card, tournament) do
    Enum.reduce(tournament, card, fn {k, v}, acc ->
      Map.put(acc, String.to_existing_atom(k), v || 0)
    end)
  end

  defp merge_price(card, nil) do
    Map.merge(card, %{
      canonical_price: nil,
      price_avg: nil,
      price_low: nil,
      price_high: nil,
      price_mid: nil,
      price_market: nil,
      price_trend: nil,
      price_avg1: nil,
      price_avg7: nil,
      price_avg30: nil,
      price_momentum_7d: nil,
      price_momentum_30d: nil,
      price_volatility: nil,
      log_price: nil,
      price_source: nil,
      price_currency: nil
    })
  end

  defp merge_price(card, price) do
    Enum.reduce(price, card, fn
      {"source", v}, acc -> Map.put(acc, :price_source, v)
      {"currency", v}, acc -> Map.put(acc, :price_currency, v)
      {"variant", _v}, acc -> acc
      {k, v}, acc -> Map.put(acc, String.to_existing_atom(k), v)
    end)
  end

  # --- Derived Features ---

  defp compute_derived(card) do
    card
    |> put_days_since_release()
    |> put_has_evolution()
    |> put_set_age_bucket()
  end

  defp put_days_since_release(%{release_date: nil} = card),
    do: Map.put(card, :days_since_release, nil)

  defp put_days_since_release(%{release_date: date} = card) do
    days = Date.diff(Date.utc_today(), date)
    Map.put(card, :days_since_release, days)
  end

  defp put_has_evolution(%{evolves_from: nil} = card),
    do: Map.put(card, :has_evolution, false)

  defp put_has_evolution(card),
    do: Map.put(card, :has_evolution, true)

  defp put_set_age_bucket(%{days_since_release: nil} = card),
    do: Map.put(card, :set_age_bucket, nil)

  defp put_set_age_bucket(%{days_since_release: days} = card) do
    bucket =
      cond do
        days < 90 -> "new"
        days < 365 -> "recent"
        days < 1095 -> "established"
        true -> "vintage"
      end

    Map.put(card, :set_age_bucket, bucket)
  end

  # --- DataFrame Preparation ---

  defp clean_for_dataframe(card) do
    card
    |> Map.drop([:name, :illustrator, :evolves_from, :image_url, :release_date, :set_id])
    |> Map.new(fn
      {k, %Decimal{} = v} -> {k, Decimal.to_float(v)}
      {k, v} -> {k, v}
    end)
  end
end
