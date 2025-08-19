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

    def initialize(*)
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
    def projects(*args)
      Commands::Projects.start(args)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "sessions SUBCOMMAND", "Manage development sessions"
    def sessions(*args)
      Commands::Sessions.start(args)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "worktree SUBCOMMAND", "Manage git worktrees"
    def worktree(*args)
      Commands::Worktrees.start(args)
    rescue Sxn::Error => e
      handle_error(e)
    end

    desc "rules SUBCOMMAND", "Manage project setup rules"
    def rules(*args)
      Commands::Rules.start(args)
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
      if options[:config]
        ENV["SXN_CONFIG_PATH"] = File.expand_path(options[:config])
      end
      
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
      
      @ui.key_value("Total Sessions", sessions.size)
      @ui.key_value("Total Projects", projects.size)
      
      # Active worktrees
      if current_session
        worktree_manager = Sxn::Core::WorktreeManager.new(config_manager, session_manager)
        worktrees = worktree_manager.list_worktrees(session_name: current_session)
        @ui.key_value("Active Worktrees", worktrees.size)
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
          issues = []
          
          unless File.directory?(config_manager.sessions_folder_path)
            issues << "Sessions folder does not exist: #{config_manager.sessions_folder_path}"
          end
          
          unless File.readable?(config_manager.config_path)
            issues << "Configuration file is not readable: #{config_manager.config_path}"
          end
          
          if issues.empty?
            @ui.success("Configuration is valid")
          else
            @ui.error("Configuration issues found:")
            issues.each { |issue| @ui.list_item(issue) }
          end
        end

      rescue => e
        @ui.error("Could not load configuration: #{e.message}")
        @ui.debug(e.backtrace.join("\n")) if ENV["SXN_DEBUG"]
      end
    end
  end
end