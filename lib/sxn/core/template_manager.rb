# frozen_string_literal: true

require_relative "../config/templates_config"

module Sxn
  module Core
    # Manages session templates - collections of projects that can be
    # applied when creating a session to automatically create multiple worktrees.
    class TemplateManager
      attr_reader :config_manager, :templates_config

      def initialize(config_manager)
        @config_manager = config_manager
        @templates_config = Config::TemplatesConfig.new(config_manager.sxn_folder_path)
      end

      # List all available templates
      # @return [Array<Hash>] Array of template info hashes
      def list_templates
        config = templates_config.load
        templates = config["templates"] || {}

        templates.map do |name, template|
          {
            name: name,
            description: template["description"],
            project_count: (template["projects"] || []).size
          }
        end
      end

      # Get a specific template by name
      # @param name [String] Template name
      # @return [Hash] Template configuration
      # @raise [SessionTemplateNotFoundError] If template not found
      def get_template(name)
        template = templates_config.get_template(name)

        unless template
          available = list_template_names
          raise SessionTemplateNotFoundError.new(name, available: available)
        end

        template
      end

      # Get list of template names
      # @return [Array<String>] Template names
      def list_template_names
        templates_config.list_template_names
      end

      # Validate a template before use
      # @param name [String] Template name
      # @raise [SessionTemplateValidationError] If template is invalid
      # @raise [SessionTemplateNotFoundError] If template not found
      def validate_template(name)
        template = get_template(name)
        projects = template["projects"] || []
        errors = []

        errors << "Template has no projects defined" if projects.empty?

        # Validate each project exists in config
        projects.each do |project_config|
          project_name = project_config["name"]
          project = config_manager.get_project(project_name)

          errors << "Project '#{project_name}' not found in configuration" unless project
        end

        raise SessionTemplateValidationError.new(name, errors.join("; ")) if errors.any?

        true
      end

      # Create a new template
      # @param name [String] Template name
      # @param description [String] Template description
      # @param projects [Array<String>] Array of project names
      # @return [Hash] Created template
      def create_template(name, description: nil, projects: [])
        validate_template_name!(name)

        raise SessionTemplateValidationError.new(name, "Template already exists") if template_exists?(name)

        # Validate all projects exist
        projects.each do |project_name|
          project = config_manager.get_project(project_name)
          raise SessionTemplateValidationError.new(name, "Project '#{project_name}' not found") unless project
        end

        template = {
          "description" => description,
          "projects" => projects.map { |p| { "name" => p } }
        }

        templates_config.set_template(name, template)

        get_template(name)
      end

      # Update an existing template
      # @param name [String] Template name
      # @param description [String, nil] New description
      # @param projects [Array<String>, nil] New project list
      # @return [Hash] Updated template
      def update_template(name, description: nil, projects: nil)
        template = get_template(name)

        # Update description if provided
        template["description"] = description if description

        # Update projects if provided
        if projects
          # Validate all projects exist
          projects.each do |project_name|
            project = config_manager.get_project(project_name)
            raise SessionTemplateValidationError.new(name, "Project '#{project_name}' not found") unless project
          end

          template["projects"] = projects.map { |p| { "name" => p } }
        end

        # Save back to config
        config = templates_config.load
        config["templates"] ||= {}
        config["templates"][name] = {
          "description" => template["description"],
          "projects" => template["projects"]
        }
        templates_config.save(config)

        get_template(name)
      end

      # Remove a template
      # @param name [String] Template name
      # @return [Boolean] True if removed
      def remove_template(name)
        # Verify template exists
        get_template(name)

        templates_config.remove_template(name)
      end

      # Check if a template exists
      # @param name [String] Template name
      # @return [Boolean]
      def template_exists?(name)
        templates_config.get_template(name) != nil
      end

      # Get project configurations for a template with branch resolution
      # @param name [String] Template name
      # @param default_branch [String] Default branch to use if not specified per-project
      # @return [Array<Hash>] Array of project configs with resolved branches
      def get_template_projects(name, default_branch:)
        template = get_template(name)
        projects = template["projects"] || []

        projects.map do |project_config|
          project_name = project_config["name"]
          project = config_manager.get_project(project_name)

          {
            name: project_name,
            path: project[:path],
            branch: project_config["branch"] || default_branch,
            rules: project_config["rules"]
          }
        end
      end

      private

      def validate_template_name!(name)
        return if name.match?(/\A[a-zA-Z0-9_-]+\z/)

        raise SessionTemplateValidationError.new(
          name,
          "Template name must contain only letters, numbers, hyphens, and underscores"
        )
      end
    end
  end
end
