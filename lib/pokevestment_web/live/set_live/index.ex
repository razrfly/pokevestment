defmodule PokevestmentWeb.SetLive.Index do
  use PokevestmentWeb, :live_view

  import Ecto.Query
  import PokevestmentWeb.LandingComponents
  import PokevestmentWeb.SetComponents

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Set
  alias Pokevestment.Predictions

  # Minimum card count to exclude tiny promo sets
  @min_cards 18
  # Minimum card count for sets without a logo (likely placeholder/unfeatured)
  @featured_min_cards 50

  @sort_options %{
    "date_desc" => [desc: :release_date],
    "date_asc" => [asc: :release_date],
    "name_asc" => [asc: :name],
    "name_desc" => [desc: :name],
    "cards_desc" => [desc_nulls_last: :card_count_total]
  }

  @sort_labels [
    {"Newest", "date_desc"},
    {"Oldest", "date_asc"},
    {"A\u2013Z", "name_asc"},
    {"Z\u2013A", "name_desc"},
    {"Most Cards", "cards_desc"}
  ]

  @era_labels [
    {"All Eras", "all"},
    {"WOTC", "wotc"},
    {"E-Series", "e_series"},
    {"EX", "ex"},
    {"Diamond & Pearl", "dp"},
    {"HeartGold/SoulSilver", "hgss"},
    {"Black & White", "bw"},
    {"XY", "xy"},
    {"Sun & Moon", "sm"},
    {"Sword & Shield", "swsh"},
    {"Scarlet & Violet", "sv"},
    {"Mega", "mega"}
  ]

  @legality_labels [
    {"All Formats", "all"},
    {"Standard", "standard"},
    {"Expanded", "expanded"}
  ]

  @default_params %{
    "sort" => "date_desc",
    "show_promos" => "false",
    "era" => "all",
    "legality" => "all",
    "q" => ""
  }

  # Shared base styling for search input and custom selects
  @input_class "rounded-xl border border-olive-200 bg-olive-50 text-sm text-olive-900 focus:border-olive-400 focus:bg-white focus:outline-none focus:ring-1 focus:ring-olive-400 dark:border-olive-700 dark:bg-olive-900/60 dark:text-olive-100 dark:focus:border-olive-600 dark:focus:bg-olive-900"

  @impl true
  def mount(_params, _session, socket) do
    signal_counts = build_signal_map(Predictions.signal_counts_by_set())

    {:ok,
     assign(socket,
       signal_counts: signal_counts,
       sort_labels: @sort_labels,
       era_labels: @era_labels,
       legality_labels: @legality_labels,
       default_params: @default_params,
       input_class: @input_class,
       page_title: "Sets"
     )}
  end

  @impl true
  def handle_params(url_params, _uri, socket) do
    params = Map.merge(@default_params, Map.take(url_params, Map.keys(@default_params)))
    sets = list_sets(params)

    {:noreply, assign(socket, sets: sets, params: params, set_count: length(sets))}
  end

  # Form change handles search input + era/legality dropdowns
  @impl true
  def handle_event("filter", form_params, socket) do
    params =
      socket.assigns.params
      |> Map.merge(Map.take(form_params, ~w(q era legality)))
      |> clean_params()

    {:noreply, push_patch(socket, to: ~p"/sets?#{params}")}
  end

  # Sort pill clicks
  def handle_event("set_filter", new_values, socket) do
    params =
      socket.assigns.params
      |> Map.merge(Map.take(new_values, ~w(sort)))
      |> clean_params()

    {:noreply, push_patch(socket, to: ~p"/sets?#{params}")}
  end

  def handle_event("toggle_promos", _params, socket) do
    show = if socket.assigns.params["show_promos"] == "true", do: "false", else: "true"

    params =
      socket.assigns.params
      |> Map.put("show_promos", show)
      |> clean_params()

    {:noreply, push_patch(socket, to: ~p"/sets?#{params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/sets")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.section class="pt-8 sm:pt-12">
      <.container>
        <.eyebrow>Browse by set</.eyebrow>
        <.heading class="mt-2">All Sets</.heading>
        <.subheading>
          Explore {@set_count} sets and discover investment signals.
        </.subheading>

        <%!-- Filter panel --%>
        <div class="mt-8 space-y-3 rounded-2xl border border-olive-200 bg-white/60 p-4 dark:border-olive-800 dark:bg-olive-900/40">
          <%!-- Row 1: Search + Era dropdown + Format dropdown --%>
          <form phx-change="filter" class="flex flex-col gap-2.5 sm:flex-row sm:items-center">
            <div class="flex-1 sm:max-w-xs">
              <input
                type="text"
                name="q"
                value={@params["q"]}
                placeholder="Search sets..."
                phx-debounce="300"
                class={[@input_class, "w-full py-2 px-3"]}
              />
            </div>

            <div class="relative">
              <select name="era" class={[@input_class, "w-full appearance-none py-2 pl-3 pr-8"]}>
                <option
                  :for={{label, value} <- @era_labels}
                  value={value}
                  selected={@params["era"] == value}
                >
                  {label}
                </option>
              </select>
              <.icon
                name="hero-chevron-down-mini"
                class="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-olive-400 dark:text-olive-500"
              />
            </div>

            <div class="relative">
              <select
                name="legality"
                class={[@input_class, "w-full appearance-none py-2 pl-3 pr-8"]}
              >
                <option
                  :for={{label, value} <- @legality_labels}
                  value={value}
                  selected={@params["legality"] == value}
                >
                  {label}
                </option>
              </select>
              <.icon
                name="hero-chevron-down-mini"
                class="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-olive-400 dark:text-olive-500"
              />
            </div>
          </form>

          <%!-- Row 2: Sort pills + Promos toggle + Clear --%>
          <div class="flex flex-wrap items-center gap-1.5">
            <button
              :for={{label, value} <- @sort_labels}
              type="button"
              phx-click="set_filter"
              phx-value-sort={value}
              class={pill_class(@params["sort"] == value)}
            >
              {label}
            </button>

            <span class="mx-1 h-4 w-px bg-olive-200 dark:bg-olive-700" />

            <button
              type="button"
              phx-click="toggle_promos"
              class={pill_class(@params["show_promos"] == "true")}
            >
              Promos & Digital
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

        <%!-- Empty state --%>
        <div :if={@sets == []} class="mt-16 flex flex-col items-center py-12 text-center">
          <.icon
            name="hero-magnifying-glass"
            class="h-12 w-12 text-olive-300 dark:text-olive-700"
          />
          <p class="mt-4 text-lg font-medium text-olive-700 dark:text-olive-400">
            No sets match your filters
          </p>
          <button
            type="button"
            phx-click="clear_filters"
            class="mt-3 text-sm font-medium text-olive-600 underline hover:text-olive-900 dark:text-olive-400 dark:hover:text-olive-200"
          >
            Clear all filters
          </button>
        </div>

        <%!-- Results grid --%>
        <div :if={@sets != []} class="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.link
            :for={set <- @sets}
            navigate={~p"/sets/#{set.id}"}
            class="group overflow-hidden rounded-2xl border border-olive-200 bg-white/60 transition-all hover:border-olive-400 hover:shadow-md dark:border-olive-800 dark:bg-olive-900/40 dark:hover:border-olive-600"
          >
            <%!-- Logo header zone --%>
            <div class="flex h-32 items-center justify-center bg-olive-50 px-6 dark:bg-olive-900/60">
              <.set_image set={set} size={:md} />
            </div>
            <%!-- Info section --%>
            <div class="p-4">
              <div class="flex items-start justify-between">
                <h3 class="font-display text-lg font-medium text-olive-950 group-hover:text-olive-700 dark:text-white dark:group-hover:text-olive-300">
                  {set.name}
                </h3>
                <span
                  :if={set.legal_standard}
                  class="ml-2 mt-0.5 inline-flex shrink-0 rounded-full bg-olive-200 px-2 py-0.5 text-xs font-medium text-olive-800 dark:bg-olive-800 dark:text-olive-300"
                >
                  Standard
                </span>
              </div>
              <div class="mt-1 flex flex-wrap items-center gap-2 text-sm text-olive-600 dark:text-olive-500">
                <span :if={set.release_date}>
                  {Calendar.strftime(set.release_date, "%b %Y")}
                </span>
                <span :if={set.card_count_total}>
                  · {set.card_count_total} cards
                </span>
              </div>
              <% count = buy_count(set.id, @signal_counts) %>
              <div :if={count > 0} class="mt-2">
                <span class="inline-flex items-center rounded-full bg-emerald-700/10 px-2.5 py-0.5 text-xs font-semibold text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-400">
                  {count} buy signal{if count != 1, do: "s"}
                </span>
              </div>
            </div>
          </.link>
        </div>
      </.container>
    </.section>
    """
  end

  # --- Pill styling ---

  @active_pill "rounded-full px-3 py-1 text-sm font-medium transition-colors bg-olive-950 text-white dark:bg-olive-100 dark:text-olive-950"
  @inactive_pill "rounded-full px-3 py-1 text-sm font-medium transition-colors bg-olive-200 text-olive-700 hover:bg-olive-300 dark:bg-olive-800 dark:text-olive-400 dark:hover:bg-olive-700"

  defp pill_class(true), do: @active_pill
  defp pill_class(_), do: @inactive_pill

  # --- Query pipeline ---

  defp list_sets(params) do
    Set
    |> filter_promos(params["show_promos"])
    |> filter_era(params["era"])
    |> filter_legality(params["legality"])
    |> filter_search(params["q"])
    |> apply_sort(params["sort"])
    |> Repo.all()
  end

  defp filter_promos(query, "true"), do: query

  defp filter_promos(query, _) do
    from(s in query,
      where: s.era != "promo" or is_nil(s.era),
      where: not ilike(s.name, "%Promo%"),
      where: s.card_count_total >= ^@min_cards or is_nil(s.card_count_total),
      where: s.card_count_total >= ^@featured_min_cards or not is_nil(s.logo_url) or is_nil(s.card_count_total)
    )
  end

  defp filter_era(query, "all"), do: query

  defp filter_era(query, era) do
    from(s in query, where: s.era == ^era)
  end

  defp filter_legality(query, "standard") do
    from(s in query, where: s.legal_standard == true)
  end

  defp filter_legality(query, "expanded") do
    from(s in query, where: s.legal_expanded == true)
  end

  defp filter_legality(query, _), do: query

  defp filter_search(query, q) when q in [nil, ""], do: query

  defp filter_search(query, q) do
    escaped = String.replace(q, ~r/[%_\\]/, fn c -> "\\#{c}" end)
    from(s in query, where: ilike(s.name, ^"%#{escaped}%"))
  end

  defp apply_sort(query, sort_key) do
    order = Map.get(@sort_options, sort_key, desc: :release_date)
    from(s in query, order_by: ^order)
  end

  # --- URL helpers ---

  defp clean_params(params) do
    params
    |> Enum.reject(fn {k, v} -> Map.get(@default_params, k) == v end)
    |> Map.new()
  end

  # --- Signal helpers ---

  defp build_signal_map(rows) do
    Enum.reduce(rows, %{}, fn %{set_id: set_id, signal: signal, count: count}, acc ->
      set_signals = Map.get(acc, set_id, %{})
      Map.put(acc, set_id, Map.put(set_signals, signal, count))
    end)
  end

  defp buy_count(set_id, signal_counts) do
    case Map.get(signal_counts, set_id) do
      nil -> 0
      signals -> Map.get(signals, "BUY", 0) + Map.get(signals, "STRONG_BUY", 0)
    end
  end
end
