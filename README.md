# Lotus Koril Trading Bot

A Ruby-based automated trading bot implementing a buy-only grid trading strategy for cryptocurrency (ETH/USD).

## Features

- **Buy-Only Grid Trading**: All trades are BUY orders with fixed $25 spacing
- **Dynamic Take Profit Ladder**: 
  - Trade 1 TP = Entry + $25
  - Trade N TP = Entry price of Trade (N-1)
- **Automatic Position Replacement**: When a position hits TP, it's replaced at the same entry price if market is still there
- **SOLID Architecture**: Maintainable, testable codebase following software engineering best practices
- **Dry-Run Mode**: Test trading logic without placing real orders
- **Comprehensive Logging**: Plain-text logs with timestamps for easy monitoring
- **Infrastructure as Code**: Terraform deployment for AWS EC2
- **Service Management**: Systemd service for process management

## Architecture

The codebase follows a clean architecture with clear separation of concerns:

```
app/
├── models/           # Domain models (Position, GridLevel, Trade)
├── services/         # Business logic services
│   ├── trading/     # Trading-specific services
│   └── analysis/    # Price analysis services
├── config/          # Configuration and logging
└── runners/         # Orchestration and main loops
```

## Installation

### Prerequisites
- Ruby 2.7+
- Bundler
- MetaTrader account with API access

### Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd ea_eth_soban
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Configure environment variables**
   Copy `.env.example` to `.env` and update with your credentials:
   ```bash
   cp .env.example .env
   # Edit .env with your API credentials
   ```

4. **Test the installation**
   ```bash
   bundle exec rspec  # Run tests
   ruby ea.rb --dry-run  # Test in dry-run mode
   ```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_KEY` | MetaTrader API key | **Required** |
| `ACCOUNT_ID` | Trading account ID | **Required** |
| `REGION_BASE_URL` | API base URL | **Required** |
| `REGION_MARKET_BASE_URL` | Market data API URL | **Required** |
| `PAIR_SYMBOL` | Trading pair symbol | `ETHUSDm` |
| `GRID_SPACING` | Spacing between grid levels | `25.0` |
| `LOT_SIZE` | Fixed lot size per trade | `0.01` |
| `DRY_RUN` | Enable dry-run mode | `false` |
| `POLLING_INTERVAL` | Price check interval (seconds) | `10` |
| `TRADE_COMMENT` | Comment for trades | `Lotus Koril BETA 0.0.1` |

### Grid Trading Rules

The bot implements the following grid strategy:

1. **First Trade**: BUY at current market price
2. **Subsequent Trades**: Each new BUY is placed $25 below the previous entry
3. **Take Profit Rules**:
   - Trade 1: TP = Entry + $25
   - Trade 2: TP = Trade 1 Entry price
   - Trade 3: TP = Trade 2 Entry price
   - ...and so on
4. **Position Replacement**: When price hits a TP level, the position closes and is immediately replaced with a new BUY at the same entry price if market is still there

### Example Scenario

```
Market Price: 1000
Trade 1: BUY @ 1000, TP @ 1025

Price drops to 975:
Trade 2: BUY @ 975, TP @ 1000 (Trade 1 entry)

Price drops to 950:
Trade 3: BUY @ 950, TP @ 975 (Trade 2 entry)

Price rises to 975 (hits TP of Trade 3):
Trade 3 closes at TP (975)
Trade 4: BUY @ 950 (if market still at 950)
```

## Usage

### Dry-Run Mode (Recommended for Testing)

```bash
DRY_RUN=true ruby ea.rb
```

This mode logs all trading decisions without placing real orders. Perfect for testing strategy logic.

### Live Trading

```bash
ruby ea.rb
```

### Running as a Service

1. **Update the service file** (`trading-bot.service`) with correct paths
2. **Install and start the service**:
   ```bash
   sudo cp trading-bot.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable trading-bot
   sudo systemctl start trading-bot
   sudo systemctl status trading-bot
   ```

### Terraform Deployment (AWS EC2)

```bash
cd terraform
# Configure terraform.tfvars with your SSH keys
terraform init
terraform plan
terraform apply
```

## Development

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/models/position_spec.rb

# Run tests with coverage
bundle exec rspec --format documentation
```

### Adding New Features

1. **Follow SOLID principles**: Single responsibility, Open/closed, Liskov substitution, Interface segregation, Dependency inversion
2. **Write tests**: Each new feature should include corresponding tests
3. **Use dependency injection**: Services should receive dependencies via constructor
4. **Add documentation**: Update README and create API docs if needed

### Code Structure Guidelines

- **Models**: Represent domain entities with business logic
- **Services**: Implement specific business capabilities
- **Config**: Configuration and cross-cutting concerns
- **Runners**: Orchestrate service interactions

## API Integration

The bot uses the MetaTrader API with the following endpoints:

- `GET /positions` - Fetch current positions
- `POST /trade` - Place new trades or modify positions
- `GET /candles` - Get historical price data

See the `ApiClient` class for implementation details.

## Error Handling

- **Retry Logic**: Automatic retry for transient API failures
- **Graceful Degradation**: Continue operation when non-critical services fail
- **Comprehensive Logging**: All errors are logged with context
- **Signal Handling**: Graceful shutdown on SIGINT/SIGTERM

## Monitoring

Check the logs for:
- Grid state snapshots
- Trade executions
- Take profit hits
- Error messages

Logs are written to stdout with timestamps and log levels.

## Troubleshooting

### Common Issues

1. **API Authentication Failed**
   - Check API_KEY in .env
   - Verify account is active
   - Ensure correct region URLs

2. **No Trades Executing**
   - Check dry-run mode is disabled
   - Verify current price is below next entry level
   - Check account balance and permissions

3. **Position Not Updating**
   - API may have rate limits
   - Check network connectivity
   - Verify position IDs match

### Getting Help

1. Check logs for error messages
2. Review environment configuration
3. Test API connectivity separately
4. Run in dry-run mode to verify logic

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

[Add appropriate license]

## Disclaimer

This trading bot is for educational purposes. Use at your own risk. Past performance is not indicative of future results. Cryptocurrency trading involves significant risk of loss.