module TradingBot
  class Trade
    attr_reader :action_type, :symbol, :volume, :take_profit, :position_id, :comment

    # Initialize a trade request
    # @param action_type [String] 'ORDER_TYPE_BUY' or 'ORDER_TYPE_SELL' or 'POSITION_MODIFY'
    # @param symbol [String] Trading symbol
    # @param volume [Float] Trade volume
    # @param take_profit [Float, nil] Take profit price
    # @param position_id [String, nil] Position ID for modifications
    # @param comment [String, nil] Trade comment
    def initialize(action_type:, symbol:, volume:, take_profit: nil, position_id: nil, comment: nil)
      @action_type = action_type
      @symbol = symbol
      @volume = volume
      @take_profit = take_profit
      @position_id = position_id
      @comment = comment
    end

    # Check if this is a buy order
    def buy?
      action_type == 'ORDER_TYPE_BUY'
    end

    # Check if this is a sell order
    def sell?
      action_type == 'ORDER_TYPE_SELL'
    end

    # Check if this is a position modification
    def modification?
      action_type == 'POSITION_MODIFY'
    end

    # Convert to API request format
    def to_api_format(relative_pips: false)
      base_data = {
        "actionType" => action_type,
        "symbol" => symbol,
        "volume" => volume
      }

      # Add take profit if specified
      if take_profit
        if relative_pips && !modification?
          base_data["takeProfit"] = take_profit
          base_data["takeProfitUnits"] = "RELATIVE_PIPS"
        else
          base_data["takeProfit"] = take_profit
        end
      end

      # Add position ID for modifications
      base_data["positionId"] = position_id if position_id && modification?

      # Add comment for new trades
      base_data["comment"] = comment if comment && !modification?

      base_data
    end

    # Convert to JSON for API request
    def to_json(relative_pips: false)
      to_api_format(relative_pips: relative_pips).to_json
    end

    # Factory method to create a buy trade for grid
    # @param entry_price [Float] Entry price (for logging purposes)
    # @param take_profit [Float] Take profit price
    # @param config [EnvironmentConfig] Configuration object
    def self.create_grid_buy(entry_price:, take_profit:, config:)
      new(
        action_type: 'ORDER_TYPE_BUY',
        symbol: config.pair_symbol,
        volume: config.lot_size,
        take_profit: take_profit,
        comment: config.trade_comment
      )
    end

    # Factory method to create a position modification
    # @param position_id [String] Position ID to modify
    # @param take_profit [Float] New take profit price
    def self.create_modification(position_id:, take_profit:)
      new(
        action_type: 'POSITION_MODIFY',
        symbol: nil,  # Will be filled by position manager
        volume: nil,  # Not needed for modifications
        take_profit: take_profit,
        position_id: position_id
      )
    end

    # String representation
    def to_s
      if modification?
        "MODIFY Position #{position_id}: TP=#{take_profit}"
      else
        "#{buy? ? 'BUY' : 'SELL'} #{symbol} @ Volume: #{volume}, TP: #{take_profit}"
      end
    end
  end
end