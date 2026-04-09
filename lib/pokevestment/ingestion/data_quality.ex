defmodule Pokevestment.Ingestion.DataQuality do
  @moduledoc """
  Pure query module for data quality checks on sold_prices and listing_prices.

  Each check returns a map with `:status` (`:ok` or `:warning`) and `:detail`.
  `run_all_checks/0` aggregates all results for the DataQualityCheck worker.
  """

  import Ecto.Query

  alias Pokevestment.Repo
  alias Pokevestment.Pricing.{SoldPrice, ListingPrice}

  @variant_pattern ~r/^[a-z0-9]+(-[a-z0-9]+)*$/

  def run_all_checks do
    today = Date.utc_today()

    %{
      null_zero_sold: check_null_zero_sold(today),
      variant_consistency: check_variant_consistency(),
      coverage: check_coverage(today),
      price_anomalies: check_price_anomalies(today),
      missing_product_id: check_missing_product_id(today),
      incomplete_cards: check_incomplete_cards(),
      missing_usd_normalization: check_missing_usd_normalization(today)
    }
  end

  @doc "Count today's sold prices where all price fields are null or zero."
  def check_null_zero_sold(today \\ Date.utc_today()) do
    count =
      from(sp in SoldPrice,
        where: sp.snapshot_date == ^today,
        where:
          (is_nil(sp.price) or sp.price == 0) and
            (is_nil(sp.price_avg_1d) or sp.price_avg_1d == 0) and
            (is_nil(sp.price_avg_7d) or sp.price_avg_7d == 0) and
            (is_nil(sp.price_avg_30d) or sp.price_avg_30d == 0)
      )
      |> Repo.aggregate(:count)

    status = if count == 0, do: :ok, else: :warning
    %{status: status, detail: "#{count} null/zero sold prices today"}
  end

  @doc "Count sold_prices with non-kebab-case variant names."
  def check_variant_consistency do
    sold_variants =
      from(sp in SoldPrice,
        where: not is_nil(sp.variant),
        distinct: sp.variant,
        select: sp.variant
      )
      |> Repo.all()

    listing_variants =
      from(lp in ListingPrice,
        where: not is_nil(lp.variant),
        distinct: lp.variant,
        select: lp.variant
      )
      |> Repo.all()

    all_variants = Enum.uniq(sold_variants ++ listing_variants)
    bad_variants = Enum.reject(all_variants, &Regex.match?(@variant_pattern, &1))
    count = length(bad_variants)

    status = if count == 0, do: :ok, else: :warning

    detail =
      if count == 0,
        do: "all variants are kebab-case",
        else: "#{count} non-kebab-case variants: #{Enum.join(bad_variants, ", ")}"

    %{status: status, detail: detail}
  end

  @doc "Percentage of cards with at least one sold_price row in the last 7 days."
  def check_coverage(today \\ Date.utc_today()) do
    week_ago = Date.add(today, -6)

    total_cards =
      from(c in "cards", select: count(c.id))
      |> Repo.one()

    cards_with_prices =
      from(sp in SoldPrice,
        where: sp.snapshot_date >= ^week_ago and sp.snapshot_date <= ^today,
        select: count(sp.card_id, :distinct)
      )
      |> Repo.one()

    pct = if total_cards > 0, do: Float.round(cards_with_prices / total_cards * 100, 1), else: 0.0
    status = if pct >= 50.0, do: :ok, else: :warning

    %{status: status, detail: "#{pct}% of cards have sold prices in last 7 days (#{cards_with_prices}/#{total_cards})"}
  end

  @doc "Cards where today's sold price_usd differs by >500% from previous snapshot."
  def check_price_anomalies(today \\ Date.utc_today()) do
    count =
      Repo.query!(
        """
        WITH today_prices AS (
          SELECT card_id, marketplace, variant, condition, price_usd::float AS price
          FROM sold_prices
          WHERE snapshot_date = $1
            AND price_usd IS NOT NULL AND price_usd > 0
        ),
        prev_prices AS (
          SELECT DISTINCT ON (card_id, marketplace, variant, condition)
                 card_id, marketplace, variant, condition, price_usd::float AS price
          FROM sold_prices
          WHERE snapshot_date < $1
            AND price_usd IS NOT NULL AND price_usd > 0
          ORDER BY card_id, marketplace, variant, condition, snapshot_date DESC
        )
        SELECT COUNT(*) FROM today_prices t
        JOIN prev_prices p ON t.card_id = p.card_id AND t.marketplace = p.marketplace AND t.variant = p.variant AND t.condition = p.condition
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

  @doc "Count today's prices without a product_id (across both tables)."
  def check_missing_product_id(today \\ Date.utc_today()) do
    sold_missing =
      from(sp in SoldPrice,
        where: sp.snapshot_date == ^today,
        where: is_nil(sp.product_id)
      )
      |> Repo.aggregate(:count)

    listing_missing =
      from(lp in ListingPrice,
        where: lp.snapshot_date == ^today,
        where: is_nil(lp.product_id)
      )
      |> Repo.aggregate(:count)

    total_missing = sold_missing + listing_missing

    total =
      from(sp in SoldPrice, where: sp.snapshot_date == ^today)
      |> Repo.aggregate(:count)
      |> Kernel.+(
        from(lp in ListingPrice, where: lp.snapshot_date == ^today)
        |> Repo.aggregate(:count)
      )

    status = if total == 0 or total_missing / total < 0.5, do: :ok, else: :warning

    %{status: status, detail: "#{total_missing}/#{total} prices missing product_id today"}
  end

  @doc "Count cards missing rarity (incomplete detail backfill)."
  def check_incomplete_cards do
    count =
      from(c in "cards", where: is_nil(c.rarity))
      |> Repo.aggregate(:count)

    total =
      from(c in "cards", select: count(c.id))
      |> Repo.one()

    status = if count == 0, do: :ok, else: :warning
    %{status: status, detail: "#{count}/#{total} cards missing detailed data (rarity, HP, etc.)"}
  end

  @doc "Count sold_prices rows where price_usd is null (missing exchange rate at ingest time)."
  def check_missing_usd_normalization(today \\ Date.utc_today()) do
    count =
      from(sp in SoldPrice,
        where: sp.snapshot_date == ^today,
        where: is_nil(sp.price_usd),
        where: not is_nil(sp.price) and sp.price > 0
      )
      |> Repo.aggregate(:count)

    total =
      from(sp in SoldPrice,
        where: sp.snapshot_date == ^today,
        where: not is_nil(sp.price) and sp.price > 0
      )
      |> Repo.aggregate(:count)

    status = if count == 0, do: :ok, else: :warning
    %{status: status, detail: "#{count}/#{total} sold prices missing USD normalization today"}
  end
end
