module TDAmeritradeDataInterface
  module RunDaemons
    extend self

    def realtime_quote_daemon_block
      puts "Real Time Quote Import: #{Time.now}"
      if is_market_day? Date.today
        ActiveRecord::Base.connection_pool.with_connection do
          import_realtime_quotes
          puts "Copying from real time quotes cache to daily_stock_prices... #{Time.now}"
          copy_realtime_quotes_to_daily_stock_prices
        end
        puts "Done #{Time.now}\n\n"
      else
        puts "Market closed today, no real time quote download necessary"
      end
    end

    def run_realtime_quotes_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0,15,30,45 10-15 * * MON-FRI') { realtime_quote_daemon_block }
      scheduler2 = Rufus::Scheduler.new
      scheduler2.cron('32,44,53 9 * * MON-FRI') { realtime_quote_daemon_block }
      puts "#{Time.now} Beginning realtime quote import daemon..."
      [scheduler, scheduler2]
    end

    def run_daily_quotes_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('10 16 * * MON-FRI') do
        puts "Daily Quote Import: #{Time.now}"
        if is_market_day? Date.today
          ActiveRecord::Base.connection_pool.with_connection do
            update_daily_stock_prices_from_real_time_snapshot
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
        puts "Prepopulating daily_stock_quotes table: #{Time.now}"
        ActiveRecord::Base.connection_pool.with_connection do
          prepopulate_daily_stock_prices(Date.today)
        end
      end
      puts "#{Time.now} Beginning daily_stock_prices prepopulate daemon..."
      scheduler
    end

    def run_premarket_quotes_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('4,25,40,59 8 * * MON-FRI') do
        puts "Premarket Quote Import: #{Time.now}"
        if is_market_day? Date.today
          ActiveRecord::Base.connection_pool.with_connection do
            import_premarket_quotes(date: Date.today)
          end
        else
          puts "Market closed today, no real time quote download necessary"
        end
      end
      puts "#{Time.now} Beginning premarket quotes update daemon..."
      scheduler
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

    def run_afterhours_quotes_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 17,18,19,21 * * MON-FRI') do
        puts "Afterhours Quote Import: #{Time.now}"
        if is_market_day? Date.today
          ActiveRecord::Base.connection_pool.with_connection do
            import_afterhours_quotes(date: Date.today)
          end
        else
          puts "Market closed today, no real time quote download necessary"
        end
      end
      puts "#{Time.now} Beginning afterhours quotes update daemon..."
      scheduler
    end

    def run_stocktwits_sync_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 0,7,16 * * *') do
        puts "StockTwits data sync: #{Time.now}"
        ActiveRecord::Base.connection_pool.with_connection do
          Stocktwit.sync_twits
        end
      end
      puts "#{Time.now} Beginning StockTwits sync daemon..."
      scheduler
    end

    def run_import_vix_futures_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 9,10,14,17 * * MON-FRI') do
        puts "VIX Futures data sync: #{Time.now}"
        ActiveRecord::Base.connection_pool.with_connection do
          VIXFuturesHistory.import_vix_futures if is_market_day?(Date.today)
        end
        puts "Done"
      end
      puts "#{Time.now} Beginning VIX Futures History daemon..."
      scheduler
    end

    def run_db_maintenance_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('0 1 * * SUN-FRI') do
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

    def run_evernote_watchlist_daemon
      scheduler = Rufus::Scheduler.new
      scheduler.cron('45 1 * * *') do
        puts "Building Evernote Watchlist #{Time.now}"
        Evernote::EvernoteWatchList.build_evernote_watchlist
        puts "Done building Evernote Watchlist"
      end
      puts "#{Time.now} Beginning Evernote watchlist daemon..."
      scheduler
    end

  end
end