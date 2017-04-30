module MarketDataUtilities
  module TickerList
    class UnscrapeShellCompanies
      include Verbalize::Action

      def call
        Ticker.shell_companies.map { |symbol, _company_name| Ticker.find_by(symbol: symbol).update(scrape_data: false) }
      end

    end
  end
end