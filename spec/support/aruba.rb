# frozen_string_literal: true

require "aruba/rspec"

Aruba.configure do |config|
  # Set up command paths
  config.command_search_paths = [File.join(Sxn.root, "bin")]
  
  # Exit timeout - some git operations can be slow
  config.exit_timeout = 30
  
  # IO wait timeout
  config.io_wait_timeout = 5
  
  # Startup wait time
  config.startup_wait_time = 2
  
  # Working directory for tests
  config.working_directory = "tmp/aruba"
  
  # Keep files around for debugging
  config.remove_ansi_escape_sequences = false
  
  # Allow absolute paths
  config.allow_absolute_paths = true
end

RSpec.configure do |config|
  config.include Aruba::Api, type: :feature
  
  # Clean up aruba temp files after each test
  config.after(:each, type: :feature) do
    restore_env
    cleanup
  end
  
  # Setup environment for CLI tests
  config.before(:each, type: :feature) do
    # Set test environment variables
    set_environment_variable("SXN_ENV", "test")
    set_environment_variable("SXN_DEBUG", "false")
    
    # Use test database path
    set_environment_variable("SXN_DATABASE_PATH", File.join(aruba.config.working_directory, ".sxn", "test.db"))
    
    # Create basic test structure
    create_directory(".sxn")
    create_directory("projects")
  end
end