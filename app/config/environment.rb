require 'dotenv'

module TradingBot
  class EnvironmentConfig
    class << self
      # Load environment variables
      def load!(env_file = nil)
        env_file ||= ENV['DOTENV'] || '.env'
        Dotenv.load(env_file)
        validate!
        true
      end

      # Required environment variables
      def api_key
        ENV['API_KEY'] or raise 'API_KEY environment variable is required'
      end

      def account_id
        ENV['ACCOUNT_ID'] or raise 'ACCOUNT_ID environment variable is required'
      end

      def region_base_url
        ENV['REGION_BASE_URL'] or raise 'REGION_BASE_URL environment variable is required'
      end

      def region_market_base_url
        ENV['REGION_MARKET_BASE_URL'] or raise 'REGION_MARKET_BASE_URL environment variable is required'
      end

      def pair_symbol
        ENV['PAIR_SYMBOL'] || 'ETHUSDm'
      end

      # Grid trading configuration
      def grid_spacing
        (ENV['GRID_SPACING'] || '25.0').to_f
      end

      def lot_size
        (ENV['LOT_SIZE'] || '0.01').to_f
      end

      # Operational configuration
      def dry_run?
        ENV['DRY_RUN']&.downcase == 'true'
      end

      def polling_interval
        (ENV['POLLING_INTERVAL'] || '10').to_i
      end

      def trade_comment
        ENV['TRADE_COMMENT'] || 'Lotus Koril BETA 0.0.1'
      end

      # Validation
      def validate!
        required_vars = ['API_KEY', 'ACCOUNT_ID', 'REGION_BASE_URL', 'REGION_MARKET_BASE_URL']
        missing = required_vars.select { |var| ENV[var].to_s.strip.empty? }
        
        unless missing.empty?
          raise "Missing required environment variables: #{missing.join(', ')}"
        end

        validate_numeric('GRID_SPACING', grid_spacing, 'positive float') { |v| v > 0 }
        validate_numeric('LOT_SIZE', lot_size, 'positive float') { |v| v > 0 }
        validate_numeric('POLLING_INTERVAL', polling_interval, 'positive integer') { |v| v > 0 }
      end

      private

      def validate_numeric(name, value, description, &block)
        return if block.call(value)
        raise "Invalid #{name}: #{value}. Must be a #{description}."
      end
    end
  end
end