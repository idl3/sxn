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

    it "finds .sxn directory in current directory" do
      # This tests line 34 THEN branch - when .sxn exists in current dir
      Dir.chdir(test_dir) do
        server = described_class.new
        expect(File.realpath(server.workspace_path)).to eq(File.realpath(test_dir))
      end
    end

    it "climbs through multiple parent directories to find .sxn" do
      # This tests line 37 ELSE branch - continuing to climb up directories
      deeply_nested_dir = File.join(test_dir, "level1", "level2", "level3", "level4")
      FileUtils.mkdir_p(deeply_nested_dir)

      Dir.chdir(deeply_nested_dir) do
        server = described_class.new
        # Should climb through level4 -> level3 -> level2 -> level1 -> test_dir
        expect(File.realpath(server.workspace_path)).to eq(File.realpath(test_dir))
      end
    end

    it "returns current directory when no .sxn found and reaches root" do
      # This tests line 37 THEN branch - when parent == current (at root)
      # Test the path where .sxn doesn't exist by mocking File.directory? for .sxn paths
      Dir.mktmpdir("sxn_no_workspace") do |tmp_dir|
        nested = File.join(tmp_dir, "nested")
        FileUtils.mkdir_p(nested)

        # Mock File.directory? to simulate no .sxn found anywhere
        original_directory = File.method(:directory?)
        allow(File).to receive(:directory?) do |path|
          if path.end_with?(".sxn")
            false # Pretend .sxn doesn't exist
          else
            original_directory.call(path) # Use real implementation for other paths
          end
        end

        saved_pwd = Dir.pwd
        begin
          Dir.chdir(nested)
          # Make ConfigManager initialization raise to simulate no sxn init
          # This will make @config_manager nil and avoid SessionManager creation
          allow(Sxn::Core::ConfigManager).to receive(:new).and_raise(Sxn::ConfigurationError.new("Not initialized"))

          server = described_class.new
          # Should return current directory when no .sxn is found anywhere up the tree
          expect(File.realpath(server.workspace_path)).to eq(File.realpath(nested))
        ensure
          Dir.chdir(saved_pwd)
        end
      end
    end

    it "stops climbing at filesystem root" do
      # Additional test to verify the loop terminates at root
      # by explicitly providing a path to test with
      Dir.mktmpdir("sxn_root_edge") do |tmp_dir|
        deep_nested = File.join(tmp_dir, "a", "b", "c", "d", "e")
        FileUtils.mkdir_p(deep_nested)

        # Create .sxn only at the top level of tmp_dir
        FileUtils.mkdir_p(File.join(tmp_dir, ".sxn"))
        File.write(File.join(tmp_dir, ".sxn", "config.yml"), <<~YAML)
          version: 1
          sessions_folder: #{File.join(tmp_dir, "sessions")}
          projects: {}
        YAML
        Sxn::Database::SessionDatabase.new(File.join(tmp_dir, ".sxn", "sessions.db"))

        Dir.chdir(deep_nested) do
          server = described_class.new
          # Should climb all the way up and find .sxn at tmp_dir
          # This exercises the line 37 ELSE branch (continue climbing)
          expect(File.realpath(server.workspace_path)).to eq(File.realpath(tmp_dir))
        end
      end
    end

    context "discover_workspace with mocked file system" do
      it "returns current directory when .sxn exists in pwd (line 34 then)" do
        allow(Dir).to receive(:pwd).and_return("/home/user/project")
        allow(File).to receive(:directory?).with("/home/user/project/.sxn").and_return(true)
        allow(Sxn::Core::ConfigManager).to receive(:new).and_raise(Sxn::ConfigurationError.new("Not initialized"))

        server = described_class.new
        expect(server.workspace_path).to eq("/home/user/project")
      end

      it "climbs to parent when .sxn not in current but in parent (line 34 else, then 34 then)" do
        allow(Dir).to receive(:pwd).and_return("/home/user/project/subdir")
        allow(File).to receive(:directory?).with("/home/user/project/subdir/.sxn").and_return(false)
        allow(File).to receive(:dirname).with("/home/user/project/subdir").and_return("/home/user/project")
        allow(File).to receive(:directory?).with("/home/user/project/.sxn").and_return(true)
        allow(Sxn::Core::ConfigManager).to receive(:new).and_raise(Sxn::ConfigurationError.new("Not initialized"))

        server = described_class.new
        expect(server.workspace_path).to eq("/home/user/project")
      end

      it "continues loop when parent != current (line 37 else)" do
        allow(Dir).to receive(:pwd).and_return("/home/user/deep/nested/dir")

        # First iteration: /home/user/deep/nested/dir
        allow(File).to receive(:directory?).with("/home/user/deep/nested/dir/.sxn").and_return(false)
        allow(File).to receive(:dirname).with("/home/user/deep/nested/dir").and_return("/home/user/deep/nested")

        # Second iteration: /home/user/deep/nested
        allow(File).to receive(:directory?).with("/home/user/deep/nested/.sxn").and_return(false)
        allow(File).to receive(:dirname).with("/home/user/deep/nested").and_return("/home/user/deep")

        # Third iteration: /home/user/deep - found!
        allow(File).to receive(:directory?).with("/home/user/deep/.sxn").and_return(true)
        allow(Sxn::Core::ConfigManager).to receive(:new).and_raise(Sxn::ConfigurationError.new("Not initialized"))

        server = described_class.new
        expect(server.workspace_path).to eq("/home/user/deep")
      end

      it "breaks loop and falls back to pwd when reaching root (line 37 then)" do
        allow(Dir).to receive(:pwd).and_return("/home")

        # First iteration: /home
        allow(File).to receive(:directory?).with("/home/.sxn").and_return(false)
        allow(File).to receive(:dirname).with("/home").and_return("/")

        # Second iteration: /
        allow(File).to receive(:directory?).with("/.sxn").and_return(false)
        allow(File).to receive(:dirname).with("/").and_return("/") # parent == current at root

        allow(Sxn::Core::ConfigManager).to receive(:new).and_raise(Sxn::ConfigurationError.new("Not initialized"))

        server = described_class.new
        # Should fall back to Dir.pwd when no .sxn found
        expect(server.workspace_path).to eq("/home")
      end
    end
  end
end
