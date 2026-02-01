require 'rest-client'
require 'json'

module TradingBot
  class ApiClient
    class ApiError < StandardError; end
    class NetworkError < ApiError; end
    class AuthenticationError < ApiError; end

    attr_reader :config, :headers

    def initialize(config = EnvironmentConfig)
      @config = config
      @headers = {
        'auth-token' => config.api_key,
        'Content-Type' => 'application/json'
      }
      @max_retries = 3
      @retry_delay = 1  # seconds for network errors
      @server_error_delay = 5  # seconds for server errors (500-599)
    end

    # Get current positions
    def get_positions
      url = "#{config.region_base_url}/users/current/accounts/#{config.account_id}/positions"
      make_request(:get, url)
    end

    # Place a trade
    def place_trade(trade_data)
      url = "#{config.region_base_url}/users/current/accounts/#{config.account_id}/trade"
      make_request(:post, url, trade_data)
    end

    # Get candles for a specific timeframe
    def get_candles(timeframe = '5m')
      url = "#{config.region_market_base_url}/users/current/accounts/#{config.account_id}/historical-market-data/symbols/#{config.pair_symbol}/timeframes/#{timeframe}/candles"
      make_request(:get, url)
    end

    # Get current price (latest candle close)
    def get_current_price
      candles = get_candles('1m')
      return nil if candles.nil? || candles.empty?
      
      # Return the close price of the latest candle
      candles.last['close'].to_f
    rescue => e
      Logger.error_with_context(e, { context: 'Failed to get current price' })
      nil
    end

    # Update a position's take profit
    def update_position(position_id, take_profit)
      trade_data = {
        "actionType" => "POSITION_MODIFY",
        "positionId" => position_id,
        "takeProfit" => take_profit
      }.to_json

      place_trade(trade_data)
    end

    private

    # Make HTTP request with retry logic
    def make_request(method, url, payload = nil)
      retries = 0
      
      begin
        Logger.debug("API #{method.upcase}: #{url}")
        
        case method
        when :get
          response = RestClient.get(url, headers)
        when :post
          response = RestClient.post(url, payload, headers)
        else
          raise ApiError, "Unsupported HTTP method: #{method}"
        end

        parse_response(response)

      rescue RestClient::ExceptionWithResponse => e
        handle_restclient_error(e, method, url, retries)
        retries += 1
        retry if retries < @max_retries
        raise ApiError, "API request failed after #{@max_retries} retries: #{e.message}"
      rescue RestClient::Exception => e
        handle_network_error(e, method, url, retries)
        retries += 1
        sleep(@retry_delay * retries)
        retry if retries < @max_retries
        raise NetworkError, "Network error after #{@max_retries} retries: #{e.message}"
      rescue => e
        Logger.error_with_context(e, { method: method, url: url, payload: payload })
        raise ApiError, "Unexpected error: #{e.message}"
      end
    end

    # Parse API response
    def parse_response(response)
      return nil if response.body.nil? || response.body.strip.empty?
      
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      Logger.error("Failed to parse JSON response: #{e.message}")
      nil
    end

    # Handle RestClient errors
    def handle_restclient_error(error, method, url, retry_count)
      error_message = "API Error (#{error.http_code}): #{error.message}"
      
      case error.http_code
      when 401, 403
        raise AuthenticationError, "Authentication failed: #{error.message}"
      when 429
        Logger.warn("Rate limit exceeded, retrying...")
        sleep(2 * (retry_count + 1))
      when 500..599
        Logger.warn("Server error (#{error.http_code}), retrying...")
        sleep(@server_error_delay * (retry_count + 1))
      else
        Logger.error_with_context(error, { 
          method: method, 
          url: url, 
          http_code: error.http_code,
          response_body: error.response&.body
        })
      end
    end

    # Handle network errors
    def handle_network_error(error, method, url, retry_count)
      Logger.warn("Network error (#{error.class.name}), retry #{retry_count + 1}/#{@max_retries}: #{error.message}")
    end
  end
end