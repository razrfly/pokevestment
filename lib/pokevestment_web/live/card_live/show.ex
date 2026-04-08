defmodule PokevestmentWeb.CardLive.Show do
  use PokevestmentWeb, :live_view

  import PokevestmentWeb.LandingComponents
  import PokevestmentWeb.PredictionComponents

  alias Pokevestment.Predictions

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"set_id" => set_id, "card_id" => card_id}, _uri, socket) do
    prediction = Predictions.get_card_prediction(card_id)

    cond do
      is_nil(prediction) ->
        {:noreply,
         socket
         |> put_flash(:error, "Card not found")
         |> push_navigate(to: ~p"/sets/#{set_id}")}

      prediction.card.set_id != set_id ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/sets/#{prediction.card.set_id}/cards/#{card_id}")}

      true ->
        marketplace_urls = Predictions.marketplace_urls_for_cards([card_id])

        card = prediction.card
        types = Enum.map(card.card_types, & &1.type_name)

        {:noreply,
         assign(socket,
           prediction: prediction,
           card: card,
           set: card.set,
           types: types,
           marketplace_urls: Map.get(marketplace_urls, card_id, %{}),
           page_title: "#{card.name} — #{card.set.name}"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.section class="pt-8 sm:pt-12">
      <.container>
        <%!-- Breadcrumb --%>
        <nav class="flex items-center gap-2 text-sm text-olive-500 dark:text-olive-500">
          <.link navigate={~p"/sets"} class="hover:text-olive-700 dark:hover:text-olive-300">
            Sets
          </.link>
          <span>&rsaquo;</span>
          <.link navigate={~p"/sets/#{@set.id}"} class="hover:text-olive-700 dark:hover:text-olive-300">
            {@set.name}
          </.link>
          <span>&rsaquo;</span>
          <span class="text-olive-700 dark:text-olive-300">{@card.name}</span>
        </nav>

        <%!-- Two-column layout --%>
        <div class="mt-6 grid grid-cols-1 gap-8 lg:grid-cols-2">
          <%!-- Left column: Card image --%>
          <div class="flex justify-center lg:justify-start">
            <div class="w-full max-w-sm">
              <img
                :if={@card.image_url}
                src={@card.image_url}
                alt={@card.name}
                class="w-full max-h-[600px] rounded-2xl object-contain shadow-lg"
              />
              <div
                :if={is_nil(@card.image_url)}
                class="flex aspect-[2/3] items-center justify-center rounded-2xl bg-olive-100 dark:bg-olive-900"
              >
                <span class="text-olive-400 dark:text-olive-600">No image</span>
              </div>
            </div>
          </div>

          <%!-- Right column: Stacked info cards --%>
          <div class="space-y-4">
            <%!-- 1. Card header --%>
            <div class="rounded-2xl border border-olive-200 bg-white/60 p-5 dark:border-olive-800 dark:bg-olive-900/40">
              <div class="flex items-start justify-between">
                <div>
                  <h1 class="font-display text-2xl font-medium tracking-tight text-olive-950 dark:text-white sm:text-3xl">
                    {@card.name}
                  </h1>
                  <div class="mt-1 flex flex-wrap items-center gap-2 text-sm text-olive-600 dark:text-olive-500">
                    <span>#{@card.local_id}</span>
                    <span :if={@card.rarity}>&middot; {@card.rarity}</span>
                    <span :if={@card.illustrator}>&middot; {@card.illustrator}</span>
                  </div>
                </div>
                <.signal_badge signal={@prediction.signal} />
              </div>

              <div :if={@types != []} class="mt-3 flex flex-wrap gap-1.5">
                <span
                  :for={type <- @types}
                  class="inline-flex rounded-full bg-olive-200 px-2.5 py-0.5 text-xs font-medium text-olive-800 dark:bg-olive-800 dark:text-olive-300"
                >
                  {type}
                </span>
              </div>
            </div>

            <%!-- 2. Price & Value --%>
            <div class="rounded-2xl border border-olive-200 bg-white/60 p-5 dark:border-olive-800 dark:bg-olive-900/40">
              <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">
                Price & Value
              </h2>
              <.value_display
                current_price={@prediction.current_price}
                predicted_fair_value={@prediction.predicted_fair_value}
                value_ratio={@prediction.value_ratio}
                price_currency={@prediction.price_currency}
              />
              <.marketplace_link
                :if={@marketplace_urls != %{}}
                urls={@marketplace_urls}
                price_source={@prediction.price_source}
              />
            </div>

            <%!-- 3. Analysis --%>
            <div
              :if={is_map(@prediction.explanation)}
              class="rounded-2xl border border-olive-200 bg-white/60 p-5 dark:border-olive-800 dark:bg-olive-900/40"
            >
              <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">
                Analysis
              </h2>
              <.explanation_panel explanation={@prediction.explanation} />
            </div>

            <%!-- 4. Price Projections --%>
            <div
              :if={@prediction.horizon_projections && @prediction.horizon_projections != %{}}
              class="rounded-2xl border border-olive-200 bg-white/60 p-5 dark:border-olive-800 dark:bg-olive-900/40"
            >
              <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">
                Price Projections
              </h2>
              <.projection_table
                projections={@prediction.horizon_projections}
                currency={@prediction.price_currency}
              />
            </div>

            <%!-- 5. Value Drivers --%>
            <div
              :if={has_driver_data?(@prediction)}
              class="rounded-2xl border border-olive-200 bg-white/60 p-5 dark:border-olive-800 dark:bg-olive-900/40"
            >
              <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-olive-500 dark:text-olive-500">
                Value Drivers
              </h2>

              <div :if={@prediction.umbrella_breakdown && @prediction.umbrella_breakdown != %{}}>
                <.umbrella_breakdown breakdown={@prediction.umbrella_breakdown} />
              </div>

              <div class="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div :if={@prediction.top_positive_drivers && @prediction.top_positive_drivers != %{}}>
                  <h3 class="mb-1.5 text-xs font-semibold uppercase tracking-wider text-emerald-600 dark:text-emerald-400">
                    Positive
                  </h3>
                  <.driver_list drivers={@prediction.top_positive_drivers} kind={:positive} />
                </div>
                <div :if={@prediction.top_negative_drivers && @prediction.top_negative_drivers != %{}}>
                  <h3 class="mb-1.5 text-xs font-semibold uppercase tracking-wider text-red-600 dark:text-red-400">
                    Negative
                  </h3>
                  <.driver_list drivers={@prediction.top_negative_drivers} kind={:negative} />
                </div>
              </div>
            </div>
          </div>
        </div>
      </.container>
    </.section>
    """
  end

  defp has_driver_data?(prediction) do
    (prediction.umbrella_breakdown && prediction.umbrella_breakdown != %{}) ||
      (prediction.top_positive_drivers && prediction.top_positive_drivers != %{}) ||
      (prediction.top_negative_drivers && prediction.top_negative_drivers != %{})
  end
end
