module TradingBot
  class GridManager
    class GridError < StandardError; end

    attr_reader :grid_levels, :grid_spacing, :highest_entry_price

    # Dynamic spacing thresholds
    LARGE_GRID_THRESHOLD = 10  # Number of levels to trigger larger spacing
    LARGE_GRID_SPACING = 50.0  # Spacing when grid has >= 10 levels
    
    # Trailing stop constants
    FIRST_TRADE_ACTIVATION = 5.0   # $5 activation for first trade
    SUBSEQUENT_ACTIVATION = 28.0   # $28 activation for subsequent trades
    TRAILING_DISTANCE = 10.0       # $10 trailing distance

    def initialize(config: EnvironmentConfig, api_client: nil)
      @config = config
      @api_client = api_client
      @grid_spacing = config.grid_spacing
      @grid_levels = []  # Array of GridLevel objects, sorted by entry price (highest to lowest)
      @highest_entry_price = nil
    end

    # Get current grid spacing based on number of levels
    # Returns $50 when grid has 10+ levels, otherwise returns configured spacing ($25)
    def current_grid_spacing
      if @grid_levels.size >= LARGE_GRID_THRESHOLD
        LARGE_GRID_SPACING
      else
        @grid_spacing
      end
    end

    # Initialize grid from existing positions
    def initialize_from_positions(positions)
      @grid_levels = []
      
      # Filter buy positions only (for buy-only grid)
      buy_positions = positions.select { |p| p['type'] == 'POSITION_TYPE_BUY' }
      return if buy_positions.empty?
      
      # Sort positions by entry price (highest to lowest)
      sorted_positions = buy_positions.sort_by { |p| -p['openPrice'].to_f }
      
      # Track highest entry price for first trade identification
      highest_entry = sorted_positions.first['openPrice'].to_f
      @highest_entry_price = highest_entry
      
      # Create grid levels
      sorted_positions.each_with_index do |position_data, index|
        level_index = index + 1
        entry_price = position_data['openPrice'].to_f
        
        # Create GridLevel without take profit (trailing stop strategy)
        level = GridLevel.new(entry_price, level_index)
        
        # Create Position object and add to level
        position = Position.new(position_data)
        
        # Mark as first trade if this is the highest entry price
        # Using tolerance for floating point comparison
        if (entry_price - highest_entry).abs < 0.001
          position.is_first_trade_in_grid = true
        else
          position.is_first_trade_in_grid = false
        end
        
        level.add_position(position)
        
        @grid_levels << level
      end
      
      # No TP recalculation needed with trailing stops
      
      Logger.info("Grid initialized with #{@grid_levels.size} levels")
      Logger.info("Grid levels: #{@grid_levels.map(&:to_s).join(', ')}")
      Logger.info("Highest entry price: #{@highest_entry_price}")
    end

    # Calculate next entry price based on grid spacing
    # Rule: Each new entry is current_grid_spacing below the latest (lowest) entry
    # When grid is empty, first trade should be placed immediately at current market price
    def calculate_next_entry_price(current_price = nil)
      if @grid_levels.empty?
        # First trade: place immediately at current market price
        # Warn if we had positions before and price has moved significantly
        if @highest_entry_price && current_price
          price_move = (@highest_entry_price - current_price).abs
          max_reasonable_move = current_grid_spacing * 5  # 5 grid levels
          
          if price_move > max_reasonable_move
            Logger.warn("Grid restart: Price moved #{price_move.round(2)} from last highest entry #{@highest_entry_price} to #{current_price}")
            Logger.warn("This exceeds reasonable move of #{max_reasonable_move} (#{current_grid_spacing} * 5)")
          else
            Logger.info("Grid restart at current price #{current_price} (moved #{price_move.round(2)} from last highest entry)")
          end
        end
        
        return current_price
      else
        # Subsequent trades: current_grid_spacing below the lowest (most recent) entry price
        lowest_entry = @grid_levels.map(&:entry_price).min
        lowest_entry - current_grid_spacing
      end
    end

    # Add a new position to the grid
    def add_position(position_data, current_price = nil)
      position = Position.new(position_data)
      entry_price = position.open_price
      
      # Basic validation: entry price should be reasonable
      if current_price
        # For buy positions, entry should not be significantly above current price
        # Allow some slippage but log warning if entry > current_price + 5
        if entry_price > current_price + 5.0
          Logger.warn("Position #{position.id} entry price #{entry_price} is significantly above current price #{current_price}")
        end
        
        # Also ensure entry price isn't impossibly high
        if entry_price > current_price * 1.05  # More than 5% above current
          Logger.error("Position #{position.id} entry price #{entry_price} is >5% above current price #{current_price}, likely corrupted data")
          return nil
        end
      end
      
      # Find or create grid level for this entry price
      level = find_or_create_level(entry_price)
      
      # Mark as first trade if this is the highest entry price
      if @grid_levels.empty? || entry_price > (@highest_entry_price || 0)
        position.is_first_trade_in_grid = true
        @highest_entry_price = entry_price
      else
        position.is_first_trade_in_grid = false
      end
      
      # Add position to level
      level.add_position(position)
      
      # Sort grid levels by entry price (highest to lowest)
      @grid_levels.sort_by! { |level| -level.entry_price }
      
      # No TP recalculation needed with trailing stops
      
      Logger.info("Added position #{position.id} to grid level #{level.level_index}")
      Logger.info("Position #{position.id} marked as first trade: #{position.is_first_trade_in_grid}")
      Logger.info("Entry price: #{entry_price}, Highest entry: #{@highest_entry_price}")
      
      level
    end

    # Remove a position from the grid
    def remove_position(position_id)
      @grid_levels.each do |level|
        if level.positions.any? { |p| p.id == position_id }
          level.remove_position(position_id)
          Logger.info("Removed position #{position_id} from grid level #{level.level_index}")
          
          # Remove level if no more positions
          if !level.active?
            @grid_levels.delete(level)
            Logger.info("Removed empty grid level #{level.level_index}")
          end
          
          # No TP recalculation needed with trailing stops
          return true
        end
      end
      
      false
    end

    # Check if we should place a new trade
    def should_place_trade?(current_price)
      return false unless current_price
      
      next_entry_price = calculate_next_entry_price(current_price)
      return false unless next_entry_price
      
      # Allow small tolerance for floating point precision issues
      tolerance = 0.001
      should_place = current_price <= next_entry_price + tolerance
      
      # Debug logging for trade decisions
      if Logger.debug?
        diff = (current_price - next_entry_price).abs
        Logger.debug("Trade decision: current_price=#{current_price}, next_entry=#{next_entry_price}, diff=#{diff}, tolerance=#{tolerance}, should_place=#{should_place}")
      end
      
      should_place
    end

    # Get the next trade to execute (no take profit with trailing stop strategy)
    def next_trade(current_price)
      return nil unless should_place_trade?(current_price)
      
      next_entry_price = calculate_next_entry_price(current_price)
      return nil unless next_entry_price
      
      {
        entry_price: next_entry_price,
        level_index: @grid_levels.size + 1
      }
    end

    # Get all active positions
    def active_positions
      @grid_levels.flat_map(&:positions)
    end

    # Get grid state for logging
    def grid_state
      @grid_levels.map(&:to_h)
    end

    private

    # Find existing level by entry price, or create new one
    def find_or_create_level(entry_price)
      # Try to find existing level with this entry price
      level = @grid_levels.find { |l| (l.entry_price - entry_price).abs < 0.001 }
      
      if level.nil?
        # Create new level
        level_index = @grid_levels.size + 1
        level = GridLevel.new(entry_price, level_index)
        @grid_levels << level
        
        # Sort levels
        @grid_levels.sort_by! { |l| -l.entry_price }
        
        # Re-index levels
        reindex_levels
      end
      
      level
    end

    # Re-index grid levels after changes
    def reindex_levels
      # Sort levels by entry price (highest to lowest) and reassign
      @grid_levels.sort_by! { |level| -level.entry_price }
      
      # Update level indices
      @grid_levels.each_with_index do |level, index|
        level.instance_variable_set(:@level_index, index + 1)
      end
    end
  end
end