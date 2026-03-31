defmodule PokevestmentWeb.LandingComponents do
  @moduledoc """
  Oatmeal Olive Instrument theme components for the landing page.
  Translated from the TSX component library patterns.
  """
  use Phoenix.Component

  # Container

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def container(assigns) do
    ~H"""
    <div class={["mx-auto max-w-7xl px-6 lg:px-8", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # Eyebrow

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <p class={[
      "font-body text-sm font-semibold uppercase tracking-widest text-olive-500 dark:text-olive-400",
      @class
    ]} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  # Heading

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def heading(assigns) do
    ~H"""
    <h2 class={[
      "font-display text-4xl font-medium tracking-tight text-olive-950 dark:text-white sm:text-5xl",
      @class
    ]} {@rest}>
      {render_slot(@inner_block)}
    </h2>
    """
  end

  # Subheading

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def subheading(assigns) do
    ~H"""
    <p class={[
      "mt-4 max-w-2xl text-lg font-medium text-olive-700 dark:text-olive-400",
      @class
    ]} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  # Text

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def text(assigns) do
    ~H"""
    <p class={[
      "text-base/7 text-olive-700 dark:text-olive-300",
      @class
    ]} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  # Button

  attr :variant, :string, default: "primary", values: ["primary", "secondary", "plain"]
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(href navigate patch)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <.link class={[
      "inline-flex items-center justify-center rounded-full px-6 py-2.5 text-sm font-semibold transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2",
      @variant == "primary" && "bg-olive-950 text-white hover:bg-olive-800 focus-visible:outline-olive-950 dark:bg-olive-100 dark:text-olive-950 dark:hover:bg-olive-200",
      @variant == "secondary" && "border border-olive-300 text-olive-700 hover:bg-olive-200 dark:border-olive-700 dark:text-olive-300 dark:hover:bg-olive-800",
      @variant == "plain" && "text-olive-700 hover:text-olive-950 dark:text-olive-400 dark:hover:text-white",
      @class
    ]} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # Section

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section class={["py-16 sm:py-24", @class]} {@rest}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  # Feature Card

  attr :title, :string, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  slot :icon
  slot :inner_block, required: true

  def feature_card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl border border-olive-200 bg-white/60 p-8 dark:border-olive-800 dark:bg-olive-900/40",
      @class
    ]} {@rest}>
      <div :if={@icon != []} class="mb-4 flex h-10 w-10 items-center justify-center rounded-lg bg-olive-950 dark:bg-olive-100">
        {render_slot(@icon)}
      </div>
      <h3 class="font-display text-lg font-medium text-olive-950 dark:text-white">
        <%= @title %>
      </h3>
      <p class="mt-2 text-sm/6 text-olive-700 dark:text-olive-400">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end

  # Stat

  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :class, :string, default: nil

  def stat(assigns) do
    ~H"""
    <div class={["flex flex-col items-center", @class]}>
      <dt class="font-display text-4xl font-medium tracking-tight text-olive-950 dark:text-white">
        <%= @value %>
      </dt>
      <dd class="mt-1 text-sm text-olive-700 dark:text-olive-400">
        <%= @label %>
      </dd>
    </div>
    """
  end

  # Navbar

  attr :class, :string, default: nil

  def navbar(assigns) do
    ~H"""
    <header class={[
      "sticky top-0 z-40 border-b border-olive-200 bg-olive-100/80 backdrop-blur-sm dark:border-olive-800 dark:bg-olive-950/80",
      @class
    ]}>
      <.container>
        <nav class="flex h-16 items-center justify-between">
          <a href="/" class="font-display text-xl text-olive-950 dark:text-white">
            Pokevestment
          </a>
          <div class="hidden items-center gap-8 sm:flex">
            <a href="#features" class="text-sm text-olive-700 hover:text-olive-950 dark:text-olive-400 dark:hover:text-white">
              Features
            </a>
            <a href="#stats" class="text-sm text-olive-700 hover:text-olive-950 dark:text-olive-400 dark:hover:text-white">
              Data
            </a>
            <a href="#cta" class="text-sm text-olive-700 hover:text-olive-950 dark:text-olive-400 dark:hover:text-white">
              About
            </a>
            <.button variant="primary" href="#">Get Started</.button>
          </div>
        </nav>
      </.container>
    </header>
    """
  end

  # Footer

  attr :class, :string, default: nil

  def footer(assigns) do
    ~H"""
    <footer class={[
      "border-t border-olive-200 bg-olive-100 dark:border-olive-800 dark:bg-olive-950",
      @class
    ]}>
      <.container class="py-12">
        <div class="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-4">
          <%!-- Brand --%>
          <div class="lg:col-span-1">
            <a href="/" class="font-display text-xl text-olive-950 dark:text-white">
              Pokevestment
            </a>
            <p class="mt-3 text-sm text-olive-700 dark:text-olive-400">
              Data-driven Pokemon card investment insights powered by tournament and market data.
            </p>
          </div>

          <%!-- Product --%>
          <div>
            <h3 class="text-sm font-semibold text-olive-950 dark:text-white">Product</h3>
            <ul class="mt-3 space-y-2">
              <li><a href="#features" class="text-sm text-olive-700 hover:text-olive-950 dark:text-olive-400 dark:hover:text-white">Features</a></li>
              <li><a href="#stats" class="text-sm text-olive-700 hover:text-olive-950 dark:text-olive-400 dark:hover:text-white">Data</a></li>
            </ul>
          </div>

          <%!-- Resources --%>
          <div>
            <h3 class="text-sm font-semibold text-olive-950 dark:text-white">Resources</h3>
            <ul class="mt-3 space-y-2">
              <li><a href="/api/health" class="text-sm text-olive-700 hover:text-olive-950 dark:text-olive-400 dark:hover:text-white">API Status</a></li>
            </ul>
          </div>

          <%!-- Legal --%>
          <div>
            <h3 class="text-sm font-semibold text-olive-950 dark:text-white">Legal</h3>
            <ul class="mt-3 space-y-2">
              <li><span class="text-sm text-olive-500 dark:text-olive-600">Privacy Policy</span></li>
              <li><span class="text-sm text-olive-500 dark:text-olive-600">Terms of Service</span></li>
            </ul>
          </div>
        </div>

        <div class="mt-12 border-t border-olive-200 pt-8 dark:border-olive-800">
          <p class="text-center text-xs text-olive-500 dark:text-olive-600">
            &copy; <%= DateTime.utc_now().year %> Pokevestment. Not affiliated with The Pokemon Company.
          </p>
        </div>
      </.container>
    </footer>
    """
  end
end
