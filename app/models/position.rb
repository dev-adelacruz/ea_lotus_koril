module TradingBot
  class Position
    attr_reader :id, :type, :symbol, :open_price, :take_profit, :volume, :current_price, :profit

    # Initialize from API response hash
    def initialize(api_data)
      @id = api_data['id']
      @type = api_data['type']  # 'POSITION_TYPE_BUY' or 'POSITION_TYPE_SELL'
      @symbol = api_data['symbol']
      @open_price = api_data['openPrice'].to_f
      @take_profit = api_data['takeProfit']&.to_f
      @volume = api_data['volume'].to_f
      @current_price = api_data['currentPrice']&.to_f
      @profit = api_data['profit']&.to_f
    end

    # Check if this is a buy position
    def buy?
      type == 'POSITION_TYPE_BUY'
    end

    # Check if this is a sell position
    def sell?
      type == 'POSITION_TYPE_SELL'
    end

    # Check if take profit has been hit
    def take_profit_hit?(current_price)
      return false unless take_profit && current_price
      
      if buy?
        current_price >= take_profit
      else
        current_price <= take_profit
      end
    end

    # Calculate distance to take profit
    def distance_to_take_profit(current_price)
      return nil unless take_profit && current_price
      
      if buy?
        take_profit - current_price
      else
        current_price - take_profit
      end
    end

    # Check if position is profitable
    def profitable?
      profit.to_f > 0
    end

    # Convert back to API format for updates
    def to_api_format
      {
        'id' => id,
        'type' => type,
        'symbol' => symbol,
        'openPrice' => open_price,
        'takeProfit' => take_profit,
        'volume' => volume
      }
    end

    # String representation
    def to_s
      "#{buy? ? 'BUY' : 'SELL'} #{symbol} @ #{open_price}, TP: #{take_profit}, Profit: #{profit}"
    end
  end
end