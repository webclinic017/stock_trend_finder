require 'open-uri'
require 'concerns/tickers/tags'

class Ticker < ActiveRecord::Base
  include Tags

  has_many :daily_stock_prices
  has_many :dividends
  has_many :minute_stock_prices
  has_many :real_time_quotes
  has_many :stock_splits
  has_many :ticker_notes

  validates_uniqueness_of :symbol

  CATEGORY_TAGS=%w(
      fundamental
      dividend

      cybersecurity
      high-growth
      new-tech
      old-tech
      four-horsemen-tech

      banks

      china

      oil_exploration
      oil_drilling
      oil_drilling_offshore

      utility
      reit
      healthcare_reit
      oil_mlp
      consumer_staples

      chemicals


      biotech
      big-pharma

      public-storage

healthcare_insurer
      drug_distributor
      healthcare_service_provider

      drugstore

      earnings-mover
  )

  scope :watching, ->{ where(scrape_data: true) }

  enum category_tag: CATEGORY_TAGS

  def create_note(note_text='', note_date: Date.today, note_type: nil)
    ticker_notes.create(
                  ticker_symbol: symbol,
                  note_text: note_text,
                  note_date: note_date,
                  note_type: note_type
    )
  end

  def self.scrape?(symbol)
    Ticker.find_by(symbol: symbol).scrape_data
  end

  def self.scrape(*symbols)
    symbols.each do |symbol|
      Ticker.find_by(symbol: symbol).update!(scrape_data: true)
    end
  end

  def self.unscrape(*symbols)
    symbols.each do |symbol|
      Ticker.find_by(symbol: symbol).update!(scrape_data: false)
    end
  end

  ########### CONVENIENCE METHODS FOR STOCK PROPERTIES ###########

  def self.avg_volume(symbol)
    DailyStockPrice.where(ticker_symbol: symbol).order(price_date: :desc).first.average_volume_50day.to_s
  end

  def self.float(symbol)
    Ticker.find_by(symbol: symbol).float.to_s
  end

  def self.short(symbol)
    t = Ticker.find_by(symbol: symbol).short
  end

  def short
    "#{short_ratio} | #{((short_pct_float || 0) * 100).round}%"
  end

  def self.add(symbol, company_name, exchange)
    raise Exception.new("Invalid exchange") if ['nasdaq', 'nyse'].index(exchange).nil?
    Ticker.create(symbol: symbol, company_name: company_name, exchange: exchange, scrape_data:true)
  end

  ########### ADDING NEW TICKERS ###########

  # SAMPLE OF INPUT (tab delimited):
  # Company Name	Symbol	Market	Price	Shares	Offer Amount	Expected IPO Date
  # JUNO THERAPEUTICS, INC.	JUNO	NASDAQ	15.00-18.00	9,250,000	$191,475,000	12/19/2014
  # FIRST GUARANTY BANCSHARES, INC.		NASDAQ	19.00-21.00	4,571,428	$110,399,982	12/19/2014
  # WORKIVA LLC	WK	New York Stock Exchange	13.00-15.00	7,200,000	$124,200,000	12/12/2014
  def self.add_nasdaq_ticker_list
    log = ''
    File.open(File.join(Rails.root, 'downloads', 'ipo_list.txt'), 'r').each_line do |line|
      company_name,symbol,market,price,shares,offer,ipo_date = line.split("\t")
      case market
        when 'NASDAQ'
          market = 'nasdaq'
        when 'New York Stock Exchange'
          market = 'nyse'
      end

      shares = Float(shares.delete(',')) / 1000

      puts "Creating: #{symbol}, #{company_name}, #{market}, #{shares}"
      log = log + "Creating: #{symbol}, #{company_name}, #{market}, #{shares}\n"
      t = Ticker.find_by(symbol: symbol)
      if t
        puts "Ticker #{symbol} already exists. Resetting scrape flag. Scrape currently #{t.scrape_data}"
        log = log + "Ticker #{symbol} already exists. Resetting scrape flag. Scrape currently #{t.scrape_data}\n"
        t.company_name = company_name
        t.float = shares
        t.exchange = market
        t.scrape_data = true
        t.save!
      else
        Ticker.create(symbol: symbol, company_name: company_name, exchange: market, float: shares, scrape_data:true)
      end

      puts log
    end
  end

  def hide_from_reports(days=1)
    self.update!(hide_from_reports_until: Date.today + days)
  end

end
