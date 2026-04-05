defmodule PokevestmentWeb.SetComponents do
  @moduledoc """
  Shared components for set display across LiveViews.
  """
  use Phoenix.Component

  attr :set, :map, required: true
  attr :size, :atom, default: :sm, values: [:sm, :md, :lg]

  def set_image(assigns) do
    ~H"""
    <div class="flex-shrink-0">
      <img
        :if={@set.logo_url}
        src={"#{@set.logo_url}.png"}
        alt={"#{@set.name} logo"}
        loading="lazy"
        class={img_class(@size)}
      />
      <img
        :if={!@set.logo_url && @set.symbol_url}
        src={"#{@set.symbol_url}.png"}
        alt={"#{@set.name} symbol"}
        loading="lazy"
        class={img_class(@size)}
      />
      <div
        :if={!@set.logo_url && !@set.symbol_url}
        class={placeholder_class(@size)}
      >
        <span class={text_class(@size)}>
          {String.first(@set.name)}
        </span>
      </div>
    </div>
    """
  end

  defp img_class(:sm), do: "h-12 w-16 object-contain"
  defp img_class(:md), do: "h-24 w-36 object-contain"
  defp img_class(:lg), do: "h-28 w-40 object-contain sm:h-32 sm:w-48"

  defp placeholder_class(:sm),
    do: "flex h-12 w-12 items-center justify-center rounded-lg bg-olive-200 dark:bg-olive-800"

  defp placeholder_class(:md),
    do: "flex h-24 w-24 items-center justify-center rounded-lg bg-olive-200 dark:bg-olive-800"

  defp placeholder_class(:lg),
    do: "flex h-28 w-28 items-center justify-center rounded-lg bg-olive-200 sm:h-32 sm:w-32 dark:bg-olive-800"

  defp text_class(:sm),
    do: "font-display text-lg font-medium text-olive-600 dark:text-olive-400"

  defp text_class(:md),
    do: "font-display text-xl font-medium text-olive-600 dark:text-olive-400"

  defp text_class(:lg),
    do: "font-display text-2xl font-medium text-olive-600 sm:text-3xl dark:text-olive-400"
end
