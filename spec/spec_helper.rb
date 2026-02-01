# spec/spec_helper.rb
require 'bundler/setup'
require 'pry'
require 'vcr'
require 'webmock/rspec'

# Load the application
$LOAD_PATH.unshift File.expand_path('../../app', __FILE__)

# Configure RSpec
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.expose_dsl_globally = true

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Configure VCR
  config.around(:each) do |example|
    vcr_tag = example.metadata[:vcr]
    
    if vcr_tag == false
      # Don't use VCR for this test
      WebMock.disable!
      example.run
      WebMock.enable!
    else
      # Use VCR
      cassette_name = vcr_tag.is_a?(Hash) ? vcr_tag[:cassette] : example.metadata[:full_description]
      VCR.use_cassette(cassette_name, record: :new_episodes) do
        example.run
      end
    end
  end
end

# Configure VCR
VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.allow_http_connections_when_no_cassette = false
  
  # Filter sensitive data
  config.filter_sensitive_data('<API_KEY>') { ENV['API_KEY'] }
  config.filter_sensitive_data('<ACCOUNT_ID>') { ENV['ACCOUNT_ID'] }
end

# Load test helpers
Dir[File.expand_path('../support/**/*.rb', __FILE__)].each { |f| require f }