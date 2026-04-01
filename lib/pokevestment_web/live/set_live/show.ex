defmodule PokevestmentWeb.SetLive.Show do
  use PokevestmentWeb, :live_view

  import PokevestmentWeb.LandingComponents
  import PokevestmentWeb.PredictionComponents
  import PokevestmentWeb.SetComponents

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Set
  alias Pokevestment.Predictions

  @signals ["STRONG_BUY", "BUY", "HOLD", "OVERVALUED", "INSUFFICIENT_DATA"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, expanded: MapSet.new())}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    set = Repo.get!(Set, id)
    signal_summary = Predictions.signal_summary_for_set(id)
    predictions = Predictions.list_for_set(id, limit: 500)

    {:noreply,
     assign(socket,
       set: set,
       signal_summary: signal_summary,
       predictions: predictions,
       signal_filter: "all",
       page_title: set.name
     )}
  end

  @impl true
  def handle_event("filter", %{"signal" => signal}, socket) do
    opts =
      if signal == "all",
        do: [limit: 500],
        else: [signal: signal, limit: 500]

    predictions = Predictions.list_for_set(socket.assigns.set.id, opts)
    {:noreply, assign(socket, predictions: predictions, signal_filter: signal)}
  end

  @impl true
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
            ← All Sets
          </.link>
          <div class="mt-2 flex items-start gap-5">
            <.set_image set={@set} size={:lg} />
            <div>
              <h1 class="font-display text-3xl font-medium tracking-tight text-olive-950 dark:text-white sm:text-4xl">
                {@set.name}
              </h1>
              <div class="mt-2 flex flex-wrap items-center gap-3 text-sm text-olive-600 dark:text-olive-500">
                <span :if={@set.release_date}>{Calendar.strftime(@set.release_date, "%B %d, %Y")}</span>
                <span :if={@set.card_count_total}>· {@set.card_count_total} cards</span>
                <span :if={@set.era}>· {@set.era}</span>
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

        <%!-- Signal summary pills --%>
        <div :if={@signal_summary != %{}} class="mt-4 flex flex-wrap gap-2">
          <span
            :for={{signal, count} <- Enum.sort_by(@signal_summary, fn {s, _} -> Enum.find_index(@signals, &(&1 == s)) || 99 end)}
            class="inline-flex items-center gap-1"
          >
            <.signal_badge signal={signal} />
            <span class="text-xs text-olive-600 dark:text-olive-500">{count}</span>
          </span>
        </div>

        <%!-- Filter bar --%>
        <div class="mt-6 flex flex-wrap gap-2">
          <button
            phx-click="filter"
            phx-value-signal="all"
            class={[
              "rounded-full px-3 py-1 text-sm font-medium transition-colors",
              if(@signal_filter == "all",
                do: "bg-olive-950 text-white dark:bg-olive-100 dark:text-olive-950",
                else: "bg-olive-200 text-olive-700 hover:bg-olive-300 dark:bg-olive-800 dark:text-olive-400 dark:hover:bg-olive-700"
              )
            ]}
          >
            All
          </button>
          <button
            :for={signal <- @signals}
            phx-click="filter"
            phx-value-signal={signal}
            class={[
              "rounded-full px-3 py-1 text-sm font-medium transition-colors",
              if(@signal_filter == signal,
                do: "bg-olive-950 text-white dark:bg-olive-100 dark:text-olive-950",
                else: "bg-olive-200 text-olive-700 hover:bg-olive-300 dark:bg-olive-800 dark:text-olive-400 dark:hover:bg-olive-700"
              )
            ]}
          >
            {format_signal_label(signal)}
          </button>
        </div>

        <%!-- Card grid --%>
        <div class="mt-8 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
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
                    <span :if={prediction.card.rarity}> · {prediction.card.rarity}</span>
                  </p>
                </div>
                <.signal_badge signal={prediction.signal} />
              </div>

              <div class="mt-2">
                <.value_display
                  current_price={prediction.current_price}
                  predicted_fair_value={prediction.predicted_fair_value}
                  value_ratio={prediction.value_ratio}
                />
              </div>

              <%!-- Expand toggle --%>
              <button
                phx-click="toggle"
                phx-value-card-id={prediction.card_id}
                class="mt-3 w-full text-center text-xs text-olive-500 hover:text-olive-700 dark:text-olive-500 dark:hover:text-olive-300"
              >
                {if MapSet.member?(@expanded, prediction.card_id), do: "Hide details ▲", else: "Show details ▼"}
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
        <div :if={@predictions == []} class="mt-12 text-center">
          <p class="text-olive-500 dark:text-olive-500">
            No predictions available for this set yet.
          </p>
        </div>
      </.container>
    </.section>
    """
  end

  defp format_signal_label(signal) do
    signal
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
