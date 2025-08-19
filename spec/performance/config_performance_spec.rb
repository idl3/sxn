# frozen_string_literal: true

require "spec_helper"
require "benchmark"
require "tmpdir"
require "fileutils"

RSpec.describe "Configuration System Performance" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_dir) { File.join(temp_dir, ".sxn") }
  let(:config_file) { File.join(config_dir, "config.yml") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "discovery performance targets" do
    context "with single configuration file" do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, {
          "version" => 1,
          "sessions_folder" => "test-sessions"
        }.to_yaml)
      end

      it "discovers configuration in under 50ms" do
        discovery = Sxn::Config::ConfigDiscovery.new(temp_dir)

        expect do
          discovery.discover_config
        end.to perform_under(50).ms
      end

      it "finds config files in under 20ms" do
        discovery = Sxn::Config::ConfigDiscovery.new(temp_dir)

        expect do
          discovery.find_config_files
        end.to perform_under(20).ms
      end
    end

    context "with large configuration" do
      let(:large_config) do
        {
          "version" => 1,
          "sessions_folder" => "large-sessions",
          "projects" => (1..200).to_h do |i|
            [
              "project-#{i}",
              {
                "path" => "./project-#{i}",
                "type" => "rails",
                "default_branch" => "main",
                "rules" => {
                  "copy_files" => [
                    { "source" => "config/master.key", "strategy" => "copy" },
                    { "source" => ".env", "strategy" => "symlink", "permissions" => 0o600 }
                  ],
                  "setup_commands" => [
                    { "command" => %w[bundle install] },
                    { "command" => ["rails", "db:create"] },
                    { "command" => ["rails", "db:migrate"] }
                  ],
                  "templates" => [
                    {
                      "source" => ".sxn/templates/README.md",
                      "destination" => "README.md",
                      "process" => true,
                      "engine" => "liquid"
                    }
                  ]
                }
              }
            ]
          end,
          "settings" => {
            "auto_cleanup" => true,
            "max_sessions" => 50,
            "worktree_cleanup_days" => 30,
            "default_rules" => {
              "templates" => [
                {
                  "source" => ".sxn/templates/session-info.md",
                  "destination" => "SESSION.md"
                }
              ]
            }
          }
        }
      end

      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, large_config.to_yaml)
      end

      it "loads large configuration in under 100ms" do
        discovery = Sxn::Config::ConfigDiscovery.new(temp_dir)

        expect do
          discovery.discover_config
        end.to perform_under(100).ms
      end

      it "parses large YAML efficiently" do
        expect do
          YAML.safe_load_file(config_file, permitted_classes: [], permitted_symbols: [], aliases: false)
        end.to perform_under(50).ms
      end
    end

    context "with deep directory structure" do
      let(:deep_path) { File.join(temp_dir, *(["level"] * 20)) }

      before do
        FileUtils.mkdir_p(deep_path)
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, { "version" => 1, "sessions_folder" => "deep-sessions" }.to_yaml)
      end

      it "walks up directory tree efficiently" do
        discovery = Sxn::Config::ConfigDiscovery.new(deep_path)

        expect do
          discovery.discover_config
        end.to perform_under(100).ms
      end

      it "finds config files efficiently from deep paths" do
        discovery = Sxn::Config::ConfigDiscovery.new(deep_path)

        expect do
          discovery.find_config_files
        end.to perform_under(50).ms
      end
    end
  end

  describe "caching performance targets" do
    let(:cache) { Sxn::Config::ConfigCache.new(cache_dir: File.join(temp_dir, ".cache")) }
    let(:config_files) { [config_file] }
    let(:sample_config) do
      {
        "version" => 1,
        "sessions_folder" => "cached-sessions",
        "projects" => (1..50).to_h { |i| ["project-#{i}", { "path" => "./project-#{i}" }] }
      }
    end

    before do
      FileUtils.mkdir_p(config_dir)
      File.write(config_file, sample_config.to_yaml)
    end

    it "caches configuration in under 10ms" do
      expect do
        cache.set(sample_config, config_files)
      end.to perform_under(10).ms
    end

    it "retrieves cached configuration in under 5ms" do
      cache.set(sample_config, config_files)

      expect do
        cache.get(config_files)
      end.to perform_under(5).ms
    end

    it "validates cache in under 5ms" do
      cache.set(sample_config, config_files)

      expect do
        cache.valid?(config_files)
      end.to perform_under(5).ms
    end

    it "handles many config files efficiently" do
      many_files = (1..100).map do |i|
        file_path = File.join(temp_dir, "config#{i}.yml")
        File.write(file_path, "version: #{i}")
        file_path
      end

      expect do
        cache.set(sample_config, many_files)
      end.to perform_under(50).ms

      expect do
        cache.get(many_files)
      end.to perform_under(20).ms
    end
  end

  describe "validation performance targets" do
    let(:validator) { Sxn::Config::ConfigValidator.new }

    context "with simple configuration" do
      let(:simple_config) do
        {
          "version" => 1,
          "sessions_folder" => "simple-sessions",
          "projects" => {}
        }
      end

      it "validates simple configuration in under 5ms" do
        expect do
          validator.valid?(simple_config)
        end.to perform_under(5).ms
      end

      it "migrates simple configuration in under 10ms" do
        expect do
          validator.validate_and_migrate(simple_config)
        end.to perform_under(10).ms
      end
    end

    context "with complex configuration" do
      let(:complex_config) do
        {
          "version" => 1,
          "sessions_folder" => "complex-sessions",
          "projects" => (1..100).to_h do |i|
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

      it "validates complex configuration in under 50ms" do
        expect do
          validator.valid?(complex_config)
        end.to perform_under(50).ms
      end

      it "migrates complex configuration in under 100ms" do
        expect do
          validator.validate_and_migrate(complex_config)
        end.to perform_under(100).ms
      end
    end

    context "with invalid configuration" do
      let(:invalid_config) do
        {
          "version" => "invalid",
          "sessions_folder" => "",
          "projects" => (1..50).to_h do |i|
            [
              "project-#{i}",
              {
                "type" => "invalid_type",
                "rules" => {
                  "copy_files" => [
                    { "strategy" => "invalid_strategy" }
                  ]
                }
              }
            ]
          end
        }
      end

      it "validates invalid configuration quickly" do
        expect do
          validator.valid?(invalid_config)
        end.to perform_under(50).ms
      end

      it "collects all errors efficiently" do
        validator.valid?(invalid_config)

        expect do
          validator.format_errors
        end.to perform_under(10).ms
      end
    end
  end

  describe "configuration manager performance targets" do
    let(:manager) { Sxn::Config::Manager.new(start_directory: temp_dir, cache_ttl: 300) }

    before do
      FileUtils.mkdir_p(config_dir)
      File.write(config_file, {
        "version" => 1,
        "sessions_folder" => "manager-sessions",
        "projects" => (1..50).to_h { |i| ["project-#{i}", { "path" => "./project-#{i}" }] }
      }.to_yaml)
    end

    it "loads configuration for first time under 100ms" do
      expect do
        manager.config
      end.to perform_under(100).ms
    end

    it "retrieves cached configuration under 10ms" do
      manager.config # Initial load

      expect do
        manager.config
      end.to perform_under(10).ms
    end

    it "performs key lookups efficiently" do
      manager.config

      expect do
        100.times { |i| manager.get("projects.project-#{i % 50}.path") }
      end.to perform_under(10).ms
    end

    it "handles concurrent access efficiently" do
      threads = 10.times.map do
        Thread.new { manager.config }
      end

      expect do
        threads.each(&:join)
      end.to perform_under(200).ms
    end

    it "reloads configuration efficiently" do
      manager.config # Initial load

      expect do
        manager.reload
      end.to perform_under(100).ms
    end
  end

  describe "memory usage performance" do
    let(:manager) { Sxn::Config::Manager.new(start_directory: temp_dir) }

    before do
      FileUtils.mkdir_p(config_dir)
      File.write(config_file, {
        "version" => 1,
        "sessions_folder" => "memory-sessions",
        "projects" => (1..1000).to_h { |i| ["project-#{i}", { "path" => "./project-#{i}" }] }
      }.to_yaml)
    end

    it "uses reasonable memory for large configurations" do
      # Get baseline memory
      GC.start
      baseline_memory = memory_usage

      # Load large configuration
      manager.config

      # Check memory increase
      GC.start
      current_memory = memory_usage
      memory_increase = current_memory - baseline_memory

      # Should not use more than 10MB for configuration
      expect(memory_increase).to be < 10 * 1024 * 1024 # 10MB in bytes
    end

    private

    def memory_usage
      case RUBY_PLATFORM
      when /linux/
        `ps -o rss= -p #{Process.pid}`.to_i * 1024 # Convert KB to bytes
      when /darwin/
        `ps -o rss= -p #{Process.pid}`.to_i * 1024 # Convert KB to bytes
      else
        # Fallback for other platforms
        GC.stat[:heap_allocated_pages] * GC.stat[:heap_page_size]
      end
    rescue StandardError
      0 # Return 0 if we can't measure memory
    end
  end

  describe "file system operation performance" do
    let(:discovery) { Sxn::Config::ConfigDiscovery.new(temp_dir) }

    context "with many small config files" do
      before do
        # Create multiple config locations
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, { "version" => 1, "local" => true }.to_yaml)

        workspace_dir = File.join(temp_dir, ".sxn-workspace")
        FileUtils.mkdir_p(workspace_dir)
        File.write(File.join(workspace_dir, "config.yml"), { "version" => 1, "workspace" => true }.to_yaml)

        # Mock global config
        global_config_file = File.expand_path("~/.sxn/config.yml")
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(global_config_file).and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with(global_config_file).and_return({ "version" => 1, "global" => true }.to_yaml)
      end

      it "reads multiple config files efficiently" do
        expect do
          discovery.discover_config
        end.to perform_under(50).ms
      end

      it "finds all config files efficiently" do
        expect do
          discovery.find_config_files
        end.to perform_under(30).ms
      end
    end

    context "with slow file system" do
      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, { "version" => 1 }.to_yaml)

        # Simulate slow file access (network filesystem)
        allow(File).to receive(:read).and_wrap_original do |original_method, *args|
          sleep(0.01) if args.first.include?(".sxn")
          original_method.call(*args)
        end
      end

      it "handles slow file access gracefully" do
        expect do
          discovery.discover_config
        end.to perform_under(200).ms
      end
    end
  end

  describe "scalability limits" do
    context "with maximum reasonable configuration size" do
      let(:max_config) do
        {
          "version" => 1,
          "sessions_folder" => "max-sessions",
          "projects" => (1..500).to_h do |i|
            [
              "project-#{i}",
              {
                "path" => "./project-#{i}",
                "type" => "rails",
                "rules" => {
                  "copy_files" => (1..10).map { |j| { "source" => "file#{j}", "strategy" => "copy" } },
                  "setup_commands" => (1..5).map { |j| { "command" => ["command#{j}"] } },
                  "templates" => (1..3).map { |j| { "source" => "template#{j}", "destination" => "dest#{j}" } }
                }
              }
            ]
          end
        }
      end

      let(:manager) { Sxn::Config::Manager.new(start_directory: temp_dir) }

      before do
        FileUtils.mkdir_p(config_dir)
        File.write(config_file, max_config.to_yaml)
      end

      it "handles maximum configuration size within performance targets" do
        # Relaxed target for maximum size
        expect do
          manager.config
        end.to perform_under(500).ms
      end

      it "validates maximum configuration efficiently" do
        expect do
          manager.valid?
        end.to perform_under(200).ms
      end

      it "caches maximum configuration efficiently" do
        manager.config # Load once

        expect do
          manager.config
        end.to perform_under(50).ms
      end
    end
  end
end
