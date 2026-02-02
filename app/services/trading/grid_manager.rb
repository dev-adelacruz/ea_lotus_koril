module TradingBot
  class GridManager
    class GridError < StandardError; end

    attr_reader :grid_levels, :grid_spacing, :highest_entry_price

    # First trade take profit offset (changed from grid_spacing to $3)
    FIRST_TRADE_TP_OFFSET = 3.0

    def initialize(config: EnvironmentConfig, api_client: nil)
      @config = config
      @api_client = api_client
      @grid_spacing = config.grid_spacing
      @grid_levels = []  # Array of GridLevel objects, sorted by entry price (highest to lowest)
      @highest_entry_price = nil
    end

    # Initialize grid from existing positions
    def initialize_from_positions(positions)
      @grid_levels = []
      
      # Filter buy positions only (for buy-only grid)
      buy_positions = positions.select { |p| p['type'] == 'POSITION_TYPE_BUY' }
      return if buy_positions.empty?
      
      # Sort positions by entry price (highest to lowest)
      sorted_positions = buy_positions.sort_by { |p| -p['openPrice'].to_f }
      
      # Create grid levels
      sorted_positions.each_with_index do |position_data, index|
        level_index = index + 1
        entry_price = position_data['openPrice'].to_f
        take_profit = position_data['takeProfit']&.to_f
        
        level = GridLevel.new(entry_price, level_index, take_profit)
        
        # Create Position object and add to level
        position = Position.new(position_data)
        level.add_position(position)
        
        @grid_levels << level
      end
      
      @highest_entry_price = @grid_levels.first&.entry_price
      
      # Recalculate take profits based on grid rules
      recalculate_take_profits
      
      Logger.info("Grid initialized with #{@grid_levels.size} levels")
      Logger.info("Grid levels: #{@grid_levels.map(&:to_s).join(', ')}")
    end

    # Calculate next entry price based on grid spacing
    # Rule: Each new entry is $grid_spacing below the latest (lowest) entry
    # When grid is empty, first trade should be placed immediately at current market price
    def calculate_next_entry_price(current_price = nil)
      if @grid_levels.empty?
        # First trade: place immediately at current market price
        return current_price
      else
        # Subsequent trades: $grid_spacing below the lowest (most recent) entry price
        lowest_entry = @grid_levels.map(&:entry_price).min
        lowest_entry - @grid_spacing
      end
    end

    # Add a new position to the grid
    def add_position(position_data, current_price = nil)
      position = Position.new(position_data)
      
      # Find or create grid level for this entry price
      entry_price = position.open_price
      level = find_or_create_level(entry_price)
      
      # Add position to level
      level.add_position(position)
      
      # Update highest entry price if this is a new highest level
      if @grid_levels.empty? || entry_price > @highest_entry_price
        @highest_entry_price = entry_price
      end
      
      # Sort grid levels by entry price (highest to lowest)
      @grid_levels.sort_by! { |level| -level.entry_price }
      
      # Recalculate take profits for all levels
      recalculate_take_profits
      
      Logger.info("Added position #{position.id} to grid level #{level.level_index}")
      
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
          
          # Recalculate take profits
          recalculate_take_profits
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
      
      # For first trade (empty grid), allow small tolerance for floating point
      # For subsequent trades, require price <= entry
      tolerance = @grid_levels.empty? ? 0.001 : 0
      current_price <= next_entry_price + tolerance
    end

    # Get the next trade to execute
    def next_trade(current_price)
      return nil unless should_place_trade?(current_price)
      
      next_entry_price = calculate_next_entry_price(current_price)
      return nil unless next_entry_price
      
      # Calculate take profit for the new level
      new_level_index = @grid_levels.size + 1
      take_profit = calculate_take_profit_for_level(new_level_index, next_entry_price)
      
      {
        entry_price: next_entry_price,
        take_profit: take_profit,
        level_index: new_level_index
      }
    end

    # Check for take profit hits and get positions to close
    def check_take_profit_hits(current_price)
      positions_to_close = []
      
      @grid_levels.each do |level|
        if level.take_profit_hit?(current_price)
          # Close the lowest position ID at this level (FIFO-like)
          position_id_to_close = level.lowest_position_id
          if position_id_to_close
            positions_to_close << {
              position_id: position_id_to_close,
              level: level,
              take_profit_price: level.take_profit_price
            }
          end
        end
      end
      
      positions_to_close
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

    # Recalculate take profits for all grid levels based on grid rules
    def recalculate_take_profits
      return if @grid_levels.empty?
      
      # Sort levels by entry price (highest to lowest)
      sorted_levels = @grid_levels.sort_by { |level| -level.entry_price }
      
      sorted_levels.each_with_index do |level, index|
        level_index = index + 1
        
        if level_index == 1
          # First level: TP = entry + $3 (FIRST_TRADE_TP_OFFSET)
          previous_entry = nil
          tp_offset = FIRST_TRADE_TP_OFFSET
        else
          # Subsequent levels: TP = previous level's entry price
          previous_entry = sorted_levels[index - 1].entry_price
          tp_offset = @grid_spacing  # Not used for levels > 1, but required parameter
        end
        
        level.calculate_take_profit(previous_entry, tp_offset)
      end
    end

    # Re-index grid levels after changes
    def reindex_levels
      sorted_levels = @grid_levels.sort_by { |level| -level.entry_price }
      
      sorted_levels.each_with_index do |level, index|
        level.instance_variable_set(:@level_index, index + 1)
      end
    end

    # Calculate take profit for a specific level
    def calculate_take_profit_for_level(level_index, entry_price)
      if level_index == 1
        # First level: TP = entry + $3 (FIRST_TRADE_TP_OFFSET)
        entry_price + FIRST_TRADE_TP_OFFSET
      else
        # Find the previous level's entry price
        previous_level = @grid_levels.find { |level| level.level_index == level_index - 1 }
        previous_level ? previous_level.entry_price : entry_price + @grid_spacing
      end
    end
  end
end