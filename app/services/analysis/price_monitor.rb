module TradingBot
  class PriceMonitor
    attr_reader :api_client, :polling_interval, :config, :position_manager, :last_price_fetch_time

    def initialize(api_client:, polling_interval: 10, config: EnvironmentConfig, position_manager: nil)
      @api_client = api_client
      @polling_interval = polling_interval
      @config = config
      @position_manager = position_manager
      @simulated_price = 2200.0  # Starting price for dry-run simulation (gold ~$2200)
      @last_price_fetch_time = nil
    end

    # Get current price - ALWAYS FETCHES FRESH, NO CACHING
    def current_price(refresh: true, positions: nil, force_cache_bust: false)
      # 'refresh' parameter is ignored - always fetches fresh price
      # Log that we're fetching fresh price
      TradingBot::Logger.debug("PriceMonitor: Fetching fresh price (caching disabled, force_cache_bust: #{force_cache_bust})")
      
      # Record when we started fetching
      fetch_start_time = Time.now
      
      if config.dry_run?
        price = simulate_price
        TradingBot::Logger.info("[DRY RUN] Simulated price: #{price.round(2)}")
        @last_price_fetch_time = Time.now
      else
        # Try to get price from multiple sources for best accuracy
        price = get_current_price_from_best_source(positions, force_cache_bust)
        
        # Log which source we're using and timestamp
        if price
          @last_price_fetch_time = Time.now
          fetch_duration = @last_price_fetch_time - fetch_start_time
          
          TradingBot::Logger.debug("PriceMonitor: Got fresh price #{price.round(2)} at #{@last_price_fetch_time.strftime('%H:%M:%S.%L')} (fetch took #{fetch_duration.round(3)}s)")
          
          # Warn if price fetch took too long
          if fetch_duration > 2.0  # More than 2 seconds
            TradingBot::Logger.warn("PriceMonitor: Price fetch took #{fetch_duration.round(2)}s (slow)")
          end
        else
          TradingBot::Logger.warn("PriceMonitor: Could not get price from any source")
        end
      end
      
      price
    end

    # Alias for backward compatibility (always fetches fresh)
    def refresh_price(positions = nil)
      current_price(refresh: true, positions: positions)
    end
    
    # Try multiple sources to get the most accurate current price
    def get_current_price_from_best_source(positions = nil, force_cache_bust = false)
      # Source 1: Try to get price from positions (most accurate when we have positions)
      price_from_positions = get_price_from_active_positions(positions)
      return price_from_positions if price_from_positions
      
      # Source 2: Fall back to candle data
      price_from_candles = api_client.get_current_price(cache_bust: force_cache_bust)
      return price_from_candles if price_from_candles
      
      nil
    end
    
    # Get current price from active positions (most accurate source when available)
    def get_price_from_active_positions(positions = nil)
      return nil unless @position_manager
      
      # Use provided positions or fetch fresh ones if not provided
      if positions.nil?
        positions = @position_manager.refresh_positions
      end
      
      return nil if positions.nil? || positions.empty?
      
      # Extract current prices from positions
      current_prices = positions.map do |position|
        # Handle both Position objects and API hash responses
        if position.is_a?(Hash)
          position['currentPrice']&.to_f
        else
          position.current_price
        end
      end.compact
      
      return nil if current_prices.empty?
      
      # Use median price to avoid outliers
      median_price = calculate_median(current_prices)
      
      # Log price source and values for debugging
      TradingBot::Logger.debug("PriceMonitor: Got price #{median_price.round(2)} from #{current_prices.size} positions")
      TradingBot::Logger.debug("Position prices: #{current_prices.map { |p| p.round(2) }.join(', ')}")
      
      median_price
    rescue => e
      TradingBot::Logger.error_with_context(e, { context: 'Failed to get price from positions' })
      nil
    end
    
    # Calculate median of an array of numbers
    def calculate_median(numbers)
      return nil if numbers.empty?
      
      sorted = numbers.sort
      len = sorted.length
      
      if len.odd?
        sorted[len / 2]
      else
        (sorted[len / 2 - 1] + sorted[len / 2]) / 2.0
      end
    end

    # Simulate a moving market for dry-run mode
    def simulate_price
      # Random walk: ±$5 per iteration with slight upward bias
      change = (rand * 10) - 4.5  # -4.5 to +5.5 range, average +0.5
      @simulated_price += change
      
      # Keep price in reasonable range
      @simulated_price = [@simulated_price, 100.0].max  # Don't go below 100
      @simulated_price.round(2)
    end

    # Clear any cached price data and force fresh fetch
    def clear_cache!
      TradingBot::Logger.info("PriceMonitor: Clearing all cached price data")
      @last_price_fetch_time = nil
      
      if config.dry_run?
        TradingBot::Logger.info("PriceMonitor: Resetting simulated price to 2200.0")
        @simulated_price = 2200.0
      end
      
      true
    end

    # Force refresh with cache busting
    def force_refresh(positions = nil)
      TradingBot::Logger.info("PriceMonitor: Force refreshing price with cache busting")
      current_price(refresh: true, positions: positions, force_cache_bust: true)
    end

    # Get price with cache busting (one-time forced refresh)
    def current_price_with_cache_bust(positions = nil)
      TradingBot::Logger.info("PriceMonitor: Getting price with cache busting")
      current_price(refresh: true, positions: positions, force_cache_bust: true)
    end

    # Check if price data is stale (older than threshold seconds)
    def price_stale?(threshold_seconds = 300)  # default 5 minutes
      return true if @last_price_fetch_time.nil?
      
      age_seconds = Time.now - @last_price_fetch_time
      stale = age_seconds > threshold_seconds
      
      if stale
        TradingBot::Logger.warn("PriceMonitor: Price data is stale! Last fetch: #{@last_price_fetch_time}, Age: #{age_seconds.round(0)} seconds")
      end
      
      stale
    end

    # Get cache status information
    def cache_status
      {
        last_price_fetch_time: @last_price_fetch_time,
        price_stale: price_stale?,
        dry_run: config.dry_run?,
        simulated_price: config.dry_run? ? @simulated_price : nil
      }
    end
  end
end
