# frozen_string_literal: true

require "thor"

module Sxn
  # Main CLI class using Thor framework
  class CLI < Thor
    class_option :verbose, type: :boolean, aliases: "-v", desc: "Enable verbose output"
    class_option :config, type: :string, aliases: "-c", desc: "Path to configuration file"

    def self.exit_on_failure?
      true
    end

    def initialize(args = ARGV, local_options = {}, config = {})
      super
      @ui = Sxn::UI::Output.new
      setup_environment
    end

    desc "version", "Show version information"
    def version
      puts "sxn #{Sxn::VERSION}"
      puts "Session management for multi-repository development"
    end

    desc "init [FOLDER]", "Initialize sxn in a project folder"
    option :force, type: :boolean, desc: "Force initialization even if already initialized"
    option :auto_detect, type: :boolean, default: true, desc: "Automatically detect and register projects"
    option :quiet, type: :boolean, aliases: "-q", desc: "Suppress interactive prompts"
    def init(folder = nil)
      # steep:ignore:start - Thor dynamic argument validation handled at runtime
      # Thor framework uses metaprogramming for argument parsing that can't be statically typed.
      # Runtime validation ensures type safety through Thor's built-in validation.
      # Validate arguments, filtering out nil values for optional arguments
      args_for_validation = [folder].compact
      expected_arg_count = folder.nil? ? 0 : 1

      RuntimeValidations.validate_thor_arguments("init", args_for_validation, options, {
                                                   args: { count: [expected_arg_count], types: [String] },
                                                   options: { force: :boolean, auto_detect: :boolean, quiet: :boolean }
                                                 })

      Commands::Init.new.init(folder)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "add SESSION_NAME", "Create a new session (shortcut for 'sxn sessions add')"
    option :description, type: :string, aliases: "-d", desc: "Session description"
    option :linear_task, type: :string, aliases: "-l", desc: "Linear task ID"
    def add(session_name)
      Commands::Sessions.new.add(session_name)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "use SESSION_NAME", "Switch to a session (shortcut for 'sxn sessions use')"
    def use(session_name)
      Commands::Sessions.new.use(session_name)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "list", "List sessions (shortcut for 'sxn sessions list')"
    option :status, type: :string, enum: %w[active inactive archived], desc: "Filter by status"
    def list
      Commands::Sessions.new.list
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "current", "Show current session (shortcut for 'sxn sessions current')"
    option :verbose, type: :boolean, aliases: "-v", desc: "Show detailed information"
    def current
      Commands::Sessions.new.current
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "projects SUBCOMMAND", "Manage project configurations"
    def projects(subcommand = nil, *args)
      Commands::Projects.start([subcommand, *args].compact)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "sessions SUBCOMMAND", "Manage development sessions"
    def sessions(subcommand = nil, *args)
      Commands::Sessions.start([subcommand, *args].compact)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "worktree SUBCOMMAND", "Manage git worktrees"
    def worktree(subcommand = nil, *args)
      Commands::Worktrees.start([subcommand, *args].compact)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "rules SUBCOMMAND", "Manage project setup rules"
    def rules(subcommand = nil, *args)
      Commands::Rules.start([subcommand, *args].compact)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "status", "Show overall sxn status"
    def status
      show_status
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "config", "Show configuration information"
    option :validate, type: :boolean, aliases: "-v", desc: "Validate configuration"
    def config
      show_config
    rescue Sxn::Error => e
      handle_error(e)
    end

    private

    def setup_environment
      ENV["SXN_DEBUG"] = "true" if options[:verbose]

      # Set custom config path if provided
      ENV["SXN_CONFIG_PATH"] = File.expand_path(options[:config]) if options[:config]

      # Setup logger based on debug environment
      if ENV["SXN_DEBUG"]
        Sxn.setup_logger(level: :debug)
      else
        Sxn.setup_logger(level: :info)
      end
    end

    def handle_error(error)
      case error
      when Sxn::ConfigurationError
        @ui.error(error.message)
        @ui.recovery_suggestion("Run 'sxn init' to initialize sxn in this project")
      when Sxn::SessionNotFoundError
        @ui.error(error.message)
        @ui.recovery_suggestion("List available sessions with 'sxn list'")
      when Sxn::ProjectNotFoundError
        @ui.error(error.message)
        @ui.recovery_suggestion("List available projects with 'sxn projects list'")
      when Sxn::NoActiveSessionError
        @ui.error(error.message)
        @ui.recovery_suggestion("Activate a session with 'sxn use <session>' or create one with 'sxn add <session>'")
      when Sxn::WorktreeNotFoundError
        @ui.error(error.message)
        @ui.recovery_suggestion("List worktrees with 'sxn worktree list' or add one with 'sxn worktree add <project>'")
      when Sxn::SecurityError, Sxn::PathValidationError
        @ui.error("Security error: #{error.message}")
        @ui.warning("This operation was blocked for security reasons")
      when Sxn::GitError, Sxn::WorktreeError
        @ui.error("Git error: #{error.message}")
        @ui.recovery_suggestion("Check git repository status and try again")
      else
        @ui.error(error.message)
        @ui.debug(error.backtrace.join("\n")) if ENV["SXN_DEBUG"]
      end

      exit(error.exit_code)
    end

    def show_status
      config_manager = Sxn::Core::ConfigManager.new

      unless config_manager.initialized?
        @ui.error("Not initialized")
        @ui.recovery_suggestion("Run 'sxn init' to initialize sxn in this project")
        return
      end

      @ui.section("Sxn Status")

      # Current session
      current_session = config_manager.current_session
      if current_session
        @ui.key_value("Current Session", current_session)
      else
        @ui.key_value("Current Session", "None")
      end

      # Sessions folder
      sessions_folder = config_manager.sessions_folder_path
      @ui.key_value("Sessions Folder", sessions_folder)

      # Quick stats
      session_manager = Sxn::Core::SessionManager.new(config_manager)
      project_manager = Sxn::Core::ProjectManager.new(config_manager)

      sessions = session_manager.list_sessions
      projects = project_manager.list_projects

      # steep:ignore:start - Safe integer to string coercion for UI display
      # These integer values are safely converted to strings for display purposes.
      # Runtime validation ensures proper type handling.
      @ui.key_value("Total Sessions",
                    RuntimeValidations.validate_and_coerce_type(sessions.size, String, "session count display"))
      @ui.key_value("Total Projects",
                    RuntimeValidations.validate_and_coerce_type(projects.size, String, "project count display"))

      # Active worktrees
      if current_session
        worktree_manager = Sxn::Core::WorktreeManager.new(config_manager, session_manager)
        worktrees = worktree_manager.list_worktrees(session_name: current_session)
        @ui.key_value("Active Worktrees",
                      RuntimeValidations.validate_and_coerce_type(worktrees.size, String, "worktree count display"))
      end

      @ui.newline
      @ui.subsection("Quick Commands")

      if current_session
        @ui.command_example("sxn worktree add <project>", "Add worktree to current session")
        @ui.command_example("sxn worktree list", "List worktrees in current session")
      else
        @ui.command_example("sxn add <session>", "Create a new session")
        @ui.command_example("sxn list", "List all sessions")
      end
    end

    def show_config
      config_manager = Sxn::Core::ConfigManager.new

      unless config_manager.initialized?
        @ui.error("Not initialized")
        @ui.recovery_suggestion("Run 'sxn init' to initialize sxn in this project")
        return
      end

      @ui.section("Configuration")

      begin
        config = config_manager.get_config
        table = Sxn::UI::Table.new
        table.config_summary({
                               sessions_folder: config.sessions_folder,
                               current_session: config_manager.current_session,
                               auto_cleanup: config.settings&.auto_cleanup,
                               max_sessions: config.settings&.max_sessions
                             })

        if options[:validate]
          @ui.subsection("Validation")

          # Validate configuration
          issues = [] # : Array[String]

          unless File.directory?(config_manager.sessions_folder_path)
            issues << "Sessions folder does not exist: #{config_manager.sessions_folder_path}"
          end

          issues << "Configuration file is not readable: #{config_manager.config_path}" unless File.readable?(config_manager.config_path)

          if issues.empty?
            @ui.success("Configuration is valid")
          else
            @ui.error("Configuration issues found:")
            issues.each { |issue| @ui.list_item(issue) }
          end
        end
      rescue StandardError => e
        @ui.error("Could not load configuration: #{e.message}")
        @ui.debug(e.backtrace.join("\n")) if ENV["SXN_DEBUG"]
      end
    end
  end
end
