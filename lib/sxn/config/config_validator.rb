# frozen_string_literal: true

require "json"
require_relative "../errors"

module Sxn
  module Config
    # Validates configuration structure and values
    #
    # Features:
    # - Schema validation for configuration structure
    # - Value validation with helpful error messages
    # - Support for configuration migrations from older versions
    # - Type checking and constraint validation
    class ConfigValidator
      # Current schema version
      CURRENT_VERSION = 1

      # Configuration schema definition
      SCHEMA = {
        "version" => {
          type: :integer,
          required: true,
          min: 1,
          max: CURRENT_VERSION
        },
        "sessions_folder" => {
          type: :string,
          required: true,
          min_length: 1
        },
        "current_session" => {
          type: :string,
          required: false
        },
        "projects" => {
          type: :hash,
          required: true,
          default: {},
          value_schema: {
            "path" => {
              type: :string,
              required: true,
              min_length: 1
            },
            "type" => {
              type: :string,
              required: false,
              allowed_values: %w[rails ruby javascript typescript react nextjs vue angular unknown]
            },
            "default_branch" => {
              type: :string,
              required: false,
              default: "main"
            },
            "package_manager" => {
              type: :string,
              required: false,
              allowed_values: %w[npm yarn pnpm]
            },
            "rules" => {
              type: :hash,
              required: false,
              default: {},
              value_schema: {
                "copy_files" => {
                  type: :array,
                  required: false,
                  item_schema: {
                    "source" => {
                      type: :string,
                      required: true,
                      min_length: 1
                    },
                    "strategy" => {
                      type: :string,
                      required: false,
                      default: "copy",
                      allowed_values: %w[copy symlink]
                    },
                    "permissions" => {
                      type: :integer,
                      required: false,
                      min: 0,
                      max: 0o777
                    },
                    "encrypt" => {
                      type: :boolean,
                      required: false,
                      default: false
                    }
                  }
                },
                "setup_commands" => {
                  type: :array,
                  required: false,
                  item_schema: {
                    "command" => {
                      type: :array,
                      required: true,
                      min_length: 1,
                      item_type: :string
                    },
                    "environment" => {
                      type: :hash,
                      required: false,
                      value_type: :string
                    },
                    "condition" => {
                      type: :string,
                      required: false,
                      allowed_values: %w[always db_not_exists file_not_exists]
                    }
                  }
                },
                "templates" => {
                  type: :array,
                  required: false,
                  item_schema: {
                    "source" => {
                      type: :string,
                      required: true,
                      min_length: 1
                    },
                    "destination" => {
                      type: :string,
                      required: true,
                      min_length: 1
                    },
                    "process" => {
                      type: :boolean,
                      required: false,
                      default: true
                    },
                    "engine" => {
                      type: :string,
                      required: false,
                      default: "liquid",
                      allowed_values: %w[liquid erb mustache]
                    }
                  }
                }
              }
            }
          }
        },
        "settings" => {
          type: :hash,
          required: false,
          default: {},
          value_schema: {
            "auto_cleanup" => {
              type: :boolean,
              required: false,
              default: true
            },
            "max_sessions" => {
              type: :integer,
              required: false,
              default: 10,
              min: 1,
              max: 100
            },
            "worktree_cleanup_days" => {
              type: :integer,
              required: false,
              default: 30,
              min: 1,
              max: 365
            },
            "default_rules" => {
              type: :hash,
              required: false,
              default: {},
              value_schema: {
                "templates" => {
                  type: :array,
                  required: false,
                  item_schema: {
                    "source" => {
                      type: :string,
                      required: true,
                      min_length: 1
                    },
                    "destination" => {
                      type: :string,
                      required: true,
                      min_length: 1
                    }
                  }
                }
              }
            }
          }
        }
      }.freeze

      attr_reader :errors

      def initialize
        @errors = []
      end

      # Validate configuration against schema
      # @param config [Hash] Configuration to validate
      # @return [Boolean] True if valid
      def valid?(config)
        @errors = []

        unless config.is_a?(Hash)
          @errors << "Configuration must be a hash, got #{config.class}"
          return false
        end

        validate_against_schema(config, SCHEMA, "")

        @errors.empty?
      end

      # Validate and migrate configuration if needed
      # @param config [Hash] Configuration to validate and migrate
      # @return [Hash] Validated and migrated configuration
      # @raise [ConfigurationError] If validation fails
      def validate_and_migrate(config)
        # First, migrate if needed
        migrated_config = migrate_config(config)

        # Debug output
        # puts "DEBUG: Original config: #{config.inspect}"
        # puts "DEBUG: Migrated config: #{migrated_config.inspect}"

        # Then validate the migrated config
        unless valid?(migrated_config)
          error_message = format_errors
          raise ConfigurationError, "Configuration validation failed:\n#{error_message}"
        end

        # Apply defaults for missing values
        apply_defaults(migrated_config)
      end

      # Get formatted error messages
      # @return [String] Formatted error messages
      def format_errors
        return "No errors" if @errors.empty?

        @errors.map.with_index(1) do |error, index|
          "  #{index}. #{error}"
        end.join("\n")
      end

      # Migrate configuration from older versions
      # @param config [Hash] Configuration to migrate
      # @return [Hash] Migrated configuration
      def migrate_config(config)
        return config unless config.is_a?(Hash)

        version = config["version"] || 0
        migrated_config = config.dup

        # Check if this is a v0 config that got merged with system defaults (version = 1)
        # but still has v0 structure (projects without paths)
        # Handle invalid version types safely
        needs_v0_migration = (version.is_a?(Integer) && version.zero?) || needs_v0_to_v1_migration?(config)

        case version
        when 0
          # Migrate from unversioned to version 1
          migrated_config = migrate_v0_to_v1(migrated_config)
        when 1
          if needs_v0_migration
            # This is a v0 config that was merged with v1 defaults, migrate it
            migrated_config = migrate_v0_to_v1(migrated_config)
          end
        end

        migrated_config
      end

      private

      # Check if config needs v0 to v1 migration based on structure
      # @param config [Hash] Configuration to check
      # @return [Boolean] True if needs migration
      def needs_v0_to_v1_migration?(config)
        return false unless config.is_a?(Hash)
        return false unless config["projects"].is_a?(Hash)

        # Check if any project is missing a path field (indicating v0 structure)
        config["projects"].any? do |_project_name, project_config|
          project_config.is_a?(Hash) &&
            (project_config["path"].nil? || project_config["path"].empty?)
        end
      end

      # Validate configuration against schema recursively
      # @param config [Hash] Configuration to validate
      # @param schema [Hash] Schema to validate against
      # @param path [String] Current path for error reporting
      def validate_against_schema(config, schema, path)
        schema.each do |key, field_schema|
          field_path = path.empty? ? key : "#{path}.#{key}"
          value = config[key]

          # Check required fields
          if field_schema[:required] && (value.nil? || (value.is_a?(String) && value.empty?))
            @errors << "Required field '#{field_path}' is missing or empty"
            next
          end

          # Skip validation if field is not present and not required
          next if value.nil? && !field_schema[:required]

          validate_field_type(value, field_schema, field_path)

          # Only validate constraints and nested schemas if type is correct
          if value_has_correct_type?(value, field_schema)
            validate_field_constraints(value, field_schema, field_path)
            validate_nested_schema(value, field_schema, field_path)
          end
        end
      end

      # Check if value has the correct type according to schema
      # @param value [Object] Value to check
      # @param schema [Hash] Field schema
      # @return [Boolean] True if value has correct type
      def value_has_correct_type?(value, schema)
        expected_type = schema[:type]
        return true unless expected_type

        case expected_type
        when :string
          value.is_a?(String)
        when :integer
          value.is_a?(Integer)
        when :boolean
          [true, false].include?(value)
        when :array
          value.is_a?(Array)
        when :hash
          value.is_a?(Hash)
        else
          false
        end
      end

      # Validate field type
      # @param value [Object] Value to validate
      # @param schema [Hash] Field schema
      # @param path [String] Field path for error reporting
      def validate_field_type(value, schema, path)
        expected_type = schema[:type]
        return unless expected_type

        return if value_has_correct_type?(value, schema)

        @errors << "Field '#{path}' must be of type #{expected_type}, got #{value.class.name.downcase}"
      end

      # Validate field constraints
      # @param value [Object] Value to validate
      # @param schema [Hash] Field schema
      # @param path [String] Field path for error reporting
      def validate_field_constraints(value, schema, path)
        # String constraints
        if value.is_a?(String)
          if schema[:min_length] && value.length < schema[:min_length]
            @errors << "Field '#{path}' must be at least #{schema[:min_length]} characters long"
          end

          if schema[:max_length] && value.length > schema[:max_length]
            @errors << "Field '#{path}' must be at most #{schema[:max_length]} characters long"
          end
        end

        # Integer constraints
        if value.is_a?(Integer)
          @errors << "Field '#{path}' must be at least #{schema[:min]}" if schema[:min] && value < schema[:min]

          @errors << "Field '#{path}' must be at most #{schema[:max]}" if schema[:max] && value > schema[:max]
        end

        # Array constraints
        if value.is_a?(Array)
          @errors << "Field '#{path}' must have at least #{schema[:min_length]} items" if schema[:min_length] && value.length < schema[:min_length]

          @errors << "Field '#{path}' must have at most #{schema[:max_length]} items" if schema[:max_length] && value.length > schema[:max_length]
        end

        # Allowed values constraint
        return unless schema[:allowed_values] && !schema[:allowed_values].include?(value)

        @errors << "Field '#{path}' must be one of: #{schema[:allowed_values].join(", ")}"
      end

      # Validate nested schemas
      # @param value [Object] Value to validate
      # @param schema [Hash] Field schema
      # @param path [String] Field path for error reporting
      def validate_nested_schema(value, schema, path)
        return unless value

        # Validate array items
        if schema[:item_schema] && value.is_a?(Array)
          value.each_with_index do |item, index|
            item_path = "#{path}[#{index}]"
            validate_against_schema(item, schema[:item_schema], item_path) if item.is_a?(Hash)
          end
        end

        # Validate array item types
        if schema[:item_type] && value.is_a?(Array)
          value.each_with_index do |item, index|
            item_path = "#{path}[#{index}]"
            validate_field_type(item, { type: schema[:item_type] }, item_path)
          end
        end

        # Validate hash values
        if schema[:value_schema] && value.is_a?(Hash)
          # Check if this is a structured hash (like settings/rules) or dynamic keys hash (like projects)
          # Structured hashes have their keys defined in value_schema
          # Dynamic hashes apply value_schema to each value
          is_structured = schema[:value_schema].is_a?(Hash) &&
                          schema[:value_schema].keys.any? { |k| k.is_a?(String) }

          if is_structured && (path.include?("settings") || path.include?("rules") || path.include?("default_rules"))
            # For structured hashes like settings/rules, validate the hash itself against value_schema
            validate_against_schema(value, schema[:value_schema], path)
          else
            # For dynamic key hashes like projects, validate each value
            value.each do |key, nested_value|
              nested_path = "#{path}.#{key}"
              validate_against_schema(nested_value, schema[:value_schema], nested_path) if nested_value.is_a?(Hash)
            end
          end
        end

        # Validate hash value types
        return unless schema[:value_type] && value.is_a?(Hash)

        value.each do |key, nested_value|
          nested_path = "#{path}.#{key}"
          validate_field_type(nested_value, { type: schema[:value_type] }, nested_path)
        end
      end

      # Apply default values to configuration
      # @param config [Hash] Configuration to apply defaults to
      # @return [Hash] Configuration with defaults applied
      def apply_defaults(config)
        apply_defaults_recursive(config, SCHEMA, config)
      end

      # Apply defaults recursively
      # @param config [Hash] Configuration to modify
      # @param schema [Hash] Schema with defaults
      # @param root_config [Hash] Root configuration for reference
      # @return [Hash] Configuration with defaults applied
      def apply_defaults_recursive(config, schema, root_config)
        schema.each do |key, field_schema|
          # Apply default value if field is missing
          if config[key].nil? && field_schema.key?(:default)
            config[key] = begin
              field_schema[:default].dup
            rescue StandardError
              field_schema[:default]
            end
          end

          # For hash fields with specific structure schema
          if config[key].is_a?(Hash) && field_schema[:value_schema]
            # For direct structured hash (like settings)
            if field_schema[:type] == :hash
              apply_defaults_recursive(config[key], field_schema[:value_schema], root_config)
            else
              # For hash with dynamic keys (like projects)
              config[key].each_value do |nested_value|
                apply_defaults_recursive(nested_value, field_schema[:value_schema], root_config) if nested_value.is_a?(Hash)
              end
            end
          end

          # Apply defaults to array items
          next unless config[key].is_a?(Array) && field_schema[:item_schema]

          config[key].each do |item|
            apply_defaults_recursive(item, field_schema[:item_schema], root_config) if item.is_a?(Hash)
          end
        end

        config
      end

      # Migrate from version 0 (unversioned) to version 1
      # @param config [Hash] Configuration to migrate
      # @return [Hash] Migrated configuration
      def migrate_v0_to_v1(config)
        migrated = config.dup

        # Add version field
        migrated["version"] = 1

        # Ensure required fields have defaults
        migrated["sessions_folder"] ||= ".sessions"
        migrated["projects"] ||= {}
        migrated["settings"] ||= {}

        # Migrate old setting names if they exist
        migrated["settings"]["auto_cleanup"] = migrated.delete("auto_cleanup") if migrated.key?("auto_cleanup")

        migrated["settings"]["max_sessions"] = migrated.delete("max_sessions") if migrated.key?("max_sessions")

        migrated["settings"]["worktree_cleanup_days"] = migrated.delete("worktree_cleanup_days") if migrated.key?("worktree_cleanup_days")

        # Ensure projects have required fields
        if migrated["projects"].is_a?(Hash)
          migrated["projects"].each do |project_name, project_config|
            next unless project_config.is_a?(Hash)

            # Ensure path is present
            migrated["projects"][project_name]["path"] = "./#{project_name}" if project_config["path"].nil? || project_config["path"].empty?

            # Convert old rule formats if needed
            migrate_rules_v0_to_v1(project_config["rules"]) if project_config["rules"]
          end
        end

        migrated
      end

      # Migrate rules from version 0 to version 1
      # @param rules [Hash] Rules to migrate
      def migrate_rules_v0_to_v1(rules)
        return unless rules.is_a?(Hash)

        # Convert old copy_files format
        if rules["copy_files"].is_a?(Array)
          rules["copy_files"].map! do |rule|
            if rule.is_a?(String)
              { "source" => rule, "strategy" => "copy" }
            else
              rule
            end
          end
        end

        # Convert old setup_commands format
        return unless rules["setup_commands"].is_a?(Array)

        rules["setup_commands"].map! do |command|
          if command.is_a?(String)
            { "command" => command.split }
          else
            command
          end
        end
      end
    end
  end
end
