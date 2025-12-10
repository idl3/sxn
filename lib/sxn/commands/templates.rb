# frozen_string_literal: true

require "thor"

module Sxn
  module Commands
    # Manage session templates
    class Templates < Thor
      include Thor::Actions

      def initialize(args = ARGV, local_options = {}, config = {})
        super
        @ui = Sxn::UI::Output.new
        @prompt = Sxn::UI::Prompt.new
        @table = Sxn::UI::Table.new
        @config_manager = Sxn::Core::ConfigManager.new
        @template_manager = Sxn::Core::TemplateManager.new(@config_manager)
        @project_manager = Sxn::Core::ProjectManager.new(@config_manager)
      end

      desc "list", "List available session templates"

      def list
        ensure_initialized!

        templates = @template_manager.list_templates

        @ui.section("Session Templates")

        if templates.empty?
          @ui.empty_state("No templates defined")
          @ui.newline
          @ui.recovery_suggestion("Create a template with 'sxn templates create'")
          @ui.recovery_suggestion("Or manually edit .sxn/templates.yml")
        else
          display_templates_table(templates)
          @ui.newline
          @ui.info("Total: #{templates.size} template(s)")
        end
      rescue Sxn::Error => e
        @ui.error(e.message)
        exit(e.exit_code)
      end

      desc "show NAME", "Show details of a session template"

      def show(name)
        ensure_initialized!

        template = @template_manager.get_template(name)

        @ui.section("Template: #{name}")
        @ui.key_value("Description", template["description"] || "(none)")
        @ui.key_value("Projects", (template["projects"] || []).size.to_s)

        @ui.newline
        @ui.subsection("Projects")

        projects = template["projects"] || []
        if projects.empty?
          @ui.empty_state("No projects in this template")
        else
          projects.each do |project_config|
            project_name = project_config["name"]
            project = @project_manager.get_project(project_name)
            status = project ? "✓" : "✗ (not found)"

            details = []
            details << "branch: #{project_config["branch"]}" if project_config["branch"]
            details << "has custom rules" if project_config["rules"]

            if details.any?
              @ui.list_item("#{project_name} #{status} (#{details.join(", ")})")
            else
              @ui.list_item("#{project_name} #{status}")
            end
          end
        end

        @ui.newline
        @ui.subsection("Usage")
        @ui.command_example(
          "sxn add my-session -t #{name} -b my-branch",
          "Create session with this template"
        )
      rescue Sxn::SessionTemplateNotFoundError => e
        @ui.error(e.message)
        exit(1)
      rescue Sxn::Error => e
        @ui.error(e.message)
        exit(e.exit_code)
      end

      desc "create", "Create a new session template"
      option :name, type: :string, aliases: "-n", desc: "Template name"
      option :description, type: :string, aliases: "-d", desc: "Template description"

      def create
        ensure_initialized!

        # Get template name
        name = options[:name]
        if name.nil?
          name = @prompt.ask("Template name:")
          if name.nil? || name.strip.empty?
            @ui.error("Template name is required")
            exit(1)
          end
        end

        # Check if template already exists
        if @template_manager.template_exists?(name)
          @ui.error("Template '#{name}' already exists")
          @ui.recovery_suggestion("Use a different name or remove existing template with 'sxn templates remove #{name}'")
          exit(1)
        end

        # Get description
        description = options[:description]
        description ||= @prompt.ask("Description (optional):")

        # Select projects
        projects = @project_manager.list_projects
        if projects.empty?
          @ui.error("No projects configured")
          @ui.recovery_suggestion("Add projects with 'sxn projects add <name> <path>' first")
          exit(1)
        end

        @ui.newline
        @ui.info("Select projects to include in the template:")
        @ui.info("(Use space to select, enter to confirm)")
        @ui.newline

        project_choices = projects.map do |p|
          { name: "#{p[:name]} (#{p[:type] || "unknown"})", value: p[:name] }
        end

        selected_projects = @prompt.multi_select("Projects:", project_choices)

        if selected_projects.empty?
          @ui.error("At least one project must be selected")
          exit(1)
        end

        # Create the template
        @ui.progress_start("Creating template '#{name}'")

        @template_manager.create_template(
          name,
          description: description,
          projects: selected_projects
        )

        @ui.progress_done
        @ui.success("Template '#{name}' created with #{selected_projects.size} project(s)")

        @ui.newline
        @ui.subsection("Usage")
        @ui.command_example(
          "sxn add my-session -t #{name} -b my-branch",
          "Create session with this template"
        )
      rescue Sxn::SessionTemplateValidationError => e
        @ui.progress_failed
        @ui.error(e.message)
        exit(1)
      rescue Sxn::Error => e
        @ui.progress_failed
        @ui.error(e.message)
        exit(e.exit_code)
      end

      desc "remove NAME", "Remove a session template"
      option :force, type: :boolean, aliases: "-f", desc: "Skip confirmation"

      def remove(name = nil)
        ensure_initialized!

        # Interactive selection if name not provided
        if name.nil?
          templates = @template_manager.list_templates
          if templates.empty?
            @ui.empty_state("No templates to remove")
            return
          end

          choices = templates.map { |t| { name: "#{t[:name]} - #{t[:description] || "(no description)"}", value: t[:name] } }
          name = @prompt.select("Select template to remove:", choices)
        end

        # Verify template exists
        @template_manager.get_template(name)

        # Confirm deletion unless force flag is used
        return if !options[:force] && !@prompt.confirm_deletion(name, "template")

        @ui.progress_start("Removing template '#{name}'")
        @template_manager.remove_template(name)
        @ui.progress_done
        @ui.success("Template '#{name}' removed")
      rescue Sxn::SessionTemplateNotFoundError => e
        @ui.error(e.message)
        exit(1)
      rescue Sxn::Error => e
        @ui.progress_failed
        @ui.error(e.message)
        exit(e.exit_code)
      end

      private

      def ensure_initialized!
        return if @config_manager.initialized?

        @ui.error("Project not initialized")
        @ui.recovery_suggestion("Run 'sxn init' to initialize sxn in this project")
        exit(1)
      end

      def display_templates_table(templates)
        @table.templates(templates)
      end
    end
  end
end
