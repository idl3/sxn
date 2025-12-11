# frozen_string_literal: true

require "thor"
require "time"
require "shellwords"

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
        @project_manager = Sxn::Core::ProjectManager.new(@config_manager)
        @worktree_manager = Sxn::Core::WorktreeManager.new(@config_manager, @session_manager)
        @template_manager = Sxn::Core::TemplateManager.new(@config_manager)
      end

      desc "add NAME", "Create a new session"
      option :description, type: :string, aliases: "-d", desc: "Session description"
      option :linear_task, type: :string, aliases: "-l", desc: "Linear task ID"
      option :branch, type: :string, aliases: "-b", desc: "Default branch for worktrees"
      option :template, type: :string, aliases: "-t", desc: "Template to use for worktree creation"
      option :activate, type: :boolean, default: true, desc: "Activate session after creation"
      option :skip_worktree, type: :boolean, default: false, desc: "Skip worktree creation wizard"

      def add(name = nil)
        ensure_initialized!

        # Get session name interactively if not provided
        if name.nil?
          existing_sessions = @session_manager.list_sessions.map { |s| s[:name] }
          name = @prompt.session_name(existing_sessions: existing_sessions)
        end

        template_id = options[:template]

        # Validate template if specified
        if template_id
          begin
            @template_manager.validate_template(template_id)
          rescue Sxn::SessionTemplateNotFoundError, Sxn::SessionTemplateValidationError => e
            @ui.error(e.message)
            exit(1)
          end
        end

        # Get default branch - use provided option, or prompt interactively
        # Branch is required when using a template
        default_branch = options[:branch]
        if default_branch.nil?
          if template_id
            @ui.error("Branch is required when using a template. Use -b/--branch to specify.")
            exit(1)
          else
            default_branch = @prompt.default_branch(session_name: name)
          end
        end

        begin
          @ui.progress_start("Creating session '#{name}'")

          session = @session_manager.create_session(
            name,
            description: options[:description],
            linear_task: options[:linear_task],
            default_branch: default_branch,
            template_id: template_id
          )

          @ui.progress_done
          @ui.success("Created session '#{name}'")

          # Always activate the new session (this is the expected behavior)
          @session_manager.use_session(name)
          @ui.success("Switched to session '#{name}'")

          display_session_info(session)

          # Apply template if specified (with atomic rollback on failure)
          if template_id
            apply_template_to_session(name, template_id, default_branch)
          elsif !options[:skip_worktree]
            # Offer to add a worktree unless skipped or template was used
            offer_worktree_wizard(name)
          end
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

        # Skip confirmation if force flag is used
        if !options[:force] && !@prompt.confirm_deletion(name, "session")
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

      desc "current [SUBCOMMAND]", "Show current session or enter its directory"
      option :verbose, type: :boolean, aliases: "-v", desc: "Show detailed information"
      option :path, type: :boolean, aliases: "-p", desc: "Output only the session path (for shell integration)"

      def current(subcommand = nil)
        ensure_initialized!

        # Handle 'sxn current enter' subcommand
        if subcommand == "enter"
          enter_session
          return
        elsif subcommand
          @ui.error("Unknown subcommand: #{subcommand}")
          @ui.info("Available: enter")
          exit(1)
        end

        begin
          session = @session_manager.current_session

          if session.nil?
            @ui.info("No active session")
            suggest_create_session
            return
          end

          # If --path flag, just output the path for shell integration
          if options[:path]
            puts session[:path]
            return
          end

          @ui.section("Current Session")
          display_session_info(session, verbose: options[:verbose])
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "enter", "Enter the current session directory (outputs cd command)"
      def enter
        enter_session
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

      def apply_template_to_session(session_name, template_id, default_branch)
        template = @template_manager.get_template(template_id)
        projects = template["projects"] || []
        created_worktrees = []

        @ui.newline
        @ui.section("Applying Template '#{template_id}'")
        @ui.info("Creating #{projects.size} worktree(s)...")

        begin
          projects.each_with_index do |project_config, index|
            project_name = project_config["name"]
            # Use project-specific branch override, or fall back to session default
            branch = project_config["branch"] || default_branch

            @ui.progress_start("Creating worktree #{index + 1}/#{projects.size}: #{project_name}")

            worktree = @worktree_manager.add_worktree(
              project_name,
              branch,
              session_name: session_name
            )
            created_worktrees << worktree

            @ui.progress_done

            # Apply project's default rules first
            apply_project_rules(project_name, session_name)

            # Apply template-specific rule overrides if defined (in addition to project defaults)
            apply_template_rules(session_name, project_name, worktree[:path], project_config["rules"]) if project_config["rules"]
          end

          @ui.newline
          @ui.success("Template applied: #{created_worktrees.size} worktree(s) created")

          # Display created worktrees
          @ui.newline
          @ui.subsection("Created Worktrees")
          created_worktrees.each do |wt|
            @ui.list_item("#{wt[:project]} (#{wt[:branch]}) → #{wt[:path]}")
          end
        rescue StandardError => e
          # ATOMIC ROLLBACK: Remove all created worktrees and the session
          @ui.progress_failed
          @ui.newline
          @ui.warning("Template application failed, rolling back...")

          rollback_template_application(session_name, created_worktrees)

          raise Sxn::SessionTemplateApplicationError.new(template_id, e.message)
        end
      end

      def rollback_template_application(session_name, created_worktrees)
        # Remove created worktrees
        created_worktrees.each do |wt|
          @worktree_manager.remove_worktree(wt[:project], session_name: session_name)
        rescue StandardError
          # Best effort cleanup, continue with rollback
          nil
        end

        # Remove the session
        @session_manager.remove_session(session_name, force: true)
        @ui.info("Session '#{session_name}' has been rolled back")
      rescue StandardError => e
        @ui.warning("Rollback encountered errors: #{e.message}")
      end

      def apply_template_rules(_session_name, project_name, worktree_path, rules)
        return unless rules.is_a?(Hash)

        rules_manager = Sxn::Core::RulesManager.new(@config_manager, worktree_path)

        rules_manager.apply_copy_files_rules(rules["copy_files"]) if rules["copy_files"]

        rules_manager.apply_setup_commands(rules["setup_commands"]) if rules["setup_commands"]
      rescue StandardError => e
        @ui.warning("Failed to apply rules for #{project_name}: #{e.message}")
      end

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
        @ui.key_value("Default Branch", session[:default_branch]) if session[:default_branch]

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

      def offer_worktree_wizard(session_name)
        @ui.newline
        @ui.section("Add Worktree")

        # Check if there are any projects configured
        projects = @project_manager.list_projects
        if projects.empty?
          @ui.info("No projects configured yet.")
          @ui.recovery_suggestion("Add projects with 'sxn projects add <name> <path>'")
          return
        end

        # Ask if user wants to add a worktree
        return unless @prompt.ask_yes_no("Would you like to add a worktree to this session?", default: true)

        # Step 1: Select project with descriptions
        @ui.newline
        @ui.info("A worktree is a linked copy of a project that allows you to work on a branch")
        @ui.info("without affecting the main repository. Select which project to add:")
        @ui.newline

        project_choices = projects.map do |p|
          {
            name: "#{p[:name]} (#{p[:type]}) - #{p[:path]}",
            value: p[:name]
          }
        end
        project_name = @prompt.select("Select project:", project_choices)

        # Step 2: Get branch name with explanation
        # Get session's default branch for the default value
        session = @session_manager.get_session(session_name)
        default_branch_for_worktree = session[:default_branch] || session_name

        @ui.newline
        @ui.info("Enter the branch name for this worktree.")
        @ui.info("This can be an existing branch or a new one to create.")
        @ui.info("Tip: Use 'remote:<branch>' to track a remote branch (e.g., 'remote:origin/main')")
        @ui.newline

        branch = @prompt.branch_name(
          "Branch name:",
          default: default_branch_for_worktree
        )

        # Step 3: Create the worktree
        create_worktree_for_session(project_name, branch, session_name)

        # Offer to add more worktrees
        add_more_worktrees(session_name)
      end

      def create_worktree_for_session(project_name, branch, session_name)
        @ui.newline
        @ui.progress_start("Creating worktree for #{project_name}")

        worktree = @worktree_manager.add_worktree(
          project_name,
          branch,
          session_name: session_name
        )

        @ui.progress_done
        @ui.success("Created worktree for #{project_name}")

        display_worktree_info(worktree)

        # Apply rules
        apply_project_rules(project_name, session_name)
      rescue Sxn::Error => e
        @ui.progress_failed
        @ui.error(e.message)
        @ui.recovery_suggestion("You can try again with 'sxn worktree add #{project_name}'")
      end

      def add_more_worktrees(session_name)
        projects = @project_manager.list_projects
        return if projects.empty?

        # Get session's default branch for the default value
        session = @session_manager.get_session(session_name)
        default_branch_for_worktree = session[:default_branch] || session_name

        while @prompt.ask_yes_no("Would you like to add another worktree?", default: false)
          @ui.newline

          project_choices = projects.map do |p|
            {
              name: "#{p[:name]} (#{p[:type]}) - #{p[:path]}",
              value: p[:name]
            }
          end
          project_name = @prompt.select("Select project:", project_choices)

          branch = @prompt.branch_name(
            "Branch name:",
            default: default_branch_for_worktree
          )

          create_worktree_for_session(project_name, branch, session_name)
        end
      end

      def display_worktree_info(worktree)
        @ui.newline
        @ui.key_value("Project", worktree[:project])
        @ui.key_value("Branch", worktree[:branch])
        @ui.key_value("Path", worktree[:path])
      end

      def enter_session
        session = @session_manager.current_session

        if session.nil?
          # When no session, provide helpful guidance instead of just a cd command
          warn "No active session. Use 'sxn use <session>' to activate a session first."
          warn ""
          warn "Tip: Add this function to your shell profile for easier navigation:"
          warn ""
          warn "  sxn-enter() { eval \"$(sxn enter 2>/dev/null)\" || sxn enter; }"
          warn ""
          exit(1)
        end

        session_path = session[:path]

        unless session_path && File.directory?(session_path)
          warn "Session directory does not exist: #{session_path || "nil"}"
          exit(1)
        end

        # Output the cd command for shell integration
        # Users can use: eval "$(sxn enter)" or the sxn-enter shell function
        puts "cd #{Shellwords.escape(session_path)}"
      rescue Sxn::Error => e
        warn e.message
        exit(e.exit_code)
      end

      def apply_project_rules(project_name, session_name)
        rules_manager = Sxn::Core::RulesManager.new(@config_manager, @project_manager)

        @ui.progress_start("Applying rules for #{project_name}")
        results = rules_manager.apply_rules(project_name, session_name)
        @ui.progress_done

        if results[:success]
          @ui.success("Applied #{results[:applied_count]} rules") if results[:applied_count].positive?
        else
          @ui.warning("Some rules failed to apply")
        end
      rescue StandardError => e
        @ui.warning("Could not apply rules: #{e.message}")
      end
    end
  end
end
