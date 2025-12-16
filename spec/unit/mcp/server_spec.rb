# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"

RSpec.describe Sxn::MCP::Server do
  let(:test_dir) { Dir.mktmpdir("sxn_mcp_test") }
  let(:sxn_dir) { File.join(test_dir, ".sxn") }
  let(:sessions_dir) { File.join(test_dir, "sxn-sessions") }

  before do
    FileUtils.mkdir_p(sxn_dir)
    FileUtils.mkdir_p(sessions_dir)

    # Create minimal config
    config_path = File.join(sxn_dir, "config.yml")
    File.write(config_path, <<~YAML)
      version: 1
      sessions_folder: #{sessions_dir}
      projects: {}
    YAML

    # Create sessions database
    db_path = File.join(sxn_dir, "sessions.db")
    Sxn::Database::SessionDatabase.new(db_path)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#initialize" do
    it "initializes with workspace path" do
      server = described_class.new(workspace_path: test_dir)
      expect(server.workspace_path).to eq(test_dir)
    end

    it "uses SXN_WORKSPACE env var if set" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SXN_WORKSPACE").and_return(test_dir)

      server = described_class.new
      expect(server.workspace_path).to eq(test_dir)
    end

    it "initializes config manager" do
      server = described_class.new(workspace_path: test_dir)
      expect(server.config_manager).to be_a(Sxn::Core::ConfigManager)
    end
  end

  describe "workspace discovery" do
    it "finds .sxn directory in parent directories" do
      nested_dir = File.join(test_dir, "some", "nested", "path")
      FileUtils.mkdir_p(nested_dir)

      Dir.chdir(nested_dir) do
        server = described_class.new
        # Use realpath to normalize paths (macOS /var -> /private/var symlink)
        expect(File.realpath(server.workspace_path)).to eq(File.realpath(test_dir))
      end
    end
  end
end
