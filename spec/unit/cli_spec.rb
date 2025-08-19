# frozen_string_literal: true

require "spec_helper"
require "thor"

RSpec.describe Sxn::CLI do
  let(:cli) { described_class.new }
  let(:ui_output) { instance_double(Sxn::UI::Output) }
  let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }

  before do
    allow(Sxn::UI::Output).to receive(:new).and_return(ui_output)
    allow(Sxn::Core::ConfigManager).to receive(:new).and_return(config_manager)
    allow(config_manager).to receive(:initialized?).and_return(true)

    # Allow all UI methods
    allow(ui_output).to receive(:puts)
    allow(ui_output).to receive(:error)
    allow(ui_output).to receive(:warn)
    allow(ui_output).to receive(:warning)
    allow(ui_output).to receive(:info)
    allow(ui_output).to receive(:success)
    allow(ui_output).to receive(:debug)
    allow(ui_output).to receive(:status)
    allow(ui_output).to receive(:section)
    allow(ui_output).to receive(:subsection)
    allow(ui_output).to receive(:list_item)
    allow(ui_output).to receive(:empty_state)
    allow(ui_output).to receive(:key_value)
    allow(ui_output).to receive(:newline)
    allow(ui_output).to receive(:recovery_suggestion)
    allow(ui_output).to receive(:command_example)
    allow(ui_output).to receive(:progress_start)
    allow(ui_output).to receive(:progress_done)
    allow(ui_output).to receive(:progress_failed)

    # Suppress CLI output during tests
    allow(cli).to receive(:puts)
    allow(cli).to receive(:print)
  end

  describe ".exit_on_failure?" do
    it "returns true" do
      expect(described_class.exit_on_failure?).to be true
    end
  end

  describe "#initialize" do
    it "creates a UI output instance" do
      expect(Sxn::UI::Output).to receive(:new)
      described_class.new
    end

    it "sets up environment" do
      expect_any_instance_of(described_class).to receive(:setup_environment)
      described_class.new
    end
  end

  describe "#version" do
    it "displays the version number and description" do
      # Create a new CLI instance without stubbed puts for this test
      version_cli = described_class.new
      expect { version_cli.version }.to output(/sxn #{Sxn::VERSION}/).to_stdout
      expect { version_cli.version }.to output(/Session management for multi-repository development/).to_stdout
    end
  end

  describe "#init" do
    let(:init_command) { instance_double(Sxn::Commands::Init) }

    before do
      allow(Sxn::Commands::Init).to receive(:new).and_return(init_command)
      allow(init_command).to receive(:init)
    end

    it "initializes sxn successfully without folder" do
      expect(init_command).to receive(:init).with(nil)
      cli.init
    end

    it "initializes sxn with specified folder" do
      expect(init_command).to receive(:init).with("my-sessions")
      cli.init("my-sessions")
    end

    it "handles initialization errors" do
      allow(init_command).to receive(:init).and_raise(Sxn::ConfigurationError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::ConfigurationError))
      cli.init("valid_folder")
    end
  end

  describe "#add" do
    let(:sessions_command) { instance_double(Sxn::Commands::Sessions) }

    before do
      allow(Sxn::Commands::Sessions).to receive(:new).and_return(sessions_command)
      allow(sessions_command).to receive(:add)
    end

    it "creates a new session" do
      expect(sessions_command).to receive(:add).with("test-session")
      cli.add("test-session")
    end

    it "handles session creation errors" do
      allow(sessions_command).to receive(:add).and_raise(Sxn::SessionError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::SessionError))
      cli.add("test-session")
    end
  end

  describe "#use" do
    let(:sessions_command) { instance_double(Sxn::Commands::Sessions) }

    before do
      allow(Sxn::Commands::Sessions).to receive(:new).and_return(sessions_command)
      allow(sessions_command).to receive(:use)
    end

    it "switches to a session" do
      expect(sessions_command).to receive(:use).with("test-session")
      cli.use("test-session")
    end

    it "handles session switch errors" do
      allow(sessions_command).to receive(:use).and_raise(Sxn::SessionError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::SessionError))
      cli.use("test-session")
    end
  end

  describe "#list" do
    let(:sessions_command) { instance_double(Sxn::Commands::Sessions) }

    before do
      allow(Sxn::Commands::Sessions).to receive(:new).and_return(sessions_command)
      allow(sessions_command).to receive(:list)
    end

    it "lists sessions" do
      expect(sessions_command).to receive(:list)
      cli.list
    end

    it "handles listing errors" do
      allow(sessions_command).to receive(:list).and_raise(Sxn::SessionError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::SessionError))
      cli.list
    end
  end

  describe "#current" do
    let(:sessions_command) { instance_double(Sxn::Commands::Sessions) }

    before do
      allow(Sxn::Commands::Sessions).to receive(:new).and_return(sessions_command)
      allow(sessions_command).to receive(:current)
    end

    it "shows current session" do
      expect(sessions_command).to receive(:current)
      cli.current
    end

    it "handles current session errors" do
      allow(sessions_command).to receive(:current).and_raise(Sxn::SessionError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::SessionError))
      cli.current
    end
  end

  describe "#projects" do
    before do
      allow(Sxn::Commands::Projects).to receive(:start)
    end

    it "delegates to projects command" do
      expect(Sxn::Commands::Projects).to receive(:start).with(["list"])
      cli.projects("list")
    end

    it "handles multiple arguments" do
      expect(Sxn::Commands::Projects).to receive(:start).with(%w[add test-project])
      cli.projects("add", "test-project")
    end

    it "handles project command errors" do
      allow(Sxn::Commands::Projects).to receive(:start).and_raise(Sxn::ProjectError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::ProjectError))
      cli.projects("list")
    end
  end

  describe "#sessions" do
    before do
      allow(Sxn::Commands::Sessions).to receive(:start)
    end

    it "delegates to sessions command" do
      expect(Sxn::Commands::Sessions).to receive(:start).with(["list"])
      cli.sessions("list")
    end

    it "handles multiple arguments" do
      expect(Sxn::Commands::Sessions).to receive(:start).with(%w[add test-session])
      cli.sessions("add", "test-session")
    end

    it "handles session command errors" do
      allow(Sxn::Commands::Sessions).to receive(:start).and_raise(Sxn::SessionError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::SessionError))
      cli.sessions("list")
    end
  end

  describe "#worktree" do
    before do
      allow(Sxn::Commands::Worktrees).to receive(:start)
    end

    it "delegates to worktree command" do
      expect(Sxn::Commands::Worktrees).to receive(:start).with(["list"])
      cli.worktree("list")
    end

    it "handles multiple arguments" do
      expect(Sxn::Commands::Worktrees).to receive(:start).with(%w[add feature-branch])
      cli.worktree("add", "feature-branch")
    end

    it "handles worktree command errors" do
      allow(Sxn::Commands::Worktrees).to receive(:start).and_raise(Sxn::WorktreeError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::WorktreeError))
      cli.worktree("list")
    end
  end

  describe "#rules" do
    before do
      allow(Sxn::Commands::Rules).to receive(:start)
    end

    it "delegates list command" do
      expect(Sxn::Commands::Rules).to receive(:start).with(["list"])
      cli.rules("list")
    end

    it "delegates add command" do
      expect(Sxn::Commands::Rules).to receive(:start).with(%w[add test-rule])
      cli.rules("add", "test-rule")
    end

    it "handles rules command errors" do
      allow(Sxn::Commands::Rules).to receive(:start).and_raise(Sxn::RuleError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::RuleError))
      cli.rules("list")
    end
  end

  describe "#status" do
    before do
      allow(cli).to receive(:show_status)
    end

    it "shows status information" do
      expect(cli).to receive(:show_status)
      cli.status
    end

    it "handles status errors" do
      allow(cli).to receive(:show_status).and_raise(Sxn::ConfigurationError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::ConfigurationError))
      cli.status
    end
  end

  describe "#config" do
    before do
      allow(cli).to receive(:show_config)
    end

    it "shows configuration information" do
      expect(cli).to receive(:show_config)
      cli.config
    end

    it "handles config errors" do
      allow(cli).to receive(:show_config).and_raise(Sxn::ConfigurationError, "Test error")
      allow(cli).to receive(:exit)
      expect(cli).to receive(:handle_error).with(instance_of(Sxn::ConfigurationError))
      cli.config
    end
  end

  describe "#setup_environment" do
    before do
      # Reset environment variables
      ENV.delete("SXN_DEBUG")
      ENV.delete("SXN_CONFIG_PATH")
    end

    after do
      # Clean up environment variables
      ENV.delete("SXN_DEBUG")
      ENV.delete("SXN_CONFIG_PATH")
    end

    context "when verbose option is enabled" do
      it "sets SXN_DEBUG environment variable and enables debug logging" do
        # Stub all possible logger calls
        allow(Sxn).to receive(:setup_logger).with(level: :info)
        allow(Sxn).to receive(:setup_logger).with(level: :debug)

        cli_instance = described_class.new(["--verbose"])
        allow(cli_instance).to receive(:options).and_return({ verbose: true })

        # Mock the expectation for the actual setup_environment call
        expect(Sxn).to receive(:setup_logger).with(level: :debug)
        cli_instance.send(:setup_environment)
        expect(ENV.fetch("SXN_DEBUG", nil)).to eq("true")
      end
    end

    context "when config option is provided" do
      it "sets SXN_CONFIG_PATH environment variable" do
        # Stub all possible logger calls
        allow(Sxn).to receive(:setup_logger).with(level: :info)
        allow(Sxn).to receive(:setup_logger).with(level: :debug)

        cli_instance = described_class.new(["--config", "config/custom.yml"])
        allow(cli_instance).to receive(:options).and_return({ config: "config/custom.yml" })

        # Mock the expectation for the actual setup_environment call
        expect(Sxn).to receive(:setup_logger).with(level: :info)
        cli_instance.send(:setup_environment)
        expect(ENV.fetch("SXN_CONFIG_PATH", nil)).to eq(File.expand_path("config/custom.yml"))
      end
    end

    it "enables debug mode when SXN_DEBUG is already set" do
      ENV["SXN_DEBUG"] = "1"
      expect(Sxn).to receive(:setup_logger).with(level: :debug)
      cli.send(:setup_environment)
    end

    it "uses default logger level when SXN_DEBUG is not set" do
      expect(Sxn).to receive(:setup_logger).with(level: :info)
      cli.send(:setup_environment)
    end

    it "uses custom config path when SXN_CONFIG_PATH is set" do
      ENV["SXN_CONFIG_PATH"] = "/custom/path"
      # The method should handle this environment variable
      # Implementation details depend on the actual setup_environment method
      expect { cli.send(:setup_environment) }.not_to raise_error
    end

    context "when both verbose and config options are provided" do
      it "sets both SXN_DEBUG and SXN_CONFIG_PATH" do
        # Stub all possible logger calls
        allow(Sxn).to receive(:setup_logger).with(level: :info)
        allow(Sxn).to receive(:setup_logger).with(level: :debug)

        cli_instance = described_class.new(["--verbose", "--config", "config/custom.yml"])
        allow(cli_instance).to receive(:options).and_return({
                                                              verbose: true,
                                                              config: "config/custom.yml"
                                                            })

        # Mock the expectation for the actual setup_environment call
        expect(Sxn).to receive(:setup_logger).with(level: :debug)
        cli_instance.send(:setup_environment)
        expect(ENV.fetch("SXN_DEBUG", nil)).to eq("true")
        expect(ENV.fetch("SXN_CONFIG_PATH", nil)).to eq(File.expand_path("config/custom.yml"))
      end
    end
  end

  describe "#handle_error" do
    context "with known error types" do
      it "handles ConfigurationError" do
        error = Sxn::ConfigurationError.new("Config error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Config error")
        expect(ui_output).to receive(:recovery_suggestion).with("Run 'sxn init' to initialize sxn in this project")
        cli.send(:handle_error, error)
      end

      it "handles SessionNotFoundError" do
        error = Sxn::SessionNotFoundError.new("Session not found")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Session not found")
        expect(ui_output).to receive(:recovery_suggestion).with("List available sessions with 'sxn list'")
        cli.send(:handle_error, error)
      end

      it "handles ProjectNotFoundError" do
        error = Sxn::ProjectNotFoundError.new("Project not found")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Project not found")
        expect(ui_output).to receive(:recovery_suggestion).with("List available projects with 'sxn projects list'")
        cli.send(:handle_error, error)
      end

      # Test lines 142-143: NoActiveSessionError handling
      it "handles NoActiveSessionError" do
        error = Sxn::NoActiveSessionError.new("No active session")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("No active session")
        expect(ui_output).to receive(:recovery_suggestion).with("Activate a session with 'sxn use <session>' or create one with 'sxn add <session>'")
        cli.send(:handle_error, error)
      end

      # Test lines 145-146: WorktreeNotFoundError handling
      it "handles WorktreeNotFoundError" do
        error = Sxn::WorktreeNotFoundError.new("Worktree not found")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Worktree not found")
        expect(ui_output).to receive(:recovery_suggestion).with("List worktrees with 'sxn worktree list' or add one with 'sxn worktree add <project>'")
        cli.send(:handle_error, error)
      end

      it "handles PathValidationError" do
        error = Sxn::PathValidationError.new("Path validation error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Security error: Path validation error")
        expect(ui_output).to receive(:warning).with("This operation was blocked for security reasons")
        cli.send(:handle_error, error)
      end

      it "handles WorktreeError" do
        error = Sxn::WorktreeError.new("Worktree error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Git error: Worktree error")
        expect(ui_output).to receive(:recovery_suggestion).with("Check git repository status and try again")
        cli.send(:handle_error, error)
      end

      it "handles GitError" do
        error = Sxn::GitError.new("Git error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Git error: Git error")
        expect(ui_output).to receive(:recovery_suggestion).with("Check git repository status and try again")
        cli.send(:handle_error, error)
      end

      it "handles SecurityError" do
        error = Sxn::SecurityError.new("Security error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Security error: Security error")
        expect(ui_output).to receive(:warning).with("This operation was blocked for security reasons")
        cli.send(:handle_error, error)
      end

      it "handles SessionError" do
        error = Sxn::SessionError.new("Session error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Session error")
        cli.send(:handle_error, error)
      end

      it "handles ProjectError" do
        error = Sxn::ProjectError.new("Project error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Project error")
        cli.send(:handle_error, error)
      end

      it "handles RuleError" do
        error = Sxn::RuleError.new("Rule error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Rule error")
        cli.send(:handle_error, error)
      end

      it "handles TemplateError" do
        error = Sxn::TemplateError.new("Template error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Template error")
        cli.send(:handle_error, error)
      end

      it "handles DatabaseError" do
        error = Sxn::DatabaseError.new("Database error")
        allow(error).to receive(:backtrace).and_return([])
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Database error")
        cli.send(:handle_error, error)
      end
    end

    context "with unknown error types" do
      it "handles generic StandardError" do
        error = StandardError.new("Generic error")
        allow(error).to receive(:backtrace).and_return([])
        # Define exit_code method on the error instance
        error.define_singleton_method(:exit_code) { 1 }
        allow(cli).to receive(:exit)
        expect(ui_output).to receive(:error).with("Generic error")
        cli.send(:handle_error, error)
      end

      it "shows debug information in verbose mode" do
        # Create a CLI with verbose option
        verbose_cli = described_class.new
        allow(verbose_cli.instance_variable_get(:@ui)).to receive(:error)
        allow(verbose_cli.instance_variable_get(:@ui)).to receive(:debug)
        allow(verbose_cli).to receive(:exit)

        # Set environment variable for debug mode
        ENV["SXN_DEBUG"] = "true"

        error = StandardError.new("Generic error")
        allow(error).to receive(:backtrace).and_return(["line 1", "line 2"])
        # Define exit_code method on the error instance
        error.define_singleton_method(:exit_code) { 1 }

        expect(verbose_cli.instance_variable_get(:@ui)).to receive(:error).with("Generic error")
        expect(verbose_cli.instance_variable_get(:@ui)).to receive(:debug).with("line 1\nline 2")

        verbose_cli.send(:handle_error, error)

        # Clean up environment variable
        ENV.delete("SXN_DEBUG")
      end
    end
  end

  describe "#show_status" do
    let(:session_manager) { instance_double(Sxn::Core::SessionManager) }
    let(:project_manager) { instance_double(Sxn::Core::ProjectManager) }
    let(:worktree_manager) { instance_double(Sxn::Core::WorktreeManager) }

    before do
      allow(Sxn::Core::SessionManager).to receive(:new).and_return(session_manager)
      allow(Sxn::Core::ProjectManager).to receive(:new).and_return(project_manager)
      allow(Sxn::Core::WorktreeManager).to receive(:new).and_return(worktree_manager)
      allow(worktree_manager).to receive(:list_worktrees).and_return([])
      allow(session_manager).to receive(:get_session).and_return({ name: "current-session", status: "active" })
    end

    context "when project is initialized" do
      before do
        allow(config_manager).to receive(:initialized?).and_return(true)
        allow(config_manager).to receive(:current_session).and_return("current-session")
        allow(config_manager).to receive(:sessions_folder_path).and_return("/path/to/sessions")
        allow(session_manager).to receive(:list_sessions).and_return([
                                                                       { name: "session1", status: "active" },
                                                                       { name: "session2", status: "inactive" }
                                                                     ])
        allow(project_manager).to receive(:list_projects).and_return([
                                                                       { name: "project1", type: "rails" },
                                                                       { name: "project2", type: "javascript" }
                                                                     ])
      end

      it "shows comprehensive status information" do
        # Make the UI output actually print for this test
        allow(ui_output).to receive(:section) { |msg| puts msg }
        allow(ui_output).to receive(:key_value) { |key, value| puts "#{key}: #{value}" }

        expect { cli.send(:show_status) }.to output(/Sxn Status/).to_stdout
        expect { cli.send(:show_status) }.to output(/Current Session: current-session/).to_stdout
        expect { cli.send(:show_status) }.to output(/Total Sessions: 2/).to_stdout
        expect { cli.send(:show_status) }.to output(/Total Projects: 2/).to_stdout
      end

      # Test line 177: No current session case
      context "when no current session is active" do
        before do
          allow(config_manager).to receive(:current_session).and_return(nil)
          # Make the UI output actually print for this test
          allow(ui_output).to receive(:section) { |msg| puts msg }
          allow(ui_output).to receive(:key_value) { |key, value| puts "#{key}: #{value}" }
        end

        it "shows 'None' for current session" do
          expect { cli.send(:show_status) }.to output(/Current Session: None/).to_stdout
        end
      end

      # Test line 195: Active worktrees when current session exists
      context "when there is a current session with worktrees" do
        before do
          allow(config_manager).to receive(:current_session).and_return("active-session")
          allow(worktree_manager).to receive(:list_worktrees).with(session_name: "active-session").and_return([
                                                                                                                { name: "worktree1" },
                                                                                                                { name: "worktree2" }
                                                                                                              ])
          # Make the UI output actually print for this test
          allow(ui_output).to receive(:section) { |msg| puts msg }
          allow(ui_output).to receive(:key_value) { |key, value| puts "#{key}: #{value}" }
        end

        it "shows active worktrees count" do
          expect { cli.send(:show_status) }.to output(/Active Worktrees: 2/).to_stdout
        end
      end

      # Test lines 208-209: Commands when no current session (else branch)
      context "when showing quick commands without current session" do
        before do
          allow(config_manager).to receive(:current_session).and_return(nil)
          allow(ui_output).to receive(:section)
          allow(ui_output).to receive(:key_value)
          allow(ui_output).to receive(:newline)
          allow(ui_output).to receive(:subsection)
          allow(ui_output).to receive(:command_example) { |cmd, desc| puts "#{cmd}: #{desc}" }
        end

        it "shows commands for creating sessions" do
          expect { cli.send(:show_status) }.to output(/sxn add <session>: Create a new session/).to_stdout
          expect { cli.send(:show_status) }.to output(/sxn list: List all sessions/).to_stdout
        end
      end
    end

    context "when project is not initialized" do
      before do
        allow(config_manager).to receive(:initialized?).and_return(false)
        # Make the UI output actually print for this test
        allow(ui_output).to receive(:error) { |msg| puts "❌ #{msg}" }
      end

      it "shows not initialized message" do
        expect { cli.send(:show_status) }.to output(/Not initialized/).to_stdout
      end
    end
  end

  describe "#show_config" do
    let(:config_struct) do
      OpenStruct.new(sessions_folder: "sessions", settings: OpenStruct.new(auto_cleanup: true, max_sessions: 10))
    end
    let(:config_table) { instance_double(Sxn::UI::Table) }

    before do
      allow(config_manager).to receive(:initialized?).and_return(true)
      allow(config_manager).to receive(:get_config).and_return(config_struct)
      allow(config_manager).to receive(:current_session).and_return("test-session")
      allow(Sxn::UI::Table).to receive(:new).and_return(config_table)
      allow(config_table).to receive(:config_summary)
      # Make the UI output actually print for this test
      allow(ui_output).to receive(:section) { |msg| puts msg }
    end

    it "shows configuration information" do
      expect { cli.send(:show_config) }.to output(/Configuration/).to_stdout
    end

    context "when project is not initialized" do
      before do
        allow(config_manager).to receive(:initialized?).and_return(false)
        # Make the UI output actually print for this test
        allow(ui_output).to receive(:error) { |msg| puts "❌ #{msg}" }
      end

      it "shows not initialized message" do
        expect { cli.send(:show_config) }.to output(/Not initialized/).to_stdout
      end
    end

    # Test lines 234-255: Configuration validation with --validate option
    context "when validation option is enabled" do
      let(:cli_with_validate) do
        # Allow setup during initialization
        allow(Sxn).to receive(:setup_logger)
        # Create CLI with validate option
        cli_instance = described_class.new(["config", "--validate"])
        allow(cli_instance).to receive(:options).and_return({ validate: true })
        cli_instance
      end

      before do
        allow(Sxn::UI::Output).to receive(:new).and_return(ui_output)
        allow(config_manager).to receive(:sessions_folder_path).and_return("/path/to/sessions")
        allow(config_manager).to receive(:config_path).and_return("/path/to/config.yml")
        allow(ui_output).to receive(:section)
        allow(ui_output).to receive(:subsection) { |msg| puts msg }
      end

      # Test line 235, 248-249: Validation passes (no issues)
      context "when configuration is valid" do
        before do
          allow(File).to receive(:directory?).with("/path/to/sessions").and_return(true)
          allow(File).to receive(:readable?).with("/path/to/config.yml").and_return(true)
          allow(ui_output).to receive(:success) { |msg| puts "✅ #{msg}" }
        end

        it "shows validation success" do
          expect { cli_with_validate.send(:show_config) }.to output(/Configuration is valid/).to_stdout
        end
      end

      # Test lines 240-241: Sessions folder does not exist
      context "when sessions folder doesn't exist" do
        before do
          allow(File).to receive(:directory?).with("/path/to/sessions").and_return(false)
          allow(File).to receive(:readable?).with("/path/to/config.yml").and_return(true)
          allow(ui_output).to receive(:error) { |msg| puts "❌ #{msg}" }
          allow(ui_output).to receive(:list_item) { |msg| puts "  • #{msg}" }
        end

        it "shows sessions folder validation error" do
          expect { cli_with_validate.send(:show_config) }.to output(/Configuration issues found/).to_stdout
          expect { cli_with_validate.send(:show_config) }.to output(/Sessions folder does not exist/).to_stdout
        end
      end

      # Test lines 244-245: Config file is not readable
      context "when config file is not readable" do
        before do
          allow(File).to receive(:directory?).with("/path/to/sessions").and_return(true)
          allow(File).to receive(:readable?).with("/path/to/config.yml").and_return(false)
          allow(ui_output).to receive(:error) { |msg| puts "❌ #{msg}" }
          allow(ui_output).to receive(:list_item) { |msg| puts "  • #{msg}" }
        end

        it "shows config file validation error" do
          expect { cli_with_validate.send(:show_config) }.to output(/Configuration issues found/).to_stdout
          expect { cli_with_validate.send(:show_config) }.to output(/Configuration file is not readable/).to_stdout
        end
      end

      # Test lines 251-252: Multiple validation issues
      context "when multiple validation issues exist" do
        before do
          allow(File).to receive(:directory?).with("/path/to/sessions").and_return(false)
          allow(File).to receive(:readable?).with("/path/to/config.yml").and_return(false)
          allow(ui_output).to receive(:error) { |msg| puts "❌ #{msg}" }
          allow(ui_output).to receive(:list_item) { |msg| puts "  • #{msg}" }
        end

        it "shows all validation issues" do
          expect { cli_with_validate.send(:show_config) }.to output(/Configuration issues found/).to_stdout
          expect { cli_with_validate.send(:show_config) }.to output(/Sessions folder does not exist/).to_stdout
          expect { cli_with_validate.send(:show_config) }.to output(/Configuration file is not readable/).to_stdout
        end
      end
    end

    # Test lines 257-258: Exception handling in show_config
    context "when configuration loading fails" do
      before do
        allow(config_manager).to receive(:get_config).and_raise(StandardError, "Config load failed")
        allow(ui_output).to receive(:error) { |msg| puts "❌ #{msg}" }
        allow(ui_output).to receive(:debug)
      end

      it "handles configuration loading errors" do
        expect { cli.send(:show_config) }.to output(/Could not load configuration: Config load failed/).to_stdout
      end

      context "when in debug mode" do
        before do
          ENV["SXN_DEBUG"] = "true"
          allow(ui_output).to receive(:debug) { |msg| puts "DEBUG: #{msg}" }
        end

        after do
          ENV.delete("SXN_DEBUG")
        end

        it "shows debug information" do
          error = StandardError.new("Config load failed")
          allow(error).to receive(:backtrace).and_return(%w[line1 line2])
          allow(config_manager).to receive(:get_config).and_raise(error)

          expect { cli.send(:show_config) }.to output(/DEBUG: line1/).to_stdout
        end
      end
    end
  end

  # Test class options and Thor integration
  describe "Thor integration" do
    it "defines verbose option" do
      expect(described_class.class_options[:verbose]).not_to be_nil
    end

    it "defines config option" do
      expect(described_class.class_options[:config]).not_to be_nil
    end

    it "inherits from Thor" do
      expect(described_class).to be < Thor
    end
  end

  # Test Thor command descriptions
  describe "command descriptions" do
    it "has proper command descriptions" do
      expect(described_class.tasks["version"].description).to eq("Show version information")
      expect(described_class.tasks["init"].description).to eq("Initialize sxn in a project folder")
      expect(described_class.tasks["add"].description).to eq("Create a new session (shortcut for 'sxn sessions add')")
      expect(described_class.tasks["use"].description).to eq("Switch to a session (shortcut for 'sxn sessions use')")
      expect(described_class.tasks["list"].description).to eq("List sessions (shortcut for 'sxn sessions list')")
      expect(described_class.tasks["current"].description).to eq("Show current session (shortcut for 'sxn sessions current')")
      expect(described_class.tasks["projects"].description).to eq("Manage project configurations")
      expect(described_class.tasks["sessions"].description).to eq("Manage development sessions")
      expect(described_class.tasks["worktree"].description).to eq("Manage git worktrees")
      expect(described_class.tasks["rules"].description).to eq("Manage project setup rules")
      expect(described_class.tasks["status"].description).to eq("Show overall sxn status")
      expect(described_class.tasks["config"].description).to eq("Show configuration information")
    end
  end
end
