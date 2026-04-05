defmodule PokevestmentWeb.SetLive.Show do
  use PokevestmentWeb, :live_view

  import PokevestmentWeb.LandingComponents
  import PokevestmentWeb.PredictionComponents
  import PokevestmentWeb.SetComponents

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Set
  alias Pokevestment.Predictions

  @signals ["STRONG_BUY", "BUY", "HOLD", "OVERVALUED", "INSUFFICIENT_DATA"]

  @sort_labels [
    {"Best Buys", "strength_desc"},
    {"Price: High", "price_desc"},
    {"Price: Low", "price_asc"},
    {"Card #", "number_asc"},
    {"Name A\u2013Z", "name_asc"}
  ]

  @default_params %{
    "signal" => "all",
    "sort" => "strength_desc",
    "q" => "",
    "min_price" => "",
    "type" => "all"
  }

  @input_class "rounded-xl border border-olive-200 bg-olive-50 text-sm text-olive-900 focus:border-olive-400 focus:bg-white focus:outline-none focus:ring-1 focus:ring-olive-400 dark:border-olive-700 dark:bg-olive-900/60 dark:text-olive-100 dark:focus:border-olive-600 dark:focus:bg-olive-900"

  # Signal pill colors: {inactive, active}
  @signal_pill_styles %{
    "STRONG_BUY" => {
      "bg-emerald-100 text-emerald-700 hover:bg-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-400 dark:hover:bg-emerald-500/20",
      "bg-emerald-700 text-white ring-2 ring-emerald-700/30 dark:bg-emerald-600 dark:text-white dark:ring-emerald-400/30"
    },
    "BUY" => {
      "bg-lime-100 text-lime-700 hover:bg-lime-200 dark:bg-lime-500/10 dark:text-lime-400 dark:hover:bg-lime-500/20",
      "bg-lime-700 text-white ring-2 ring-lime-700/30 dark:bg-lime-600 dark:text-white dark:ring-lime-400/30"
    },
    "HOLD" => {
      "bg-olive-100 text-olive-700 hover:bg-olive-200 dark:bg-olive-500/10 dark:text-olive-400 dark:hover:bg-olive-500/20",
      "bg-olive-600 text-white ring-2 ring-olive-600/30 dark:bg-olive-500 dark:text-white dark:ring-olive-400/30"
    },
    "OVERVALUED" => {
      "bg-red-100 text-red-700 hover:bg-red-200 dark:bg-red-500/10 dark:text-red-400 dark:hover:bg-red-500/20",
      "bg-red-700 text-white ring-2 ring-red-700/30 dark:bg-red-600 dark:text-white dark:ring-red-400/30"
    },
    "INSUFFICIENT_DATA" => {
      "bg-gray-100 text-gray-600 hover:bg-gray-200 dark:bg-gray-500/10 dark:text-gray-400 dark:hover:bg-gray-500/20",
      "bg-gray-500 text-white ring-2 ring-gray-500/30 dark:bg-gray-600 dark:text-white dark:ring-gray-400/30"
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, expanded: MapSet.new())}
  end

  @impl true
  def handle_params(%{"id" => id} = url_params, _uri, socket) do
    set = Repo.get!(Set, id)
    signal_summary = Predictions.signal_summary_for_set(id)
    set_types = Predictions.types_for_set(id)
    params = Map.merge(@default_params, Map.take(url_params, Map.keys(@default_params)))
    predictions = fetch_predictions(id, params)
    total_cards = Enum.sum(Map.values(signal_summary))

    {:noreply,
     assign(socket,
       set: set,
       signal_summary: signal_summary,
       total_cards: total_cards,
       set_types: set_types,
       predictions: predictions,
       params: params,
       sort_labels: @sort_labels,
       default_params: @default_params,
       input_class: @input_class,
       page_title: set.name
     )}
  end

  # Search input, min price, and type dropdown changes
  @impl true
  def handle_event("filter", form_params, socket) do
    params =
      socket.assigns.params
      |> Map.merge(Map.take(form_params, ~w(q min_price type)))
      |> clean_params()

    {:noreply, push_patch(socket, to: ~p"/sets/#{socket.assigns.set.id}?#{params}", replace: true)}
  end

  # Sort pill clicks
  def handle_event("set_sort", %{"sort" => sort}, socket) do
    params =
      socket.assigns.params
      |> Map.put("sort", sort)
      |> clean_params()

    {:noreply, push_patch(socket, to: ~p"/sets/#{socket.assigns.set.id}?#{params}")}
  end

  # Signal filter pill clicks
  def handle_event("set_signal", %{"signal" => signal}, socket) do
    params =
      socket.assigns.params
      |> Map.put("signal", signal)
      |> clean_params()

    {:noreply, push_patch(socket, to: ~p"/sets/#{socket.assigns.set.id}?#{params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/sets/#{socket.assigns.set.id}")}
  end

  def handle_event("toggle", %{"card-id" => card_id}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, card_id),
        do: MapSet.delete(socket.assigns.expanded, card_id),
        else: MapSet.put(socket.assigns.expanded, card_id)

    {:noreply, assign(socket, expanded: expanded)}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, signals: @signals)

    ~H"""
    <.section class="pt-8 sm:pt-12">
      <.container>
        <%!-- Header --%>
        <div>
          <.link navigate={~p"/sets"} class="text-sm text-olive-500 hover:text-olive-700 dark:text-olive-500 dark:hover:text-olive-300">
            &larr; All Sets
          </.link>
          <div class="mt-2 flex items-start gap-5">
            <.set_image set={@set} size={:lg} />
            <div>
              <h1 class="font-display text-3xl font-medium tracking-tight text-olive-950 dark:text-white sm:text-4xl">
                {@set.name}
              </h1>
              <div class="mt-2 flex flex-wrap items-center gap-3 text-sm text-olive-600 dark:text-olive-500">
                <span :if={@set.release_date}>{Calendar.strftime(@set.release_date, "%B %d, %Y")}</span>
                <span :if={@set.card_count_total}>&middot; {@set.card_count_total} cards</span>
                <span :if={@set.era}>&middot; {@set.era}</span>
                <span
                  :if={@set.legal_standard}
                  class="inline-flex rounded-full bg-olive-200 px-2 py-0.5 text-xs font-medium text-olive-800 dark:bg-olive-800 dark:text-olive-300"
                >
                  Standard
                </span>
              </div>
            </div>
          </div>
        </div>

        <%!-- Unified filter & sort panel --%>
        <div class="mt-6 space-y-3 rounded-2xl border border-olive-200 bg-white/60 p-4 dark:border-olive-800 dark:bg-olive-900/40">
          <%!-- Row 1: Search + Type dropdown + Min Price --%>
          <form phx-change="filter" class="flex flex-col gap-2.5 sm:flex-row sm:items-center">
            <div class="flex-1 sm:max-w-xs">
              <input
                type="text"
                name="q"
                value={@params["q"]}
                placeholder="Search cards..."
                phx-debounce="300"
                class={[@input_class, "w-full py-2 px-3"]}
              />
            </div>

            <div :if={@set_types != []} class="relative">
              <select name="type" class={[@input_class, "w-full appearance-none py-2 pl-3 pr-8"]}>
                <option value="all" selected={@params["type"] == "all"}>All Types</option>
                <option
                  :for={type <- @set_types}
                  value={type}
                  selected={@params["type"] == type}
                >
                  {type}
                </option>
              </select>
              <.icon
                name="hero-chevron-down-mini"
                class="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-olive-400 dark:text-olive-500"
              />
            </div>

            <div class="relative w-32">
              <span class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-olive-400 dark:text-olive-500">
                $
              </span>
              <input
                type="text"
                inputmode="decimal"
                name="min_price"
                value={@params["min_price"]}
                placeholder="Min"
                phx-debounce="500"
                class={[@input_class, "w-full py-2 pl-7 pr-3"]}
              />
            </div>
          </form>

          <%!-- Row 2: Sort pills --%>
          <div class="flex flex-wrap items-center gap-1.5">
            <button
              :for={{label, value} <- @sort_labels}
              type="button"
              phx-click="set_sort"
              phx-value-sort={value}
              class={sort_pill_class(@params["sort"] == value)}
            >
              {label}
            </button>
          </div>

          <%!-- Divider --%>
          <div class="border-t border-olive-200 dark:border-olive-700/60" />

          <%!-- Row 3: Colored signal pills with counts --%>
          <div class="flex flex-wrap items-center gap-1.5">
            <button
              type="button"
              phx-click="set_signal"
              phx-value-signal="all"
              class={sort_pill_class(@params["signal"] == "all")}
            >
              All {@total_cards}
            </button>
            <button
              :for={signal <- @signals}
              type="button"
              phx-click="set_signal"
              phx-value-signal={signal}
              class={signal_pill_class(signal, @params["signal"] == signal)}
            >
              {format_signal_label(signal)}
              <span class="ml-1 tabular-nums">
                {Map.get(@signal_summary, signal, 0)}
              </span>
            </button>

            <button
              :if={@params != @default_params}
              type="button"
              phx-click="clear_filters"
              class="ml-1 inline-flex items-center gap-1 text-xs font-medium text-olive-500 transition-colors hover:text-olive-700 dark:text-olive-400 dark:hover:text-olive-200"
            >
              <.icon name="hero-x-mark" class="h-3 w-3" />
              Clear
            </button>
          </div>
        </div>

        <%!-- Results count --%>
        <p class="mt-4 text-sm text-olive-500 dark:text-olive-500">
          {length(@predictions)} card{if length(@predictions) != 1, do: "s"}
        </p>

        <%!-- Card grid --%>
        <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <div
            :for={prediction <- @predictions}
            class="overflow-hidden rounded-2xl border border-olive-200 bg-white/60 dark:border-olive-800 dark:bg-olive-900/40"
          >
            <%!-- Card image --%>
            <div :if={prediction.card.image_url} class="aspect-[2/3] overflow-hidden bg-olive-100 dark:bg-olive-900">
              <img
                src={prediction.card.image_url}
                alt={prediction.card.name}
                loading="lazy"
                class="h-full w-full object-contain"
              />
            </div>

            <%!-- Card info --%>
            <div class="p-4">
              <div class="flex items-start justify-between">
                <div class="min-w-0 flex-1">
                  <h3 class="font-display text-base font-medium text-olive-950 dark:text-white">
                    {prediction.card.name}
                  </h3>
                  <p class="text-xs text-olive-500 dark:text-olive-500">
                    #{prediction.card.local_id}
                    <span :if={prediction.card.rarity}> &middot; {prediction.card.rarity}</span>
                  </p>
                </div>
                <.signal_badge signal={prediction.signal} />
              </div>

              <div class="mt-2">
                <.value_display
                  current_price={prediction.current_price}
                  predicted_fair_value={prediction.predicted_fair_value}
                  value_ratio={prediction.value_ratio}
                  price_currency={prediction.price_currency || "USD"}
                />
              </div>

              <%!-- Expand toggle --%>
              <button
                phx-click="toggle"
                phx-value-card-id={prediction.card_id}
                class="mt-3 w-full text-center text-xs text-olive-500 hover:text-olive-700 dark:text-olive-500 dark:hover:text-olive-300"
              >
                {if MapSet.member?(@expanded, prediction.card_id), do: "Hide details \u25B2", else: "Show details \u25BC"}
              </button>

              <%!-- Expanded panel --%>
              <div :if={MapSet.member?(@expanded, prediction.card_id)} class="mt-3 space-y-4 border-t border-olive-200 pt-3 dark:border-olive-800">
                <%!-- Umbrella breakdown --%>
                <div :if={prediction.umbrella_breakdown && prediction.umbrella_breakdown != %{}}>
                  <h4 class="mb-2 text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">
                    Value Drivers
                  </h4>
                  <.umbrella_breakdown breakdown={prediction.umbrella_breakdown} />
                </div>

                <%!-- Positive drivers --%>
                <div :if={prediction.top_positive_drivers && prediction.top_positive_drivers != %{}}>
                  <h4 class="mb-1 text-xs font-semibold uppercase tracking-wider text-emerald-600 dark:text-emerald-400">
                    Top Positive
                  </h4>
                  <.driver_list drivers={prediction.top_positive_drivers} kind={:positive} />
                </div>

                <%!-- Negative drivers --%>
                <div :if={prediction.top_negative_drivers && prediction.top_negative_drivers != %{}}>
                  <h4 class="mb-1 text-xs font-semibold uppercase tracking-wider text-red-600 dark:text-red-400">
                    Top Negative
                  </h4>
                  <.driver_list drivers={prediction.top_negative_drivers} kind={:negative} />
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Empty state --%>
        <div :if={@predictions == []} class="mt-12 flex flex-col items-center py-12 text-center">
          <.icon
            name="hero-magnifying-glass"
            class="h-12 w-12 text-olive-300 dark:text-olive-700"
          />
          <p class="mt-4 text-lg font-medium text-olive-700 dark:text-olive-400">
            No cards match your filters
          </p>
          <button
            type="button"
            phx-click="clear_filters"
            class="mt-3 text-sm font-medium text-olive-600 underline hover:text-olive-900 dark:text-olive-400 dark:hover:text-olive-200"
          >
            Clear all filters
          </button>
        </div>
      </.container>
    </.section>
    """
  end

  # --- Sort pill styling (olive theme, matches index page) ---

  @active_sort "rounded-full px-3 py-1 text-sm font-medium transition-colors bg-olive-950 text-white dark:bg-olive-100 dark:text-olive-950"
  @inactive_sort "rounded-full px-3 py-1 text-sm font-medium transition-colors bg-olive-200 text-olive-700 hover:bg-olive-300 dark:bg-olive-800 dark:text-olive-400 dark:hover:bg-olive-700"

  defp sort_pill_class(true), do: @active_sort
  defp sort_pill_class(_), do: @inactive_sort

  # --- Signal pill styling (colored per signal) ---

  @pill_base "inline-flex items-center rounded-full px-3 py-1 text-sm font-medium transition-colors cursor-pointer"

  defp signal_pill_class(signal, active?) do
    {inactive, active} = Map.get(@signal_pill_styles, signal, {@inactive_sort, @active_sort})
    [@pill_base, if(active?, do: active, else: inactive)]
  end

  # --- Query helpers ---

  defp fetch_predictions(set_id, params) do
    opts = [limit: 500, sort: params["sort"]]

    opts =
      if params["signal"] != "all",
        do: Keyword.put(opts, :signal, params["signal"]),
        else: opts

    opts =
      case params["q"] do
        q when q in [nil, ""] -> opts
        q -> Keyword.put(opts, :search, q)
      end

    opts =
      case parse_min_price(params["min_price"]) do
        nil -> opts
        price -> Keyword.put(opts, :min_price, price)
      end

    opts =
      if params["type"] not in [nil, "", "all"],
        do: Keyword.put(opts, :type, params["type"]),
        else: opts

    Predictions.list_for_set(set_id, opts)
  end

  defp parse_min_price(nil), do: nil
  defp parse_min_price(""), do: nil

  defp parse_min_price(str) do
    str = String.trim(str)

    case Decimal.parse(str) do
      {d, ""} -> if Decimal.compare(d, Decimal.new(0)) == :gt, do: d
      _ -> nil
    end
  end

  # --- URL helpers ---

  defp clean_params(params) do
    params
    |> Enum.reject(fn {k, v} -> Map.get(@default_params, k) == v end)
    |> Map.new()
  end

  defp format_signal_label(signal) do
    signal
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
