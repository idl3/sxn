# frozen_string_literal: true

require_relative "base_rule"
require_relative "errors"
require_relative "../templates/template_processor"

module Sxn
  module Rules
    # TemplateRule processes and applies template files using the secure template processor.
    # It supports variable substitution, multiple template engines, and safe file generation.
    #
    # Configuration format:
    # {
    #   "templates" => [
    #     {
    #       "source" => ".sxn/templates/session-info.md.liquid",
    #       "destination" => "README.md",
    #       "variables" => { "custom_var" => "value" },
    #       "engine" => "liquid",
    #       "required" => true,
    #       "overwrite" => false
    #     }
    #   ]
    # }
    #
    # @example Basic usage
    #   rule = TemplateRule.new(
    #     "generate_docs",
    #     {
    #       "templates" => [
    #         {
    #           "source" => ".sxn/templates/CLAUDE.md.liquid",
    #           "destination" => "CLAUDE.md"
    #         }
    #       ]
    #     },
    #     "/path/to/project",
    #     "/path/to/session"
    #   )
    #   rule.validate
    #   rule.apply
    #
    class TemplateRule < BaseRule
      # Supported template engines
      SUPPORTED_ENGINES = %w[liquid].freeze

      # Initialize the template rule
      def initialize(arg1 = nil, arg2 = nil, arg3 = nil, arg4 = nil, dependencies: [])
        super(arg1, arg2, arg3, arg4, dependencies: dependencies)
        @template_processor = Templates::TemplateProcessor.new
        @template_variables = Templates::TemplateVariables.new
      end

      # Validate the rule configuration
      def validate
        super
      end

      # Apply the template processing operations
      def apply
        change_state!(APPLYING)

        begin
          @config["templates"].each_with_index do |template_config, index|
            apply_template(template_config, index)
          end

          change_state!(APPLIED)
          log(:info, "Successfully processed #{@config["templates"].size} templates")
          true
        rescue StandardError => e
          @errors << e
          change_state!(FAILED)
          raise ApplicationError, "Failed to process templates: #{e.message}"
        end
      end

      protected

      # Validate rule-specific configuration
      def validate_rule_specific!
        raise ValidationError, "TemplateRule requires 'templates' configuration" unless @config.key?("templates")

        raise ValidationError, "TemplateRule 'templates' must be an array" unless @config["templates"].is_a?(Array)

        raise ValidationError, "TemplateRule 'templates' cannot be empty" if @config["templates"].empty?

        @config["templates"].each_with_index do |template_config, index|
          validate_template_config!(template_config, index)
        end
      end

      private

      # Validate individual template configuration
      def validate_template_config!(template_config, index)
        raise ValidationError, "Template config #{index} must be a hash" unless template_config.is_a?(Hash)

        unless template_config.key?("source") && template_config["source"].is_a?(String)
          raise ValidationError, "Template config #{index} must have a 'source' string"
        end

        unless template_config.key?("destination") && template_config["destination"].is_a?(String)
          raise ValidationError, "Template config #{index} must have a 'destination' string"
        end

        # Validate engine
        if template_config.key?("engine")
          engine = template_config["engine"]
          unless SUPPORTED_ENGINES.include?(engine)
            raise ValidationError,
                  "Template config #{index} has unsupported engine '#{engine}'. Supported: #{SUPPORTED_ENGINES.join(", ")}"
          end
        end

        # Validate variables
        if template_config.key?("variables")
          variables = template_config["variables"]
          raise ValidationError, "Template config #{index} 'variables' must be a hash" unless variables.is_a?(Hash)
        end

        # Validate source template exists if required
        source_path = File.join(@project_path, template_config["source"])
        required = template_config.fetch("required", true)

        if required && !File.exist?(source_path)
          raise ValidationError, "Required template file does not exist: #{template_config["source"]}"
        end

        # Validate destination path is safe
        destination = template_config["destination"]
        return unless destination.include?("..") || destination.start_with?("/")

        raise ValidationError, "Template config #{index} destination path is not safe: #{destination}"
      end

      # Apply a single template operation
      def apply_template(template_config, _index)
        source = template_config["source"]
        destination = template_config["destination"]
        required = template_config.fetch("required", true)
        overwrite = template_config.fetch("overwrite", false)

        source_path = File.join(@project_path, source)
        destination_path = File.join(@session_path, destination)

        # Skip if source doesn't exist and is not required
        unless File.exist?(source_path)
          raise ApplicationError, "Required template file does not exist: #{source}" if required

          log(:debug, "Skipping optional missing template: #{source}")
          return

        end

        # Check if destination already exists
        if File.exist?(destination_path) && !overwrite
          log(:warn, "Destination file already exists, skipping: #{destination}")
          return
        end

        log(:debug, "Processing template: #{source} -> #{destination}")

        begin
          # Prepare template variables
          variables = build_template_variables(template_config)

          # Validate template syntax first
          template_content = File.read(source_path)
          @template_processor.validate_syntax(template_content)

          # Process the template
          processed_content = @template_processor.process(template_content, variables)

          # Create destination directory if needed
          destination_dir = File.dirname(destination_path)
          FileUtils.mkdir_p(destination_dir) unless File.directory?(destination_dir)

          # Create backup if file exists and we're overwriting
          backup_path = nil
          if File.exist?(destination_path) && overwrite
            backup_path = "#{destination_path}.backup.#{Time.now.to_i}"
            FileUtils.cp(destination_path, backup_path)
          end

          # Write processed content
          File.write(destination_path, processed_content)

          # Set appropriate permissions
          File.chmod(0o644, destination_path)

          track_change(:file_created, destination_path, {
                         source: source_path,
                         template: true,
                         backup_path: backup_path,
                         variables_used: extract_used_variables(template_content)
                       })

          log(:debug, "Template processed successfully", {
                source: source,
                destination: destination,
                size: processed_content.bytesize
              })
        rescue Templates::Errors::TemplateSyntaxError => e
          raise ApplicationError, "Template syntax error in #{source}: #{e.message}"
        rescue Templates::Errors::TemplateProcessingError => e
          raise ApplicationError, "Template processing error for #{source}: #{e.message}"
        rescue StandardError => e
          raise ApplicationError, "Failed to process template #{source}: #{e.message}"
        end
      end

      # Build variables hash for template processing
      def build_template_variables(template_config)
        # Start with system-generated variables
        variables = @template_variables.build_variables

        # Add any custom variables from configuration
        if template_config.key?("variables")
          custom_vars = template_config["variables"]
          variables = deep_merge(variables, custom_vars)
        end

        # Add template-specific metadata
        variables[:template] = {
          source: template_config["source"],
          destination: template_config["destination"],
          processed_at: Time.now.iso8601
        }

        variables
      end

      # Deep merge two hashes, with the second hash taking precedence
      # Handles mixed symbol/string keys by preserving both when merging
      def deep_merge(hash1, hash2)
        result = hash1.dup

        hash2.each do |key, value|
          # Check if there's an existing key with the same string representation
          existing_key = result.keys.find { |k| k.to_s == key.to_s }
          
          if existing_key && result[existing_key].is_a?(Hash) && value.is_a?(Hash)
            # Merge the hashes and set the new key (preserving the incoming key type)
            merged_value = deep_merge(result[existing_key], value)
            result.delete(existing_key) if existing_key != key  # Remove old key if different
            result[key] = merged_value
          else
            # For non-hash values or new keys, just set the value
            result.delete(existing_key) if existing_key && existing_key != key
            result[key] = value
          end
        end

        result
      end

      # Extract variable names used in a template
      def extract_used_variables(template_content)
        @template_processor.extract_variables(template_content)
      rescue StandardError => e
        log(:warn, "Could not extract variables from template: #{e.message}")
        []
      end

    end
  end
end
