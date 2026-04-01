defmodule PokevestmentWeb.SetLive.Index do
  use PokevestmentWeb, :live_view

  import Ecto.Query
  import PokevestmentWeb.LandingComponents

  alias Pokevestment.Repo
  alias Pokevestment.Cards.Set
  alias Pokevestment.Predictions

  @impl true
  def mount(_params, _session, socket) do
    sets =
      from(s in Set, order_by: [desc: s.release_date])
      |> Repo.all()

    signal_counts = build_signal_map(Predictions.signal_counts_by_set())

    {:ok, assign(socket, sets: sets, signal_counts: signal_counts, page_title: "Sets")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.section class="pt-8 sm:pt-12">
      <.container>
        <.eyebrow>Browse by set</.eyebrow>
        <.heading class="mt-2">All Sets</.heading>
        <.subheading>
          Explore {length(@sets)} sets and discover investment signals.
        </.subheading>

        <div class="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.link
            :for={set <- @sets}
            navigate={~p"/sets/#{set.id}"}
            class="group rounded-2xl border border-olive-200 bg-white/60 p-6 transition-all hover:border-olive-400 hover:shadow-md dark:border-olive-800 dark:bg-olive-900/40 dark:hover:border-olive-600"
          >
            <div class="flex items-start gap-4">
              <div class="flex-shrink-0">
                <img
                  :if={set.logo_url}
                  src={"#{set.logo_url}.png"}
                  alt={"#{set.name} logo"}
                  loading="lazy"
                  class="h-12 w-auto object-contain"
                />
                <img
                  :if={!set.logo_url && set.symbol_url}
                  src={"#{set.symbol_url}.png"}
                  alt={"#{set.name} symbol"}
                  loading="lazy"
                  class="h-12 w-auto object-contain"
                />
                <div
                  :if={!set.logo_url && !set.symbol_url}
                  class="flex h-12 w-12 items-center justify-center rounded-lg bg-olive-200 dark:bg-olive-800"
                >
                  <span class="font-display text-lg font-medium text-olive-600 dark:text-olive-400">
                    {String.first(set.name)}
                  </span>
                </div>
              </div>
              <div class="flex min-w-0 flex-1 items-start justify-between">
                <div class="min-w-0 flex-1">
                  <h3 class="font-display text-lg font-medium text-olive-950 group-hover:text-olive-700 dark:text-white dark:group-hover:text-olive-300">
                    {set.name}
                  </h3>
                  <div class="mt-1 flex flex-wrap items-center gap-2 text-sm text-olive-600 dark:text-olive-500">
                    <span :if={set.release_date}>
                      {Calendar.strftime(set.release_date, "%b %Y")}
                    </span>
                    <span :if={set.card_count_total}>
                      · {set.card_count_total} cards
                    </span>
                  </div>
                </div>
                <div class="ml-3 flex flex-col items-end gap-1">
                  <span
                    :if={set.legal_standard}
                    class="inline-flex rounded-full bg-olive-200 px-2 py-0.5 text-xs font-medium text-olive-800 dark:bg-olive-800 dark:text-olive-300"
                  >
                    Standard
                  </span>
                </div>
              </div>
            </div>
            <% count = buy_count(set.id, @signal_counts) %>
            <div :if={count > 0} class="mt-3">
              <span class="inline-flex items-center rounded-full bg-emerald-700/10 px-2.5 py-0.5 text-xs font-semibold text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-400">
                {count} buy signal{if count != 1, do: "s"}
              </span>
            </div>
          </.link>
        </div>
      </.container>
    </.section>
    """
  end

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
