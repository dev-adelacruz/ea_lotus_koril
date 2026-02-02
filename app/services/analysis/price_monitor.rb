module TradingBot
  class PriceMonitor
    attr_reader :api_client, :polling_interval, :last_price, :price_history, :config

    def initialize(api_client:, polling_interval: 10, config: EnvironmentConfig)
      @api_client = api_client
      @polling_interval = polling_interval
      @config = config
      @last_price = nil
      @price_history = []  # Simple history for basic analysis
      @max_history_size = 100
      @simulated_price = 2200.0  # Starting price for dry-run simulation (gold ~$2200)
    end

    # Get current price with caching
    def current_price(refresh: true)
      if refresh || @last_price.nil?
        refresh_price
      end
      @last_price
    end

    # Refresh price from API or simulate in dry-run mode
    def refresh_price
      if config.dry_run?
        price = simulate_price
        TradingBot::Logger.info("[DRY RUN] Simulated price: #{price.round(2)}")
      else
        price = api_client.get_current_price
      end
      
      if price
        @last_price = price
        add_to_history(price)
      end
      price
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

    # Check if price has crossed a threshold
    # @param threshold [Float] The price level to check
    # @param direction [:above, :below] Direction of crossing
    # @return [Boolean] True if price has crossed the threshold in specified direction
    def crossed_threshold?(threshold, direction: :above)
      return false if @price_history.size < 2
      
      previous_price = @price_history[-2]
      current_price = @last_price
      
      case direction
      when :above
        previous_price < threshold && current_price >= threshold
      when :below
        previous_price > threshold && current_price <= threshold
      else
        false
      end
    end

    # Get price change over last N readings
    # @param periods [Integer] Number of periods to look back
    # @return [Float, nil] Price change or nil if not enough data
    def price_change(periods = 1)
      return nil if @price_history.size < periods + 1
      
      current = @last_price
      past = @price_history[-(periods + 1)]
      current - past
    end

    # Get percentage price change
    # @param periods [Integer] Number of periods to look back
    # @return [Float, nil] Percentage change or nil if not enough data
    def price_change_percent(periods = 1)
      return nil if @price_history.size < periods + 1
      
      current = @last_price
      past = @price_history[-(periods + 1)]
      
      return 0.0 if past == 0
      ((current - past) / past.abs) * 100.0
    end

    # Simple moving average
    # @param periods [Integer] Number of periods for SMA
    # @return [Float, nil] SMA or nil if not enough data
    def sma(periods = 10)
      return nil if @price_history.size < periods
      
      recent_prices = @price_history.last(periods)
      recent_prices.sum / periods.to_f
    end

    # Get price volatility (standard deviation of recent prices)
    # @param periods [Integer] Number of periods to analyze
    # @return [Float, nil] Standard deviation or nil if not enough data
    def volatility(periods = 20)
      return nil if @price_history.size < periods
      
      recent_prices = @price_history.last(periods)
      mean = recent_prices.sum / periods.to_f
      
      variance = recent_prices.sum { |price| (price - mean) ** 2 } / periods.to_f
      Math.sqrt(variance)
    end

    # Check if price is trending (simple detection)
    # @param short_period [Integer] Short-term SMA period
    # @param long_period [Integer] Long-term SMA period
    # @return [:up, :down, :sideways] Trend direction
    def trend(short_period: 5, long_period: 20)
      short_sma = sma(short_period)
      long_sma = sma(long_period)
      
      return :sideways if short_sma.nil? || long_sma.nil?
      
      if short_sma > long_sma
        :up
      elsif short_sma < long_sma
        :down
      else
        :sideways
      end
    end

    # Reset price history
    def reset_history
      @price_history = []
    end

    private

    def add_to_history(price)
      @price_history << price
      
      # Keep history size manageable
      if @price_history.size > @max_history_size
        @price_history.shift(@price_history.size - @max_history_size)
      end
    end
  end
end