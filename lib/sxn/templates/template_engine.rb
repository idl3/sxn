# frozen_string_literal: true

require_relative "template_processor"
require_relative "template_variables"
require_relative "template_security"
require_relative "errors"
require_relative "../runtime_validations"

# Add support for hash deep merging if not available
# :nocov: - SimpleCov cannot track coverage for conditional class definitions at load time
unless Hash.method_defined?(:deep_merge)
  class Hash
    def deep_merge(other_hash)
      merge(other_hash) do |_key, oldval, newval|
        if oldval.is_a?(Hash) && newval.is_a?(Hash)
          oldval.deep_merge(newval)
        else
          newval
        end
      end
    end
  end
end
# :nocov:

module Sxn
  module Templates
    # TemplateEngine is the main interface for template processing in sxn.
    # It combines template processing, variable collection, and security validation
    # to provide a safe and convenient API for generating files from templates.
    #
    # Features:
    # - Built-in template discovery
    # - Automatic variable collection
    # - Security validation
    # - Template caching
    # - Multiple template formats support
    #
    # Example:
    #   engine = TemplateEngine.new(session: session, project: project)
    #   engine.process_template("rails/CLAUDE.md", "/path/to/output.md")
    class TemplateEngine
      # Built-in template directory
      TEMPLATES_DIR = File.expand_path("../templates", __dir__)

      def initialize(session: nil, project: nil, config: nil)
        @session = session
        @project = project
        @config = config

        @processor = TemplateProcessor.new
        @variables_collector = TemplateVariables.new(session, project, config)
        @security = TemplateSecurity.new
        @template_cache = {}
      end

      # Process a template and write it to the specified destination
      #
      # @param template_name [String] Name/path of the template (e.g., "rails/CLAUDE.md")
      # @param destination_path [String] Where to write the processed template
      # @param custom_variables [Hash] Additional variables to merge
      # @param options [Hash] Processing options
      # @option options [Boolean] :force (false) Overwrite existing files
      # @option options [Boolean] :validate (true) Validate template security
      # @option options [String] :template_dir Custom template directory
      # @return [String] Path to the created file
      def process_template(template_name, destination_path, custom_variables = {}, options = {})
        options = { force: false, validate: true, template_dir: nil }.merge(options)

        # Find the template file
        template_path = find_template(template_name, options[:template_dir])

        # Check if destination exists and handle accordingly
        destination = Pathname.new(destination_path)
        if destination.exist? && !options[:force]
          raise Errors::TemplateError,
                "Destination file already exists: #{destination_path}. Use force: true to overwrite."
        end

        # steep:ignore:start - Template processing uses dynamic variable resolution
        # Liquid template processing and variable collection use dynamic features
        # that cannot be statically typed. Runtime validation provides safety.

        # Collect variables
        variables = collect_variables(custom_variables)

        # Runtime validation of template variables
        variables = RuntimeValidations.validate_template_variables(variables)

        # Validate template security if requested
        if options[:validate]
          template_content = File.read(template_path)
          @security.validate_template(template_content, variables)
        end

        # Process the template with runtime validation
        result = @processor.process_file(template_path, variables, options)

        # Create destination directory if it doesn't exist
        destination.dirname.mkpath

        # Write the result
        destination.write(result)

        destination_path
      rescue Errors::TemplateSecurityError
        # Re-raise security errors without wrapping
        raise
      rescue StandardError => e
        raise Errors::TemplateProcessingError,
              "Failed to process template '#{template_name}': #{e.message}"
      end

      # List available built-in templates
      #
      # @param category [String] Optional category filter (rails, javascript, common)
      # @return [Array<String>] List of available template names
      def list_templates(category = nil)
        templates_dir = category ? File.join(TEMPLATES_DIR, category) : TEMPLATES_DIR
        return [] unless Dir.exist?(templates_dir)

        Dir.glob("**/*.liquid", base: templates_dir).map do |path|
          category ? File.join(category, path) : path
        end.sort
      end

      # Get template categories
      #
      # @return [Array<String>] List of template categories
      def template_categories
        return [] unless Dir.exist?(TEMPLATES_DIR)

        Dir.entries(TEMPLATES_DIR)
           .select { |entry| File.directory?(File.join(TEMPLATES_DIR, entry)) }
           .reject { |entry| entry.start_with?(".") }
           .sort
      end

      # Check if a template exists
      #
      # @param template_name [String] Name of the template to check
      # @param template_dir [String] Optional custom template directory
      # @return [Boolean] true if template exists
      def template_exists?(template_name, template_dir = nil)
        find_template(template_name, template_dir)
        true
      rescue Errors::TemplateNotFoundError
        false
      end

      # Get template information
      #
      # @param template_name [String] Name of the template
      # @param template_dir [String] Optional custom template directory
      # @return [Hash] Template metadata
      def template_info(template_name, template_dir = nil)
        template_path = find_template(template_name, template_dir)
        template_content = File.read(template_path)

        {
          name: template_name,
          path: template_path,
          size: template_content.bytesize,
          variables: @processor.extract_variables(template_content),
          syntax_valid: validate_template_syntax(template_content)
        }
      rescue StandardError => e
        {
          name: template_name,
          error: e.message,
          syntax_valid: false
        }
      end

      # Validate template syntax without processing
      #
      # @param template_name [String] Name of the template
      # @param template_dir [String] Optional custom template directory
      # @return [Boolean] true if template syntax is valid
      def validate_template_syntax(template_name, template_dir = nil)
        # Better detection: if it contains Liquid syntax and no path separators, treat as content
        if template_name.is_a?(String) &&
           (template_name.include?("{{") || template_name.include?("{%")) &&
           !template_name.include?("/") && !template_name.end_with?(".liquid")
          # It's template content with Liquid syntax
          template_content = template_name
        elsif template_name.is_a?(String) && !template_name.include?("\n") &&
              (template_name.include?("/") || template_name.match?(/\.\w+$/) || !template_name.include?("{{"))
          # It's a template name/path
          template_path = find_template(template_name, template_dir)
          template_content = File.read(template_path)
        else
          # Default: treat as content for backward compatibility
          template_content = template_name
        end

        @processor.validate_syntax(template_content)
      rescue Errors::TemplateSyntaxError, Errors::TemplateNotFoundError
        false
      end

      # Get available variables for templates
      #
      # @param custom_variables [Hash] Additional variables to include
      # @return [Hash] All available variables
      def available_variables(custom_variables = {})
        collect_variables(custom_variables)
      end

      # Refresh variable cache (useful for long-running processes)
      def refresh_variables!
        @variables_collector.refresh!
      end

      # Clear template cache
      def clear_cache!
        @template_cache.clear
        @security.clear_cache!
      end

      # Process a template string directly (not from file)
      #
      # @param template_content [String] The template content
      # @param custom_variables [Hash] Variables to use
      # @param options [Hash] Processing options
      # @return [String] Processed template
      def process_string(template_content, custom_variables = {}, options = {})
        options = { validate: true }.merge(options)

        variables = collect_variables(custom_variables)

        @security.validate_template(template_content, variables) if options[:validate]

        @processor.process(template_content, variables, options)
      end

      # Render a template with variables
      #
      # @param template_name [String] Name/path of the template
      # @param variables [Hash] Variables to use for rendering
      # @param options [Hash] Processing options
      # @return [String] Rendered template content
      def render_template(template_name, variables = {}, options = {})
        # Find the template file
        template_path = find_template(template_name, options[:template_dir])

        # Read template content
        template_content = File.read(template_path)

        # Merge with available variables
        all_variables = collect_variables(variables)

        # Validate template security if requested
        @security.validate_template(template_content, all_variables) if options.fetch(:validate, true)

        # Process and return the result
        @processor.process(template_content, all_variables, options)
      rescue Errors::TemplateSecurityError
        # Re-raise security errors without wrapping
        raise
      rescue StandardError => e
        raise Errors::TemplateProcessingError,
              "Failed to render template '#{template_name}': #{e.message}"
      end

      # Apply a set of templates to a directory
      #
      # @param template_set [String] Name of template set (rails, javascript, common)
      # @param destination_dir [String] Directory to apply templates to
      # @param custom_variables [Hash] Additional variables
      # @param options [Hash] Processing options
      # @return [Array<String>] List of created files
      def apply_template_set(template_set, destination_dir, custom_variables = {}, options = {})
        templates = list_templates(template_set)
        created_files = []

        templates.each do |template_name|
          # Determine output filename (remove .liquid extension)
          output_name = template_name.sub(/\.liquid$/, "")
          output_path = File.join(destination_dir, File.basename(output_name))

          begin
            process_template(template_name, output_path, custom_variables, options)
            created_files << output_path
          rescue StandardError => e
            # Log error but continue with other templates
            warn "Failed to process template #{template_name}: #{e.message}"
          end
        end

        created_files
      end

      private

      # Find a template file by name
      def find_template(template_name, custom_template_dir = nil)
        # Remove .liquid extension if present for search
        search_name = template_name.sub(/\.liquid$/, "")

        # Search locations in order of preference
        search_paths = []

        # 1. Custom template directory if provided
        if custom_template_dir
          search_paths << File.join(custom_template_dir, "#{search_name}.liquid")
          search_paths << File.join(custom_template_dir, search_name)
        end

        # 2. Built-in templates
        search_paths << File.join(TEMPLATES_DIR, "#{search_name}.liquid")
        search_paths << File.join(TEMPLATES_DIR, search_name)

        # 3. Try with explicit .liquid extension
        search_paths << File.join(TEMPLATES_DIR, template_name) if template_name.end_with?(".liquid")

        # Find first existing template
        found_path = search_paths.find { |path| File.exist?(path) }

        unless found_path
          available = list_templates.join(", ")
          raise Errors::TemplateNotFoundError,
                "Template '#{template_name}' not found. Available templates: #{available}"
        end

        found_path
      end

      # Collect all variables for template processing
      def collect_variables(custom_variables = {})
        # Get base variables from collector
        base_variables = @variables_collector.collect

        # Add sxn-specific variables
        sxn_variables = {
          sxn: {
            version: Sxn::VERSION,
            template_engine: "liquid",
            generated_at: Time.now.iso8601
          }
        }

        # Merge all variables (custom takes precedence)
        base_variables.deep_merge(sxn_variables).deep_merge(custom_variables)
      end
    end
  end
end
