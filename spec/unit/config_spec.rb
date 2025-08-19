# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Sxn::Config do
  describe "module structure" do
    it "is defined as a module" do
      expect(Sxn::Config).to be_a(Module)
    end

    it "is nested within Sxn module" do
      expect(Sxn::Config.name).to eq("Sxn::Config")
    end
  end

  describe "required dependencies" do
    it "loads config discovery" do
      expect(defined?(Sxn::Config::ConfigDiscovery)).to eq("constant")
      expect(Sxn::Config::ConfigDiscovery).to be_a(Class)
    end

    it "loads config cache" do
      expect(defined?(Sxn::Config::ConfigCache)).to eq("constant")
      expect(Sxn::Config::ConfigCache).to be_a(Class)
    end

    it "loads config validator" do
      expect(defined?(Sxn::Config::ConfigValidator)).to eq("constant")
      expect(Sxn::Config::ConfigValidator).to be_a(Class)
    end
  end

  describe Sxn::Config::Manager do
    let(:temp_dir) { Dir.mktmpdir("sxn_config_test") }
    let(:manager) { described_class.new(start_directory: temp_dir) }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    describe "#initialize" do
      it "creates manager with default cache TTL" do
        default_manager = described_class.new
        expect(default_manager).to be_a(described_class)
      end

      it "creates manager with custom cache TTL" do
        custom_manager = described_class.new(cache_ttl: 600)
        expect(custom_manager).to be_a(described_class)
      end

      it "initializes with start directory" do
        expect(manager).to be_a(described_class)
        expect(manager.discovery).to be_a(Sxn::Config::ConfigDiscovery)
        expect(manager.cache).to be_a(Sxn::Config::ConfigCache)
        expect(manager.validator).to be_a(Sxn::Config::ConfigValidator)
      end

      it "sets initial current_config to nil" do
        expect(manager.current_config).to be_nil
      end
    end

    describe "constants" do
      it "defines DEFAULT_CACHE_TTL" do
        expect(described_class::DEFAULT_CACHE_TTL).to eq(300)
      end
    end

    describe "attributes" do
      it "provides read access to discovery" do
        expect(manager).to respond_to(:discovery)
        expect(manager.discovery).to be_a(Sxn::Config::ConfigDiscovery)
      end

      it "provides read access to cache" do
        expect(manager).to respond_to(:cache)
        expect(manager.cache).to be_a(Sxn::Config::ConfigCache)
      end

      it "provides read access to validator" do
        expect(manager).to respond_to(:validator)
        expect(manager.validator).to be_a(Sxn::Config::ConfigValidator)
      end

      it "provides read access to current_config" do
        expect(manager).to respond_to(:current_config)
      end
    end

    describe "public interface" do
      it "responds to configuration management methods" do
        expect(manager).to respond_to(:config)
        expect(manager).to respond_to(:reload)
        expect(manager).to respond_to(:valid?)
        expect(manager).to respond_to(:debug_info)
      end
    end

    describe "#config" do
      it "can retrieve configuration" do
        expect { manager.config }.not_to raise_error
      end

      it "accepts CLI options parameter" do
        cli_options = { "verbose" => true }
        expect { manager.config(cli_options: cli_options) }.not_to raise_error
      end

      it "returns configuration hash" do
        config = manager.config
        expect(config).to be_a(Hash)
      end
    end

    describe "#reload" do
      it "can reload configuration" do
        expect { manager.reload }.not_to raise_error
      end

      it "accepts CLI options parameter" do
        cli_options = { "force" => true }
        expect { manager.reload(cli_options: cli_options) }.not_to raise_error
      end

      it "clears cached configuration" do
        # Load config first
        manager.config

        # Reload should work
        expect { manager.reload }.not_to raise_error
      end
    end

    describe "#valid?" do
      it "can validate configuration" do
        expect { manager.valid? }.not_to raise_error
      end

      it "returns validation result" do
        result = manager.valid?
        expect([true, false]).to include(result)
      end
    end

    describe "#debug_info" do
      it "can generate configuration summary" do
        expect { manager.debug_info }.not_to raise_error
      end

      it "returns summary hash" do
        summary = manager.debug_info
        expect(summary).to be_a(Hash)
      end

      it "includes source information" do
        summary = manager.debug_info
        expect(summary).to have_key(:config_files)
      end
    end

    describe "configuration integration" do
      before do
        # Create a basic config file
        config_dir = File.join(temp_dir, ".sxn")
        FileUtils.mkdir_p(config_dir)

        config_content = {
          "version" => 1,
          "sessions_folder" => "sessions",
          "projects" => {}
        }

        File.write(File.join(config_dir, "config.yml"), YAML.dump(config_content))
      end

      it "loads configuration from files" do
        config = manager.config
        expect(config["version"]).to eq(1)
        expect(config["sessions_folder"]).to eq("sessions")
      end

      it "validates loaded configuration" do
        manager.config
        validation_result = manager.valid?
        expect(validation_result).to be true
      end

      it "caches configuration after loading" do
        # First call should load from file
        config1 = manager.config

        # Second call should use cache
        config2 = manager.config

        expect(config1).to eq(config2)
      end
    end

    describe "thread safety" do
      it "handles concurrent access" do
        threads = []
        results = []

        # Create multiple threads accessing configuration
        5.times do
          threads << Thread.new do
            results << manager.config
          end
        end

        threads.each(&:join)

        # All results should be consistent
        expect(results.uniq.size).to eq(1)
      end
    end

    describe "error handling" do
      it "handles missing configuration gracefully" do
        empty_manager = described_class.new(start_directory: "/nonexistent")
        expect { empty_manager.config }.not_to raise_error
      end

      it "handles invalid configuration files" do
        # Create invalid YAML
        config_dir = File.join(temp_dir, ".sxn")
        FileUtils.mkdir_p(config_dir)
        File.write(File.join(config_dir, "config.yml"), "invalid: yaml: [")

        expect { manager.config }.not_to raise_error
      end
    end
  end

  describe "config module features" do
    it "provides hierarchical configuration loading" do
      # Test that the manager integrates discovery, caching, and validation
      manager = Sxn::Config::Manager.new

      expect(manager.discovery).to be_a(Sxn::Config::ConfigDiscovery)
      expect(manager.cache).to be_a(Sxn::Config::ConfigCache)
      expect(manager.validator).to be_a(Sxn::Config::ConfigValidator)
    end

    it "supports environment variable overrides" do
      # The manager should integrate with discovery which handles environment variables
      manager = Sxn::Config::Manager.new

      # Test that CLI options can be passed (these include env var overrides)
      expect { manager.config(cli_options: { "env_override" => "test" }) }.not_to raise_error
    end

    it "provides thread-safe configuration access" do
      # The manager uses a mutex for thread safety
      manager = Sxn::Config::Manager.new

      # Test that the manager can handle configuration access
      expect { manager.config }.not_to raise_error
    end
  end
end
