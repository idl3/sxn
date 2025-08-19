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
      def initialize(arg1 = nil, arg2 = nil, arg3 = nil, arg4 = nil, dependencies: [])
        super
        @command_executor = Security::SecureCommandExecutor.new(@session_path, logger: logger)
        @executed_commands = []
      end

      # Validate the rule configuration

      # Apply the command execution operations
      def apply(_context = {})
        change_state!(APPLYING)
        continue_on_failure = @config.fetch("continue_on_failure", false)

        begin
          @config["commands"].each_with_index do |command_config, index|
            apply_command(command_config, index, continue_on_failure)
          end

          change_state!(APPLIED)
          log(:info, "Successfully executed #{@executed_commands.size} commands")
          true
        rescue StandardError => e
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
        raise ValidationError, "SetupCommandsRule requires 'commands' configuration" unless @config.key?("commands")

        raise ValidationError, "SetupCommandsRule 'commands' must be an array" unless @config["commands"].is_a?(Array)

        raise ValidationError, "SetupCommandsRule 'commands' cannot be empty" if @config["commands"].empty?

        @config["commands"].each_with_index do |command_config, index|
          validate_command_config!(command_config, index)
        end

        # Validate global options
        return unless @config.key?("continue_on_failure")
        return if [true, false].include?(@config["continue_on_failure"])

        raise ValidationError, "continue_on_failure must be true or false"
      end

      private

      # Validate individual command configuration
      def validate_command_config!(command_config, index)
        raise ValidationError, "Command config #{index} must be a hash" unless command_config.is_a?(Hash)

        raise ValidationError, "Command config #{index} must have a 'command' field" unless command_config.key?("command")

        command = command_config["command"]
        raise ValidationError, "Command config #{index} 'command' must be a non-empty array" unless command.is_a?(Array) && !command.empty?

        # Validate that command is whitelisted
        raise ValidationError, "Command config #{index}: command not whitelisted: #{command.first}" unless @command_executor.command_allowed?(command)

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
          raise ValidationError, "Command config #{index}: env must be a hash" unless env.is_a?(Hash)

          env.each do |key, value|
            raise ValidationError, "Command config #{index}: env keys and values must be strings" unless key.is_a?(String) && value.is_a?(String)
          end
        end

        # Validate condition
        if command_config.key?("condition")
          condition = command_config["condition"]
          raise ValidationError, "Command config #{index}: invalid condition format: #{condition}" unless valid_condition?(condition)
        end

        # Validate working directory
        return unless command_config.key?("working_directory")

        working_dir = command_config["working_directory"]
        raise ValidationError, "Command config #{index}: working_directory must be a string" unless working_dir.is_a?(String)

        full_path = File.expand_path(working_dir, @session_path)
        return if full_path.start_with?(@session_path)

        raise ValidationError, "Command config #{index}: working_directory must be within session path"
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

            error_msg += "\nSTDERR: #{result.stderr}" if result.stderr && !result.stderr.empty?

            raise ApplicationError, error_msg unless continue_on_failure

            log(:warn, error_msg)

          else
            log(:debug, "Command completed successfully", {
                  exit_status: result.exit_status,
                  duration: result.duration
                })
          end
        rescue StandardError => e
          error_msg = "Failed to execute command: #{description} - #{e.message}"

          raise ApplicationError, error_msg unless continue_on_failure

          log(:error, error_msg)
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
