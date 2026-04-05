defmodule PokevestmentWeb.HomeLive do
  use PokevestmentWeb, :live_view

  import PokevestmentWeb.LandingComponents
  import PokevestmentWeb.PredictionComponents
  import PokevestmentWeb.SetComponents

  alias Pokevestment.Predictions

  @signal_order [
    {"STRONG_BUY", "bg-emerald-500", "Strong Buy"},
    {"BUY", "bg-lime-500", "Buy"},
    {"HOLD", "bg-olive-500", "Hold"},
    {"OVERVALUED", "bg-red-500", "Overvalued"},
    {"INSUFFICIENT_DATA", "bg-gray-400", "No Data"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    top_buys = Predictions.top_buys(8)
    signal_summary = Predictions.global_signal_summary()
    top_sets = Predictions.top_sets_by_signals(4)
    stats = Predictions.homepage_stats()
    last_updated = Predictions.last_prediction_date()

    {:ok,
     assign(socket,
       page_title: "Home",
       top_buys: top_buys,
       signal_summary: signal_summary,
       top_sets: top_sets,
       stats: stats,
       last_updated: last_updated
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Hero Section --%>
    <.section class="pt-24 sm:pt-32">
      <.container>
        <div class="max-w-2xl">
          <.eyebrow>Investment intelligence</.eyebrow>
          <h1 class="mt-4 font-display text-5xl font-medium tracking-tight text-olive-950 dark:text-white sm:text-6xl">
            Data-driven Pokemon card investment insights.
          </h1>
          <.subheading>
            Track prices, analyze tournament meta, and discover undervalued cards — powered by real tournament data and market analysis.
          </.subheading>
          <div class="mt-8 flex items-center gap-4">
            <.button variant="primary" href="/sets">Get Started</.button>
            <.button variant="plain" href="#features">See how it works</.button>
          </div>
          <p :if={@last_updated} class="mt-4 text-xs text-olive-500 dark:text-olive-600">
            Signals last updated {Calendar.strftime(@last_updated, "%B %d, %Y")}
          </p>
        </div>
      </.container>
    </.section>

    <%!-- Today's Best Buys --%>
    <.section :if={@top_buys != []} id="best-buys" class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <.eyebrow>Top picks</.eyebrow>
        <.heading class="mt-2">
          Today's Best Buys
        </.heading>

        <div class="mt-10 -mx-6 px-6 lg:-mx-8 lg:px-8">
          <div class="flex gap-4 overflow-x-auto pb-4 snap-x snap-mandatory scrollbar-thin scrollbar-thumb-olive-300 dark:scrollbar-thumb-olive-700">
            <.buy_card :for={prediction <- @top_buys} prediction={prediction} />
          </div>
        </div>
      </.container>
    </.section>

    <%!-- Hot Sets --%>
    <.section :if={@top_sets != []} id="hot-sets" class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <.eyebrow>Trending</.eyebrow>
        <.heading class="mt-2">
          Hot Sets
        </.heading>

        <div class="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <.link
            :for={{set, count} <- @top_sets}
            navigate={~p"/sets/#{set.id}"}
            class="group flex items-center gap-4 rounded-2xl border border-olive-200 bg-white/60 p-4 transition-colors hover:border-olive-300 hover:bg-white dark:border-olive-800 dark:bg-olive-900/40 dark:hover:border-olive-700 dark:hover:bg-olive-900/60"
          >
            <.set_image set={set} size={:sm} />
            <div class="min-w-0 flex-1">
              <h3 class="truncate font-display text-sm font-medium text-olive-950 group-hover:text-olive-700 dark:text-white dark:group-hover:text-olive-200">
                {set.name}
              </h3>
              <p class="mt-0.5 text-xs text-olive-500 dark:text-olive-500">
                {count} buy signal{if count != 1, do: "s"}
              </p>
            </div>
          </.link>
        </div>
      </.container>
    </.section>

    <%!-- Live Stats --%>
    <.section id="stats" class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <div class="text-center">
          <.eyebrow>Built on real data</.eyebrow>
          <.heading class="mx-auto mt-2">
            The numbers behind the insights.
          </.heading>
        </div>

        <dl class="mt-12 flex flex-col items-center gap-8 sm:flex-row sm:justify-center sm:gap-16">
          <.stat value={format_number(@stats.cards)} label="Cards Tracked" />
          <.stat value={format_number(@stats.tournaments)} label="Tournaments Analyzed" />
          <.stat value={format_number(@stats.sets)} label="Sets Covered" />
        </dl>
      </.container>
    </.section>

    <%!-- Market Overview --%>
    <.section :if={@signal_summary != %{}} id="market" class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <div class="text-center">
          <.eyebrow>Market overview</.eyebrow>
          <.heading class="mx-auto mt-2">
            Signal Distribution
          </.heading>
        </div>

        <div class="mx-auto mt-10 max-w-2xl">
          <.signal_bar summary={@signal_summary} />
        </div>
      </.container>
    </.section>

    <%!-- Features Section --%>
    <.section id="features" class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <.eyebrow>Powerful insights</.eyebrow>
        <.heading class="mt-2">
          Everything you need to make smarter Pokemon card investments.
        </.heading>

        <div class="mt-12 grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-3">
          <.feature_card title="Tournament Meta Analysis">
            <:icon>
              <svg class="h-5 w-5 text-white dark:text-olive-950" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 18.75h-9m9 0a3 3 0 0 1 3 3h-15a3 3 0 0 1 3-3m9 0v-3.375c0-.621-.503-1.125-1.125-1.125h-.871M7.5 18.75v-3.375c0-.621.504-1.125 1.125-1.125h.872m5.007 0H9.497m5.007 0a7.454 7.454 0 0 1-.982-3.172M9.497 14.25a7.454 7.454 0 0 0 .981-3.172M5.25 4.236c-.982.143-1.954.317-2.916.52A6.003 6.003 0 0 0 7.73 9.728M5.25 4.236V4.5c0 2.108.966 3.99 2.48 5.228M5.25 4.236V2.721C7.456 2.41 9.71 2.25 12 2.25c2.291 0 4.545.16 6.75.47v1.516M18.75 4.236c.982.143 1.954.317 2.916.52A6.003 6.003 0 0 1 16.27 9.728M18.75 4.236V4.5c0 2.108-.966 3.99-2.48 5.228m0 0a6.023 6.023 0 0 1-2.52.587 6.023 6.023 0 0 1-2.52-.587" />
              </svg>
            </:icon>
            Track winning deck compositions across all major tournaments. Identify cards gaining competitive traction before prices move.
          </.feature_card>

          <.feature_card title="Price Intelligence">
            <:icon>
              <svg class="h-5 w-5 text-white dark:text-olive-950" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 18 9 11.25l4.306 4.306a11.95 11.95 0 0 1 5.814-5.518l2.74-1.22m0 0-5.94-2.281m5.94 2.28-2.28 5.941" />
              </svg>
            </:icon>
            Daily price tracking with historical trends. Spot undervalued cards and emerging price patterns across the entire market.
          </.feature_card>

          <.feature_card title="Investment Signals">
            <:icon>
              <svg class="h-5 w-5 text-white dark:text-olive-950" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5m.75-9 3-3 2.148 2.148A12.061 12.061 0 0 1 16.5 7.605" />
              </svg>
            </:icon>
            Our 7-umbrella scoring system analyzes tournament power, rarity, price action, and more to surface the best opportunities.
          </.feature_card>
        </div>
      </.container>
    </.section>

    <%!-- CTA Section --%>
    <.section id="cta" class="border-t border-olive-200 dark:border-olive-800">
      <.container>
        <div class="mx-auto max-w-2xl text-center">
          <.heading>Ready to invest smarter?</.heading>
          <.text class="mt-4">
            Join investors using real tournament data and market analysis to make better Pokemon card decisions.
          </.text>
          <div class="mt-8">
            <.button variant="primary" href="/sets">Get Started</.button>
          </div>
        </div>
      </.container>
    </.section>
    """
  end

  # --- Private components ---

  defp buy_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/sets/#{@prediction.card.set_id}"}
      class="group flex-shrink-0 snap-start w-56 rounded-2xl border border-olive-200 bg-white/60 overflow-hidden transition-colors hover:border-olive-300 hover:bg-white dark:border-olive-800 dark:bg-olive-900/40 dark:hover:border-olive-700 dark:hover:bg-olive-900/60"
    >
      <div :if={@prediction.card.image_url} class="aspect-[2/3] overflow-hidden bg-olive-100 dark:bg-olive-900">
        <img
          src={@prediction.card.image_url}
          alt={@prediction.card.name}
          loading="lazy"
          class="h-full w-full object-contain transition-transform group-hover:scale-105"
        />
      </div>
      <div class="p-3">
        <div class="flex items-start justify-between gap-1">
          <h3 class="truncate text-sm font-medium text-olive-950 dark:text-white">
            {@prediction.card.name}
          </h3>
          <.signal_badge signal={@prediction.signal} />
        </div>
        <div class="mt-1">
          <.value_display
            current_price={@prediction.current_price}
            predicted_fair_value={@prediction.predicted_fair_value}
            value_ratio={@prediction.value_ratio}
            price_currency={@prediction.price_currency}
          />
        </div>
      </div>
    </.link>
    """
  end

  defp signal_bar(assigns) do
    total = Enum.sum(Map.values(assigns.summary))
    assigns = assign(assigns, total: total, signal_order: @signal_order)

    ~H"""
    <div :if={@total > 0}>
      <%!-- Stacked bar --%>
      <div class="flex h-6 overflow-hidden rounded-full">
        <div
          :for={{signal, color, label} <- @signal_order}
          :if={Map.get(@summary, signal, 0) > 0}
          class={[color, "transition-all"]}
          style={"width: #{Map.get(@summary, signal, 0) / @total * 100}%"}
          title={"#{label}: #{Map.get(@summary, signal, 0)}"}
        />
      </div>

      <%!-- Legend --%>
      <div class="mt-4 flex flex-wrap justify-center gap-x-6 gap-y-2">
        <div
          :for={{signal, color, label} <- @signal_order}
          :if={Map.get(@summary, signal, 0) > 0}
          class="flex items-center gap-2 text-sm text-olive-700 dark:text-olive-400"
        >
          <span class={["inline-block h-3 w-3 rounded-full", color]} />
          <span>{label}</span>
          <span class="tabular-nums font-medium text-olive-900 dark:text-olive-200">
            {format_number(Map.get(@summary, signal, 0))}
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp format_number(n) when n >= 1000 do
    Integer.to_string(div(n, 1000)) <> "," <> String.pad_leading(Integer.to_string(rem(n, 1000)), 3, "0")
  end

  defp format_number(n), do: Integer.to_string(n)
end
