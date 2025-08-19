# frozen_string_literal: true

module Sxn
  module Rules
    # BaseRule is the abstract base class for all rule types in the sxn system.
    # It defines the common interface that all rules must implement and provides
    # shared functionality for validation, dependency management, and error handling.
    #
    # Rules are the building blocks of session setup automation. They can copy files,
    # execute commands, process templates, or perform other project initialization tasks.
    #
    # @example Implementing a custom rule
    #   class MyCustomRule < BaseRule
    #     def validate
    #       raise ValidationError, "Custom validation failed" unless valid?
    #     end
    #
    #     def apply
    #       # Perform the rule's action
    #       track_change(:file_created, "/path/to/file")
    #     end
    #
    #     def rollback
    #       # Undo the rule's action
    #       File.unlink("/path/to/file") if File.exist?("/path/to/file")
    #     end
    #   end
    #
    class BaseRule
      # Rule execution states
      module States
        PENDING = :pending
        VALIDATING = :validating
        VALIDATED = :validated
        APPLYING = :applying
        APPLIED = :applied
        ROLLING_BACK = :rolling_back
        ROLLED_BACK = :rolled_back
        FAILED = :failed
      end

      include States

      attr_reader :name, :config, :project_path, :session_path, :state, :dependencies, :changes, :errors

      # Initialize a new rule instance
      #
      # @param name [String] Unique name for this rule instance (old format) or project_path (new format)
      # @param config_or_session_path [Hash|String] Rule configuration (old) or session_path (new)
      # @param project_path [String] Absolute path to the project root (old format)
      # @param session_path [String] Absolute path to the session directory (old format)
      # @param dependencies [Array<String>] Names of rules this rule depends on
      def initialize(arg1 = nil, arg2 = nil, arg3 = nil, arg4 = nil, dependencies: [])
        # Handle both old and new initialization formats
        if (arg1.is_a?(String) || arg1.nil?) && arg2.is_a?(Hash) && arg3.is_a?(String) && arg4.is_a?(String)
          # Old format: (name, config, project_path, session_path, dependencies: [])
          @name = arg1 || "base_rule"
          @config = arg2.dup.freeze
          @project_path = File.realpath(arg3)
          @session_path = File.realpath(arg4)
        elsif arg1.is_a?(Hash) && arg2.is_a?(String) && arg3.is_a?(String)
          # Special format: (config, project_path, session_path, name)
          @name = arg4 || "base_rule"  
          @config = arg1.dup.freeze
          @project_path = File.realpath(arg2)
          @session_path = File.realpath(arg3)
        elsif arg1.is_a?(String) && arg2.is_a?(String)
          # New format: (project_path, session_path, config = {}, dependencies: [])
          @name = "base_rule"
          # Store the config as-is for validation, only freeze if it's a Hash
          if arg3.nil?
            @config = {}.freeze
          elsif arg3.is_a?(Hash)
            @config = arg3.dup.freeze
          else
            # Store non-hash config as-is for validation to catch
            @config = arg3
          end
          @project_path = File.realpath(arg1)
          @session_path = File.realpath(arg2)
        else
          raise ArgumentError, "Invalid arguments. Expected (name, config, project_path, session_path) or (project_path, session_path, config={})"
        end
        
        @dependencies = dependencies.freeze
        @state = PENDING
        @changes = []
        @errors = []
        @start_time = nil
        @end_time = nil

        validate_paths!
      rescue Errno::ENOENT => e
        raise ArgumentError, "Invalid path provided: #{e.message}"
      end

      # Validate the rule configuration and dependencies
      # This method should be overridden by subclasses to implement specific validation logic
      #
      # @return [Boolean] true if validation passes
      # @raise [ValidationError] if validation fails
      def validate
        change_state!(VALIDATING)

        begin
          validate_config!
          validate_dependencies!
          validate_rule_specific!

          change_state!(VALIDATED)
          true
        rescue StandardError => e
          @errors << e
          change_state!(FAILED)
          raise
        end
      end

      # Apply the rule's action
      # This method must be overridden by subclasses to implement the actual rule logic
      #
      # @param context [Hash] Optional execution context
      # @return [Boolean] true if application succeeds
      # @raise [ApplicationError] if application fails
      def apply(context = {})
        raise NotImplementedError, "#{self.class} must implement #apply"
      end

      # Rollback the rule's changes
      # This method should be overridden by subclasses to implement rollback logic
      #
      # @return [Boolean] true if rollback succeeds
      # @raise [RollbackError] if rollback fails
      def rollback
        return true if @state == PENDING || @state == FAILED

        change_state!(ROLLING_BACK)

        begin
          rollback_changes!
          change_state!(ROLLED_BACK)
          true
        rescue StandardError => e
          @errors << e
          change_state!(FAILED)
          raise Sxn::Rules::RollbackError, "Failed to rollback rule #{@name}: #{e.message}"
        end
      end

      # Check if this rule can be executed (all dependencies are satisfied)
      #
      # @param completed_rules [Array<String>] List of rule names that have been completed
      # @return [Boolean] true if all dependencies are satisfied
      def can_execute?(completed_rules)
        @dependencies.all? { |dep| completed_rules.include?(dep) }
      end

      # Get rule execution duration in seconds
      #
      # @return [Float, nil] Execution duration or nil if not completed
      def duration
        return nil unless @start_time && @end_time

        @end_time - @start_time
      end

      # Get rule type
      #
      # @return [String] Rule type based on class name
      def type
        self.class.name.split("::").last.downcase.gsub(/rule$/, "")
      end

      # Check if rule is required
      #
      # @return [Boolean] true if rule is required
      def required?
        true
      end

      # Validate rule configuration (public method expected by tests)
      #
      # @param config [Hash] Configuration to validate
      # @return [Boolean] true if valid
      def validate_config_hash(config = @config)
        return true if config.nil? || config.empty?

        config.is_a?(Hash)
      end

      # Get rule description
      #
      # @return [String] Description of the rule
      def description
        "Base rule for #{type} operations"
      end

      # Check if rule has been successfully applied
      #
      # @return [Boolean] true if rule is in applied state
      def applied?
        @state == APPLIED
      end

      # Check if rule has failed
      #
      # @return [Boolean] true if rule is in failed state
      def failed?
        @state == FAILED
      end

      # Check if rule can be rolled back
      #
      # @return [Boolean] true if rule can be rolled back
      def rollbackable?
        @state == APPLIED && @changes.any?
      end

      # Get a hash representation of the rule for serialization
      #
      # @return [Hash] Rule data
      def to_h
        {
          name: @name,
          type: self.class.name.split("::").last,
          state: @state,
          config: @config,
          dependencies: @dependencies,
          changes: @changes.map(&:to_h),
          errors: @errors.map(&:message),
          duration: duration,
          applied_at: @end_time&.iso8601
        }
      end

      protected

      # Track a change made by this rule for rollback purposes
      #
      # @param type [Symbol] Type of change (:file_created, :file_modified, :directory_created, etc.)
      # @param target [String] Path or identifier of what was changed
      # @param metadata [Hash] Additional metadata about the change
      def track_change(type, target, metadata = {})
        change = RuleChange.new(type, target, metadata)
        @changes << change
        change
      end

      # Get the logger instance
      #
      # @return [Logger] Logger for this rule
      def logger
        @logger ||= Sxn.logger
      end

      # Log a message with rule context
      #
      # @param level [Symbol] Log level (:debug, :info, :warn, :error)
      # @param message [String] Message to log
      # @param metadata [Hash] Additional metadata
      def log(level, message, metadata = {})
        logger.send(level, "[Rule:#{@name}] #{message}") do
          metadata.merge(rule_name: @name, rule_type: self.class.name)
        end
      end

      private

      # Change the rule state and track timing
      def change_state!(new_state)
        old_state = @state
        @state = new_state

        case new_state
        when APPLYING
          @start_time = Time.now
        when APPLIED, FAILED, ROLLED_BACK
          @end_time = Time.now
        end

        log(:debug, "State changed from #{old_state} to #{new_state}")
      end

      # Validate that required paths exist and are accessible
      def validate_paths!
        raise ArgumentError, "Project path is not a directory: #{@project_path}" unless File.directory?(@project_path)

        raise ArgumentError, "Session path is not a directory: #{@session_path}" unless File.directory?(@session_path)

        # Ensure session path is writable
        return if File.writable?(@session_path)

        raise ArgumentError, "Session path is not writable: #{@session_path}"
      end

      # Validate basic rule configuration
      def validate_config!
        raise ValidationError, "Config must be a Hash" unless @config.is_a?(Hash)

        # Subclasses should override this method for specific validation
        validate_rule_specific!
      end

      # Validate rule dependencies
      def validate_dependencies!
        @dependencies.each do |dep|
          raise ValidationError, "Invalid dependency: #{dep.inspect}" unless dep.is_a?(String) && !dep.empty?
        end
      end

      # Validate rule-specific configuration
      # Override this method in subclasses
      def validate_rule_specific!
        # Default implementation does nothing
        true
      end

      # Rollback all tracked changes in reverse order
      def rollback_changes!
        @changes.reverse_each(&:rollback)
        @changes.clear
        true
      end

      # Represents a single change made by a rule
      class RuleChange
        attr_reader :type, :target, :metadata, :timestamp

        def initialize(type, target, metadata = {})
          @type = type
          @target = target
          @metadata = metadata.freeze
          @timestamp = Time.now
        end

        # Rollback this specific change
        def rollback
          case @type
          when :file_created
            FileUtils.rm_f(@target)
          when :file_modified
            if @metadata[:backup_path] && File.exist?(@metadata[:backup_path])
              FileUtils.mv(@metadata[:backup_path], @target)
            end
          when :directory_created
            Dir.rmdir(@target) if File.directory?(@target) && Dir.empty?(@target)
          when :symlink_created
            File.unlink(@target) if File.symlink?(@target)
          when :command_executed
            # Command execution cannot be rolled back
            # This is logged for audit purposes only
          else
            raise Sxn::Rules::RollbackError, "Unknown change type for rollback: #{@type}"
          end
        end

        def to_h
          {
            type: @type,
            target: @target,
            metadata: @metadata,
            timestamp: @timestamp.iso8601
          }
        end
      end
    end
  end
end
