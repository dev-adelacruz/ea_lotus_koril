require 'spec_helper'
require 'models/position'

RSpec.describe TradingBot::Position do
  let(:api_data) do
    {
      'id' => '12345',
      'type' => 'POSITION_TYPE_BUY',
      'symbol' => 'XAUUSD-VIP',
      'openPrice' => 3000.0,
      'takeProfit' => 3025.0,
      'volume' => 0.01,
      'currentPrice' => 3010.0,
      'profit' => 10.0
    }
  end

  describe '#initialize' do
    it 'creates a position from API data' do
      position = described_class.new(api_data)
      
      expect(position.id).to eq('12345')
      expect(position.buy?).to be true
      expect(position.sell?).to be false
      expect(position.open_price).to eq(3000.0)
      expect(position.take_profit).to eq(3025.0)
      expect(position.volume).to eq(0.01)
      expect(position.current_price).to eq(3010.0)
      expect(position.profit).to eq(10.0)
    end

    it 'handles nil take profit' do
      data = api_data.dup
      data['takeProfit'] = nil
      position = described_class.new(data)
      
      expect(position.take_profit).to be_nil
    end
  end

  describe '#buy?' do
    it 'returns true for buy positions' do
      position = described_class.new(api_data)
      expect(position.buy?).to be true
    end

    it 'returns false for sell positions' do
      data = api_data.dup
      data['type'] = 'POSITION_TYPE_SELL'
      position = described_class.new(data)
      
      expect(position.buy?).to be false
      expect(position.sell?).to be true
    end
  end

  describe '#take_profit_hit?' do
    it 'returns true when current price >= take profit for buy' do
      position = described_class.new(api_data)
      
      # Current price equal to TP
      expect(position.take_profit_hit?(3025.0)).to be true
      
      # Current price above TP
      expect(position.take_profit_hit?(3030.0)).to be true
    end

    it 'returns false when current price < take profit for buy' do
      position = described_class.new(api_data)
      
      expect(position.take_profit_hit?(3020.0)).to be false
      expect(position.take_profit_hit?(3000.0)).to be false
    end

    it 'returns false when take profit is nil' do
      data = api_data.dup
      data['takeProfit'] = nil
      position = described_class.new(data)
      
      expect(position.take_profit_hit?(5000.0)).to be false
    end

    it 'handles sell positions correctly' do
      data = api_data.dup
      data['type'] = 'POSITION_TYPE_SELL'
      data['takeProfit'] = 2975.0
      position = described_class.new(data)
      
      # For sell, TP hit when price <= TP
      expect(position.take_profit_hit?(2975.0)).to be true
      expect(position.take_profit_hit?(2970.0)).to be true
      expect(position.take_profit_hit?(2980.0)).to be false
    end
  end

  describe '#distance_to_take_profit' do
    it 'calculates distance for buy positions' do
      position = described_class.new(api_data)
      
      expect(position.distance_to_take_profit(3010.0)).to eq(15.0) # 3025 - 3010
      expect(position.distance_to_take_profit(3025.0)).to eq(0.0)
      expect(position.distance_to_take_profit(3030.0)).to eq(-5.0) # Negative when past TP
    end

    it 'calculates distance for sell positions' do
      data = api_data.dup
      data['type'] = 'POSITION_TYPE_SELL'
      data['takeProfit'] = 2975.0
      position = described_class.new(data)
      
      expect(position.distance_to_take_profit(2980.0)).to eq(5.0) # 2980 - 2975, price above TP, needs to fall
      expect(position.distance_to_take_profit(2975.0)).to eq(0.0)
      expect(position.distance_to_take_profit(2970.0)).to eq(-5.0) # Negative when past TP (price below TP)
    end

    it 'returns nil when take profit is nil' do
      data = api_data.dup
      data['takeProfit'] = nil
      position = described_class.new(data)
      
      expect(position.distance_to_take_profit(3000.0)).to be_nil
    end
  end

  describe '#profitable?' do
    it 'returns true when profit > 0' do
      position = described_class.new(api_data)
      expect(position.profitable?).to be true
    end

    it 'returns false when profit <= 0' do
      data = api_data.dup
      data['profit'] = -10.0
      position = described_class.new(data)
      
      expect(position.profitable?).to be false
    end

    it 'handles nil profit' do
      data = api_data.dup
      data['profit'] = nil
      position = described_class.new(data)
      
      expect(position.profitable?).to be false
    end
  end

  describe '#to_api_format' do
    it 'converts position back to API format' do
      position = described_class.new(api_data)
      result = position.to_api_format
      
      expect(result).to eq({
        'id' => '12345',
        'type' => 'POSITION_TYPE_BUY',
        'symbol' => 'XAUUSD-VIP',
        'openPrice' => 3000.0,
        'takeProfit' => 3025.0,
        'volume' => 0.01
      })
    end
  end

  describe '#to_s' do
    it 'returns string representation' do
      position = described_class.new(api_data)
      expect(position.to_s).to eq('BUY XAUUSD-VIP @ 3000.0, TP: 3025.0, Profit: 10.0')
    end
  end
end