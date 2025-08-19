# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Configuration System Integration" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:project_root) { temp_dir }
  let(:nested_dir) { File.join(project_root, "deeply", "nested", "directory") }

  # Configuration directories
  let(:global_config_dir) { File.expand_path("~/.sxn") }
  let(:workspace_config_dir) { File.join(project_root, ".sxn-workspace") }
  let(:local_config_dir) { File.join(project_root, ".sxn") }

  # Configuration files
  let(:global_config_file) { File.join(global_config_dir, "config.yml") }
  let(:workspace_config_file) { File.join(workspace_config_dir, "config.yml") }
  let(:local_config_file) { File.join(local_config_dir, "config.yml") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "hierarchical configuration loading" do
    let(:global_config) do
      {
        "version" => 1,
        "sessions_folder" => "global-sessions",
        "settings" => {
          "auto_cleanup" => true,
          "max_sessions" => 5,
          "worktree_cleanup_days" => 14
        },
        "projects" => {
          "global-project" => {
            "path" => "./global-project",
            "type" => "ruby"
          }
        }
      }
    end

    let(:workspace_config) do
      {
        "version" => 1,
        "sessions_folder" => "workspace-sessions",
        "settings" => {
          "max_sessions" => 8,
          "worktree_cleanup_days" => 21
        },
        "projects" => {
          "workspace-project" => {
            "path" => "./workspace-project",
            "type" => "javascript"
          },
          "shared-project" => {
            "path" => "./shared-from-workspace",
            "type" => "react"
          }
        }
      }
    end

    let(:local_config) do
      {
        "version" => 1,
        "sessions_folder" => "local-sessions",
        "current_session" => "current-local-session",
        "settings" => {
          "worktree_cleanup_days" => 30
        },
        "projects" => {
          "local-project" => {
            "path" => "./local-project",
            "type" => "rails",
            "rules" => {
              "copy_files" => [
                {
                  "source" => "config/master.key",
                  "strategy" => "copy",
                  "permissions" => 0o600
                }
              ],
              "setup_commands" => [
                {
                  "command" => %w[bundle install],
                  "environment" => { "RAILS_ENV" => "development" }
                }
              ]
            }
          },
          "shared-project" => {
            "path" => "./shared-from-local",
            "type" => "rails"
          }
        }
      }
    end

    before do
      FileUtils.mkdir_p(nested_dir)

      # Mock global config (can't write to actual home directory in tests)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(global_config_file).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(global_config_file).and_return(global_config.to_yaml)

      # Create workspace config
      FileUtils.mkdir_p(workspace_config_dir)
      File.write(workspace_config_file, workspace_config.to_yaml)

      # Create local config
      FileUtils.mkdir_p(local_config_dir)
      File.write(local_config_file, local_config.to_yaml)
    end

    context "from nested directory" do
      let(:manager) { Sxn::Config::Manager.new(start_directory: nested_dir) }

      it "finds and merges all configuration sources with correct precedence" do
        config = manager.config

        # Verify precedence: local > workspace > global > defaults
        expect(config["sessions_folder"]).to eq "local-sessions" # Local overrides
        expect(config["current_session"]).to eq "current-local-session" # Local only
        expect(config["settings"]["auto_cleanup"]).to be true # Global value
        expect(config["settings"]["max_sessions"]).to eq 8 # Workspace overrides global
        expect(config["settings"]["worktree_cleanup_days"]).to eq 30 # Local overrides all

        # Verify projects are merged from all sources
        expect(config["projects"]).to have_key("global-project")
        expect(config["projects"]).to have_key("workspace-project")
        expect(config["projects"]).to have_key("local-project")

        # Local config should override workspace for shared project
        expect(config["projects"]["shared-project"]["path"]).to eq "./shared-from-local"
        expect(config["projects"]["shared-project"]["type"]).to eq "rails"
      end

      it "includes default values for missing configuration" do
        config = manager.config

        # Should have system defaults for fields not specified
        expect(config["settings"]["default_rules"]).to be_a(Hash)
        expect(config["version"]).to eq 1
      end

      it "validates the merged configuration" do
        expect(manager.valid?).to be true
        expect(manager.errors).to be_empty
      end
    end

    context "with environment variable overrides" do
      let(:manager) { Sxn::Config::Manager.new(start_directory: nested_dir) }

      before do
        allow(ENV).to receive(:each).and_yield("SXN_SESSIONS_FOLDER", "env-sessions")
                                    .and_yield("SXN_AUTO_CLEANUP", "false")
                                    .and_yield("SXN_MAX_SESSIONS", "15")
                                    .and_yield("OTHER_VAR", "ignored")
      end

      it "applies environment variable overrides with highest precedence" do
        config = manager.config

        # Environment variables should override all config files
        expect(config["sessions_folder"]).to eq "env-sessions"
        expect(config["auto_cleanup"]).to be false
        expect(config["max_sessions"]).to eq "15"

        # Non-overridden values should come from config files
        expect(config["current_session"]).to eq "current-local-session"
      end
    end

    context "with CLI options" do
      let(:manager) { Sxn::Config::Manager.new(start_directory: nested_dir) }
      let(:cli_options) do
        {
          "sessions_folder" => "cli-sessions",
          "max_sessions" => 25,
          "new_cli_option" => "cli-value"
        }
      end

      it "applies CLI options with highest precedence" do
        config = manager.config(cli_options: cli_options)

        # CLI options should override everything
        expect(config["sessions_folder"]).to eq "cli-sessions"
        expect(config["max_sessions"]).to eq 25
        expect(config["new_cli_option"]).to eq "cli-value"

        # Non-overridden values should come from configs
        expect(config["current_session"]).to eq "current-local-session"
      end
    end
  end

  describe "configuration caching with file watching" do
    let(:manager) { Sxn::Config::Manager.new(start_directory: project_root, cache_ttl: 300) }

    before do
      FileUtils.mkdir_p(local_config_dir)
      File.write(local_config_file, {
        "version" => 1,
        "sessions_folder" => "cached-sessions"
      }.to_yaml)
    end

    it "caches configuration after first load" do
      # First load
      config1 = manager.config
      expect(config1["sessions_folder"]).to eq "cached-sessions"

      # Should be cached
      cache_stats = manager.cache_stats
      expect(cache_stats[:exists]).to be true
      expect(cache_stats[:valid]).to be true

      # Second load should use cache (no file access)
      expect(manager.discovery).not_to receive(:discover_config)
      config2 = manager.config
      expect(config2["sessions_folder"]).to eq "cached-sessions"
    end

    it "invalidates cache when configuration files change" do
      # Load initial config
      manager.config
      expect(manager.cache_stats[:valid]).to be true

      # Modify config file
      sleep(0.1) # Ensure different mtime
      File.write(local_config_file, {
        "version" => 1,
        "sessions_folder" => "modified-sessions"
      }.to_yaml)

      # Should reload from disk
      config = manager.config
      expect(config["sessions_folder"]).to eq "modified-sessions"
    end

    it "handles cache corruption gracefully" do
      # Load initial config to create cache
      manager.config

      # Corrupt cache file
      cache_file = manager.cache.cache_file_path
      File.write(cache_file, "corrupted json content")

      # Should fall back to discovery
      config = manager.config
      expect(config["sessions_folder"]).to eq "cached-sessions"
    end
  end

  describe "configuration validation and migration" do
    let(:manager) { Sxn::Config::Manager.new(start_directory: project_root) }

    context "with version 0 configuration" do
      let(:v0_config) do
        {
          # No version field (version 0)
          "sessions_folder" => "old-sessions",
          "auto_cleanup" => false,
          "max_sessions" => 3,
          "projects" => {
            "old-project" => {
              "rules" => {
                "copy_files" => ["config/master.key", ".env"],
                "setup_commands" => ["bundle install", "rails db:create"]
              }
            }
          }
        }
      end

      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, v0_config.to_yaml)
      end

      it "migrates configuration to current version" do
        config = manager.config

        # Should be migrated to version 1
        expect(config["version"]).to eq 1

        # Settings should be moved to settings hash
        expect(config["settings"]["auto_cleanup"]).to be false
        expect(config["settings"]["max_sessions"]).to eq 3

        # Project path should be inferred
        expect(config["projects"]["old-project"]["path"]).to eq "./old-project"

        # Rules should be converted to new format
        copy_files = config["projects"]["old-project"]["rules"]["copy_files"]
        expect(copy_files).to eq [
          { "source" => "config/master.key", "strategy" => "copy" },
          { "source" => ".env", "strategy" => "copy" }
        ]

        setup_commands = config["projects"]["old-project"]["rules"]["setup_commands"]
        expect(setup_commands).to eq [
          { "command" => %w[bundle install] },
          { "command" => ["rails", "db:create"] }
        ]
      end

      it "validates migrated configuration" do
        expect(manager.valid?).to be true
        expect(manager.errors).to be_empty
      end
    end

    context "with invalid configuration" do
      let(:invalid_config) do
        {
          "version" => "not_a_number",
          "sessions_folder" => "",
          "projects" => "not_a_hash",
          "settings" => {
            "max_sessions" => -5,
            "worktree_cleanup_days" => 500
          }
        }
      end

      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, invalid_config.to_yaml)
      end

      it "raises detailed configuration error" do
        expect { manager.config }.to raise_error(Sxn::ConfigurationError) do |error|
          expect(error.message).to include("version")
          expect(error.message).to include("sessions_folder")
          expect(error.message).to include("projects")
          expect(error.message).to include("max_sessions")
          expect(error.message).to include("worktree_cleanup_days")
        end
      end

      it "reports validation errors without raising" do
        expect(manager.valid?).to be false

        errors = manager.errors
        expect(errors).not_to be_empty
        expect(errors.join).to include("version")
        expect(errors.join).to include("projects")
      end
    end
  end

  describe "performance with deep directory structures" do
    let(:deep_path) { File.join(project_root, *(["level"] * 15)) }
    let(:manager) { Sxn::Config::Manager.new(start_directory: deep_path, cache_ttl: 300) }

    before do
      FileUtils.mkdir_p(deep_path)
      FileUtils.mkdir_p(local_config_dir)
      File.write(local_config_file, {
        "version" => 1,
        "sessions_folder" => "deep-sessions"
      }.to_yaml)
    end

    it "discovers configuration efficiently in deep directory structures" do
      expect do
        manager.config
      end.to perform_under(100).ms
    end

    it "caches configuration for subsequent access" do
      manager.config # Initial load

      expect do
        5.times { manager.config }
      end.to perform_under(50).ms
    end
  end

  describe "concurrent access safety" do
    let(:manager) { Sxn::Config::Manager.new(start_directory: project_root) }

    before do
      FileUtils.mkdir_p(local_config_dir)
      File.write(local_config_file, {
        "version" => 1,
        "sessions_folder" => "concurrent-sessions"
      }.to_yaml)
    end

    it "handles concurrent configuration access safely" do
      threads = 10.times.map do
        Thread.new { manager.config }
      end

      results = threads.map(&:value)
      expect(results).to all(include("sessions_folder" => "concurrent-sessions"))
    end

    it "handles concurrent cache invalidation safely" do
      manager.config # Initial load

      threads = 5.times.map do
        Thread.new do
          manager.invalidate_cache
          manager.config
        end
      end

      results = threads.map(&:value)
      expect(results).to all(be_a(Hash))
    end
  end

  describe "error recovery scenarios" do
    let(:manager) { Sxn::Config::Manager.new(start_directory: project_root) }

    context "with temporarily unavailable config file" do
      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, { "version" => 1 }.to_yaml)
      end

      it "recovers when file becomes available again" do
        # Load initial config
        manager.config

        # Make file temporarily unavailable
        original_mode = File.stat(local_config_file).mode
        File.chmod(0o000, local_config_file)

        # Should use defaults when file is unavailable
        begin
          manager.reload
        rescue Sxn::ConfigurationError
          # Expected error
        end

        # Restore file access
        File.chmod(original_mode, local_config_file)

        # Should work again
        config = manager.reload
        expect(config["version"]).to eq 1
      end
    end

    context "with network filesystem delays" do
      before do
        FileUtils.mkdir_p(local_config_dir)
        File.write(local_config_file, { "version" => 1 }.to_yaml)

        # Simulate slow file access
        allow(File).to receive(:read).and_wrap_original do |original_method, *args|
          sleep(0.1) if args.first == local_config_file
          original_method.call(*args)
        end
      end

      it "handles slow file access gracefully" do
        expect do
          manager.config
        end.to perform_under(200).ms
      end
    end
  end

  describe "configuration debugging and introspection" do
    let(:manager) { Sxn::Config::Manager.new(start_directory: project_root) }

    before do
      FileUtils.mkdir_p(local_config_dir)
      File.write(local_config_file, {
        "version" => 1,
        "sessions_folder" => "debug-sessions"
      }.to_yaml)
    end

    it "provides comprehensive debug information" do
      manager.config # Load config

      debug_info = manager.debug_info

      expect(debug_info[:start_directory]).to eq project_root
      expect(debug_info[:config_files]).to include(local_config_file)
      expect(debug_info[:cache_stats]).to include(:exists, :valid)
      expect(debug_info[:validation_errors]).to be_an(Array)
      expect(debug_info[:environment_variables]).to be_a(Hash)
      expect(debug_info[:discovery_performance]).to be_a(Float)
    end

    it "reports configuration file paths in precedence order" do
      paths = manager.config_file_paths
      expect(paths).to include(local_config_file)
      expect(paths).to be_an(Array)
    end
  end

  describe "configuration system performance targets" do
    let(:large_project_config) do
      {
        "version" => 1,
        "sessions_folder" => "large-sessions",
        "projects" => (1..50).to_h do |i|
          [
            "project-#{i}",
            {
              "path" => "./project-#{i}",
              "type" => %w[rails javascript react vue angular].sample,
              "rules" => {
                "copy_files" => [
                  { "source" => "config/master.key", "strategy" => "copy" },
                  { "source" => ".env", "strategy" => "symlink" }
                ],
                "setup_commands" => [
                  { "command" => %w[bundle install] },
                  { "command" => %w[npm install] }
                ],
                "templates" => [
                  {
                    "source" => ".sxn/templates/README.md",
                    "destination" => "README.md",
                    "process" => true
                  }
                ]
              }
            }
          ]
        end
      }
    end

    let(:manager) { Sxn::Config::Manager.new(start_directory: project_root) }

    before do
      FileUtils.mkdir_p(local_config_dir)
      File.write(local_config_file, large_project_config.to_yaml)
    end

    it "meets discovery performance target (< 100ms with caching)" do
      # First load (discovery + validation)
      expect do
        manager.config
      end.to perform_under(200).ms

      # Subsequent loads (cached)
      expect do
        manager.config
      end.to perform_under(50).ms
    end

    it "handles key lookups efficiently" do
      manager.config # Load config

      expect do
        50.times { |i| manager.get("projects.project-#{i}.type") }
      end.to perform_under(10).ms
    end

    it "validates large configurations efficiently" do
      expect do
        manager.valid?
      end.to perform_under(100).ms
    end
  end
end
