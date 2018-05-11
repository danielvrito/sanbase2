defmodule Sanbase.ExternalServices.Coinmarketcap2 do
  @moduledoc """
    A GenServer, which updates the data from coinmarketcap on a regular basis.
    On regular intervals it will fetch the data from coinmarketcap and insert it
    into a local DB
  """
  use GenServer, restart: :permanent, shutdown: 5_000

  import Ecto.Query

  require Sanbase.Utils.Config
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store
  # TODO: Change
  alias Sanbase.ExternalServices.Coinmarketcap.GraphData2, as: GraphData
  alias Sanbase.Utils.Config

  # 5 minutes
  @default_update_interval 1000 * 60 * 5
  @request_timeout 300_000

  def start_link(_state) do
    GenServer.start_link(__MODULE__, :ok)
  end

  def init(_arg) do
    if Config.get(:sync_enabled, false) do
      # Create an influxdb if it does not exists, no-op if it exists
      Store.create_db()

      # Start scraping immediately
      Process.send(self(), :fetch_missing_info, [:noconnect])
      Process.send(self(), :fetch_total_market, [:noconnect])
      Process.send(self(), :fetch_prices, [:noconnect])

      update_interval = Config.get(:update_interval, @default_update_interval)

      # Scrape total market and prices often. Scrape the missing info rarely.
      # There are many projects for which the missing info is not available. The
      # missing info could become available at any time so the scraping attempts
      # should continue. This is made to speed the scraping as the API is rate limited.
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
      timeout: @request_timeout
    )
    |> Stream.run()

    Process.send_after(self(), :fetch_missing_info, update_interval)
    {:noreply, state}
  end

  def handle_info(:fetch_total_market, %{total_market_update_interval: update_interval} = state) do
    # Start the task under the supervisor in a way that does not need await.
    # As there is only one data record to be fetched we fire and forget about it,
    # so the work can continue to scraping the projects' prices in parallel.
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
      timeout: @request_timeout
    )
    |> Stream.run()

    Process.send_after(self(), :fetch_prices, update_interval)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warn("Unknown message received in #{__MODULE__}: #{msg}")
    {:noreply, state}
  end

  # Private functions

  # List of all projects with coinmarketcap id
  defp projects() do
    Project
    |> where([p], not is_nil(p.coinmarketcap_id))
    |> Sanbase.Repo.all()
  end

  defp project_info_missing?(%Project{
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
       }) do
    !website_link or !email or !reddit_link or !twitter_link or !btt_link or !blog_link or
      !github_link or !telegram_link or !slack_link or !facebook_link or !whitepaper_link or
      !ticker or !name or !main_contract_address or !token_decimals
  end

  # Fetch project info from Coinmarketcap and Etherscan. Fill only missing info
  # and does not override existing info.
  defp fetch_project_info(project) do
    alias Sanbase.ExternalServices.ProjectInfo

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

  # Fetch history coinmarketcap data and store it in DB
  defp fetch_and_process_price_data(%Project{} = project) do
    last_price_datetime = last_price_datetime(project)
    GraphData.fetch_and_store_prices(project, last_price_datetime)

    # TODO: Activate later when old coinmarketcap is disabled
    # process_notifications(project)
  end

  defp process_notifications(%Project{} = project) do
    Sanbase.Notifications.CheckPrices.exec(project, "usd")
    Sanbase.Notifications.CheckPrices.exec(project, "btc")
    Sanbase.Notifications.PriceVolumeDiff.exec(project, "usd")
  end

  defp last_price_datetime(%Project{ticker: ticker, coinmarketcap_id: coinmarketcap_id} = project)
       when nil != ticker and nil != coinmarketcap_id do
    measurement_name = Sanbase.Influxdb.Measurement.name_from(project)

    case Store.last_history_datetime_cmc!(measurement_name) do
      nil ->
        GraphData.fetch_first_datetime(coinmarketcap_id)

      datetime ->
        datetime
    end
  end

  defp last_marketcap_total_datetime() do
    measurement_name = "TOTAL_MARKET_total-market"

    case Store.last_history_datetime_cmc!(measurement_name) do
      nil ->
        GraphData.fetch_first_datetime("TOTAL_MARKET")

      datetime ->
        datetime
    end
  end

  defp fetch_and_process_marketcap_total_data() do
    last_marketcap_total_datetime()
    |> GraphData.fetch_and_store_marketcap_total()
  end
end
