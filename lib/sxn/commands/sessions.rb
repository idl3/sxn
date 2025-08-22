# frozen_string_literal: true

require "thor"
require "time"

module Sxn
  module Commands
    # Manage development sessions
    class Sessions < Thor
      include Thor::Actions

      def initialize(args = ARGV, local_options = {}, config = {})
        super
        @ui = Sxn::UI::Output.new
        @prompt = Sxn::UI::Prompt.new
        @table = Sxn::UI::Table.new
        @config_manager = Sxn::Core::ConfigManager.new
        @session_manager = Sxn::Core::SessionManager.new(@config_manager)
      end

      desc "add NAME", "Create a new session"
      option :description, type: :string, aliases: "-d", desc: "Session description"
      option :linear_task, type: :string, aliases: "-l", desc: "Linear task ID"
      option :activate, type: :boolean, default: true, desc: "Activate session after creation"

      def add(name = nil)
        ensure_initialized!

        # Get session name interactively if not provided
        if name.nil?
          existing_sessions = @session_manager.list_sessions.map { |s| s[:name] }
          name = @prompt.session_name(existing_sessions: existing_sessions)
        end

        begin
          @ui.progress_start("Creating session '#{name}'")

          session = @session_manager.create_session(
            name,
            description: options[:description],
            linear_task: options[:linear_task]
          )

          @ui.progress_done
          @ui.success("Created session '#{name}'")

          if options[:activate]
            @session_manager.use_session(name)
            @ui.success("Activated session '#{name}'")
          end

          display_session_info(session)
        rescue Sxn::Error => e
          @ui.progress_failed
          @ui.error(e.message)
          exit(e.exit_code)
        rescue StandardError => e
          @ui.progress_failed
          @ui.error("Unexpected error: #{e.message}")
          @ui.debug(e.backtrace.join("\n")) if ENV["SXN_DEBUG"]
          exit(1)
        end
      end

      desc "remove NAME", "Remove a session"
      option :force, type: :boolean, aliases: "-f", desc: "Force removal even with uncommitted changes"

      def remove(name = nil)
        ensure_initialized!

        # Interactive selection if name not provided
        if name.nil?
          sessions = @session_manager.list_sessions
          if sessions.empty?
            @ui.empty_state("No sessions found")
            return
          end

          choices = sessions.map { |s| { name: s[:name], value: s[:name] } }
          name = @prompt.select("Select session to remove:", choices)
        end

        unless @prompt.confirm_deletion(name, "session")
          @ui.info("Cancelled")
          return
        end

        begin
          @ui.progress_start("Removing session '#{name}'")
          @session_manager.remove_session(name, force: options[:force])
          @ui.progress_done
          @ui.success("Removed session '#{name}'")
        rescue Sxn::SessionHasChangesError => e
          @ui.progress_failed
          @ui.error(e.message)
          @ui.recovery_suggestion("Use --force to remove anyway, or commit/stash changes first")
          exit(e.exit_code)
        rescue Sxn::Error => e
          @ui.progress_failed
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "list", "List all sessions"
      option :status, type: :string, enum: %w[active inactive archived], desc: "Filter by status"
      option :limit, type: :numeric, default: 50, desc: "Maximum number of sessions to show"

      def list
        ensure_initialized!

        begin
          sessions = @session_manager.list_sessions(
            status: options[:status],
            limit: options[:limit]&.to_i || 50
          )

          @ui.section("Sessions")

          if sessions.empty?
            @ui.empty_state("No sessions found")
            suggest_create_session
          else
            @table.sessions(sessions)
            @ui.newline
            @ui.info("Total: #{sessions.size} sessions")

            current = @session_manager.current_session
            if current
              @ui.info("Current: #{current[:name]}")
            else
              @ui.recovery_suggestion("Use 'sxn use <session>' to activate a session")
            end
          end
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "use NAME", "Switch to a session"
      def use(name = nil)
        ensure_initialized!

        # Interactive selection if name not provided
        if name.nil?
          sessions = @session_manager.list_sessions(status: "active")
          if sessions.empty?
            @ui.empty_state("No active sessions found")
            suggest_create_session
            return
          end

          choices = sessions.map do |s|
            { name: "#{s[:name]} - #{s[:description] || "No description"}", value: s[:name] }
          end
          name = @prompt.select("Select session to activate:", choices)
        end

        begin
          session = @session_manager.use_session(name)
          @ui.success("Activated session '#{name}'")
          display_session_info(session)
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "current", "Show current session"
      option :verbose, type: :boolean, aliases: "-v", desc: "Show detailed information"

      def current
        ensure_initialized!

        begin
          session = @session_manager.current_session

          if session.nil?
            @ui.info("No active session")
            suggest_create_session
            return
          end

          @ui.section("Current Session")
          display_session_info(session, verbose: options[:verbose])
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "archive NAME", "Archive a session"
      def archive(name = nil)
        ensure_initialized!

        if name.nil?
          active_sessions = @session_manager.list_sessions(status: "active")
          if active_sessions.empty?
            @ui.empty_state("No active sessions to archive")
            return
          end

          choices = active_sessions.map { |s| { name: s[:name], value: s[:name] } }
          name = @prompt.select("Select session to archive:", choices)
        end

        begin
          @session_manager.archive_session(name)
          @ui.success("Archived session '#{name}'")
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "activate NAME", "Activate an archived session"
      def activate(name = nil)
        ensure_initialized!

        if name.nil?
          archived_sessions = @session_manager.list_sessions(status: "archived")
          if archived_sessions.empty?
            @ui.empty_state("No archived sessions to activate")
            return
          end

          choices = archived_sessions.map { |s| { name: s[:name], value: s[:name] } }
          name = @prompt.select("Select session to activate:", choices)
        end

        begin
          @session_manager.activate_session(name)
          @ui.success("Activated session '#{name}'")
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      private

      def ensure_initialized!
        return if @config_manager.initialized?

        @ui.error("Project not initialized")
        @ui.recovery_suggestion("Run 'sxn init' to initialize sxn in this project")
        exit(1)
      end

      def display_session_info(session, verbose: false)
        return unless session

        @ui.newline
        @ui.key_value("Name", session[:name] || "Unknown")
        @ui.key_value("Status", (session[:status] || "unknown").capitalize)
        @ui.key_value("Path", session[:path] || "Unknown")

        @ui.key_value("Description", session[:description]) if session[:description]

        @ui.key_value("Linear Task", session[:linear_task]) if session[:linear_task]

        @ui.key_value("Created", format_timestamp(session[:created_at]))
        @ui.key_value("Updated", format_timestamp(session[:updated_at]))

        if verbose && session[:projects]&.any?
          @ui.newline
          @ui.subsection("Projects")
          session[:projects].each { |project| @ui.list_item(project) }
        end

        @ui.newline
        display_session_commands(session[:name]) if session[:name]
      end

      def display_session_commands(session_name)
        @ui.subsection("Available Commands")

        @ui.command_example(
          "sxn worktree add <project> [branch]",
          "Add a worktree to this session"
        )

        @ui.command_example(
          "sxn worktree list",
          "List worktrees in this session"
        )

        @ui.command_example(
          "cd #{@session_manager.get_session(session_name)[:path]}",
          "Navigate to session directory"
        )
      end

      def suggest_create_session
        @ui.newline
        @ui.recovery_suggestion("Create your first session with 'sxn add <session-name>'")
      end

      def format_timestamp(timestamp)
        return "Unknown" if timestamp.nil? || timestamp.empty?
        
        # Parse the ISO8601 timestamp and convert to local time
        time = Time.parse(timestamp)
        local_time = time.localtime
        
        # Format as "YYYY-MM-DD HH:MM:SS AM/PM Timezone"
        local_time.strftime("%Y-%m-%d %I:%M:%S %p %Z")
      rescue ArgumentError
        timestamp # Return original if parsing fails
      end
    end
  end
end
