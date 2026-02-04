module TradingBot
  class PositionManager
    attr_reader :api_client, :grid_manager, :trade_executor, :stop_manager, :config

    def initialize(api_client:, grid_manager:, trade_executor:, config: EnvironmentConfig)
      @api_client = api_client
      @grid_manager = grid_manager
      @trade_executor = trade_executor
      @config = config
      @stop_manager = StopManager.new(trade_executor: trade_executor)
      @recently_stopped_positions = {}  # position_id => timestamp
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

    # Update trailing stops based on current price
    # This should be called on each price update
    def update_trailing_stops(current_price)
      return unless current_price
      
      positions = grid_manager.active_positions
      return if positions.empty?
      
      # Initialize first trade flags for stop manager
      stop_manager.initialize_first_trade_flags(positions, grid_manager.grid_levels)
      
      # Update trailing stops
      update_results = stop_manager.update_trailing_stops(positions, current_price)
      
      # Log updates
      update_results.each do |result|
        case result[:action]
        when 'activated'
          Logger.info("Stop activated for position #{result[:position_id]} at #{result[:stop_price]} (threshold: #{result[:threshold]})")
        when 'trailed'
          Logger.info("Stop trailed for position #{result[:position_id]}: #{result[:old_stop]} -> #{result[:new_stop]} (+#{result[:move_distance]})")
        end
      end
      
      update_results.size
    end

    # Check for and handle stop loss hits
    def handle_stop_loss_hits(current_price)
      return 0 unless current_price
      
      positions = grid_manager.active_positions
      return 0 if positions.empty?
      
      positions_to_close = stop_manager.check_stop_loss_hits(positions, current_price)
      
      positions_to_close.each do |stop_info|
        position = stop_info[:position]
        
        Logger.info("Stop loss hit for position #{position.id} at #{stop_info[:stop_price]} (current: #{stop_info[:current_price]})")
        
        # Remove from grid
        grid_manager.remove_position(position.id)
        
        # Track recently stopped position to handle API latency
        @recently_stopped_positions[position.id] = Time.now
        Logger.debug("Tracked recently stopped position #{position.id}")
        
        # Note: With trailing stop strategy, we don't immediately replace positions
        # New positions will be created based on grid spacing rules
        Logger.info("Position #{position.id} closed via stop loss. Profit/Loss: #{position.profit}")
      end
      
      positions_to_close.size
    end

    # Check if new trade should be placed and execute if needed
    def handle_new_trades(current_price)
      return unless current_price
      
      next_trade = grid_manager.next_trade(current_price)
      return unless next_trade
      
      Logger.info("Placing new trade at level #{next_trade[:level_index]}: Entry=#{next_trade[:entry_price]}")
      
      # Execute the trade WITHOUT take profit (trailing stop strategy)
      # Note: We need to modify Trade model to support trades without TP
      # For now, we'll pass nil for take_profit
      result = trade_executor.execute_grid_buy(
        entry_price: next_trade[:entry_price],
        take_profit: nil  # No TP with trailing stop strategy
      )
      
      # If trade was successful (or dry-run), we need to add it to grid
      # In real execution, we'd need to get the actual position ID from response
      # For now, we'll simulate by fetching positions again after a delay
      result
    end

    # Get grid state for logging
    def grid_state
      grid_manager.grid_state
    end

    # Log current state with stop loss information
    def log_state(current_price)
      positions = grid_manager.active_positions
      next_entry_price = grid_manager.calculate_next_entry_price(current_price)
      
      # Log basic grid state
      Logger.grid_state(positions.map(&:to_api_format), current_price, next_entry_price)
      
      # Log detailed position info with stops
      positions.each do |position|
        stop_info = position.stop_loss ? "SL: #{position.stop_loss}" : "SL: None (needs +#{position.activation_threshold})"
        entry_diff = current_price ? (current_price - position.open_price).round(2) : "N/A"
        Logger.info("  Position #{position.id}: Entry #{position.open_price} (#{entry_diff}), #{stop_info}, P&L: #{position.profit}")
      end
      
      # Log grid levels
      grid_manager.grid_levels.each do |level|
        Logger.info("  #{level}")
      end
    end

    private

    # Create a simulated position for dry-run mode (without TP)
    def create_simulated_position
      {
        'id' => 'dry-run-simulated-1',
        'type' => 'POSITION_TYPE_BUY',
        'symbol' => config.pair_symbol,
        'openPrice' => 4881.0,  # Starting price of PriceMonitor simulation
        'takeProfit' => nil,  # No TP with trailing stop strategy
        'volume' => config.lot_size,
        'currentPrice' => 4881.0,
        'profit' => 0.0
      }
    end

    # Sync API positions with grid manager state
    def sync_positions_with_grid(api_positions)
      current_position_ids = grid_manager.active_positions.map(&:id)
      api_position_ids = api_positions.map { |p| p['id'] }
      
      # Filter out recently stopped positions to handle API latency
      current_time = Time.now
      api_positions_filtered = api_positions.reject do |p|
        position_id = p['id']
        if @recently_stopped_positions[position_id]
          # Keep for 30 seconds after stop, then allow re-addition if still in API
          if current_time - @recently_stopped_positions[position_id] > 30
            @recently_stopped_positions.delete(position_id)
            false
          else
            Logger.debug("Filtering out recently stopped position #{position_id}")
            true
          end
        else
          false
        end
      end
      
      # Update API position IDs after filtering
      api_position_ids = api_positions_filtered.map { |p| p['id'] }
      
      # Find positions that are in grid but not in API (closed positions)
      closed_position_ids = current_position_ids - api_position_ids
      closed_position_ids.each do |position_id|
        grid_manager.remove_position(position_id)
        Logger.info("Position #{position_id} appears to be closed (not in API response)")
      end
      
      # Find positions that are in API but not in grid (new positions)
      new_position_ids = api_position_ids - current_position_ids
      new_position_ids.each do |position_id|
        position_data = api_positions_filtered.find { |p| p['id'] == position_id }
        if position_data
          grid_manager.add_position(position_data)
          Logger.info("Added new position #{position_id} to grid")
        end
      end
    end
  end
end
