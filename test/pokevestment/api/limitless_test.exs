defmodule Pokevestment.Api.LimitlessTest do
  use ExUnit.Case, async: true

  alias Pokevestment.Api.Limitless

  describe "module structure" do
    test "exports list_tournaments/0 and list_tournaments/1" do
      # Ensure module is loaded so function_exported? works
      Code.ensure_loaded!(Limitless)
      assert function_exported?(Limitless, :list_tournaments, 0)
      assert function_exported?(Limitless, :list_tournaments, 1)
    end

    test "exports get_standings/1" do
      Code.ensure_loaded!(Limitless)
      assert function_exported?(Limitless, :get_standings, 1)
    end
  end
end
