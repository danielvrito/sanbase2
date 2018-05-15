defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Repo

  alias Sanbase.Model.{
    Project,
    ProjectEthAddress,
    ProjectBtcAddress,
    Ico,
    IcoCurrencies,
    Currency,
    MarketSegment,
    Infrastructure,
    LatestCoinmarketcapData,
    ProjectTransparencyStatus
  }

  import Ecto.Query

  schema "project" do
    field(:name, :string)
    field(:ticker, :string)
    field(:logo_url, :string)
    field(:website_link, :string)
    field(:email, :string)
    field(:btt_link, :string)
    field(:facebook_link, :string)
    field(:github_link, :string)
    field(:reddit_link, :string)
    field(:twitter_link, :string)
    field(:whitepaper_link, :string)
    field(:blog_link, :string)
    field(:slack_link, :string)
    field(:linkedin_link, :string)
    field(:telegram_link, :string)
    field(:token_address, :string)
    field(:team_token_wallet, :string)
    field(:token_decimals, :integer)
    field(:total_supply, :decimal)
    field(:description, :string)
    field(:project_transparency, :boolean, default: false)
    field(:main_contract_address, :string)
    belongs_to(:project_transparency_status, ProjectTransparencyStatus, on_replace: :nilify)
    field(:project_transparency_description, :string)
    has_many(:eth_addresses, ProjectEthAddress)
    has_many(:btc_addresses, ProjectBtcAddress)
    belongs_to(:market_segment, MarketSegment, on_replace: :nilify)
    belongs_to(:infrastructure, Infrastructure, on_replace: :nilify)

    belongs_to(
      :latest_coinmarketcap_data,
      LatestCoinmarketcapData,
      foreign_key: :coinmarketcap_id,
      references: :coinmarketcap_id,
      type: :string,
      on_replace: :nilify
    )

    has_many(:icos, Ico)
  end

  @doc false
  def changeset(%Project{} = project, attrs \\ %{}) do
    project
    |> cast(attrs, [
      :name,
      :ticker,
      :logo_url,
      :coinmarketcap_id,
      :website_link,
      :email,
      :market_segment_id,
      :infrastructure_id,
      :btt_link,
      :facebook_link,
      :github_link,
      :reddit_link,
      :twitter_link,
      :whitepaper_link,
      :blog_link,
      :slack_link,
      :linkedin_link,
      :telegram_link,
      :token_address,
      :main_contract_address,
      :team_token_wallet,
      :description,
      :project_transparency,
      :project_transparency_status_id,
      :project_transparency_description,
      :token_decimals,
      :total_supply
    ])
    |> validate_required([:name])
    |> unique_constraint(:coinmarketcap_id)
  end

  def initial_ico(%Project{id: id}) do
    Ico
    |> where([i], i.project_id == ^id)
    |> first(:start_date)
    |> Repo.one()
  end

  def roi_usd(project) do
    Sanbase.Model.Project.Roi.roi_usd(project)
  end

  @doc ~S"""
    Returns an Ecto query that selects all projects with eth contract
  """
  @spec all_projects_with_eth_contract_query() :: %Ecto.Query{}
  def all_projects_with_eth_contract_query() do
    all_icos_query =
      from(
        i in Ico,
        select: %{
          project_id: i.project_id,
          contract_block_number: i.contract_block_number,
          contract_abi: i.contract_abi,
          rank:
            fragment(
              "row_number() over(partition by ? order by ? asc)",
              i.project_id,
              i.start_date
            )
        }
      )

    query =
      from(
        d in subquery(all_icos_query),
        inner_join: p in Project,
        on: p.id == d.project_id,
        where:
          not is_nil(p.coinmarketcap_id) and d.rank == 1 and not is_nil(p.main_contract_address) and
            not is_nil(d.contract_block_number) and not is_nil(d.contract_abi),
        order_by: p.name,
        select: p
      )

    query
  end

  def funds_raised_usd_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_usd_ico_end_price/1)
  end

  def funds_raised_eth_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_eth_ico_end_price/1)
  end

  def funds_raised_btc_ico_end_price(project) do
    funds_raised_ico_end_price(project, &Ico.funds_raised_btc_ico_end_price/1)
  end

  defp funds_raised_ico_end_price(project, ico_funds_raised_fun) do
    Repo.preload(project, :icos).icos
    |> Enum.map(ico_funds_raised_fun)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      amounts -> Enum.reduce(amounts, 0, &Kernel.+/2)
    end
  end

  @doc """
    For every currency aggregates all amounts for every ICO of the given project
  """
  def funds_raised_icos(%Project{id: id}) do
    query =
      from(
        i in Ico,
        inner_join: ic in IcoCurrencies,
        on: ic.ico_id == i.id and not is_nil(ic.amount),
        inner_join: c in Currency,
        on: c.id == ic.currency_id,
        where: i.project_id == ^id,
        group_by: c.code,
        order_by: fragment("case
            when ? = 'BTC' then '_'
            when ? = 'ETH' then '__'
            when ? = 'USD' then '___'
            else ?
          end", c.code, c.code, c.code, c.code),
        select: %{currency_code: c.code, amount: sum(ic.amount)}
      )

    Repo.all(query)
  end

  def eth_addresses_by_tickers(tickers) do
    query =
      from(
        p in Project,
        where: p.ticker in ^tickers and not is_nil(p.coinmarketcap_id),
        preload: [:eth_addresses]
      )

    Repo.all(query)
    |> Stream.map(fn %Project{ticker: ticker, eth_addresses: eth_addresses} ->
      eth_addresses = eth_addresses |> Enum.map(&Map.get(&1, :address))

      {ticker, eth_addresses}
    end)
    |> Enum.into(%{})
  end
end
