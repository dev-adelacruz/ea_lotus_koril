module TradingBot
  class PositionManager
    attr_reader :api_client, :grid_manager, :trade_executor, :config

    def initialize(api_client:, grid_manager:, trade_executor:, config: EnvironmentConfig)
      @api_client = api_client
      @grid_manager = grid_manager
      @trade_executor = trade_executor
      @config = config
    end

    # Fetch and process current positions
    def refresh_positions
      # In dry-run mode with empty grid, simulate having 1 position to bootstrap the grid
      if config.dry_run? && grid_manager.grid_levels.empty?
        Logger.info("[DRY RUN] Simulating initial position to bootstrap grid")
        simulated_position = create_simulated_position
        our_positions = [simulated_position]
        
        # Initialize grid manager with simulated position
        grid_manager.initialize_from_positions(our_positions)
        return our_positions
      end
      
      begin
        positions_data = api_client.get_positions
        return [] if positions_data.nil? || positions_data.empty?
        
        # Filter for our trading pair and buy positions only
        our_positions = positions_data.select do |position|
          position['symbol'] == config.pair_symbol && position['type'] == 'POSITION_TYPE_BUY'
        end
        
        # Initialize or update grid manager
        if grid_manager.grid_levels.empty?
          grid_manager.initialize_from_positions(our_positions)
        else
          sync_positions_with_grid(our_positions)
        end
        
        our_positions
        
      rescue ApiClient::ApiError => e
        Logger.error_with_context(e, { context: 'Failed to refresh positions' })
        []
      end
    end

    # Get current price from API
    def current_price
      api_client.get_current_price
    end

    # Check for and handle take profit hits
    def handle_take_profit_hits(current_price)
      return unless current_price
      
      positions_to_close = grid_manager.check_take_profit_hits(current_price)
      
      positions_to_close.each do |tp_info|
        position_id = tp_info[:position_id]
        level = tp_info[:level]
        
        Logger.info("Take profit hit for position #{position_id} at level #{level.level_index}")
        
        # Close the position (in real trading, this would be automatic when TP hits)
        # For our purposes, we just remove it from grid tracking
        grid_manager.remove_position(position_id)
        
        # Try to replace the position if market is still at entry level
        trade_executor.replace_position_at_level(level, current_price)
      end
      
      positions_to_close.size
    end

    # Check if new trade should be placed and execute if needed
    def handle_new_trades(current_price)
      return unless current_price
      
      next_trade = grid_manager.next_trade(current_price)
      return unless next_trade
      
      Logger.info("Placing new trade at level #{next_trade[:level_index]}: Entry=#{next_trade[:entry_price]}, TP=#{next_trade[:take_profit]}")
      
      # Execute the trade
      result = trade_executor.execute_grid_buy(
        entry_price: next_trade[:entry_price],
        take_profit: next_trade[:take_profit]
      )
      
      # If trade was successful (or dry-run), we need to add it to grid
      # In real execution, we'd need to get the actual position ID from response
      # For now, we'll simulate by fetching positions again after a delay
      result
    end

    # Update take profits for all positions based on current grid state
    def update_all_take_profits
      positions_to_update = []
      
      grid_manager.grid_levels.each do |level|
        level.positions.each do |position|
          positions_to_update << {
            id: position.id,
            take_profit: level.take_profit_price
          }
        end
      end
      
      return if positions_to_update.empty?
      
      Logger.info("Updating take profits for #{positions_to_update.size} positions")
      results = trade_executor.update_positions_take_profits(positions_to_update)
      
      # Log results
      successful = results.count { |r| r[:success] }
      failed = results.count { |r| !r[:success] }
      
      if failed > 0
        Logger.warn("Failed to update #{failed} position(s)")
      end
      
      results
    end

    # Get grid state for logging
    def grid_state
      grid_manager.grid_state
    end

    # Log current state
    def log_state(current_price)
      positions = grid_manager.active_positions
      next_entry_price = grid_manager.calculate_next_entry_price(current_price)
      
      Logger.grid_state(positions.map(&:to_api_format), current_price, next_entry_price)
      
      # Log grid levels
      grid_manager.grid_levels.each do |level|
        Logger.info("  #{level}")
      end
    end

    private

    # Create a simulated position for dry-run mode
    def create_simulated_position
      {
        'id' => 'dry-run-simulated-1',
        'type' => 'POSITION_TYPE_BUY',
        'symbol' => config.pair_symbol,
        'openPrice' => 4881.0,  # Starting price of PriceMonitor simulation
        'takeProfit' => 4881.0 + config.grid_spacing,  # TP = entry + grid_spacing
        'volume' => config.lot_size,
        'currentPrice' => 4881.0,
        'profit' => 0.0
      }
    end

    # Sync API positions with grid manager state
    def sync_positions_with_grid(api_positions)
      current_position_ids = grid_manager.active_positions.map(&:id)
      api_position_ids = api_positions.map { |p| p['id'] }
      
      # Find positions that are in grid but not in API (closed positions)
      closed_position_ids = current_position_ids - api_position_ids
      closed_position_ids.each do |position_id|
        grid_manager.remove_position(position_id)
        Logger.info("Position #{position_id} appears to be closed (not in API response)")
      end
      
      # Find positions that are in API but not in grid (new positions)
      new_position_ids = api_position_ids - current_position_ids
      new_position_ids.each do |position_id|
        position_data = api_positions.find { |p| p['id'] == position_id }
        if position_data
          grid_manager.add_position(position_data)
          Logger.info("Added new position #{position_id} to grid")
        end
      end
    end
  end
end