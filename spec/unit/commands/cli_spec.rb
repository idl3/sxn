# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::CLI do
  let(:cli) { described_class.new }

  describe "class configuration" do
    it "exits on failure" do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe "#version" do
    it "displays version information" do
      expect { cli.version }.to output(/sxn #{Sxn::VERSION}/).to_stdout
    end
  end

  describe "command delegation" do
    it "delegates init to Commands::Init" do
      init_command = instance_double(Sxn::Commands::Init)
      expect(Sxn::Commands::Init).to receive(:new).and_return(init_command)
      expect(init_command).to receive(:init).with("test-folder")

      cli.init("test-folder")
    end

    it "delegates sessions to Commands::Sessions" do
      expect(Sxn::Commands::Sessions).to receive(:start).with(["list"])

      cli.sessions("list")
    end

    it "delegates projects to Commands::Projects" do
      expect(Sxn::Commands::Projects).to receive(:start).with(%w[add test])

      cli.projects("add", "test")
    end

    it "delegates worktree to Commands::Worktrees" do
      expect(Sxn::Commands::Worktrees).to receive(:start).with(["list"])

      cli.worktree("list")
    end

    it "delegates rules to Commands::Rules" do
      expect(Sxn::Commands::Rules).to receive(:start).with(["list"])

      cli.rules("list")
    end
  end

  describe "shortcut commands" do
    it "provides add shortcut for sessions" do
      sessions_command = instance_double(Sxn::Commands::Sessions)
      expect(Sxn::Commands::Sessions).to receive(:new).and_return(sessions_command)
      expect(sessions_command).to receive(:add).with("test-session")

      cli.add("test-session")
    end

    it "provides use shortcut for sessions" do
      sessions_command = instance_double(Sxn::Commands::Sessions)
      expect(Sxn::Commands::Sessions).to receive(:new).and_return(sessions_command)
      expect(sessions_command).to receive(:use).with("test-session")

      cli.use("test-session")
    end

    it "provides list shortcut for sessions" do
      sessions_command = instance_double(Sxn::Commands::Sessions)
      expect(Sxn::Commands::Sessions).to receive(:new).and_return(sessions_command)
      expect(sessions_command).to receive(:list)

      cli.list
    end

    it "provides current shortcut for sessions" do
      sessions_command = instance_double(Sxn::Commands::Sessions)
      expect(Sxn::Commands::Sessions).to receive(:new).and_return(sessions_command)
      expect(sessions_command).to receive(:current)

      cli.current
    end
  end

  describe "error handling" do
    let(:ui_output) { instance_double(Sxn::UI::Output) }

    before do
      cli.instance_variable_set(:@ui, ui_output)
    end

    it "handles ConfigurationError with helpful message" do
      expect(ui_output).to receive(:error).with("Test config error")
      expect(ui_output).to receive(:recovery_suggestion)
        .with("Run 'sxn init' to initialize sxn in this project")

      error = Sxn::ConfigurationError.new("Test config error")
      error.define_singleton_method(:exit_code) { 1 }
      expect { cli.send(:handle_error, error) }.to raise_error(SystemExit)
    end

    it "handles SessionNotFoundError with helpful message" do
      expect(ui_output).to receive(:error).with("Session not found")
      expect(ui_output).to receive(:recovery_suggestion)
        .with("List available sessions with 'sxn list'")

      error = Sxn::SessionNotFoundError.new("Session not found")
      error.define_singleton_method(:exit_code) { 1 }
      expect { cli.send(:handle_error, error) }.to raise_error(SystemExit)
    end

    it "handles ProjectNotFoundError with helpful message" do
      expect(ui_output).to receive(:error).with("Project not found")
      expect(ui_output).to receive(:recovery_suggestion)
        .with("List available projects with 'sxn projects list'")

      error = Sxn::ProjectNotFoundError.new("Project not found")
      error.define_singleton_method(:exit_code) { 1 }
      expect { cli.send(:handle_error, error) }.to raise_error(SystemExit)
    end

    it "handles SecurityError with warning" do
      expect(ui_output).to receive(:error).with("Security error: Path validation failed")
      expect(ui_output).to receive(:warning)
        .with("This operation was blocked for security reasons")

      error = Sxn::SecurityError.new("Path validation failed")
      error.define_singleton_method(:exit_code) { 1 }
      expect { cli.send(:handle_error, error) }.to raise_error(SystemExit)
    end

    it "handles GitError with recovery suggestion" do
      expect(ui_output).to receive(:error).with("Git error: Repository not found")
      expect(ui_output).to receive(:recovery_suggestion)
        .with("Check git repository status and try again")

      error = Sxn::GitError.new("Repository not found")
      error.define_singleton_method(:exit_code) { 1 }
      expect { cli.send(:handle_error, error) }.to raise_error(SystemExit)
    end

    it "handles generic errors with debug info when verbose" do
      ENV["SXN_DEBUG"] = "true"

      expect(ui_output).to receive(:error).with("Unknown error")
      expect(ui_output).to receive(:debug).with(kind_of(String))

      error = Sxn::Error.new("Unknown error")
      error.set_backtrace(%w[line1 line2])
      error.define_singleton_method(:exit_code) { 1 }

      expect { cli.send(:handle_error, error) }.to raise_error(SystemExit)

      ENV.delete("SXN_DEBUG")
    end
  end

  describe "environment setup" do
    it "sets debug mode when verbose option is enabled" do
      # Create a mock Thor options object
      options_hash = Thor::CoreExt::HashWithIndifferentAccess.new
      options_hash["verbose"] = true

      # Create a new CLI instance and set options
      test_cli = described_class.new
      test_cli.instance_variable_set(:@options, options_hash)
      test_cli.send(:setup_environment)

      expect(ENV.fetch("SXN_DEBUG", nil)).to eq("true")

      ENV.delete("SXN_DEBUG")
    end

    it "sets custom config path when provided" do
      # Create a mock Thor options object
      options_hash = Thor::CoreExt::HashWithIndifferentAccess.new
      options_hash["config"] = "/custom/path/config.yml"

      # Create a new CLI instance and set options
      test_cli = described_class.new
      test_cli.instance_variable_set(:@options, options_hash)
      test_cli.send(:setup_environment)

      expect(ENV.fetch("SXN_CONFIG_PATH", nil)).to eq("/custom/path/config.yml")

      ENV.delete("SXN_CONFIG_PATH")
    end
  end
end
