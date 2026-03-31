defmodule PokevestmentWeb.Layouts do
  @moduledoc """
  Layout components for PokevestmentWeb.
  """
  use PokevestmentWeb, :html

  import PokevestmentWeb.LandingComponents

  embed_templates "layouts/*"

  @doc """
  The app layout wraps page content with navbar, flash messages, and footer.
  """
  def app(assigns) do
    ~H"""
    <.navbar />
    <main>
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
    <.footer />
    """
  end
end
