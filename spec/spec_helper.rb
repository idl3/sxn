# frozen_string_literal: true

require "simplecov"

# Start SimpleCov if coverage is requested
if ENV["COVERAGE"]
  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/vendor/"
    
    add_group "Commands", "lib/sxn/commands"
    add_group "Core", "lib/sxn/core"
    add_group "Security", "lib/sxn/security"
    add_group "Rules", "lib/sxn/rules"
    add_group "Database", "lib/sxn/database"
    add_group "MCP", "lib/sxn/mcp"
    
    minimum_coverage 90
    minimum_coverage_by_file 85
  end
end

require "bundler/setup"
require "sxn"
require "rspec"
require "faker"
require "climate_control"
require "webmock/rspec"

# Require support files
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Use documentation format for verbose output
  config.default_formatter = "doc" if config.files_to_run.one?

  # Run tests in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Configure expectations
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Configure mocks
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Shared context for all tests
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Filter to run only focused tests
  config.filter_run_when_matching :focus

  # Disable WebMock by default, enable per test
  config.before(:each) do
    WebMock.disable!
  end

  # Clean up after each test
  config.after(:each) do
    # Reset logger level
    Sxn.logger.level = Logger::INFO
    
    # Clean up test files
    FileUtils.rm_rf(Dir.glob("/tmp/sxn_test_*"))
  end

  # Global test setup
  config.before(:suite) do
    # Setup test logger
    Sxn.setup_logger(level: :warn)
    
    # Ensure clean test environment
    ENV["SXN_CONFIG_PATH"] = nil
    ENV["SXN_DATABASE_PATH"] = nil
  end

  # Global setup to prevent any interactive prompts
  config.before(:each) do
    # Stub all TTY::Prompt methods to prevent actual prompts
    allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return("test-input")
    allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_return(true)
    allow_any_instance_of(TTY::Prompt).to receive(:select).and_return("test-selection")
    allow_any_instance_of(TTY::Prompt).to receive(:multi_select).and_return(["test-multi"])
    
    # Stub all Sxn::UI::Prompt methods
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:ask).and_return("test-input")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:ask_yes_no).and_return(true)
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:select).and_return("test-selection")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:multi_select).and_return(["test-multi"])
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:folder_name).and_return("test-folder")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:session_name).and_return("test-session")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_name).and_return("test-project")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_path).and_return("/test/path")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:branch_name).and_return("test-branch")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:confirm_deletion).and_return(true)
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:rule_type).and_return("copy_files")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:sessions_folder_setup).and_return("test-sessions")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_detection_confirm).and_return(true)
    
    # Stub puts and print that might trigger prompts in UI::Prompt
    allow(STDOUT).to receive(:puts)
    allow(STDOUT).to receive(:print)
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:puts)
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:print)
  end
end

# Helper method to create temporary directory
def create_temp_directory(prefix = "sxn_test")
  Dir.mktmpdir(prefix, "/tmp")
end

# Helper method to create temporary git repository
def create_temp_git_repo(path = nil)
  path ||= create_temp_directory("sxn_git_test")
  
  Dir.chdir(path) do
    `git init --quiet`
    `git config user.name "Test User"`
    `git config user.email "test@example.com"`
    
    # Create initial commit
    File.write("README.md", "# Test Repository")
    `git add README.md`
    `git commit --quiet -m "Initial commit"`
  end
  
  path
end