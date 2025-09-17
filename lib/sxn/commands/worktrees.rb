# frozen_string_literal: true

require "thor"

module Sxn
  module Commands
    # Manage git worktrees
    class Worktrees < Thor
      include Thor::Actions

      def initialize(args = ARGV, local_options = {}, config = {})
        super
        @ui = Sxn::UI::Output.new
        @prompt = Sxn::UI::Prompt.new
        @table = Sxn::UI::Table.new
        @config_manager = Sxn::Core::ConfigManager.new
        @project_manager = Sxn::Core::ProjectManager.new(@config_manager)
        @session_manager = Sxn::Core::SessionManager.new(@config_manager)
        @worktree_manager = Sxn::Core::WorktreeManager.new(@config_manager, @session_manager)
      end

      desc "add PROJECT [BRANCH]", "Add worktree to current session (defaults branch to session name)"
      long_desc <<-DESC
        Add a worktree for a project to the current session.

        Branch options:
        - No branch specified: Uses the session name as the branch name
        - Branch name: Creates or checks out the specified branch
        - remote:<branch>: Fetches and tracks the remote branch

        Examples:
        - sxn worktree add atlas-core
          Creates worktree with branch name matching current session

        - sxn worktree add atlas-core feature-branch
          Creates worktree with specified branch name

        - sxn worktree add atlas-core remote:origin/main
          Fetches and tracks the remote branch
      DESC
      option :session, type: :string, aliases: "-s", desc: "Target session (defaults to current)"
      option :apply_rules, type: :boolean, default: true, desc: "Apply project rules after creation"
      option :interactive, type: :boolean, aliases: "-i", desc: "Interactive mode"

      def add(project_name = nil, branch = nil)
        ensure_initialized!

        # Interactive selection if project not provided
        if options[:interactive] || project_name.nil?
          project_name = select_project("Select project for worktree:")
          return if project_name.nil?
        end

        # Interactive branch selection if not provided and interactive mode
        # Note: If branch is nil, WorktreeManager will use session name as default
        if options[:interactive] && branch.nil?
          session_name = options[:session] || @config_manager.current_session
          branch = @prompt.branch_name("Enter branch name:", default: session_name)
        end

        session_name = options[:session] || @config_manager.current_session
        unless session_name
          @ui.error("No active session")
          @ui.recovery_suggestion("Use 'sxn use <session>' or specify --session")
          exit(1)
        end

        begin
          @ui.progress_start("Creating worktree for #{project_name}")

          worktree = @worktree_manager.add_worktree(
            project_name,
            branch,
            session_name: session_name
          )

          @ui.progress_done
          @ui.success("Created worktree for #{project_name}")

          display_worktree_info(worktree)

          # Apply rules if requested
          apply_project_rules(project_name, session_name) if options[:apply_rules]
        rescue Sxn::Error => e
          @ui.progress_failed
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "remove PROJECT", "Remove worktree from current session"
      option :session, type: :string, aliases: "-s", desc: "Target session (defaults to current)"
      option :force, type: :boolean, aliases: "-f", desc: "Force removal even with uncommitted changes"

      def remove(project_name = nil)
        ensure_initialized!

        session_name = options[:session] || @config_manager.current_session
        unless session_name
          @ui.error("No active session")
          @ui.recovery_suggestion("Use 'sxn use <session>' or specify --session")
          exit(1)
        end

        # Interactive selection if project not provided
        if project_name.nil?
          worktrees = @worktree_manager.list_worktrees(session_name: session_name)
          if worktrees.empty?
            @ui.empty_state("No worktrees in current session")
            suggest_add_worktree
            return
          end

          choices = worktrees.map do |w|
            { name: "#{w[:project]} (#{w[:branch]})", value: w[:project] }
          end
          project_name = @prompt.select("Select worktree to remove:", choices)
        end

        # Check for uncommitted changes unless forced
        unless options[:force]
          worktree = @worktree_manager.get_worktree(project_name, session_name: session_name)
          if worktree && worktree[:status] != "clean" && !@prompt.ask_yes_no(
            "Worktree has uncommitted changes. Continue?", default: false
          )
            @ui.info("Cancelled")
            return
          end
        end

        unless @prompt.confirm_deletion(project_name, "worktree")
          @ui.info("Cancelled")
          return
        end

        begin
          @ui.progress_start("Removing worktree for #{project_name}")
          @worktree_manager.remove_worktree(project_name, session_name: session_name)
          @ui.progress_done
          @ui.success("Removed worktree for #{project_name}")
        rescue Sxn::Error => e
          @ui.progress_failed
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "list", "List worktrees in current session"
      option :session, type: :string, aliases: "-s", desc: "Target session (defaults to current)"
      option :validate, type: :boolean, aliases: "-v", desc: "Validate worktree status"
      option :all_sessions, type: :boolean, aliases: "-a", desc: "List worktrees from all sessions"

      def list
        ensure_initialized!

        if options[:all_sessions]
          list_all_worktrees
        else
          list_session_worktrees
        end
      end

      desc "validate PROJECT", "Validate a worktree"
      option :session, type: :string, aliases: "-s", desc: "Target session (defaults to current)"

      def validate(project_name = nil)
        ensure_initialized!

        session_name = options[:session] || @config_manager.current_session
        unless session_name
          @ui.error("No active session")
          exit(1)
        end

        # Interactive selection if project not provided
        if project_name.nil?
          worktrees = @worktree_manager.list_worktrees(session_name: session_name)
          if worktrees.empty?
            @ui.empty_state("No worktrees in current session")
            return
          end

          choices = worktrees.map do |w|
            { name: "#{w[:project]} (#{w[:branch]})", value: w[:project] }
          end
          project_name = @prompt.select("Select worktree to validate:", choices)
        end

        begin
          result = @worktree_manager.validate_worktree(project_name, session_name: session_name)

          @ui.section("Worktree Validation: #{project_name}")

          if result[:valid]
            @ui.success("Worktree is valid")
          else
            @ui.error("Worktree has issues:")
            result[:issues].each { |issue| @ui.list_item(issue) }
          end

          display_worktree_info(result[:worktree], detailed: true) if result[:worktree]
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "status", "Show status of all worktrees in current session"
      option :session, type: :string, aliases: "-s", desc: "Target session (defaults to current)"

      def status
        ensure_initialized!

        session_name = options[:session] || @config_manager.current_session
        unless session_name
          @ui.error("No active session")
          exit(1)
        end

        begin
          worktrees = @worktree_manager.list_worktrees(session_name: session_name)

          @ui.section("Worktree Status - Session: #{session_name}")

          if worktrees.empty?
            @ui.empty_state("No worktrees in current session")
            suggest_add_worktree
          else
            display_worktree_status(worktrees)
          end
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

      def select_project(message)
        projects = @project_manager.list_projects
        if projects.empty?
          @ui.empty_state("No projects configured")
          @ui.recovery_suggestion("Add projects with 'sxn projects add <name> <path>'")
          return nil
        end

        choices = projects.map do |p|
          { name: "#{p[:name]} (#{p[:type]}) - #{p[:path]}", value: p[:name] }
        end
        @prompt.select(message, choices)
      end

      def list_session_worktrees
        session_name = options[:session] || @config_manager.current_session
        unless session_name
          @ui.error("No active session")
          @ui.recovery_suggestion("Use 'sxn use <session>' or specify --session")
          exit(1)
        end

        begin
          worktrees = @worktree_manager.list_worktrees(session_name: session_name)

          @ui.section("Worktrees - Session: #{session_name}")

          if worktrees.empty?
            @ui.empty_state("No worktrees in current session")
            suggest_add_worktree
          elsif options[:validate]
            list_with_validation(worktrees, session_name)
          else
            @table.worktrees(worktrees)
            @ui.newline
            @ui.info("Total: #{worktrees.size} worktrees")
          end
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      def list_all_worktrees
        sessions = @session_manager.list_sessions(status: "active")

        @ui.section("All Worktrees")

        if sessions.empty?
          @ui.empty_state("No active sessions")
          return
        end

        sessions.each do |session|
          worktrees = @worktree_manager.list_worktrees(session_name: session[:name])
          next if worktrees.empty?

          @ui.subsection("Session: #{session[:name]}")
          @table.worktrees(worktrees)
          @ui.newline
        end
      rescue Sxn::Error => e
        @ui.error(e.message)
        exit(e.exit_code)
      end

      def list_with_validation(worktrees, session_name)
        @ui.subsection("Worktree Validation")

        Sxn::UI::ProgressBar.with_progress("Validating worktrees", worktrees) do |worktree, progress|
          validation = @worktree_manager.validate_worktree(
            worktree[:project],
            session_name: session_name
          )

          status = validation[:valid] ? "✅" : "❌"
          progress.log("#{status} #{worktree[:project]}")

          unless validation[:valid]
            validation[:issues].each do |issue|
              progress.log("   - #{issue}")
            end
          end

          validation
        end

        @ui.newline
        @table.worktrees(worktrees)
      end

      def display_worktree_info(worktree, detailed: false)
        @ui.newline
        @ui.key_value("Project", worktree[:project])
        @ui.key_value("Branch", worktree[:branch])
        @ui.key_value("Path", worktree[:path])
        @ui.key_value("Session", worktree[:session]) if worktree[:session]

        if detailed
          @ui.key_value("Created", worktree[:created_at]) if worktree[:created_at]
          @ui.key_value("Exists", worktree[:exists] ? "Yes" : "No")
          @ui.key_value("Status", worktree[:status]) if worktree[:status]
        end

        @ui.newline
        display_worktree_commands(worktree)
      end

      def display_worktree_commands(worktree)
        @ui.subsection("Available Commands")

        @ui.command_example(
          "cd #{worktree[:path]}",
          "Navigate to worktree directory"
        )

        if worktree[:project]
          @ui.command_example(
            "sxn rules apply #{worktree[:project]}",
            "Apply project rules to this worktree"
          )
        end

        @ui.command_example(
          "sxn worktree validate #{worktree[:project]}",
          "Validate this worktree"
        )
      end

      def display_worktree_status(worktrees)
        clean_count = worktrees.count { |w| w[:status] == "clean" }
        modified_count = worktrees.count { |w| w[:status] == "modified" }
        missing_count = worktrees.count { |w| !w[:exists] }

        @table.worktrees(worktrees)
        @ui.newline

        @ui.info("Summary:")
        @ui.key_value("  Clean", clean_count, indent: 2)
        @ui.key_value("  Modified", modified_count, indent: 2) if modified_count.positive?
        @ui.key_value("  Missing", missing_count, indent: 2) if missing_count.positive?
        @ui.key_value("  Total", worktrees.size, indent: 2)

        if modified_count.positive?
          @ui.newline
          @ui.warning("#{modified_count} worktrees have uncommitted changes")
        end

        return unless missing_count.positive?

        @ui.newline
        @ui.error("#{missing_count} worktrees are missing from filesystem")
      end

      def apply_project_rules(project_name, session_name)
        rules_manager = Sxn::Core::RulesManager.new(@config_manager, @project_manager)

        begin
          @ui.newline
          @ui.subsection("Applying Project Rules")

          @ui.progress_start("Applying rules for #{project_name}")
          results = rules_manager.apply_rules(project_name, session_name)
          @ui.progress_done

          if results[:success]
            @ui.success("Applied #{results[:applied_count]} rules successfully")
          else
            @ui.warning("Some rules failed to apply")
            results[:errors].each { |error| @ui.error("  #{error}") }
          end
        rescue StandardError => e
          @ui.warning("Could not apply rules: #{e.message}")
          @ui.recovery_suggestion("Apply rules manually with 'sxn rules apply #{project_name}'")
        end
      end

      def suggest_add_worktree
        current_session = @config_manager.current_session
        @ui.newline
        if current_session
          @ui.recovery_suggestion("Add worktrees with 'sxn worktree add <project> [branch]'")
        else
          @ui.recovery_suggestion("Create and activate a session first with 'sxn add <session>'")
        end
      end
    end
  end
end
