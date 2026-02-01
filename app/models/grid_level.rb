module TradingBot
  class GridLevel
    attr_reader :entry_price, :positions, :take_profit_price, :level_index

    # Initialize a grid level
    # @param entry_price [Float] The price at which to enter trades at this level
    # @param level_index [Integer] The index of this level (1-based)
    # @param take_profit_price [Float, nil] The take profit price for this level
    def initialize(entry_price, level_index, take_profit_price = nil)
      @entry_price = entry_price
      @level_index = level_index
      @take_profit_price = take_profit_price
      @positions = []  # Array of Position objects at this level
    end

    # Add a position to this grid level
    def add_position(position)
      @positions << position unless @positions.any? { |p| p.id == position.id }
    end

    # Remove a position from this grid level
    def remove_position(position_id)
      @positions.reject! { |p| p.id == position_id }
    end

    # Check if this level has any active positions
    def active?
      !@positions.empty?
    end

    # Get the number of active positions at this level
    def position_count
      @positions.size
    end

    # Check if the take profit price has been hit
    def take_profit_hit?(current_price)
      return false unless take_profit_price && current_price
      current_price >= take_profit_price  # For buy-only grid
    end

    # Calculate the take profit price based on grid rules
    # Rule: Level 1 TP = entry + grid_spacing, Level N TP = entry of Level N-1
    # @param previous_level_entry [Float, nil] The entry price of the previous level
    # @param grid_spacing [Float] The spacing between grid levels
    def calculate_take_profit(previous_level_entry, grid_spacing)
      if level_index == 1
        # First level: TP = entry + grid_spacing
        @take_profit_price = entry_price + grid_spacing
      elsif previous_level_entry
        # Subsequent levels: TP = previous level's entry price
        @take_profit_price = previous_level_entry
      else
        # Should not happen in valid grid
        @take_profit_price = entry_price + grid_spacing
      end
    end

    # Update take profit for all positions at this level
    def update_positions_take_profit(new_take_profit)
      @take_profit_price = new_take_profit
      # Note: Actual position updates are handled by PositionManager
    end

    # Get the lowest position ID at this level (for replacement logic)
    def lowest_position_id
      @positions.min_by(&:id)&.id
    end

    # String representation
    def to_s
      active_str = active? ? "ACTIVE (#{position_count} positions)" : "INACTIVE"
      "Level #{level_index}: Entry=#{entry_price}, TP=#{take_profit_price}, #{active_str}"
    end

    # Convert to hash for serialization
    def to_h
      {
        entry_price: entry_price,
        level_index: level_index,
        take_profit_price: take_profit_price,
        position_count: position_count,
        active: active?,
        position_ids: @positions.map(&:id)
      }
    end
  end
end