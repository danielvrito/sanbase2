defmodule Sanbase.ExternalServices.Coinmarketcap2 do
  @moduledoc """
  # Syncronize data from coinmarketcap.com

  A GenServer, which updates the data from coinmarketcap on a regular basis.
  On regular intervals it will fetch the data from coinmarketcap and insert it
  into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  import Ecto.Query

  require Sanbase.Utils.Config
  require Logger

  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo
  alias Sanbase.Prices.Store
  alias Sanbase.ExternalServices.ProjectInfo
  alias Sanbase.ExternalServices.Coinmarketcap.GraphData
  alias Sanbase.Notifications.CheckPrices
  alias Sanbase.Notifications.PriceVolumeDiff
  alias Sanbase.Utils.Config

  # 5 minutes
  @default_update_interval 1000 * 60 * 5

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    if Config.get(:sync_enabled, false) do
      Store.create_db()

      Process.send(self(), :fetch_missing_info)
      Process.send(self(), :fetch_total_market)
      Process.send(self(), :fetch_prices)

      update_interval = Config.get(:update_interval, @default_update_interval)

      {:ok,
       %{
         missing_info_update_interval: update_interval * 10,
         total_market_update_interval: update_interval,
         prices_update_interval: update_interval
       }}
    else
      :ignore
    end
  end

  def handle_info(:fetch_missing_info, %{missing_info_update_interval: update_interval} = state) do
    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      projects(),
      &fetch_project_info/1,
      ordered: false,
      max_concurrency: 5,
      timeout: 180_000
    )
    |> Stream.run()

    Process.send_after(self(), :fetch_missing_info, update_interval)
    {:noreply, state}
  end

  def handle_info(:fetch_total_market, %{total_market_update_interval: update_interval} = state) do
    # Start the task under the supervisor in a way that does not need await
    Task.Supervisor.start_child(
      Sanbase.TaskSupervisor,
      &fetch_and_process_marketcap_total_data/0
    )

    Process.send_after(self(), :fetch_total_market, update_interval)
    {:noreply, state}
  end

  def handle_info(:fetch_prices, %{prices_update_interval: update_interval} = state) do
    # Run the tasks in a stream concurrently so `max_concurrency` can be used.
    # Otherwise risking to start too many tasks to a service that's rate limited
    Task.Supervisor.async_stream_nolink(
      Sanbase.TaskSupervisor,
      projects(),
      &fetch_and_process_price_data/1,
      ordered: false,
      max_concurrency: 5,
      timeout: 180_000
    )
    |> Stream.run()

    Process.send_after(self(), :fetch_prices, update_interval)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn("Unknown message received: #{msg}")
    {:noreply, state}
  end

  # Private functions

  defp projects() do
    Project
    |> where([p], not is_nil(p.coinmarketcap_id))
    |> Repo.all()
  end

  defp project_info_missing?(
         %Project{
           website_link: website_link,
           email: email,
           reddit_link: reddit_link,
           twitter_link: twitter_link,
           btt_link: btt_link,
           blog_link: blog_link,
           github_link: github_link,
           telegram_link: telegram_link,
           slack_link: slack_link,
           facebook_link: facebook_link,
           whitepaper_link: whitepaper_link,
           ticker: ticker,
           name: name,
           token_decimals: token_decimals,
           main_contract_address: main_contract_address
         } = project
       ) do
    !website_link or !email or !reddit_link or !twitter_link or !btt_link or !blog_link or
      !github_link or !telegram_link or !slack_link or !facebook_link or !whitepaper_link or
      !ticker or !name or !main_contract_address or !token_decimals
  end

  defp fetch_project_info(project) do
    if project_info_missing?(project) do
      ProjectInfo.from_project(project)
      |> ProjectInfo.fetch_coinmarketcap_info()
      |> case do
        {:ok, project_info_with_coinmarketcap_info} ->
          project_info_with_coinmarketcap_info
          |> ProjectInfo.fetch_etherscan_token_summary()
          |> ProjectInfo.fetch_contract_info()
          |> ProjectInfo.update_project(project)

        _ ->
          nil
      end
    end
  end

  defp missing_ico_info?(%Ico{
         contract_abi: contract_abi,
         contract_block_number: contract_block_number
       }) do
    !contract_abi or !contract_block_number
  end

  defp fetch_and_process_price_data(%Project{} = project) do
    last_price_datetime = last_price_datetime(project)
    GraphData.fetch_and_store_prices(project, last_price_datetime)

    # TODO: Activate later when old coinmarketcap is disabled
    # process_notifications(project)
  end

  defp process_notifications(%Project{} = project) do
    CheckPrices.exec(project, "usd")
    CheckPrices.exec(project, "btc")

    PriceVolumeDiff.exec(project, "usd")
  end

  defp last_price_datetime(%Project{ticker: ticker, coinmarketcap_id: coinmarketcap_id}) do
    case Store.last_history_datetime_cmc!(ticker <> _ <> coinmarketcap_id) do
      nil ->
        GraphData.fetch_first_price_datetime(coinmarketcap_id)

      datetime ->
        datetime
    end
  end

  defp fetch_and_process_marketcap_total_data() do
    last_marketcap_total_datetime = last_marketcap_total_datetime()
    GraphData.fetch_and_store_marketcap_total(last_marketcap_total_datetime)
  end

  defp last_marketcap_total_datetime() do
    case Store.last_history_datetime_cmc!("TOTAL_MARKET") do
      nil ->
        GraphData.fetch_first_marketcap_total_datetime()

      datetime ->
        datetime
    end
  end
end
