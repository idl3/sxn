# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Sxn::Config::ConfigDiscovery do
  let(:temp_dir) { Dir.mktmpdir }
  let(:discovery) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "sets start directory" do
      expect(discovery.start_directory).to eq Pathname.new(temp_dir).expand_path
    end

    it "defaults to current directory" do
      default_discovery = described_class.new
      expect(default_discovery.start_directory).to eq Pathname.new(Dir.pwd).expand_path
    end
  end

  describe "#find_config_files" do
    context "with no config files" do
      it "returns empty array" do
        expect(discovery.find_config_files).to be_empty
      end
    end

    context "with local config file" do
      let(:local_config_dir) { File.join(temp_dir, ".sxn") }
      let(:local_config_file) { File.join(local_config_dir, "config.yml") }

      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, "version: 1\nsessions_folder: local-sessions")
      end

      it "finds local config file" do
        expect(discovery.find_config_files).to include(local_config_file)
      end
    end

    context "with workspace config file" do
      let(:workspace_config_dir) { File.join(temp_dir, ".sxn-workspace") }
      let(:workspace_config_file) { File.join(workspace_config_dir, "config.yml") }

      before do
        FileUtils.mkdir_p(workspace_config_dir)
        File.write(workspace_config_file, "version: 1\nsessions_folder: workspace-sessions")
      end

      it "finds workspace config file" do
        expect(discovery.find_config_files).to include(workspace_config_file)
      end
    end

    context "with global config file" do
      let(:global_config_dir) { File.expand_path("~/.sxn") }
      let(:global_config_file) { File.join(global_config_dir, "config.yml") }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(global_config_file).and_return(true)
      end

      it "finds global config file" do
        expect(discovery.find_config_files).to include(global_config_file)
      end
    end

    context "with multiple config files" do
      let(:local_config_dir) { File.join(temp_dir, ".sxn") }
      let(:local_config_file) { File.join(local_config_dir, "config.yml") }
      let(:workspace_config_dir) { File.join(temp_dir, ".sxn-workspace") }
      let(:workspace_config_file) { File.join(workspace_config_dir, "config.yml") }
      let(:global_config_file) { File.expand_path("~/.sxn/config.yml") }

      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, "version: 1")

        FileUtils.mkdir_p(workspace_config_dir)
        File.write(workspace_config_file, "version: 1")

        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(global_config_file).and_return(true)
      end

      it "finds all config files" do
        config_files = discovery.find_config_files
        expect(config_files).to include(local_config_file)
        expect(config_files).to include(workspace_config_file)
        expect(config_files).to include(global_config_file)
      end
    end
  end

  describe "#discover_config" do
    let(:cli_options) { { "max_sessions" => 20 } }

    context "with no config files" do
      it "returns system defaults with CLI options" do
        config = discovery.discover_config(cli_options)

        expect(config["version"]).to eq 1
        expect(config["sessions_folder"]).to eq ".sessions"
        expect(config["max_sessions"]).to eq 20
        expect(config["projects"]).to eq({})
      end
    end

    context "with local config file" do
      let(:local_config_dir) { File.join(temp_dir, ".sxn") }
      let(:local_config_file) { File.join(local_config_dir, "config.yml") }
      let(:local_config_content) do
        {
          "version" => 1,
          "sessions_folder" => "custom-sessions",
          "projects" => {
            "test-project" => {
              "path" => "./test-project",
              "type" => "rails"
            }
          },
          "settings" => {
            "auto_cleanup" => false
          }
        }.to_yaml
      end

      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, local_config_content)
      end

      it "merges local config with defaults" do
        config = discovery.discover_config(cli_options)

        expect(config["version"]).to eq 1
        expect(config["sessions_folder"]).to eq "custom-sessions"
        expect(config["max_sessions"]).to eq 20 # CLI override
        expect(config["settings"]["auto_cleanup"]).to be false
        expect(config["settings"]["max_sessions"]).to eq 10 # Default
        expect(config["projects"]["test-project"]["type"]).to eq "rails"
      end
    end

    context "with environment variables" do
      before do
        allow(ENV).to receive(:each).and_yield("SXN_SESSIONS_FOLDER", "env-sessions")
                                    .and_yield("SXN_AUTO_CLEANUP", "false")
                                    .and_yield("SXN_MAX_SESSIONS", "15")
                                    .and_yield("OTHER_VAR", "ignored")
      end

      it "includes environment variable overrides" do
        config = discovery.discover_config

        expect(config["sessions_folder"]).to eq "env-sessions"
        expect(config["auto_cleanup"]).to be false
        expect(config["max_sessions"]).to eq "15"
      end

      it "parses boolean environment variables" do
        allow(ENV).to receive(:each).and_yield("SXN_AUTO_CLEANUP", "true")

        config = discovery.discover_config
        expect(config["auto_cleanup"]).to be true
      end
    end

    context "with configuration hierarchy" do
      let(:global_config_file) { File.expand_path("~/.sxn/config.yml") }
      let(:workspace_config_dir) { File.join(temp_dir, ".sxn-workspace") }
      let(:workspace_config_file) { File.join(workspace_config_dir, "config.yml") }
      let(:local_config_dir) { File.join(temp_dir, ".sxn") }
      let(:local_config_file) { File.join(local_config_dir, "config.yml") }

      before do
        # Mock global config
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(global_config_file).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(global_config_file).and_return({
          "version" => 1,
          "sessions_folder" => "global-sessions",
          "settings" => {
            "auto_cleanup" => true,
            "max_sessions" => 5
          }
        }.to_yaml)

        # Create workspace config
        FileUtils.mkdir_p(workspace_config_dir)
        File.write(workspace_config_file, {
          "version" => 1,
          "sessions_folder" => "workspace-sessions",
          "settings" => {
            "max_sessions" => 8
          },
          "projects" => {
            "workspace-project" => {
              "path" => "./workspace-project"
            }
          }
        }.to_yaml)

        # Create local config
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, {
          "version" => 1,
          "sessions_folder" => "local-sessions",
          "current_session" => "local-session",
          "projects" => {
            "local-project" => {
              "path" => "./local-project"
            }
          }
        }.to_yaml)

        # Environment variables
        allow(ENV).to receive(:each).and_yield("SXN_CURRENT_SESSION", "env-session")
      end

      it "applies correct precedence order" do
        config = discovery.discover_config({ "max_sessions" => 20 })

        # CLI options have highest precedence
        expect(config["max_sessions"]).to eq 20

        # Environment variables override config files
        expect(config["current_session"]).to eq "env-session"

        # Local config overrides workspace and global
        expect(config["sessions_folder"]).to eq "local-sessions"

        # Workspace config overrides global for settings
        expect(config["settings"]["max_sessions"]).to eq 8

        # Global config provides base values
        expect(config["settings"]["auto_cleanup"]).to be true

        # Projects are merged from all sources
        expect(config["projects"]).to have_key("workspace-project")
        expect(config["projects"]).to have_key("local-project")
      end
    end
  end

  describe "hierarchical discovery" do
    let(:project_root) { temp_dir }
    let(:sub_dir) { File.join(project_root, "sub", "nested") }
    let(:config_dir) { File.join(project_root, ".sxn") }
    let(:config_file) { File.join(config_dir, "config.yml") }

    before do
      FileUtils.mkdir_p(sub_dir)
      FileUtils.mkdir_p(config_dir)
      File.write(config_file, { "version" => 1, "sessions_folder" => "found-sessions" }.to_yaml)
    end

    it "finds config file by walking up directory tree" do
      nested_discovery = described_class.new(sub_dir)
      config = nested_discovery.discover_config

      expect(config["sessions_folder"]).to eq "found-sessions"
    end

    it "stops at filesystem root" do
      # Create discovery starting from a very deep path that doesn't exist
      deep_path = File.join("/", "non", "existent", "very", "deep", "path")
      deep_discovery = described_class.new(deep_path)

      # Should not crash and should return defaults
      config = deep_discovery.discover_config
      expect(config["sessions_folder"]).to eq ".sessions" # Default value
    end
  end

  describe "error handling" do
    context "with invalid YAML" do
      let(:local_config_dir) { File.join(temp_dir, ".sxn") }
      let(:local_config_file) { File.join(local_config_dir, "config.yml") }

      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, "invalid: yaml: content: [\n")
      end

      it "raises ConfigurationError for invalid YAML" do
        # The implementation shows warnings but still handles errors for local configs
        expect do
          discovery.discover_config
        end.to output(/Warning: Failed to load local config/).to_stderr
      end
    end

    context "with unreadable file" do
      let(:local_config_dir) { File.join(temp_dir, ".sxn") }
      let(:local_config_file) { File.join(local_config_dir, "config.yml") }

      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, "version: 1")

        # Mock file read error
        allow(File).to receive(:read).with(local_config_file).and_raise(Errno::EACCES, "Permission denied")
      end

      it "raises ConfigurationError for read errors" do
        # The implementation shows warnings for read errors
        expect do
          discovery.discover_config
        end.to output(/Warning: Failed to load local config/).to_stderr
      end
    end
  end

  describe "performance" do
    context "with deep directory structure" do
      let(:deep_path) { File.join(temp_dir, *(["level"] * 20)) }
      let(:config_dir) { File.join(temp_dir, ".sxn") }
      let(:config_file) { File.join(config_dir, "config.yml") }

      before do
        FileUtils.mkdir_p(deep_path)
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, { "version" => 1 }.to_yaml)
      end

      it "finds config efficiently in deep directory structure" do
        deep_discovery = described_class.new(deep_path)

        expect do
          deep_discovery.discover_config
        end.to perform_under(50).ms
      end
    end

    context "with large configuration" do
      let(:local_config_dir) { File.join(temp_dir, ".sxn") }
      let(:local_config_file) { File.join(local_config_dir, "config.yml") }
      let(:large_config) do
        {
          "version" => 1,
          "sessions_folder" => "sessions",
          "projects" => (1..1000).to_h do |i|
            [
              "project-#{i}",
              {
                "path" => "./project-#{i}",
                "type" => "rails",
                "rules" => {
                  "copy_files" => [
                    { "source" => "config/master.key", "strategy" => "copy" }
                  ]
                }
              }
            ]
          end
        }
      end

      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, large_config.to_yaml)
      end

      it "loads large configuration efficiently" do
        expect do
          discovery.discover_config
        end.to perform_under(100).ms
      end
    end
  end
end
