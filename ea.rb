#!/usr/bin/env ruby

# Lotus Koril Trading Bot - Buy-Only Grid System
# Version: BETA 0.0.1
# Architecture: Refactored with SOLID principles

require_relative 'app/runners/main_runner'

# Set up signal handlers for graceful shutdown
def setup_signal_handlers(runner)
  Signal.trap('INT') do
    puts "\nReceived INT signal, shutting down..."
    runner.stop
    exit(0)
  end

  Signal.trap('TERM') do
    puts "\nReceived TERM signal, shutting down..."
    runner.stop
    exit(0)
  end
end

# Main entry point
def main
  puts "=" * 60
  puts "Lotus Koril Trading Bot - BETA 0.0.1"
  puts "Buy-Only Grid Trading System"
  puts "=" * 60
  
  # Initialize the main runner
  runner = TradingBot::MainRunner.new
  
  # Set up signal handlers for graceful shutdown
  setup_signal_handlers(runner)
  
  # Run the trading bot
  begin
    runner.run
  rescue => e
    TradingBot::Logger.error_with_context(e, { context: 'Fatal error in main loop' })
    puts "Fatal error occurred: #{e.message}"
    puts "Check logs for details."
    exit(1)
  end
end

# Run if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  main
end