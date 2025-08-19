# frozen_string_literal: true

require_relative "base_rule"
require_relative "errors"
require_relative "../security/secure_command_executor"

module Sxn
  module Rules
    # SetupCommandsRule executes project setup commands safely using the SecureCommandExecutor.
    # It supports environment variables, conditional execution, and proper error handling.
    #
    # Configuration format:
    # {
    #   "commands" => [
    #     {
    #       "command" => ["bundle", "install"],
    #       "env" => { "RAILS_ENV" => "development" },
    #       "timeout" => 120,
    #       "condition" => "file_missing:Gemfile.lock",
    #       "description" => "Install Ruby dependencies",
    #       "required" => true,
    #       "working_directory" => "."
    #     }
    #   ],
    #   "continue_on_failure" => false
    # }
    #
    # @example Basic usage
    #   rule = SetupCommandsRule.new(
    #     "rails_setup",
    #     {
    #       "commands" => [
    #         { "command" => ["bundle", "install"] },
    #         { "command" => ["bin/rails", "db:create"] },
    #         { "command" => ["bin/rails", "db:migrate"] }
    #       ]
    #     },
    #     "/path/to/project",
    #     "/path/to/session"
    #   )
    #   rule.validate
    #   rule.apply
    #
    class SetupCommandsRule < BaseRule
      # Supported condition types for conditional execution
      CONDITION_TYPES = {
        "file_exists" => :file_exists?,
        "file_missing" => :file_missing?,
        "directory_exists" => :directory_exists?,
        "directory_missing" => :directory_missing?,
        "command_available" => :command_available?,
        "env_var_set" => :env_var_set?,
        "always" => :always_true
      }.freeze

      # Default command timeout in seconds
      DEFAULT_TIMEOUT = 60

      # Maximum allowed timeout in seconds
      MAX_TIMEOUT = 1800 # 30 minutes

      # Initialize the setup commands rule
      def initialize(name, config, project_path, session_path, dependencies: [])
        super(name, config, project_path, session_path, dependencies: dependencies)
        @command_executor = Security::SecureCommandExecutor.new(@session_path, logger: logger)
        @executed_commands = []
      end

      # Validate the rule configuration
      def validate
        super
      end

      # Apply the command execution operations
      def apply
        change_state!(APPLYING)
        continue_on_failure = @config.fetch("continue_on_failure", false)
        
        begin
          @config["commands"].each_with_index do |command_config, index|
            apply_command(command_config, index, continue_on_failure)
          end
          
          change_state!(APPLIED)
          log(:info, "Successfully executed #{@executed_commands.size} commands")
          true
        rescue => e
          @errors << e
          change_state!(FAILED)
          raise ApplicationError, "Failed to execute setup commands: #{e.message}"
        end
      end

      # Get summary of executed commands
      def execution_summary
        @executed_commands.map do |cmd_result|
          {
            command: cmd_result[:command],
            success: cmd_result[:result].success?,
            duration: cmd_result[:result].duration,
            exit_status: cmd_result[:result].exit_status
          }
        end
      end

      protected

      # Validate rule-specific configuration
      def validate_rule_specific!
        unless @config.key?("commands")
          raise ValidationError, "SetupCommandsRule requires 'commands' configuration"
        end

        unless @config["commands"].is_a?(Array)
          raise ValidationError, "SetupCommandsRule 'commands' must be an array"
        end

        if @config["commands"].empty?
          raise ValidationError, "SetupCommandsRule 'commands' cannot be empty"
        end

        @config["commands"].each_with_index do |command_config, index|
          validate_command_config!(command_config, index)
        end

        # Validate global options
        if @config.key?("continue_on_failure")
          unless [true, false].include?(@config["continue_on_failure"])
            raise ValidationError, "continue_on_failure must be true or false"
          end
        end
      end

      private

      # Validate individual command configuration
      def validate_command_config!(command_config, index)
        unless command_config.is_a?(Hash)
          raise ValidationError, "Command config #{index} must be a hash"
        end

        unless command_config.key?("command")
          raise ValidationError, "Command config #{index} must have a 'command' field"
        end

        command = command_config["command"]
        unless command.is_a?(Array) && !command.empty?
          raise ValidationError, "Command config #{index} 'command' must be a non-empty array"
        end

        # Validate that command is whitelisted
        unless @command_executor.command_allowed?(command)
          raise ValidationError, "Command config #{index}: command not whitelisted: #{command.first}"
        end

        # Validate timeout
        if command_config.key?("timeout")
          timeout = command_config["timeout"]
          unless timeout.is_a?(Integer) && timeout.positive? && timeout <= MAX_TIMEOUT
            raise ValidationError, "Command config #{index}: timeout must be positive integer <= #{MAX_TIMEOUT}"
          end
        end

        # Validate environment variables
        if command_config.key?("env")
          env = command_config["env"]
          unless env.is_a?(Hash)
            raise ValidationError, "Command config #{index}: env must be a hash"
          end
          
          env.each do |key, value|
            unless key.is_a?(String) && value.is_a?(String)
              raise ValidationError, "Command config #{index}: env keys and values must be strings"
            end
          end
        end

        # Validate condition
        if command_config.key?("condition")
          condition = command_config["condition"]
          unless valid_condition?(condition)
            raise ValidationError, "Command config #{index}: invalid condition format: #{condition}"
          end
        end

        # Validate working directory
        if command_config.key?("working_directory")
          working_dir = command_config["working_directory"]
          unless working_dir.is_a?(String)
            raise ValidationError, "Command config #{index}: working_directory must be a string"
          end
          
          full_path = File.expand_path(working_dir, @session_path)
          unless full_path.start_with?(@session_path)
            raise ValidationError, "Command config #{index}: working_directory must be within session path"
          end
        end
      end

      # Check if condition format is valid
      def valid_condition?(condition)
        return true if condition.nil? || condition == "always"
        
        condition.is_a?(String) && condition.include?(":") &&
          CONDITION_TYPES.key?(condition.split(":", 2).first)
      end

      # Apply a single command operation
      def apply_command(command_config, index, continue_on_failure)
        command = command_config["command"]
        description = command_config.fetch("description", command.join(" "))
        
        log(:debug, "Evaluating command #{index}: #{description}")

        # Check condition
        unless should_execute_command?(command_config)
          log(:info, "Skipping command due to condition: #{description}")
          return
        end

        log(:info, "Executing command: #{description}")

        begin
          result = execute_command_safely(command_config)
          
          @executed_commands << {
            index: index,
            command: command,
            description: description,
            result: result
          }

          track_change(:command_executed, command.join(" "), {
            working_directory: determine_working_directory(command_config),
            env: command_config.fetch("env", {}),
            exit_status: result.exit_status,
            duration: result.duration
          })

          if result.failure?
            error_msg = "Command failed: #{description} (exit status: #{result.exit_status})"
            
            if result.stderr && !result.stderr.empty?
              error_msg += "\nSTDERR: #{result.stderr}"
            end

            if continue_on_failure
              log(:warn, error_msg)
            else
              raise ApplicationError, error_msg
            end
          else
            log(:debug, "Command completed successfully", {
              exit_status: result.exit_status,
              duration: result.duration
            })
          end

        rescue => e
          error_msg = "Failed to execute command: #{description} - #{e.message}"
          
          if continue_on_failure
            log(:error, error_msg)
          else
            raise ApplicationError, error_msg
          end
        end
      end

      # Execute a command with the security layer
      def execute_command_safely(command_config)
        command = command_config["command"]
        env = command_config.fetch("env", {})
        timeout = command_config.fetch("timeout", DEFAULT_TIMEOUT)
        working_dir = determine_working_directory(command_config)

        @command_executor.execute(
          command,
          env: env,
          timeout: timeout,
          chdir: working_dir
        )
      end

      # Determine the working directory for command execution
      def determine_working_directory(command_config)
        if command_config.key?("working_directory")
          File.expand_path(command_config["working_directory"], @session_path)
        else
          @session_path
        end
      end

      # Check if command should be executed based on its condition
      def should_execute_command?(command_config)
        condition = command_config["condition"]
        return true if condition.nil? || condition == "always"

        condition_type, condition_arg = condition.split(":", 2)
        method_name = CONDITION_TYPES[condition_type]
        
        return true unless method_name

        send(method_name, condition_arg)
      end

      # Condition evaluation methods
      def file_exists?(path)
        full_path = File.expand_path(path, @session_path)
        File.exist?(full_path)
      end

      def file_missing?(path)
        !file_exists?(path)
      end

      def directory_exists?(path)
        full_path = File.expand_path(path, @session_path)
        File.directory?(full_path)
      end

      def directory_missing?(path)
        !directory_exists?(path)
      end

      def command_available?(command_name)
        @command_executor.command_allowed?([command_name])
      end

      def env_var_set?(var_name)
        ENV.key?(var_name) && !ENV[var_name].to_s.empty?
      end

      def always_true(_arg = nil)
        true
      end
    end
  end
end