module TradingBot
  class TradeExecutor
    class TradeError < StandardError; end

    attr_reader :api_client, :config, :dry_run

    def initialize(api_client:, config: EnvironmentConfig)
      @api_client = api_client
      @config = config
      @dry_run = config.dry_run?
    end

    # Execute a trade
    # @param trade [Trade] The trade to execute
    # @return [Hash, nil] API response or nil in dry-run mode
    def execute(trade)
      # Check if trades are disabled globally
      if config.trade_disabled?
        Logger.warn("TRADES DISABLED: Would execute trade but trades are disabled via TRADE_DISABLED environment variable")
        Logger.warn("Trade details: #{trade}")
        return { 'trades_disabled' => true, 'trade' => trade.to_s, 'action' => 'blocked' }
      end
      
      if dry_run
        Logger.trade_executed(
          trade.buy? ? 'BUY' : 'SELL',
          trade.take_profit, # Using take_profit as approximate price for logging
          trade.volume,
          trade.take_profit,
          dry_run: true
        )
        Logger.info("[DRY RUN] Would execute: #{trade}")
        return { 'dry_run' => true, 'trade' => trade.to_s }
      end

      begin
        # Convert trade to JSON
        trade_json = trade.to_json(relative_pips: !trade.modification?)
        
        # Execute trade via API
        response = api_client.place_trade(trade_json)
        
        # Log execution
        Logger.trade_executed(
          trade.buy? ? 'BUY' : 'SELL',
          trade.take_profit, # Using take_profit as approximate price for logging
          trade.volume,
          trade.take_profit,
          dry_run: false
        )
        
        Logger.info("Trade executed successfully: #{response}")
        response
        
      rescue ApiClient::ApiError => e
        Logger.error_with_context(e, { trade: trade.to_s })
        raise TradeError, "Failed to execute trade: #{e.message}"
      rescue => e
        Logger.error_with_context(e, { trade: trade.to_s })
        raise TradeError, "Unexpected error executing trade: #{e.message}"
      end
    end

    # Execute a grid buy trade
    # @param entry_price [Float] Entry price (for logging)
    # @param take_profit [Float] Take profit price
    # @return [Hash, nil] API response or nil in dry-run mode
    def execute_grid_buy(entry_price:, take_profit:)
      trade = Trade.create_grid_buy(
        entry_price: entry_price,
        take_profit: take_profit,
        config: config
      )
      
      execute(trade)
    end

    # Close a position
    # @param position_id [String] Position ID to close
    # @return [Hash, nil] API response or nil in dry-run mode
    def close_position(position_id)
      # For MetaTrader API, we might need to create a sell trade with same volume
      # or use a different endpoint. For now, we'll implement basic closing.
      # This is a placeholder - actual implementation depends on API capabilities.
      
      if dry_run
        Logger.info("[DRY RUN] Would close position: #{position_id}")
        return { 'dry_run' => true, 'action' => 'close', 'position_id' => position_id }
      end

      Logger.info("Closing position: #{position_id}")
      # TODO: Implement actual position closing based on API documentation
      # This might require getting position details first, then placing opposite trade
      { 'status' => 'not_implemented', 'position_id' => position_id }
    end

    # Update a position's take profit
    # @param position_id [String] Position ID to update
    # @param take_profit [Float] New take profit price
    # @return [Hash, nil] API response or nil in dry-run mode
    def update_position_take_profit(position_id:, take_profit:)
      if dry_run
        Logger.info("[DRY RUN] Would update position #{position_id} TP to #{take_profit}")
        return { 'dry_run' => true, 'action' => 'update_tp', 'position_id' => position_id, 'take_profit' => take_profit }
      end

      begin
        response = api_client.update_position(position_id, take_profit)
        Logger.info("Updated position #{position_id} TP to #{take_profit}: #{response}")
        response
      rescue ApiClient::ApiError => e
        Logger.error_with_context(e, { position_id: position_id, take_profit: take_profit })
        raise TradeError, "Failed to update position TP: #{e.message}"
      end
    end

    # Update a position's stop loss
    # @param position_id [String] Position ID to update
    # @param stop_loss [Float] New stop loss price
    # @return [Hash, nil] API response or nil in dry-run mode
    def update_position_stop_loss(position_id:, stop_loss:)
      if dry_run
        Logger.info("[DRY RUN] Would update position #{position_id} SL to #{stop_loss}")
        return { 'dry_run' => true, 'action' => 'update_sl', 'position_id' => position_id, 'stop_loss' => stop_loss }
      end

      begin
        response = api_client.update_position_stop_loss(position_id, stop_loss)
        Logger.info("Updated position #{position_id} SL to #{stop_loss}: #{response}")
        response
      rescue ApiClient::ApiError => e
        Logger.error_with_context(e, { position_id: position_id, stop_loss: stop_loss })
        raise TradeError, "Failed to update position SL: #{e.message}"
      end
    end

    # Update take profits for multiple positions
    # @param positions [Array<Hash>] Array of position hashes with id and take_profit
    # @return [Array<Hash>] Array of results
    def update_positions_take_profits(positions)
      results = []
      
      positions.each do |position_info|
        position_id = position_info[:id]
        take_profit = position_info[:take_profit]
        
        begin
          result = update_position_take_profit(position_id: position_id, take_profit: take_profit)
          results << { position_id: position_id, success: true, result: result }
        rescue TradeError => e
          results << { position_id: position_id, success: false, error: e.message }
        end
      end
      
      results
    end

    # Replace a closed position with a new one at same level
    # This is called when a position hits TP and we want to maintain grid density
    # @param level [GridLevel] The grid level to replace position at
    # @param current_price [Float] Current market price
    # @return [Hash, nil] Result of replacement attempt
    def replace_position_at_level(level, current_price)
      # Check if market is still at this level's entry price
      # Using a small tolerance for price matching
      tolerance = 0.01
      at_entry_level = (current_price - level.entry_price).abs <= tolerance
      
      unless at_entry_level
        Logger.info("Market price #{current_price} not at level #{level.level_index} entry #{level.entry_price}, skipping replacement")
        return { replaced: false, reason: 'price_not_at_level' }
      end
      
      # Create and execute new trade at this level
      execute_grid_buy(
        entry_price: level.entry_price,
        take_profit: level.take_profit_price
      )
    end
  end
end