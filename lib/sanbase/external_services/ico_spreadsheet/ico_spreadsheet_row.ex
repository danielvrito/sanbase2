defmodule Sanbase.ExternalServices.IcoSpreadsheet.IcoSpreadsheetRow do
  defstruct [
    :project_name,
    :ticker,
    :ico_start_date,
    :ico_end_date,
    :tokens_issued_at_ico,
    :tokens_sold_at_ico,
    :usd_btc_icoend,
    :funds_raised_btc,
    :funds_raised_usd,
    :funds_raised_eth,
    :usd_eth_icoend,
    :ico_currencies,
    :minimal_cap_amount,
    :maximal_cap_amount,
    :cap_currency,
    :market_segment,
    :infrastructure,
    :website_link,
    :github_link,
    :wp_link,
    :btt_link,
    :twitter_link,
    :facebook_link,
    :reddit_link,
    :blog_link,
    :slack_link,
    :linkedin_link,
    :telegram_link,
    :ico_main_contract_address,
    :token_address,
    :team_token_wallet,
    :eth_wallets,
    :btc_wallets,
    :project_transparency,
    :comments
  ]

  def get_column_indices do
    %{
      project_name: 1,
      ticker: 2,
      ico_start_date: 15,
      ico_end_date: 16,
      tokens_issued_at_ico: 22,
      tokens_sold_at_ico: 23,
      funds_raised_usd: 27,
      usd_btc_icoend: 28,
      funds_raised_btc: 29,
      usd_eth_icoend: 30,
      funds_raised_eth: 31,
      ico_currencies: 32,
      minimal_cap_amount: 40,
      maximal_cap_amount: 43,
      cap_currency: 44,
      market_segment: 45,
      infrastructure: 52,
      website_link: 86,
      github_link: 96,
      wp_link: 100,
      btt_link: 105,
      twitter_link: 115,
      facebook_link: 126,
      reddit_link: 129,
      blog_link: 130,
      slack_link: 131,
      linkedin_link: 132,
      telegram_link: 133,
      ico_main_contract_address: 135,
      token_address: 136,
      team_token_wallet: 137,
      eth_wallet: 138,
      btc_wallet: 139,
      btc_wallet2: 140,
      btc_wallet3: 141,
      btc_wallet4: 142,
      btc_wallet5: 143,
      blockchain: 145,
      project_transparency: 146,
      comments: 147
    }
  end
end
