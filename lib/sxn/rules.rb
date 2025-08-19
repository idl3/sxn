# frozen_string_literal: true

require_relative "rules/errors"
require_relative "rules/base_rule"
require_relative "rules/copy_files_rule"
require_relative "rules/setup_commands_rule"
require_relative "rules/template_rule"
require_relative "rules/rules_engine"
require_relative "rules/project_detector"

module Sxn
  # The Rules module provides a comprehensive system for automating project setup
  # through configurable rules. It includes secure file copying, command execution,
  # template processing, and intelligent project detection.
  #
  # @example Basic usage
  #   engine = Rules::RulesEngine.new("/path/to/project", "/path/to/session")
  #   detector = Rules::ProjectDetector.new("/path/to/project")
  #   
  #   # Detect project characteristics and suggest rules
  #   suggested_rules = detector.suggest_default_rules
  #   
  #   # Apply rules to set up the session
  #   result = engine.apply_rules(suggested_rules)
  #   
  #   if result.success?
  #     puts "Applied #{result.applied_rules.size} rules successfully"
  #   else
  #     puts "Failed to apply rules: #{result.errors}"
  #     engine.rollback_rules
  #   end
  #
  module Rules
    # Get all available rule types
    #
    # @return [Array<String>] Available rule type names
    def self.available_types
      RulesEngine::RULE_TYPES.keys
    end

    # Create a rule instance from configuration
    #
    # @param name [String] Rule name
    # @param type [String] Rule type
    # @param config [Hash] Rule configuration
    # @param project_path [String] Project root path
    # @param session_path [String] Session directory path
    # @param dependencies [Array<String>] Rule dependencies
    # @return [BaseRule] Rule instance
    # @raise [ArgumentError] if rule type is invalid
    def self.create_rule(name, type, config, project_path, session_path, dependencies: [])
      rule_class = RulesEngine::RULE_TYPES[type]
      raise ArgumentError, "Invalid rule type: #{type}" unless rule_class

      rule_class.new(name, config, project_path, session_path, dependencies: dependencies)
    end

    # Validate a rules configuration hash
    #
    # @param rules_config [Hash] Rules configuration
    # @param project_path [String] Project root path
    # @param session_path [String] Session directory path
    # @return [Boolean] true if valid
    # @raise [ValidationError] if configuration is invalid
    def self.validate_configuration(rules_config, project_path, session_path)
      engine = RulesEngine.new(project_path, session_path)
      engine.validate_rules_config(rules_config)
      true
    end

    # Get rule type information
    #
    # @return [Hash] Rule type information including descriptions and supported options
    def self.rule_type_info
      {
        "copy_files" => {
          description: "Securely copy or symlink files with permission control and optional encryption",
          config_schema: {
            "files" => {
              type: "array",
              required: true,
              description: "List of files to copy",
              items: {
                "source" => { type: "string", required: true, description: "Source file path" },
                "destination" => { type: "string", required: false, description: "Destination path (defaults to source)" },
                "strategy" => { type: "string", required: false, enum: ["copy", "symlink"], default: "copy" },
                "permissions" => { type: "string", required: false, description: "File permissions (e.g., '0600')" },
                "encrypt" => { type: "boolean", required: false, default: false },
                "required" => { type: "boolean", required: false, default: true }
              }
            }
          }
        },
        "setup_commands" => {
          description: "Execute project setup commands securely with environment control",
          config_schema: {
            "commands" => {
              type: "array",
              required: true,
              description: "List of commands to execute",
              items: {
                "command" => { type: "array", required: true, description: "Command and arguments" },
                "env" => { type: "object", required: false, description: "Environment variables" },
                "timeout" => { type: "integer", required: false, default: 60, maximum: 1800 },
                "condition" => { type: "string", required: false, description: "Execution condition" },
                "working_directory" => { type: "string", required: false, description: "Working directory" },
                "description" => { type: "string", required: false, description: "Command description" },
                "required" => { type: "boolean", required: false, default: true }
              }
            },
            "continue_on_failure" => { type: "boolean", required: false, default: false }
          }
        },
        "template" => {
          description: "Process and apply template files with variable substitution",
          config_schema: {
            "templates" => {
              type: "array",
              required: true,
              description: "List of templates to process",
              items: {
                "source" => { type: "string", required: true, description: "Template file path" },
                "destination" => { type: "string", required: true, description: "Output file path" },
                "variables" => { type: "object", required: false, description: "Additional template variables" },
                "engine" => { type: "string", required: false, enum: ["liquid"], default: "liquid" },
                "required" => { type: "boolean", required: false, default: true },
                "overwrite" => { type: "boolean", required: false, default: false }
              }
            }
          }
        }
      }
    end
  end
end