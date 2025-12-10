# frozen_string_literal: true

require "yaml"
require "pathname"

module Sxn
  module Config
    # Handles loading and saving session templates from .sxn/templates.yml
    #
    # Templates define collections of projects (worktree configurations)
    # that can be applied when creating a session.
    class TemplatesConfig
      TEMPLATES_FILE = "templates.yml"

      attr_reader :sxn_path, :templates_file_path

      def initialize(sxn_path)
        @sxn_path = Pathname.new(sxn_path)
        @templates_file_path = @sxn_path / TEMPLATES_FILE
      end

      # Load templates configuration from file
      # @return [Hash] Templates configuration
      def load
        return default_config unless templates_file_path.exist?

        content = File.read(templates_file_path)
        config = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
        normalize_config(config)
      rescue Psych::SyntaxError => e
        raise ConfigurationError, "Invalid YAML in #{templates_file_path}: #{e.message}"
      rescue StandardError => e
        raise ConfigurationError, "Failed to load templates file #{templates_file_path}: #{e.message}"
      end

      # Save templates configuration to file
      # @param config [Hash] Templates configuration
      def save(config)
        ensure_directory_exists!

        # Ensure version is set
        config["version"] ||= 1
        config["templates"] ||= {}

        File.write(templates_file_path, YAML.dump(stringify_keys(config)))
      end

      # Check if templates file exists
      # @return [Boolean]
      def exists?
        templates_file_path.exist?
      end

      # Get a specific template by name
      # @param name [String] Template name
      # @return [Hash, nil] Template configuration or nil if not found
      def get_template(name)
        config = load
        templates = config["templates"] || {}
        template = templates[name]

        return nil unless template

        # Normalize project entries to hashes
        normalize_template(name, template)
      end

      # List all template names
      # @return [Array<String>] Template names
      def list_template_names
        config = load
        (config["templates"] || {}).keys
      end

      # Add or update a template
      # @param name [String] Template name
      # @param template [Hash] Template configuration
      def set_template(name, template)
        config = load
        config["templates"] ||= {}
        config["templates"][name] = template
        save(config)
      end

      # Remove a template
      # @param name [String] Template name
      # @return [Boolean] True if template was removed
      def remove_template(name)
        config = load
        templates = config["templates"] || {}

        return false unless templates.key?(name)

        templates.delete(name)
        save(config)
        true
      end

      private

      def default_config
        {
          "version" => 1,
          "templates" => {}
        }
      end

      def normalize_config(config)
        config["version"] ||= 1
        config["templates"] ||= {}
        config
      end

      def normalize_template(name, template)
        {
          "name" => name,
          "description" => template["description"],
          "projects" => normalize_projects(template["projects"] || [])
        }
      end

      def normalize_projects(projects)
        projects.map do |project|
          if project.is_a?(String)
            { "name" => project }
          elsif project.is_a?(Hash)
            # Ensure name key exists
            project["name"] ||= project[:name]
            stringify_keys(project)
          else
            { "name" => project.to_s }
          end
        end
      end

      def stringify_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_s).transform_values do |value|
          case value
          when Hash then stringify_keys(value)
          when Array then value.map { |v| v.is_a?(Hash) ? stringify_keys(v) : v }
          else value
          end
        end
      end

      def ensure_directory_exists!
        FileUtils.mkdir_p(sxn_path) unless sxn_path.exist?
      end
    end
  end
end
