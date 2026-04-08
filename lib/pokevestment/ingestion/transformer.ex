defmodule Pokevestment.Ingestion.Transformer do
  @moduledoc """
  Pure functions to transform API responses into Ecto-compatible attribute maps.
  No database access — all functions are side-effect free.
  """

  alias Pokevestment.Ingestion.FeatureExtractor
  alias Pokevestment.Pricing.ExchangeRate

  @generation_ranges [
    {1, 1, 151},
    {2, 152, 251},
    {3, 252, 386},
    {4, 387, 493},
    {5, 494, 649},
    {6, 650, 721},
    {7, 722, 809},
    {8, 810, 905},
    {9, 906, 1025}
  ]

  @roman_numerals %{
    "i" => 1,
    "ii" => 2,
    "iii" => 3,
    "iv" => 4,
    "v" => 5,
    "vi" => 6,
    "vii" => 7,
    "viii" => 8,
    "ix" => 9
  }

  # --- Series ---

  @doc "Transform a raw TCGdex series response into Series schema attrs."
  def series_attrs(raw) do
    %{
      id: raw["id"],
      name: raw["name"],
      logo_url: raw["logo"],
      metadata: raw
    }
  end

  # --- Set ---

  @doc "Transform a raw TCGdex set detail response into Set schema attrs."
  def set_attrs(raw) do
    card_count = raw["cardCount"] || %{}
    serie = raw["serie"] || %{}
    legal = raw["legal"] || %{}

    base = %{
      id: raw["id"],
      name: raw["name"],
      series_id: serie["id"],
      release_date: parse_date(raw["releaseDate"]),
      card_count_official: card_count["official"],
      card_count_total: card_count["total"],
      logo_url: raw["logo"],
      symbol_url: raw["symbol"],
      ptcgo_code: raw["tcgOnline"],
      legal_standard: legal["standard"] || false,
      legal_expanded: legal["expanded"] || false,
      card_count_breakdown: card_count,
      metadata: Map.drop(raw, ["cards"])
    }

    set_features =
      FeatureExtractor.compute_set_features(%{
        series_id: serie["id"],
        card_count_official: card_count["official"],
        card_count_total: card_count["total"]
      })

    Map.merge(base, set_features)
  end

  # --- Pokemon Species ---

  @doc "Transform PokeAPI species + pokemon responses into Species schema attrs."
  def species_attrs(species_raw, pokemon_raw) do
    generation_name = get_in(species_raw, ["generation", "name"]) || ""

    %{
      id: species_raw["id"],
      name: species_raw["name"],
      generation: parse_generation_name(generation_name),
      is_legendary: species_raw["is_legendary"] || false,
      is_mythical: species_raw["is_mythical"] || false,
      is_baby: species_raw["is_baby"] || false,
      color: get_in(species_raw, ["color", "name"]),
      habitat: get_in(species_raw, ["habitat", "name"]),
      shape: get_in(species_raw, ["shape", "name"]),
      capture_rate: species_raw["capture_rate"],
      base_happiness: species_raw["base_happiness"],
      growth_rate: get_in(species_raw, ["growth_rate", "name"]),
      flavor_text: extract_flavor_text(species_raw["flavor_text_entries"]),
      genus: extract_genus(species_raw["genera"]),
      evolves_from_species_id: extract_evolves_from_id(species_raw["evolves_from_species"]),
      sprite_url: get_in(pokemon_raw, ["sprites", "other", "official-artwork", "front_default"]),
      metadata: species_raw
    }
  end

  # --- Card ---

  @doc """
  Transform a raw TCGdex card detail response into a tuple of attribute maps.

  Returns `{card_attrs, [card_type_attrs], [card_dex_id_attrs], [sold_price_attrs], [listing_price_attrs]}`.

  `set_data` should be a map with `:card_count_official` for secret rare derivation.
  """
  def card_attrs(card_raw, set_data) do
    card_id = card_raw["id"]
    set_info = card_raw["set"] || %{}
    legal = card_raw["legal"] || %{}
    dex_ids = card_raw["dexId"] || []
    types = card_raw["types"] || []

    card = %{
      id: card_id,
      name: truncate(card_raw["name"], 150),
      local_id: truncate(card_raw["localId"], 20),
      category: card_raw["category"] |> safe_string("Unknown") |> truncate(20),
      rarity: truncate(card_raw["rarity"], 50),
      hp: card_raw["hp"],
      stage: truncate(card_raw["stage"], 20),
      suffix: truncate(card_raw["suffix"], 30),
      illustrator: truncate(card_raw["illustrator"], 100),
      evolves_from: truncate(card_raw["evolveFrom"], 150),
      retreat_cost: card_raw["retreat"],
      regulation_mark: truncate(card_raw["regulationMark"], 5),
      energy_type: truncate(card_raw["energyType"], 20),
      trainer_type: truncate(card_raw["trainerType"], 20),
      set_id: set_info["id"],
      legal_standard: legal["standard"] || false,
      legal_expanded: legal["expanded"] || false,
      variants: card_raw["variants"],
      variants_detailed: card_raw["variants_detailed"],
      attacks: card_raw["attacks"],
      abilities: card_raw["abilities"],
      weaknesses: card_raw["weaknesses"],
      resistances: card_raw["resistances"],
      image_url: build_image_url(card_raw["image"]),
      api_updated_at: parse_datetime(card_raw["updated"]),
      is_secret_rare: secret_rare?(card_raw["localId"], set_data),
      generation: generation_from_dex_ids(dex_ids),
      metadata: card_raw
    }

    features =
      FeatureExtractor.compute_features(%{
        attacks: card_raw["attacks"],
        abilities: card_raw["abilities"],
        weaknesses: card_raw["weaknesses"],
        resistances: card_raw["resistances"],
        variants: card_raw["variants"],
        variants_detailed: card_raw["variants_detailed"]
      })

    card = Map.merge(card, features)

    art_features = FeatureExtractor.compute_art_features(%{rarity: card_raw["rarity"]})
    card = Map.merge(card, art_features)

    energy_features = FeatureExtractor.compute_energy_cost(%{attacks: card_raw["attacks"]})
    card = Map.merge(card, energy_features)

    card_type_attrs =
      types |> Enum.uniq() |> Enum.map(fn type -> %{card_id: card_id, type_name: type} end)

    card_dex_id_attrs =
      dex_ids |> Enum.uniq() |> Enum.map(fn dex_id -> %{card_id: card_id, dex_id: dex_id} end)

    {sold_prices, listing_prices} = build_prices(card_id, card_raw["pricing"], "tcgdex")

    {card, card_type_attrs, card_dex_id_attrs, sold_prices, listing_prices}
  end

  @doc """
  Create minimal card attrs from a set response card entry.

  Used as fallback when the card detail endpoint is unavailable.
  Only provides required fields (id, name, local_id, set_id, category).
  """
  def card_attrs_minimal(card_entry, set_id) do
    card_id = card_entry["id"]
    image_base = card_entry["image"]

    card = %{
      id: card_id,
      name: truncate(card_entry["name"], 150),
      local_id: truncate(card_entry["localId"], 20),
      category: card_entry["category"] |> safe_string("Unknown") |> truncate(20),
      set_id: set_id,
      image_url: build_image_url(image_base)
    }

    {card, [], [], [], []}
  end

  # --- Price Builders (Sold / Listing separation) ---

  @doc """
  Build sold and listing price attrs from a card's TCGdex pricing data.

  Returns `{[sold_price_attrs], [listing_price_attrs]}`.
  """
  def build_prices(_card_id, nil, _api_source), do: {[], []}

  def build_prices(card_id, pricing, api_source) do
    today = Date.utc_today()

    {tcg_sold, tcg_listing} =
      build_tcgdex_tcgplayer_prices(card_id, pricing["tcgplayer"], today, api_source)

    {cm_sold, cm_listing} =
      build_tcgdex_cardmarket_prices(card_id, pricing["cardmarket"], today, api_source)

    {tcg_sold ++ cm_sold, tcg_listing ++ cm_listing}
  end

  defp build_tcgdex_tcgplayer_prices(_card_id, nil, _today, _api_source), do: {[], []}

  defp build_tcgdex_tcgplayer_prices(card_id, tcgplayer, today, api_source) do
    source_updated_at = parse_datetime(tcgplayer["updated"])
    currency = tcgplayer["unit"] || "USD"

    tcgplayer
    |> Map.drop(~w(updated unit))
    |> Enum.reduce({[], []}, fn
      {variant, data}, {sold_acc, listing_acc} when is_map(data) ->
        normalized_variant = normalize_variant(variant)
        market_price = to_decimal(data["marketPrice"])
        {price_usd, rate, rate_date} = ExchangeRate.convert_to_usd(market_price, currency)

        base = %{
          card_id: card_id,
          marketplace: "tcgplayer",
          api_source: api_source,
          variant: normalized_variant,
          snapshot_date: today,
          currency_original: currency,
          product_id: data["productId"],
          source_updated_at: source_updated_at
        }

        sold =
          if market_price do
            [
              Map.merge(base, %{
                price: market_price,
                price_usd: price_usd,
                exchange_rate: rate,
                exchange_rate_date: rate_date
              })
            ]
          else
            []
          end

        low = to_decimal(data["lowPrice"])
        mid = to_decimal(data["midPrice"])
        high = to_decimal(data["highPrice"])
        direct_low = to_decimal(data["directLowPrice"])
        {low_usd, _, _} = ExchangeRate.convert_to_usd(low, currency)
        {mid_usd, _, _} = ExchangeRate.convert_to_usd(mid, currency)
        {high_usd, l_rate, l_rate_date} = ExchangeRate.convert_to_usd(high, currency)

        listing =
          if low || mid || high do
            [
              Map.merge(base, %{
                price_low: low,
                price_mid: mid,
                price_high: high,
                price_direct_low: direct_low,
                price_low_usd: low_usd,
                price_mid_usd: mid_usd,
                price_high_usd: high_usd,
                exchange_rate: l_rate,
                exchange_rate_date: l_rate_date
              })
            ]
          else
            []
          end

        {sold ++ sold_acc, listing ++ listing_acc}

      _, acc ->
        acc
    end)
  end

  defp build_tcgdex_cardmarket_prices(_card_id, nil, _today, _api_source), do: {[], []}

  defp build_tcgdex_cardmarket_prices(card_id, cardmarket, today, api_source) do
    source_updated_at = parse_datetime(cardmarket["updated"])
    currency = cardmarket["unit"] || "EUR"
    product_id = cardmarket["idProduct"]

    avg = to_decimal(cardmarket["avg"])
    {price_usd, rate, rate_date} = ExchangeRate.convert_to_usd(avg, currency)

    base = %{
      card_id: card_id,
      marketplace: "cardmarket",
      api_source: api_source,
      variant: "normal",
      snapshot_date: today,
      currency_original: currency,
      product_id: product_id,
      source_updated_at: source_updated_at
    }

    normal_sold =
      if avg do
        [
          Map.merge(base, %{
            price: avg,
            price_avg_1d: to_decimal(cardmarket["avg1"]),
            price_avg_7d: to_decimal(cardmarket["avg7"]),
            price_avg_30d: to_decimal(cardmarket["avg30"]),
            price_usd: price_usd,
            exchange_rate: rate,
            exchange_rate_date: rate_date
          })
        ]
      else
        []
      end

    low = to_decimal(cardmarket["low"])
    trend = to_decimal(cardmarket["trend"])
    {low_usd, l_rate, l_rate_date} = ExchangeRate.convert_to_usd(low, currency)

    normal_listing =
      if low do
        [
          Map.merge(base, %{
            price_low: low,
            price_low_usd: low_usd,
            exchange_rate: l_rate,
            exchange_rate_date: l_rate_date,
            metadata: if(trend, do: %{"trend_price" => Decimal.to_string(trend)})
          })
        ]
      else
        []
      end

    # Holo variant
    holo_values = [
      cardmarket["avg-holo"],
      cardmarket["low-holo"],
      cardmarket["trend-holo"],
      cardmarket["avg1-holo"],
      cardmarket["avg7-holo"],
      cardmarket["avg30-holo"]
    ]

    {holo_sold, holo_listing} =
      if Enum.any?(holo_values, fn val -> is_number(val) and val > 0 end) do
        holo_base = %{base | variant: "holo"}
        holo_avg = to_decimal(cardmarket["avg-holo"])
        {h_usd, h_rate, h_rate_date} = ExchangeRate.convert_to_usd(holo_avg, currency)

        h_sold =
          if holo_avg do
            [
              Map.merge(holo_base, %{
                price: holo_avg,
                price_avg_1d: to_decimal(cardmarket["avg1-holo"]),
                price_avg_7d: to_decimal(cardmarket["avg7-holo"]),
                price_avg_30d: to_decimal(cardmarket["avg30-holo"]),
                price_usd: h_usd,
                exchange_rate: h_rate,
                exchange_rate_date: h_rate_date
              })
            ]
          else
            []
          end

        holo_low = to_decimal(cardmarket["low-holo"])
        holo_trend = to_decimal(cardmarket["trend-holo"])
        {hl_usd, hl_rate, hl_rate_date} = ExchangeRate.convert_to_usd(holo_low, currency)

        h_listing =
          if holo_low do
            [
              Map.merge(holo_base, %{
                price_low: holo_low,
                price_low_usd: hl_usd,
                exchange_rate: hl_rate,
                exchange_rate_date: hl_rate_date,
                metadata: if(holo_trend, do: %{"trend_price" => Decimal.to_string(holo_trend)})
              })
            ]
          else
            []
          end

        {h_sold, h_listing}
      else
        {[], []}
      end

    {normal_sold ++ holo_sold, normal_listing ++ holo_listing}
  end

  # --- Pokemon TCG API Price Builders ---

  @doc """
  Build sold and listing price attrs from Pokemon TCG API card data.

  Returns `{[sold_price_attrs], [listing_price_attrs]}`.
  """
  def build_prices_from_ptcg(_card_id, nil, nil), do: {[], []}

  def build_prices_from_ptcg(card_id, tcgplayer, cardmarket) do
    today = Date.utc_today()
    api_source = "pokemontcg.io"

    {tcg_sold, tcg_listing} =
      build_ptcg_tcgplayer_prices(card_id, tcgplayer, today, api_source)

    {cm_sold, cm_listing} =
      build_ptcg_cardmarket_prices(card_id, cardmarket, today, api_source)

    {tcg_sold ++ cm_sold, tcg_listing ++ cm_listing}
  end

  defp build_ptcg_tcgplayer_prices(_card_id, nil, _today, _api_source), do: {[], []}

  defp build_ptcg_tcgplayer_prices(card_id, tcgplayer, today, api_source) do
    source_updated_at = parse_datetime(tcgplayer["updatedAt"])
    product_id = extract_product_id_from_url(tcgplayer["url"])
    marketplace_url = tcgplayer["url"]
    prices = tcgplayer["prices"] || %{}

    Enum.reduce(prices, {[], []}, fn
      {variant, data}, {sold_acc, listing_acc} when is_map(data) ->
        normalized_variant = normalize_variant(variant)
        market_price = to_decimal(data["market"])
        {price_usd, rate, rate_date} = ExchangeRate.convert_to_usd(market_price, "USD")

        base = %{
          card_id: card_id,
          marketplace: "tcgplayer",
          api_source: api_source,
          variant: normalized_variant,
          snapshot_date: today,
          currency_original: "USD",
          product_id: product_id,
          source_updated_at: source_updated_at,
          metadata: if(marketplace_url, do: %{"marketplace_url" => marketplace_url})
        }

        sold =
          if market_price do
            [
              Map.merge(base, %{
                price: market_price,
                price_usd: price_usd,
                exchange_rate: rate,
                exchange_rate_date: rate_date
              })
            ]
          else
            []
          end

        low = to_decimal(data["low"])
        mid = to_decimal(data["mid"])
        high = to_decimal(data["high"])
        direct_low = to_decimal(data["directLow"])

        listing =
          if low || mid || high do
            [
              Map.merge(base, %{
                price_low: low,
                price_mid: mid,
                price_high: high,
                price_direct_low: direct_low,
                price_low_usd: low,
                price_mid_usd: mid,
                price_high_usd: high,
                exchange_rate: Decimal.new(1),
                exchange_rate_date: Date.utc_today()
              })
            ]
          else
            []
          end

        {sold ++ sold_acc, listing ++ listing_acc}

      _, acc ->
        acc
    end)
  end

  defp build_ptcg_cardmarket_prices(_card_id, nil, _today, _api_source), do: {[], []}

  defp build_ptcg_cardmarket_prices(card_id, cardmarket, today, api_source) do
    source_updated_at = parse_datetime(cardmarket["updatedAt"])
    product_id = extract_product_id_from_url(cardmarket["url"])
    marketplace_url = cardmarket["url"]
    prices = cardmarket["prices"] || %{}

    avg = to_decimal(prices["averageSellPrice"])
    {price_usd, rate, rate_date} = ExchangeRate.convert_to_usd(avg, "EUR")

    base = %{
      card_id: card_id,
      marketplace: "cardmarket",
      api_source: api_source,
      variant: "normal",
      snapshot_date: today,
      currency_original: "EUR",
      product_id: product_id,
      source_updated_at: source_updated_at,
      metadata: if(marketplace_url, do: %{"marketplace_url" => marketplace_url})
    }

    normal_sold =
      if avg do
        [
          Map.merge(base, %{
            price: avg,
            price_avg_1d: to_decimal(prices["avg1"]),
            price_avg_7d: to_decimal(prices["avg7"]),
            price_avg_30d: to_decimal(prices["avg30"]),
            price_usd: price_usd,
            exchange_rate: rate,
            exchange_rate_date: rate_date
          })
        ]
      else
        []
      end

    low = to_decimal(prices["lowPrice"])
    trend = to_decimal(prices["trendPrice"])
    {low_usd, l_rate, l_rate_date} = ExchangeRate.convert_to_usd(low, "EUR")

    normal_listing =
      if low do
        trend_meta =
          if trend,
            do: %{"trend_price" => Decimal.to_string(trend)},
            else: nil

        listing_meta =
          case {marketplace_url, trend_meta} do
            {nil, nil} -> nil
            {url, nil} -> %{"marketplace_url" => url}
            {nil, tm} -> tm
            {url, tm} -> Map.put(tm, "marketplace_url", url)
          end

        [
          Map.merge(base, %{
            price_low: low,
            price_low_usd: low_usd,
            exchange_rate: l_rate,
            exchange_rate_date: l_rate_date,
            metadata: listing_meta
          })
        ]
      else
        []
      end

    # Reverse holo variant
    holo_values = [
      prices["reverseHoloAvg1"],
      prices["reverseHoloAvg7"],
      prices["reverseHoloAvg30"],
      prices["reverseHoloLow"],
      prices["reverseHoloTrend"],
      prices["reverseHoloSell"]
    ]

    {holo_sold, holo_listing} =
      if Enum.any?(holo_values, fn val -> is_number(val) and val > 0 end) do
        holo_base = %{base | variant: "reverse-holofoil"}
        holo_avg = to_decimal(prices["reverseHoloSell"])
        {h_usd, h_rate, h_rate_date} = ExchangeRate.convert_to_usd(holo_avg, "EUR")

        h_sold =
          if holo_avg do
            [
              Map.merge(holo_base, %{
                price: holo_avg,
                price_avg_1d: to_decimal(prices["reverseHoloAvg1"]),
                price_avg_7d: to_decimal(prices["reverseHoloAvg7"]),
                price_avg_30d: to_decimal(prices["reverseHoloAvg30"]),
                price_usd: h_usd,
                exchange_rate: h_rate,
                exchange_rate_date: h_rate_date
              })
            ]
          else
            []
          end

        holo_low = to_decimal(prices["reverseHoloLow"])
        holo_trend = to_decimal(prices["reverseHoloTrend"])
        {hl_usd, hl_rate, hl_rate_date} = ExchangeRate.convert_to_usd(holo_low, "EUR")

        h_listing =
          if holo_low do
            h_trend_meta =
              if holo_trend,
                do: %{"trend_price" => Decimal.to_string(holo_trend)},
                else: nil

            h_listing_meta =
              case {marketplace_url, h_trend_meta} do
                {nil, nil} -> nil
                {url, nil} -> %{"marketplace_url" => url}
                {nil, tm} -> tm
                {url, tm} -> Map.put(tm, "marketplace_url", url)
              end

            [
              Map.merge(holo_base, %{
                price_low: holo_low,
                price_low_usd: hl_usd,
                exchange_rate: hl_rate,
                exchange_rate_date: hl_rate_date,
                metadata: h_listing_meta
              })
            ]
          else
            []
          end

        {h_sold, h_listing}
      else
        {[], []}
      end

    {normal_sold ++ holo_sold, normal_listing ++ holo_listing}
  end

  # --- Public Helpers ---

  @doc "Parse an ISO 8601 datetime string, returning nil on failure."
  def parse_datetime(nil), do: nil

  def parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        DateTime.truncate(dt, :second)

      _ ->
        # Fallback: try parsing "YYYY/MM/DD" format from Pokemon TCG API
        parse_slash_date(str)
    end
  end

  defp parse_slash_date(str) do
    case String.split(str, "/") do
      [y, m, d] ->
        with {year, ""} <- Integer.parse(y),
             {month, ""} <- Integer.parse(m),
             {day, ""} <- Integer.parse(d),
             {:ok, date} <- Date.new(year, month, day) do
          DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc "Map a national Pokedex ID to its generation number (1-9)."
  def generation_for_dex_id(nil), do: nil

  def generation_for_dex_id(dex_id) when is_integer(dex_id) do
    Enum.find_value(@generation_ranges, fn {gen, min, max} ->
      if dex_id >= min and dex_id <= max, do: gen
    end)
  end

  @doc "Convert a number (integer, float, or nil) to Decimal."
  def to_decimal(nil), do: nil
  def to_decimal(val) when is_integer(val), do: Decimal.new(val)
  def to_decimal(val) when is_float(val), do: Decimal.from_float(val)
  def to_decimal(_), do: nil

  # --- Private Helpers ---

  defp truncate(nil, _max), do: nil

  defp truncate(str, max) when is_binary(str) do
    if String.length(str) > max, do: String.slice(str, 0, max), else: str
  end

  defp safe_string(val, _fallback) when is_binary(val), do: val
  defp safe_string(_val, fallback), do: fallback

  defp parse_date(nil), do: nil

  defp parse_date(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_generation_name("generation-" <> numeral) do
    Map.get(@roman_numerals, numeral)
  end

  defp parse_generation_name(_), do: nil

  defp extract_flavor_text(nil), do: nil

  defp extract_flavor_text(entries) when is_list(entries) do
    entries
    |> Enum.filter(fn entry -> get_in(entry, ["language", "name"]) == "en" end)
    |> List.last()
    |> case do
      nil -> nil
      entry -> entry["flavor_text"] |> String.replace(~r/[\n\f\r]/, " ") |> String.trim()
    end
  end

  defp extract_genus(nil), do: nil

  defp extract_genus(genera) when is_list(genera) do
    genera
    |> Enum.find(fn g -> get_in(g, ["language", "name"]) == "en" end)
    |> case do
      nil -> nil
      g -> g["genus"]
    end
  end

  defp extract_evolves_from_id(nil), do: nil

  defp extract_evolves_from_id(%{"url" => url}) when is_binary(url) do
    url
    |> String.trim_trailing("/")
    |> String.split("/")
    |> List.last()
    |> String.to_integer()
  rescue
    _ -> nil
  end

  defp extract_evolves_from_id(_), do: nil

  @doc """
  Extract an integer product ID from a TCGPlayer or CardMarket URL.

  ## Examples

      iex> extract_product_id_from_url("https://www.tcgplayer.com/product/12345/foo-bar")
      12345

      iex> extract_product_id_from_url("https://www.cardmarket.com/en/Pokemon/Products/Singles/Foo/Bar/12345")
      12345

      iex> extract_product_id_from_url(nil)
      nil
  """
  def extract_product_id_from_url(nil), do: nil

  def extract_product_id_from_url(url) when is_binary(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> Kernel.||("")
    |> String.split("/")
    |> Enum.find_value(fn segment ->
      case Integer.parse(segment) do
        {id, ""} when id > 0 -> id
        _ -> nil
      end
    end)
  end

  @doc "Normalize variant names to kebab-case. Used by both TCGdex and Pokemon TCG API paths."
  def normalize_variant("reverseHolofoil"), do: "reverse-holofoil"
  def normalize_variant("1stEdition"), do: "1st-edition"
  def normalize_variant("1stEditionHolofoil"), do: "1st-edition-holofoil"
  def normalize_variant("1stEditionNormal"), do: "1st-edition-normal"
  def normalize_variant("unlimitedHolofoil"), do: "unlimited-holofoil"
  def normalize_variant(other), do: other

  defp build_image_url(nil), do: nil
  defp build_image_url(base_url), do: base_url <> "/high.webp"

  defp secret_rare?(local_id, set_data) when is_binary(local_id) do
    case Integer.parse(local_id) do
      {num, ""} ->
        card_count = Map.get(set_data || %{}, :card_count_official)
        if card_count, do: num > card_count, else: false

      _ ->
        false
    end
  end

  defp secret_rare?(_, _), do: false

  defp generation_from_dex_ids([first | _]), do: generation_for_dex_id(first)
  defp generation_from_dex_ids(_), do: nil
end
