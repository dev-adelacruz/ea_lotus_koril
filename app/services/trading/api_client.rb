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

    # Update a position's stop loss
    # Note: This assumes the API supports stop loss updates via POSITION_MODIFY
    # with a "stopLoss" field. If not, this will need to be adjusted.
    def update_position_stop_loss(position_id, stop_loss)
      trade_data = {
        "actionType" => "POSITION_MODIFY",
        "positionId" => position_id,
        "stopLoss" => stop_loss
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

    # Parse API response and check for errors
    def parse_response(response)
      return nil if response.body.nil? || response.body.strip.empty?
      
      parsed = JSON.parse(response.body)
      
      # Check for error codes in MetaTrader API responses
      # Success code: 10009 (TRADE_RETCODE_DONE)
      # Error codes: 10016 (TRADE_RETCODE_INVALID_STOPS), etc.
      if parsed.is_a?(Hash) && parsed.key?('numericCode')
        numeric_code = parsed['numericCode']
        
        # Check if this is an error response
        if numeric_code != 10009  # Not success
          error_message = parsed['message'] || parsed['stringCode'] || "API error #{numeric_code}"
          Logger.error("API error response: #{parsed}")
          raise ApiError, error_message
        end
      end
      
      parsed
    rescue JSON::ParserError => e
      Logger.error("Failed to parse JSON response: #{e.message}")
      raise ApiError, "Invalid JSON response: #{e.message}"
    end

    # Handle RestClient errors
    def handle_restclient_error(error, method, url, retry_count)
      error_message = "API Error (#{error.http_code}): #{error.message}"
      
      case error.http_code
      when 401, 403
        raise AuthenticationError, "Authentication failed: #{error.message}"
      when 400, 422  # Bad Request, Unprocessable Entity - client errors, don't retry
        # Parse the error response for more details
        error_details = "Client error (#{error.http_code}): #{error.message}"
        begin
          if error.response&.body
            parsed = JSON.parse(error.response.body)
            error_details = "Client error (#{error.http_code}): #{parsed['message'] || parsed['stringCode'] || error.message}"
          end
        rescue JSON::ParserError
          # Ignore JSON parsing errors
        end
        raise ApiError, error_details
      when 429
        Logger.warn("Rate limit exceeded, retrying...")
        sleep(2 * (retry_count + 1))
      when 500..599
        Logger.warn("Server error (#{error.http_code}), retrying...")
        sleep(@server_error_delay * (retry_count + 1))
      else
        # For other 4xx errors and unknown errors, raise immediately
        raise ApiError, "API error (#{error.http_code}): #{error.message}"
      end
    end

    # Handle network errors
    def handle_network_error(error, method, url, retry_count)
      Logger.warn("Network error (#{error.class.name}), retry #{retry_count + 1}/#{@max_retries}: #{error.message}")
    end
  end
end