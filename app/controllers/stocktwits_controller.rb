class StocktwitsController < ApplicationController
  layout "stocktwits"
  before_action :user_id, :ticker_symbol

  def index
    unless ticker_symbol.present?
      @twits = Stocktwit.showing(@user_id).order(stocktwit_date: :desc, id: :desc).limit(20)
    else
      # If we have a ticker param, don't load any because the Javascript will load the page
      @twits = Stocktwit.none
    end

    ticker_list = Stocktwit.ticker_list('ticker_symbol', @user_id)
    @ticker_list_symbol = ticker_list.to_a
    @ticker_list_count = @ticker_list_symbol.sort { |a,b| b['count'].to_i <=> a['count'].to_i }
    @ticker_list_updated = @ticker_list_symbol.sort { |a,b| b['last_updated_date'] <=> a['last_updated_date'] }
    @ticker_list_watching = Stocktwit.watching_list

    @setup_list = Stocktwit.setup_list
  end

  def load_twits
    maxtwit = Stocktwit.select(:id, :stocktwit_date, :stocktwit_time).find(params[:max]) if params[:max].present?

    @twits = Stocktwit.showing(@user_id)
    @twits = @twits.where("stocktwits.stocktwit_date <= ?", maxtwit.stocktwit_date) if params[:max].present?
    @twits = @twits.where(symbol: ticker_symbol) if ticker_symbol.present?
    @twits = @twits.joins(:stocktwit_hashtags).where(stocktwit_hashtags: {tag: params[:setup]}) if params[:setup].present?
    @twits = @twits.order(stocktwit_date: :desc, id: :desc)
    @twits = @twits.limit(20)

    if @twits.length == 0
      render status: :ok, layout: false
    else
      render "load_twits", layout: false
    end
  end

  def add_twit
    head :bad_request  if params[:message].nil?
    outcome, @twit = LocalNoteTaker::CreateStocktwitNoteWithScreenshot.(
      note: params[:message],
      stocktwit_time: params[:followup_id].present? ? Stocktwit.find(params[:followup_id]).stocktwit_time + 60 : Time.now,
      screen_count: screen_count || 2
    )

    if outcome == :ok
      render 'twit_result_ok'
    else
      render 'twit_result_error'
    end
  end

  def edit_twit
    head :bad_request if params[:message].nil?
    outcome, @twit = LocalNoteTaker::EditStocktwit.(
      stocktwit_id: params[:id],
      message: params[:message]
    )

    if outcome == :ok
      render 'edit_twit_ok'
    else
      render 'edit_twit_error'
    end
  end

  def edit_note
    head :bad_request  if params[:note].nil? || params[:id].nil?
    if @twit = Stocktwits::AddNote.(stocktwit_id: params[:id], note_message: params[:note])
      render 'note_result_ok'
    else
      render 'note_result_error'
    end
  end

  def refresh
    Stocktwit.sync_twits
    redirect_to stocktwits_path
  end

  def toggle_watching
    symbol = params[:symbol]
    @result = Stocktwit.toggle_watching(symbol)
    render status: :ok
  end

  def watching
    symbol = params[:symbol]
    @result = { watching: Stocktwit.watching?(symbol) }
    render json: @result
  end

  def call_result
    head :bad_request  if params[:call_result].nil? || params[:id].nil?
    @twit = Stocktwit.find(params[:id])
    if @twit.update(call_result: params[:call_result])
      render 'call_result_ok'
    else
      render 'call_result_error'
    end
  end

  def hide
    head :bad_request if params[:id].nil?
    @twit = Stocktwit.find(params[:id])
    @twit.update(hide: true)
  end

private
  TICKER_SYMBOL_ALIASES = [%w(SPY SPXL SSO), %w(VXX VXXB XIV SVXY)]

  def ticker_symbol
    return @ticker_symbol if @ticker_symbol.present?

    ticker_raw = params[:symbol].to_s.strip
    aliases = TICKER_SYMBOL_ALIASES.select { |a| a.include?(ticker_raw) }.flatten
    @ticker_symbol = aliases.any? ? aliases : ticker_raw
  end

  def screen_count
    params[:screen_count] =~ /1/ ? 1 : 2
  end

  def user_id
    @user_id = params[:user_id] || 'greenspud'
  end
end
