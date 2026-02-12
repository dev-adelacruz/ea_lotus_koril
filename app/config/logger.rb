module TradingBot
  class Logger
    class << self
      # Enable immediate flushing of logs
      def configure!
        $stdout.sync = true
        $stderr.sync = true
      end

      # Log a message with timestamp
      def log(message, level = :info)
        timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        formatted_message = format_message(message, level, timestamp)
        
        case level
        when :error, :warn
          $stderr.puts formatted_message
        else
          $stdout.puts formatted_message
        end
      end

      # Convenience methods
      def info(message)
        log(message, :info)
      end

      def warn(message)
        log(message, :warn)
      end

      def error(message)
        log(message, :error)
      end

      def debug(message)
        log(message, :debug) if ENV['DEBUG'] == 'true'
      end

      # Check if debug logging is enabled
      def debug?
        ENV['DEBUG'] == 'true'
      end

      # Log grid state snapshot
      def grid_state(positions, current_price, next_entry_price)
        info("=== GRID STATE SNAPSHOT ===")
        info("Current Price: #{current_price}")
        info("Next Entry Price: #{next_entry_price}")
        info("Active Positions: #{positions.size}")
        
        positions.each_with_index do |position, index|
          position_num = index + 1
          entry_price = position['openPrice']
          take_profit = position['takeProfit']
          profit = position['profit']
          
          info("  Position #{position_num}: Entry=#{entry_price}, TP=#{take_profit}, Profit=#{profit}")
        end
        info("==========================")
      end

      # Log trade execution
      def trade_executed(action, price, volume, take_profit, dry_run: false)
        dry_run_prefix = dry_run ? "[DRY RUN] " : ""
        info("#{dry_run_prefix}Trade executed: #{action} @ #{price}, Volume: #{volume}, TP: #{take_profit}")
      end

      # Log error with context
      def error_with_context(error, context = {})
        error("ERROR: #{error.message}")
        error("Context: #{context}") unless context.empty?
        error("Backtrace:") if ENV['DEBUG'] == 'true'
        error(error.backtrace.join("\n")) if ENV['DEBUG'] == 'true'
      end

      private

      def format_message(message, level, timestamp)
        level_str = level.to_s.upcase
        "[#{timestamp}] #{level_str.rjust(5)} - #{message}"
      end
    end
  end
end