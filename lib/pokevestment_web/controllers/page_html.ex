defmodule PokevestmentWeb.PageHTML do
  @moduledoc """
  HTML views for page controller.
  """
  use PokevestmentWeb, :html

  import PokevestmentWeb.LandingComponents

  embed_templates "page_html/*"
end
