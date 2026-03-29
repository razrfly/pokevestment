defmodule Pokevestment.Helpers do
  @moduledoc """
  Shared utility functions used across ingestion modules and mix tasks.
  """

  @doc """
  Format a duration in milliseconds to a human-readable string.

  ## Examples

      iex> Pokevestment.Helpers.format_duration(500)
      "500ms"

      iex> Pokevestment.Helpers.format_duration(45_000)
      "45.0s"

      iex> Pokevestment.Helpers.format_duration(125_000)
      "2m 5.0s"
  """
  def format_duration(ms) when ms < 1_000, do: "#{ms}ms"
  def format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"

  def format_duration(ms) do
    minutes = div(ms, 60_000)
    seconds = Float.round(rem(ms, 60_000) / 1_000, 1)
    "#{minutes}m #{seconds}s"
  end
end
