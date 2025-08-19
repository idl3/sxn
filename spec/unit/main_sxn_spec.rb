# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn do
  describe "module configuration" do
    it "has a version constant" do
      expect(Sxn::VERSION).to be_a(String)
      expect(Sxn::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end

    it "defines autoloaded modules" do
      expect(defined?(Sxn::Commands)).to be_truthy
      expect(defined?(Sxn::Core)).to be_truthy
      expect(defined?(Sxn::UI)).to be_truthy
      expect(defined?(Sxn::Rules)).to be_truthy
      expect(defined?(Sxn::Database)).to be_truthy
      expect(defined?(Sxn::Security)).to be_truthy
      expect(defined?(Sxn::Templates)).to be_truthy
    end
  end

  describe ".root" do
    it "returns the gem root directory" do
      expect(Sxn.root).to be_a(String)
      expect(File.directory?(Sxn.root)).to be(true)
      expect(File.basename(Sxn.root)).to eq("sxn")
    end
  end

  describe ".lib_root" do
    it "returns the lib directory path" do
      expect(Sxn.lib_root).to eq(File.join(Sxn.root, "lib"))
      expect(File.directory?(Sxn.lib_root)).to be(true)
    end
  end

  describe ".version" do
    it "returns the version constant" do
      expect(Sxn.version).to eq(Sxn::VERSION)
    end
  end

  describe "logger configuration" do
    # Use a fresh mock for each test to prevent leakage
    let(:mock_logger) { instance_double(Logger, level: nil, formatter: nil, "level=": nil, "formatter=": nil) }

    before do
      # Reset Sxn logger state before each test
      Sxn.instance_variable_set(:@logger, nil)

      # Clear any existing stubs on Sxn
      RSpec::Mocks.space.proxy_for(Sxn).reset if RSpec::Mocks.space.proxy_for(Sxn).respond_to?(:reset)
    end

    describe ".setup_logger" do
      it "creates a logger with default info level" do
        fresh_logger = instance_double(Logger, level: nil, formatter: nil)
        expect(Logger).to receive(:new).with($stdout).and_return(fresh_logger)
        expect(fresh_logger).to receive(:level=).with(Logger::INFO)
        expect(fresh_logger).to receive(:formatter=).with(anything)

        logger = Sxn.setup_logger

        expect(logger).to eq(fresh_logger)
        expect(Sxn.logger).to eq(fresh_logger)
      end

      it "accepts custom log level" do
        fresh_logger = instance_double(Logger, level: nil, formatter: nil)
        allow(Logger).to receive(:new).and_return(fresh_logger)
        expect(fresh_logger).to receive(:level=).with(Logger::DEBUG)
        expect(fresh_logger).to receive(:formatter=).with(anything)

        Sxn.setup_logger(level: :debug)
      end

      it "accepts log level as string" do
        fresh_logger = instance_double(Logger, level: nil, formatter: nil)
        allow(Logger).to receive(:new).and_return(fresh_logger)
        expect(fresh_logger).to receive(:level=).with(Logger::ERROR)
        expect(fresh_logger).to receive(:formatter=).with(anything)

        Sxn.setup_logger(level: "error")
      end

      it "sets custom formatter" do
        time = Time.new(2023, 1, 1, 12, 0, 0)
        allow(Time).to receive(:now).and_return(time)

        fresh_logger = instance_double(Logger, level: nil)
        allow(Logger).to receive(:new).and_return(fresh_logger)
        allow(fresh_logger).to receive(:level=)

        # Capture the formatter that gets set
        formatter = nil
        allow(fresh_logger).to receive(:formatter=) do |f|
          formatter = f
        end

        Sxn.setup_logger

        # Test the formatter
        formatted = formatter.call("INFO", time, nil, "Test message")
        expect(formatted).to eq("[2023-01-01 12:00:00] INFO: Test message\n")
      end
    end

    describe ".logger" do
      it "returns the configured logger" do
        fresh_logger = instance_double(Logger, level: nil, formatter: nil)
        allow(Logger).to receive(:new).and_return(fresh_logger)
        allow(fresh_logger).to receive(:level=)
        allow(fresh_logger).to receive(:formatter=)
        Sxn.setup_logger
        expect(Sxn.logger).to eq(fresh_logger)
      end
    end

    describe ".logger=" do
      it "allows setting a custom logger" do
        # Ensure we start with a nil logger
        Sxn.instance_variable_set(:@logger, nil)

        custom_logger = double("CustomLogger")
        Sxn.logger = custom_logger
        expect(Sxn.logger).to eq(custom_logger)
      end
    end
  end

  describe "configuration management" do
    let(:mock_config) { double("Config") }

    before do
      allow(Sxn::Config).to receive(:current).and_return(mock_config)
    end

    describe ".load_config" do
      it "loads configuration using Config.current" do
        Sxn.load_config

        expect(Sxn::Config).to have_received(:current)
        expect(Sxn.config).to eq(mock_config)
      end
    end

    describe ".config" do
      it "returns the loaded configuration" do
        Sxn.load_config
        expect(Sxn.config).to eq(mock_config)
      end
    end

    describe ".config=" do
      it "allows setting custom configuration" do
        custom_config = double("CustomConfig")
        Sxn.config = custom_config
        expect(Sxn.config).to eq(custom_config)
      end
    end
  end

  describe "module loading behavior" do
    it "initializes logger by default" do
      # The logger should be initialized when the module is loaded
      expect(Sxn.logger).to be_a(Logger)
    end

    it "loads required dependencies" do
      # Test that Zeitwerk is properly configured
      expect(defined?(Zeitwerk)).to be_truthy

      # Test that key modules are autoloaded
      expect { Sxn::Core::ConfigManager }.not_to raise_error
      expect { Sxn::Commands::Init }.not_to raise_error
      expect { Sxn::UI::Output }.not_to raise_error
    end
  end

  describe "error handling" do
    it "defines custom error classes" do
      expect(defined?(Sxn::Error)).to be_truthy
      expect(defined?(Sxn::ConfigurationError)).to be_truthy
      expect(defined?(Sxn::SessionNotFoundError)).to be_truthy
      expect(defined?(Sxn::ProjectNotFoundError)).to be_truthy
    end

    it "error classes inherit from Sxn::Error" do
      expect(Sxn::ConfigurationError.new).to be_a(Sxn::Error)
      expect(Sxn::SessionNotFoundError.new).to be_a(Sxn::Error)
      expect(Sxn::ProjectNotFoundError.new).to be_a(Sxn::Error)
    end
  end

  describe "class methods behavior" do
    describe "accessor methods" do
      it "allows reading and writing logger" do
        # Clear any existing stubs on Sxn from the global setup
        RSpec::Mocks.space.proxy_for(Sxn).reset if RSpec::Mocks.space.proxy_for(Sxn).respond_to?(:reset)

        # Ensure clean state
        Sxn.instance_variable_set(:@logger, nil)

        new_logger = double("NewLogger")

        Sxn.logger = new_logger
        expect(Sxn.logger).to eq(new_logger)

        # Clean up after test
        Sxn.instance_variable_set(:@logger, nil)
      end

      it "allows reading and writing config" do
        original_config = Sxn.config
        new_config = double("NewConfig")

        Sxn.config = new_config
        expect(Sxn.config).to eq(new_config)

        # Restore original
        Sxn.config = original_config
      end
    end
  end

  describe "integration with other modules" do
    it "can access core managers" do
      # Create a temp config for managers that need it
      temp_dir = Dir.mktmpdir("sxn_test")
      config_manager = Sxn::Core::ConfigManager.new(temp_dir)
      
      # Initialize the config first
      config_manager.initialize_project(temp_dir)
      
      expect { Sxn::Core::ConfigManager.new }.not_to raise_error
      expect { Sxn::Core::SessionManager.new(config_manager) }.not_to raise_error
      expect { Sxn::Core::ProjectManager.new(config_manager) }.not_to raise_error
      
      FileUtils.rm_rf(temp_dir)
    end

    it "can access UI components" do
      expect { Sxn::UI::Output.new }.not_to raise_error
      expect { Sxn::UI::Prompt.new }.not_to raise_error
    end

    it "can access command classes" do
      # Create a temp config for commands that need it
      temp_dir = Dir.mktmpdir("sxn_test")
      config_manager = Sxn::Core::ConfigManager.new(temp_dir)
      config_manager.initialize_project(temp_dir)
      
      expect { Sxn::Commands::Init.new }.not_to raise_error
      expect { Sxn::Commands::Sessions.new }.not_to raise_error
      
      FileUtils.rm_rf(temp_dir)
    end
  end
end
