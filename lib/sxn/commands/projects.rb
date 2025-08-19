# frozen_string_literal: true

require "thor"

module Sxn
  module Commands
    # Manage project configurations
    class Projects < Thor
      include Thor::Actions

      def initialize(args = ARGV, local_options = {}, config = {})
        super
        @ui = Sxn::UI::Output.new
        @prompt = Sxn::UI::Prompt.new
        @table = Sxn::UI::Table.new
        @config_manager = Sxn::Core::ConfigManager.new
        @project_manager = Sxn::Core::ProjectManager.new(@config_manager)
      end

      desc "add NAME PATH", "Add a project"
      option :type, type: :string, desc: "Project type (rails, javascript, etc.)"
      option :default_branch, type: :string, desc: "Default branch name"
      option :interactive, type: :boolean, aliases: "-i", desc: "Interactive mode"

      def add(name = nil, path = nil)
        ensure_initialized!

        # Interactive mode
        if options[:interactive] || name.nil? || path.nil?
          name ||= @prompt.project_name
          path ||= @prompt.project_path
        end

        begin
          @ui.progress_start("Adding project '#{name}'")

          project = @project_manager.add_project(
            name,
            path,
            type: options[:type],
            default_branch: options[:default_branch]
          )

          @ui.progress_done
          @ui.success("Added project '#{name}'")

          display_project_info(project)
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

      desc "remove NAME", "Remove a project"
      option :force, type: :boolean, aliases: "-f", desc: "Force removal even if used in sessions"

      def remove(name = nil)
        ensure_initialized!

        # Interactive selection if name not provided
        if name.nil?
          projects = @project_manager.list_projects
          if projects.empty?
            @ui.empty_state("No projects configured")
            suggest_add_project
            return
          end

          choices = projects.map { |p| { name: "#{p[:name]} (#{p[:type]})", value: p[:name] } }
          name = @prompt.select("Select project to remove:", choices)
        end

        unless @prompt.confirm_deletion(name, "project")
          @ui.info("Cancelled")
          return
        end

        begin
          @ui.progress_start("Removing project '#{name}'")
          @project_manager.remove_project(name)
          @ui.progress_done
          @ui.success("Removed project '#{name}'")
        rescue Sxn::ProjectInUseError => e
          @ui.progress_failed
          @ui.error(e.message)
          @ui.recovery_suggestion("Archive or remove the sessions first, or use --force")
          exit(e.exit_code)
        rescue Sxn::Error => e
          @ui.progress_failed
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "list", "List all projects"
      option :validate, type: :boolean, aliases: "-v", desc: "Validate project paths"

      def list
        ensure_initialized!

        begin
          projects = @project_manager.list_projects

          @ui.section("Registered Projects")

          if projects.empty?
            @ui.empty_state("No projects configured")
            suggest_add_project
          elsif options[:validate]
            list_with_validation(projects)
          else
            @table.projects(projects)
            @ui.newline
            @ui.info("Total: #{projects.size} projects")
          end
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "scan [PATH]", "Scan for projects and optionally register them"
      option :register, type: :boolean, aliases: "-r", desc: "Automatically register detected projects"
      option :interactive, type: :boolean, aliases: "-i", default: true, desc: "Prompt before registering"

      def scan(base_path = nil)
        ensure_initialized!

        base_path ||= Dir.pwd

        begin
          @ui.progress_start("Scanning for projects in #{base_path}")
          detected = @project_manager.scan_projects(base_path)
          @ui.progress_done

          @ui.section("Detected Projects")

          if detected.empty?
            @ui.empty_state("No projects detected")
            return
          end

          display_detected_projects(detected)

          if options[:register]
            register_projects(detected)
          elsif options[:interactive]
            register_projects(detected) if @prompt.ask_yes_no("Register detected projects?", default: true)
          else
            @ui.info("Use --register to add these projects automatically")
          end
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "validate NAME", "Validate a project configuration"
      def validate(name = nil)
        ensure_initialized!

        if name.nil?
          projects = @project_manager.list_projects
          if projects.empty?
            @ui.empty_state("No projects configured")
            return
          end

          choices = projects.map { |p| { name: "#{p[:name]} (#{p[:type]})", value: p[:name] } }
          name = @prompt.select("Select project to validate:", choices)
        end

        begin
          result = @project_manager.validate_project(name)

          @ui.section("Project Validation: #{name}")

          if result[:valid]
            @ui.success("Project is valid")
          else
            @ui.error("Project has issues:")
            result[:issues].each { |issue| @ui.list_item(issue) }
          end

          display_project_info(result[:project])
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "info NAME", "Show detailed project information"
      def info(name = nil)
        ensure_initialized!

        if name.nil?
          projects = @project_manager.list_projects
          if projects.empty?
            @ui.empty_state("No projects configured")
            return
          end

          choices = projects.map { |p| { name: "#{p[:name]} (#{p[:type]})", value: p[:name] } }
          name = @prompt.select("Select project:", choices)
        end

        begin
          project = @project_manager.get_project(name)
          raise Sxn::ProjectNotFoundError, "Project '#{name}' not found" unless project

          @ui.section("Project Information: #{name}")
          display_project_info(project, detailed: true)

          # Show rules
          rules_manager = Sxn::Core::RulesManager.new(@config_manager, @project_manager)
          begin
            rules = rules_manager.list_rules(name)
            if rules.any?
              @ui.subsection("Rules")
              @table.rules(rules, name)
            else
              @ui.info("No rules configured for this project")
            end
          rescue StandardError => e
            @ui.debug("Could not load rules: #{e.message}")
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

      def display_project_info(project, detailed: false)
        @ui.newline
        @ui.key_value("Name", project[:name])
        @ui.key_value("Type", project[:type] || "unknown")
        @ui.key_value("Path", project[:path])
        @ui.key_value("Default Branch", project[:default_branch] || "master")

        if detailed
          # Additional validation info
          validation = @project_manager.validate_project(project[:name])
          status = validation[:valid] ? "✅ Valid" : "❌ Invalid"
          @ui.key_value("Status", status)

          unless validation[:valid]
            @ui.subsection("Issues")
            validation[:issues].each { |issue| @ui.list_item(issue) }
          end
        end

        @ui.newline
        display_project_commands(project[:name])
      end

      def display_project_commands(project_name)
        @ui.subsection("Available Commands")

        @ui.command_example(
          "sxn worktree add #{project_name} [branch]",
          "Create worktree for this project"
        )

        @ui.command_example(
          "sxn rules add #{project_name} <type> <config>",
          "Add setup rules for this project"
        )

        @ui.command_example(
          "sxn projects validate #{project_name}",
          "Validate project configuration"
        )
      end

      def display_detected_projects(projects)
        projects.each do |project|
          @ui.list_item("#{project[:name]} (#{project[:type]})", project[:path])
        end
        @ui.newline
        @ui.info("Total: #{projects.size} projects detected")
      end

      def register_projects(projects)
        return if projects.empty?

        @ui.subsection("Registering Projects")

        results = @project_manager.auto_register_projects(projects)

        success_count = results.count { |r| r[:status] == :success }
        error_count = results.count { |r| r[:status] == :error }

        results.each do |result|
          if result[:status] == :success
            @ui.success("✅ #{result[:project][:name]}")
          else
            @ui.error("❌ #{result[:project][:name]}: #{result[:error]}")
          end
        end

        @ui.newline
        @ui.info("Registered #{success_count} projects successfully")
        @ui.warning("#{error_count} projects failed") if error_count.positive?
      end

      def list_with_validation(projects)
        @ui.subsection("Project Validation")

        Sxn::UI::ProgressBar.with_progress("Validating projects", projects) do |project, progress|
          validation = @project_manager.validate_project(project[:name])

          status = validation[:valid] ? "✅" : "❌"
          progress.log("#{status} #{project[:name]}")

          unless validation[:valid]
            validation[:issues].each do |issue|
              progress.log("   - #{issue}")
            end
          end

          validation
        end

        @ui.newline
        @table.projects(projects)
      end

      def suggest_add_project
        @ui.newline
        @ui.recovery_suggestion("Add projects with 'sxn projects add <name> <path>' or scan with 'sxn projects scan'")
      end
    end
  end
end
