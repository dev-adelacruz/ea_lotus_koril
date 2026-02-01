require 'spec_helper'
require 'models/grid_level'
require 'models/position'

RSpec.describe TradingBot::GridLevel do
  let(:grid_spacing) { 25.0 }
  
  describe '#initialize' do
    it 'creates a grid level with entry price and index' do
      level = described_class.new(1000.0, 1, 1025.0)
      
      expect(level.entry_price).to eq(1000.0)
      expect(level.level_index).to eq(1)
      expect(level.take_profit_price).to eq(1025.0)
      expect(level.position_count).to eq(0)
      expect(level.active?).to be false
    end

    it 'creates level without take profit' do
      level = described_class.new(1000.0, 1)
      
      expect(level.entry_price).to eq(1000.0)
      expect(level.take_profit_price).to be_nil
    end
  end

  describe '#add_position and #remove_position' do
    let(:level) { described_class.new(1000.0, 1, 1025.0) }
    let(:position_data) do
      {
        'id' => '123',
        'type' => 'POSITION_TYPE_BUY',
        'symbol' => 'ETHUSDm',
        'openPrice' => 1000.0,
        'takeProfit' => 1025.0,
        'volume' => 0.01
      }
    end
    let(:position) { TradingBot::Position.new(position_data) }

    it 'adds a position to the level' do
      level.add_position(position)
      
      expect(level.position_count).to eq(1)
      expect(level.active?).to be true
      expect(level.positions).to include(position)
    end

    it 'does not add duplicate positions' do
      level.add_position(position)
      level.add_position(position) # Same position
      
      expect(level.position_count).to eq(1)
    end

    it 'removes a position from the level' do
      level.add_position(position)
      expect(level.position_count).to eq(1)
      
      level.remove_position('123')
      expect(level.position_count).to eq(0)
      expect(level.active?).to be false
    end

    it 'returns false when removing non-existent position' do
      result = level.remove_position('999')
      expect(result).to be_nil
    end
  end

  describe '#take_profit_hit?' do
    it 'returns true when current price >= take profit' do
      level = described_class.new(1000.0, 1, 1025.0)
      
      expect(level.take_profit_hit?(1025.0)).to be true
      expect(level.take_profit_hit?(1030.0)).to be true
    end

    it 'returns false when current price < take profit' do
      level = described_class.new(1000.0, 1, 1025.0)
      
      expect(level.take_profit_hit?(1020.0)).to be false
      expect(level.take_profit_hit?(1000.0)).to be false
    end

    it 'returns false when take profit is nil' do
      level = described_class.new(1000.0, 1)
      
      expect(level.take_profit_hit?(5000.0)).to be false
    end
  end

  describe '#calculate_take_profit' do
    it 'calculates TP for first level as entry + spacing' do
      level = described_class.new(1000.0, 1)
      level.calculate_take_profit(nil, grid_spacing)
      
      expect(level.take_profit_price).to eq(1025.0)
    end

    it 'calculates TP for subsequent levels as previous entry' do
      level = described_class.new(975.0, 2)
      level.calculate_take_profit(1000.0, grid_spacing)
      
      expect(level.take_profit_price).to eq(1000.0)
    end

    it 'falls back to entry + spacing when no previous entry' do
      level = described_class.new(975.0, 2)
      level.calculate_take_profit(nil, grid_spacing)
      
      expect(level.take_profit_price).to eq(1000.0) # 975 + 25
    end
  end

  describe '#lowest_position_id' do
    it 'returns lowest position ID when positions exist' do
      level = described_class.new(1000.0, 1)
      
      position1 = TradingBot::Position.new('id' => '100', 'type' => 'POSITION_TYPE_BUY', 'symbol' => 'ETHUSDm', 'openPrice' => 1000.0)
      position2 = TradingBot::Position.new('id' => '200', 'type' => 'POSITION_TYPE_BUY', 'symbol' => 'ETHUSDm', 'openPrice' => 1000.0)
      position3 = TradingBot::Position.new('id' => '050', 'type' => 'POSITION_TYPE_BUY', 'symbol' => 'ETHUSDm', 'openPrice' => 1000.0)
      
      level.add_position(position1)
      level.add_position(position2)
      level.add_position(position3)
      
      expect(level.lowest_position_id).to eq('050')
    end

    it 'returns nil when no positions' do
      level = described_class.new(1000.0, 1)
      expect(level.lowest_position_id).to be_nil
    end
  end

  describe '#to_s' do
    it 'returns string representation for active level' do
      level = described_class.new(1000.0, 1, 1025.0)
      position = TradingBot::Position.new('id' => '123', 'type' => 'POSITION_TYPE_BUY', 'symbol' => 'ETHUSDm', 'openPrice' => 1000.0)
      level.add_position(position)
      
      expect(level.to_s).to eq('Level 1: Entry=1000.0, TP=1025.0, ACTIVE (1 positions)')
    end

    it 'returns string representation for inactive level' do
      level = described_class.new(1000.0, 1, 1025.0)
      
      expect(level.to_s).to eq('Level 1: Entry=1000.0, TP=1025.0, INACTIVE')
    end
  end

  describe '#to_h' do
    it 'returns hash representation' do
      level = described_class.new(1000.0, 1, 1025.0)
      position = TradingBot::Position.new('id' => '123', 'type' => 'POSITION_TYPE_BUY', 'symbol' => 'ETHUSDm', 'openPrice' => 1000.0)
      level.add_position(position)
      
      result = level.to_h
      
      expect(result).to include(
        entry_price: 1000.0,
        level_index: 1,
        take_profit_price: 1025.0,
        position_count: 1,
        active: true,
        position_ids: ['123']
      )
    end
  end
end