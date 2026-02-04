module TradingBot
  class StopManager
    class StopError < StandardError; end

    attr_reader :trade_executor

    # Initialize with trade executor for API updates
    def initialize(trade_executor:)
      @trade_executor = trade_executor
    end

    # Update trailing stops for all positions based on current price
    # This should be called on each price update
    # @param positions [Array<Position>] Array of Position objects
    # @param current_price [Float] Current market price
    # @return [Array<Hash>] Array of update results
    def update_trailing_stops(positions, current_price)
      return [] if positions.empty? || current_price.nil?

      update_results = []
      
      positions.each do |position|
        # Skip sell positions (grid is buy-only)
        next unless position.buy?
        
        # Update highest price tracking
        position.update_highest_price(current_price)
        
        result = update_position_stop(position, current_price)
        update_results << result if result
      end
      
      update_results
    end

    # Check for stop loss hits and get positions to close
    # @param positions [Array<Position>] Array of Position objects
    # @param current_price [Float] Current market price
    # @return [Array<Hash>] Array of positions that hit their stop loss
    def check_stop_loss_hits(positions, current_price)
      return [] if positions.empty? || current_price.nil?

      positions_to_close = []
      
      positions.each do |position|
        # Skip sell positions (grid is buy-only)
        next unless position.buy?
        
        if position.stop_loss_hit?(current_price)
          positions_to_close << {
            position: position,
            stop_price: position.stop_loss,
            current_price: current_price,
            reason: 'stop_loss_hit'
          }
        end
      end
      
      positions_to_close
    end

    # Initialize first trade flag for positions in grid
    # Should be called by GridManager when positions are added
    # @param positions [Array<Position>] Array of Position objects
    # @param grid_levels [Array<GridLevel>] Grid levels for context
    def initialize_first_trade_flags(positions, grid_levels)
      return if positions.empty?
      
      # Find the highest entry price (first trade in grid)
      highest_entry = grid_levels.map(&:entry_price).max
      
      positions.each do |position|
        # Mark as first trade if this position is at the highest entry
        # Using tolerance for floating point comparison
        if (position.open_price - highest_entry).abs < 0.001
          position.is_first_trade_in_grid = true
        else
          position.is_first_trade_in_grid = false
        end
      end
    end

    private

    # Update stop loss for a single position
    # Returns hash with update info if stop was changed
    def update_position_stop(position, current_price)
      # Skip if already stopped out
      return nil if position.stop_loss_hit?(current_price)
      
      # Check for initial activation
      if position.stop_loss.nil? && position.reached_activation_level?(current_price)
        return activate_stop_loss(position, current_price)
      end
      
      # Check for trailing update
      if position.stop_loss && position.should_update_trailing_stop?(current_price)
        return update_trailing_stop(position, current_price)
      end
      
      nil
    end

    # Activate initial stop loss
    def activate_stop_loss(position, current_price)
      # Calculate initial stop price
      # For buy positions: stop at activation price (entry + threshold)
      threshold = position.activation_threshold
      stop_price = position.open_price + threshold
      
      # Debug logging for nil values
      if stop_price.nil? || current_price.nil?
        Logger.error("Stop price or current price is nil in activate_stop_loss. stop_price=#{stop_price}, current_price=#{current_price}, open_price=#{position.open_price}, threshold=#{threshold}")
        return nil
      end
      
      # Ensure stop is at or below current price for buy positions
      # (should be, since we're activating when price reached threshold)
      if position.buy? && stop_price && current_price && stop_price > current_price
        stop_price = current_price
      end
      
      # Update via API first
      update_result = update_stop_loss_via_api(position, stop_price)
      
      # Only update position if API call succeeded
      if update_result[:success]
        position.stop_loss = stop_price
        Logger.info("Stop activated for position #{position.id} at #{stop_price} (threshold: #{threshold})")
      else
        Logger.error("Failed to activate stop for position #{position.id} at #{stop_price}: #{update_result[:error]}")
        # Keep stop_loss as nil since API failed
      end
      
      {
        position_id: position.id,
        action: 'activated',
        stop_price: stop_price,
        threshold: threshold,
        api_result: update_result,
        success: update_result[:success]
      }
    end

    # Update trailing stop to current price
    def update_trailing_stop(position, current_price)
      old_stop = position.stop_loss
      new_stop = current_price
      
      # Guard against nil values
      if old_stop.nil? || new_stop.nil?
        Logger.error("Nil value in update_trailing_stop. old_stop=#{old_stop}, new_stop=#{new_stop}, position_id=#{position.id}")
        return nil
      end
      
      # Ensure stop only moves up (for buy positions)
      if position.buy? && new_stop <= old_stop
        return nil  # Stop shouldn't move down
      end
      
      # Update via API first
      update_result = update_stop_loss_via_api(position, new_stop)
      
      # Only update position if API call succeeded
      if update_result[:success]
        position.stop_loss = new_stop
        Logger.info("Stop trailed for position #{position.id}: #{old_stop} -> #{new_stop} (+#{new_stop - old_stop})")
      else
        Logger.error("Failed to trail stop for position #{position.id} from #{old_stop} to #{new_stop}: #{update_result[:error]}")
        # Keep old stop since API failed
      end
      
      {
        position_id: position.id,
        action: 'trailed',
        old_stop: old_stop,
        new_stop: new_stop,
        move_distance: (new_stop - old_stop).abs,
        api_result: update_result,
        success: update_result[:success]
      }
    end

    # Update stop loss via API through trade executor
    # @param position [Position] The position to update
    # @param stop_price [Float, nil] The stop price to set (optional, defaults to position.stop_loss)
    # @return [Hash] Result with :success boolean and :error or :response
    def update_stop_loss_via_api(position, stop_price = nil)
      stop_price ||= position.stop_loss
      
      begin
        response = @trade_executor.update_position_stop_loss(
          position_id: position.id,
          stop_loss: stop_price
        )
        
        # Check if API call succeeded
        # Success codes: 10009 (TRADE_RETCODE_DONE)
        # Error codes: 10016 (TRADE_RETCODE_INVALID_STOPS), etc.
        if response.is_a?(Hash) && response['numericCode'] == 10009
          { success: true, response: response }
        else
          Logger.error("API error updating stop loss for position #{position.id}: #{response}")
          { success: false, error: "API error: #{response['stringCode'] || response['message'] || 'Unknown error'}" }
        end
      rescue => e
        Logger.error("Failed to update stop loss for position #{position.id}: #{e.message}")
        { success: false, error: e.message }
      end
    end
  end
end