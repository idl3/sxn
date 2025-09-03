# frozen_string_literal: true

require "spec_helper"
require "ostruct"

RSpec.describe "Sxn::Core::ConfigManager#get_config returns OpenStruct" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_manager) { Sxn::Core::ConfigManager.new(temp_dir) }
  let(:config_path) { File.join(temp_dir, ".sxn", "config.yml") }

  after { FileUtils.rm_rf(temp_dir) }

  before do
    # Initialize the project
    config_manager.initialize_project("test-sessions")
  end

  describe "#get_config" do
    it "returns an OpenStruct object" do
      config = config_manager.get_config
      expect(config).to be_a(OpenStruct)
    end

    it "allows accessing top-level properties as methods" do
      config = config_manager.get_config
      expect { config.sessions_folder }.not_to raise_error
      expect(config.sessions_folder).to be_a(String)
    end

    it "allows accessing nested properties as methods" do
      config = config_manager.get_config
      expect { config.settings }.not_to raise_error
      expect(config.settings).to be_a(OpenStruct)
      expect { config.settings.auto_cleanup }.not_to raise_error
      expect { config.settings.max_sessions }.not_to raise_error
    end

    it "returns correct values for configuration properties" do
      config = config_manager.get_config
      expect(config.version).to eq(1)
      expect(config.sessions_folder).to eq("test-sessions")
      expect(config.settings.auto_cleanup).to eq(true)
      expect(config.settings.max_sessions).to eq(10)
    end

    it "handles deeply nested structures" do
      # Manually create a config with deeper nesting
      FileUtils.mkdir_p(File.dirname(config_path))
      config_data = {
        "version" => 1,
        "sessions_folder" => "sessions",
        "deep" => {
          "level1" => {
            "level2" => {
              "value" => "deep_value"
            }
          }
        }
      }
      File.write(config_path, YAML.dump(config_data))

      config = config_manager.get_config
      expect(config.deep).to be_a(OpenStruct)
      expect(config.deep.level1).to be_a(OpenStruct)
      expect(config.deep.level1.level2).to be_a(OpenStruct)
      expect(config.deep.level1.level2.value).to eq("deep_value")
    end

    it "handles empty hash values as OpenStruct" do
      FileUtils.mkdir_p(File.dirname(config_path))
      config_data = {
        "version" => 1,
        "sessions_folder" => "sessions",
        "empty_hash" => {}
      }
      File.write(config_path, YAML.dump(config_data))

      config = config_manager.get_config
      expect(config.empty_hash).to be_a(OpenStruct)
    end

    it "preserves non-hash values" do
      FileUtils.mkdir_p(File.dirname(config_path))
      config_data = {
        "version" => 1,
        "sessions_folder" => "sessions",
        "array_value" => [1, 2, 3],
        "string_value" => "test",
        "number_value" => 42,
        "boolean_value" => true,
        "nil_value" => nil
      }
      File.write(config_path, YAML.dump(config_data))

      config = config_manager.get_config
      expect(config.array_value).to eq([1, 2, 3])
      expect(config.string_value).to eq("test")
      expect(config.number_value).to eq(42)
      expect(config.boolean_value).to eq(true)
      expect(config.nil_value).to be_nil
    end

    context "when project is not initialized" do
      let(:uninitialized_manager) { Sxn::Core::ConfigManager.new(Dir.mktmpdir) }

      it "raises ConfigurationError" do
        expect { uninitialized_manager.get_config }.to raise_error(
          Sxn::ConfigurationError,
          "Project not initialized. Run 'sxn init' first."
        )
      end
    end
  end
end
