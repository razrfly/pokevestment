defmodule Pokevestment.Ingestion.DataQuality do
  @moduledoc """
  Pure query module for data quality checks on price snapshots.

  Each check returns a map with `:status` (`:ok` or `:warning`) and `:detail`.
  `run_all_checks/0` aggregates all results for the DataQualityCheck worker.
  """

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Pricing.PriceSnapshot

  @variant_pattern ~r/^[a-z0-9]+(-[a-z0-9]+)*$/

  def run_all_checks do
    today = Date.utc_today()

    %{
      null_zero_rows: check_null_zero_rows(today),
      variant_consistency: check_variant_consistency(),
      stale_market_prices: check_stale_market_prices(today),
      coverage: check_coverage(today),
      price_anomalies: check_price_anomalies(today),
      missing_product_id: check_missing_product_id(today)
    }
  end

  @doc "Count today's snapshots where all price fields are null or zero."
  def check_null_zero_rows(today \\ Date.utc_today()) do
    count =
      from(ps in PriceSnapshot,
        where: ps.snapshot_date == ^today,
        where:
          (is_nil(ps.price_low) or ps.price_low == 0) and
            (is_nil(ps.price_mid) or ps.price_mid == 0) and
            (is_nil(ps.price_high) or ps.price_high == 0) and
            (is_nil(ps.price_market) or ps.price_market == 0) and
            (is_nil(ps.price_avg) or ps.price_avg == 0) and
            (is_nil(ps.price_trend) or ps.price_trend == 0)
      )
      |> Repo.aggregate(:count)

    status = if count == 0, do: :ok, else: :warning
    %{status: status, detail: "#{count} null/zero-price snapshots today"}
  end

  @doc "Count snapshots with non-kebab-case variant names."
  def check_variant_consistency do
    variants =
      from(ps in PriceSnapshot,
        where: not is_nil(ps.variant),
        distinct: ps.variant,
        select: ps.variant
      )
      |> Repo.all()

    bad_variants = Enum.reject(variants, &Regex.match?(@variant_pattern, &1))
    count = length(bad_variants)

    status = if count == 0, do: :ok, else: :warning

    detail =
      if count == 0,
        do: "all variants are kebab-case",
        else: "#{count} non-kebab-case variants: #{Enum.join(bad_variants, ", ")}"

    %{status: status, detail: detail}
  end

  @doc "Count today's snapshots where market price < 50% of low price (stale market data)."
  def check_stale_market_prices(today \\ Date.utc_today()) do
    count =
      from(ps in PriceSnapshot,
        where: ps.snapshot_date == ^today,
        where: not is_nil(ps.price_market) and ps.price_market > 0,
        where: not is_nil(ps.price_low) and ps.price_low > 0,
        where: ps.price_market < fragment("? * 0.5", ps.price_low)
      )
      |> Repo.aggregate(:count)

    status = if count == 0, do: :ok, else: :warning
    %{status: status, detail: "#{count} snapshots with stale market prices today"}
  end

  @doc "Percentage of cards with at least one price snapshot in the last 7 days."
  def check_coverage(today \\ Date.utc_today()) do
    week_ago = Date.add(today, -6)

    total_cards =
      from(c in "cards", select: count(c.id))
      |> Repo.one()

    cards_with_prices =
      from(ps in PriceSnapshot,
        where: ps.snapshot_date >= ^week_ago,
        select: count(ps.card_id, :distinct)
      )
      |> Repo.one()

    pct = if total_cards > 0, do: Float.round(cards_with_prices / total_cards * 100, 1), else: 0.0
    status = if pct >= 50.0, do: :ok, else: :warning

    %{status: status, detail: "#{pct}% of cards have prices in last 7 days (#{cards_with_prices}/#{total_cards})"}
  end

  @doc "Cards where today's canonical price differs by >500% from previous snapshot."
  def check_price_anomalies(today \\ Date.utc_today()) do
    # Find cards with today's prices and their most recent previous price
    count =
      Repo.query!(
        """
        WITH today_prices AS (
          SELECT card_id, source, variant,
                 COALESCE(price_market, COALESCE(price_mid, price_avg)) AS price
          FROM price_snapshots
          WHERE snapshot_date = $1
            AND COALESCE(price_market, COALESCE(price_mid, price_avg)) > 0
        ),
        prev_prices AS (
          SELECT DISTINCT ON (card_id, source, variant)
                 card_id, source, variant,
                 COALESCE(price_market, COALESCE(price_mid, price_avg)) AS price
          FROM price_snapshots
          WHERE snapshot_date < $1
            AND COALESCE(price_market, COALESCE(price_mid, price_avg)) > 0
          ORDER BY card_id, source, variant, snapshot_date DESC
        )
        SELECT COUNT(*) FROM today_prices t
        JOIN prev_prices p ON t.card_id = p.card_id AND t.source = p.source AND t.variant = p.variant
        WHERE t.price > p.price * 5 OR t.price < p.price / 5
        """,
        [today]
      )
      |> Map.get(:rows)
      |> List.first()
      |> List.first()

    status = if count == 0, do: :ok, else: :warning
    %{status: status, detail: "#{count} price anomalies (>500% change) today"}
  end

  @doc "Count today's snapshots without a product_id."
  def check_missing_product_id(today \\ Date.utc_today()) do
    count =
      from(ps in PriceSnapshot,
        where: ps.snapshot_date == ^today,
        where: is_nil(ps.product_id)
      )
      |> Repo.aggregate(:count)

    total =
      from(ps in PriceSnapshot,
        where: ps.snapshot_date == ^today
      )
      |> Repo.aggregate(:count)

    status = if total == 0 or count / total < 0.5, do: :ok, else: :warning

    %{status: status, detail: "#{count}/#{total} snapshots missing product_id today"}
  end
end
