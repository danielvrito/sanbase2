defmodule SanbaseWeb.Graphql.PriceStore do
  alias Sanbase.Prices
  alias SanbaseWeb.Graphql.Helpers.Cache

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(pair, ids) when is_list(ids) do
    ids
    |> Enum.uniq()
    |> Enum.map(fn id ->
      {id, fetch_price(pair, id)}
    end)
    |> Map.new()
  end

  # Helper functions

  # TODO: not covered in tests
  defp fetch_price(pair, :last) do
    Cache.func(fn -> fetch_last_price_record(pair) end, :fetch_price_last_record, %{pair: pair}).()
  end

  defp fetch_price(pair, %{from: from, to: to, interval: interval} = args) do
    Cache.func(
      fn -> Prices.Store.fetch_prices_with_resolution(pair, from, to, interval) end,
      :fetch_prices_with_resolution,
      Map.merge(%{pair: pair}, args)
    ).()
  end

  defp fetch_last_price_record(pair) do
    with {:ok, {_dt, price, _mcap, _volume}} <- Prices.Store.last_record(pair) do
      Decimal.new(price)
    else
      _error -> nil
    end
  end
end
