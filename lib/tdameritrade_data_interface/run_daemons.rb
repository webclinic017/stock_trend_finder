require 'rake'

module TDAmeritradeDataInterface
  module RunDaemons
    extend self

    def realtime_quote_daemon_block
      puts "Real Time Quote Import: #{Time.now}"
      if is_market_day? Date.today
        ActiveRecord::Base.connection_pool.with_connection do
          # import_realtime_quotes
          MarketDataPull::TDAmeritrade::DailyQuotes::PullRealTimeQuotes.call
          puts "Copying from real time quotes cache to daily_stock_prices... #{Time.now}"
          copy_realtime_quotes_to_daily_stock_prices
        end

        puts "Done #{Time.now}\n\n"
      else
        puts "Market closed today, no real time quote download necessary"
      end
    end

    def take_reports_snapshot(reports)
      puts "Saving Report Snapshots: #{Time.now} - #{reports.join(',')}"
      Reports::Snapshots::SaveSnapshots.call(reports: reports)
    end

    def run_realtime_quotes_daemon
      schedulers = [
        '12,24,36,48,59 10-15 * * MON-FRI',
        '34,48,59 9 * * MON-FRI',
      ].map do |scheduled_time|
        scheduler = Rufus::Scheduler.new
        scheduler.cron(scheduled_time) { realtime_quote_daemon_block }
        scheduler
      end
      puts "#{Time.now} Beginning realtime quote import daemon..."
      schedulers
    end

    def run_finalize_realtime_snapshot_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('10 17 * * FRI') do
        puts "Finalizing real time quotes: #{Time.now}"
        if is_market_day? Date.today
          ActiveRecord::Base.connection_pool.with_connection do
            MarketDataPull::TDAmeritrade::DailyQuotes::FinalizeDailyQuotesFromRealtimeSnapshot.call
          end
        else
          puts "Market closed today, no real time quote download necessary"
        end
      end
      puts "#{Time.now} Beginning daily quotes update daemon..."
      scheduler
    end

    def run_prepopulate_daily_stock_quotes_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('12 6 * * MON-FRI') do
        ActiveRecord::Base.connection_pool.with_connection do
          prepopulate_daily_stock_prices(Date.today)
        end
      end
      puts "#{Time.now} Beginning daily_stock_prices prepopulate daemon..."
      scheduler
    end

    def run_premarket_quotes_daemon
      schedulers = [
        '4,25,40,59 8 * * MON-FRI',
        '8,15,24 9 * * MON-FRI',
      ].map  do |scheduled_time|
        scheduler = Rufus::Scheduler.new
        scheduler.cron(scheduled_time) do
          puts "Premarket Quote Import: #{Time.now}"
          if is_market_day? Date.today
            ActiveRecord::Base.connection_pool.with_connection do
              import_premarket_quotes(date: Date.today)
            end

            puts "Done #{Time.now}"
          else
            puts "Market closed today, no real time quote download necessary"
          end
        end
        scheduler
      end
      puts "#{Time.now} Beginning premarket quotes update daemon..."
    end

    def run_premarket_memoization_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 5 * * MON-FRI') do
        puts "Memoizing premarket high, low, close, average volume - #{Time.now}"
        if is_market_day? Date.today
          ActiveRecord::Base.connection_pool.with_connection do
            populate_premarket_memoized_fields(Date.today)
          end
        else
          puts "Market closed today, no real time quote download necessary"
        end
      end
      puts "#{Time.now} Beginning premarket calculations memoization daemon..."
      scheduler
    end

    def run_report_snapshots_daemon
      puts "#{Time.now} Beginning report snapshots daemon..."

      premarket_reports = [:premarket]
      daytime_reports = [:active, :fifty_two_week_high, :fifty_two_week_low, :gaps]
      afterhours_reports = [:after_hours]

      schedulers = Array.new(8) { Rufus::Scheduler.new }
      schedulers[0].cron('50 8 * * MON-FRI') { take_reports_snapshot(premarket_reports) }
      schedulers[1].cron('45 9 * * MON-FRI') { take_reports_snapshot(premarket_reports) }
      schedulers[2].cron('50 9,10,11,13,15,17 * * MON-FRI') { take_reports_snapshot(daytime_reports) }
      schedulers[3].cron('51 17,18,20 * * MON-FRI') { take_reports_snapshot(afterhours_reports) }
      schedulers
    end

    def run_afterhours_quotes_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('25 17,18,21 * * MON-FRI') do
        puts "Afterhours Quote Import: #{Time.now}"
        if is_market_day? Date.today
          ActiveRecord::Base.connection_pool.with_connection do
            import_afterhours_quotes(date: Date.today)
          end

          puts "Done #{Time.now}"
        else
          puts "Market closed today, no real time quote download necessary"
        end
      end
      puts "#{Time.now} Beginning afterhours quotes update daemon..."
      scheduler
    end

    def run_import_vix_futures_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 9,17 * * MON-FRI') do
        puts "VIX Futures data sync: #{Time.now}"
        # ActiveRecord::Base.connection_pool.with_connection do
        #   VIXFuturesHistory.import_vix_futures if is_market_day?(Date.today)
        # end
        VIXCentralScreenshot.new.download_screenshot
        puts "Done"
      end
      puts "#{Time.now} Beginning VIX Futures History daemon..."
      scheduler
    end

    def run_db_maintenance_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 1 * * SAT') do
        puts "Running DB VACUUM: #{Time.now}"
        ActiveRecord::Base.connection_pool.with_connection do
          ActiveRecord::Base.connection.execute "VACUUM FULL"
          ActiveRecord::Base.connection.execute "VACUUM ANALYZE"
        end
        puts "Done"
      end

      scheduler_rts = Rufus::Scheduler.new
      scheduler_rts.cron('0 1 * * SAT') do
        puts "Resetting Realtime Snapshot Flags #{Time.now}"
        ActiveRecord::Base.connection_pool.with_connection do
          $stf.reset_snapshot_flags
        end
        puts "Done"
      end
      puts "#{Time.now} Beginning DB Maintenance daemon..."
      scheduler
    end

    def run_fundamentals_history_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 20 * * SAT') do
        puts "#{Time.current} - Beginning download of fundamentals data from TD Ameritrade OAuth API..."
        MarketDataPull::TDAmeritrade::UpdateFundamentals.call
        puts "Done"

        puts "#{Time.current} - Updating the S&P 500 list"
        MarketDataPull::Wikipedia::UpdateSP500List.call
        puts "Done"
      end
      puts "#{Time.now} Beginning TDA Fundamentals daemon..."
      scheduler
    end

    def run_institutional_ownership_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 19 27 * *') do
        puts "#{Time.now} - Beginning download of institutional ownership..."
          t = Time.now
          MarketDataPull::Nasdaq::InstitutionalHoldings::ScrapeAll.call
          puts "Done (began at #{t}, now #{Time.now})"
      end
      puts "#{Time.now} Beginning institutional ownership daemon..."

      scheduler
    end

    def run_update_company_list_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('1 20 * * MON-FRI') do
        puts "#{Time.now} - Beginning download of company list..."
        Rake::Task["tickers:update_company_list"].execute
      end
      puts "#{Time.now} Beginning update company list daemon..."

      scheduler
    end

    def run_short_interest_daemon
      scheduler = Rufus::Scheduler.new
      # This is set to run the 2nd, 13th, 17th,28th of every month
      scheduler.cron('0 19 2,13,17,28 * *') do
        puts "#{Time.now} - Beginning download of short interest..."
        MarketDataUtilities::ShortInterest::Update.call
      end
      puts "#{Time.now} Beginning short interest daemon..."

      scheduler
    end

    def run_market_cap_aggregations_daemon
      scheduler = Rufus::Scheduler.new
      # This is set to run the 2nd, 13th, 17th,28th of every month
      scheduler.cron('30 18 * * MON-FRI') do
        return unless is_market_day?
        puts "#{Time.now} - Beginning market cap aggregations calculation..."
        MarketDataUtilities::MarketCapAggregation::BuildForDate.call(date: Date.current)
      end
      puts "#{Time.now} Beginning market cap aggregations daemon..."

      scheduler
    end

  end
end