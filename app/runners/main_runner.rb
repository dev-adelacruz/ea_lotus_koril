require_relative '../../app/config/environment'
require_relative '../../app/config/logger'
require_relative '../../app/models/position'
require_relative '../../app/models/grid_level'
require_relative '../../app/models/trade'
require_relative '../../app/services/trading/api_client'
require_relative '../../app/services/trading/grid_manager'
require_relative '../../app/services/trading/trade_executor'
require_relative '../../app/services/trading/position_manager'
require_relative '../../app/services/analysis/price_monitor'

module TradingBot
  class MainRunner
    attr_reader :config, :api_client, :grid_manager, :trade_executor, :position_manager, :price_monitor

    def initialize
      # Load configuration
      @config = EnvironmentConfig
      @config.load!
      
      # Configure logging
      Logger.configure!
      
      # Log startup information
      Logger.info("=" * 60)
      Logger.info("Lotus Koril Trading Bot BETA 0.0.1")
      Logger.info("Grid Spacing: $#{config.grid_spacing}")
      Logger.info("Lot Size: #{config.lot_size}")
      Logger.info("Dry Run Mode: #{config.dry_run? ? 'ON' : 'OFF'}")
      Logger.info("Polling Interval: #{config.polling_interval} seconds")
      Logger.info("=" * 60)
      
      # Initialize services with dependency injection
      @api_client = ApiClient.new(config)
      @grid_manager = GridManager.new(config: config, api_client: @api_client)
      @trade_executor = TradeExecutor.new(api_client: @api_client, config: config)
      @position_manager = PositionManager.new(
        api_client: @api_client,
        grid_manager: @grid_manager,
        trade_executor: @trade_executor,
        config: config
      )
      @price_monitor = PriceMonitor.new(
        api_client: @api_client,
        polling_interval: config.polling_interval,
        config: config
      )
      
      @running = true
      @iteration_count = 0
      
      Logger.info("Services initialized successfully")
    end

    # Main execution loop
    def run
      Logger.info("Starting main execution loop...")
      
      while @running
        begin
          @iteration_count += 1
          Logger.info("Iteration #{@iteration_count}")
          
          # Refresh current price
          current_price = @price_monitor.current_price(refresh: true)
          
          if current_price.nil?
            Logger.error("Failed to get current price, skipping iteration")
            sleep(config.polling_interval)
            next
          end
          
          # Refresh positions from API
          positions = @position_manager.refresh_positions
          
          # Log current state
          @position_manager.log_state(current_price)
          
          # Handle take profit hits
          tp_hits = @position_manager.handle_take_profit_hits(current_price)
          Logger.info("Take profit hits: #{tp_hits}") if tp_hits > 0
          
          # Handle new trades if needed
          trade_result = @position_manager.handle_new_trades(current_price)
          if trade_result
            Logger.info("Trade placed: #{trade_result}")
            
            # After placing trade, refresh positions to capture it
            @position_manager.refresh_positions
          end
          
          # Update take profits if grid changed
          if tp_hits > 0 || trade_result
            @position_manager.update_all_take_profits
          end
          
          # Log grid state
          log_grid_summary(current_price)
          
        rescue => e
          Logger.error_with_context(e, { iteration: @iteration_count })
          # Don't stop on error, continue with next iteration
        ensure
          # Sleep before next iteration unless we're stopping
          if @running
            Logger.info("Sleeping for #{config.polling_interval} seconds...")
            sleep(config.polling_interval)
          end
        end
      end
      
      Logger.info("Execution loop stopped")
    end

    # Stop the execution loop
    def stop
      Logger.info("Stopping execution loop...")
      @running = false
    end

    # Single iteration (useful for testing)
    def run_once
      Logger.info("Running single iteration...")
      
      current_price = @price_monitor.current_price(refresh: true)
      return false if current_price.nil?
      
      positions = @position_manager.refresh_positions
      @position_manager.log_state(current_price)
      
      tp_hits = @position_manager.handle_take_profit_hits(current_price)
      trade_result = @position_manager.handle_new_trades(current_price)
      
      if tp_hits > 0 || trade_result
        @position_manager.update_all_take_profits
      end
      
      log_grid_summary(current_price)
      
      true
    end

    # Get current status
    def status
      {
        iteration_count: @iteration_count,
        running: @running,
        grid_levels: @grid_manager.grid_levels.size,
        active_positions: @grid_manager.active_positions.size,
        current_price: @price_monitor.current_price(refresh: false),
        dry_run: config.dry_run?
      }
    end

    private

    def log_grid_summary(current_price)
      levels = @grid_manager.grid_levels
      active_positions = @grid_manager.active_positions.size
      next_entry = @grid_manager.calculate_next_entry_price(current_price)
      
      Logger.info("=== GRID SUMMARY ===")
      Logger.info("Active Positions: #{active_positions}")
      Logger.info("Grid Levels: #{levels.size}")
      Logger.info("Current Price: #{current_price}")
      Logger.info("Next Entry Price: #{next_entry}")
      
      if next_entry
        distance_to_next = current_price - next_entry
        if distance_to_next <= 0
          Logger.info("READY FOR NEXT TRADE (price at or below next entry)")
        else
          Logger.info("Distance to next entry: #{distance_to_next.round(2)}")
        end
      end
      
      Logger.info("====================")
    end
  end
end