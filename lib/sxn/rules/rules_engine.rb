# frozen_string_literal: true

require_relative "base_rule"
require_relative "copy_files_rule"
require_relative "setup_commands_rule"
require_relative "template_rule"

module Sxn
  module Rules
    # RulesEngine manages the loading, validation, dependency resolution, and execution
    # of project setup rules. It provides transactional execution with rollback
    # capabilities and supports parallel execution of independent rules.
    #
    # @example Basic usage
    #   engine = RulesEngine.new("/path/to/project", "/path/to/session")
    #
    #   rules_config = {
    #     "copy_secrets" => {
    #       "type" => "copy_files",
    #       "config" => { "files" => [{"source" => "config/master.key"}] }
    #     },
    #     "install_deps" => {
    #       "type" => "setup_commands",
    #       "config" => { "commands" => [{"command" => ["bundle", "install"]}] },
    #       "dependencies" => ["copy_secrets"]
    #     }
    #   }
    #
    #   result = engine.apply_rules(rules_config)
    #   puts "Applied #{result.applied_rules.size} rules successfully"
    #
    class RulesEngine
      # Execution result for rule application
      class ExecutionResult
        attr_reader :applied_rules, :failed_rules, :total_duration, :errors
        
        def skipped_rules
          @skipped_rules.map { |s| s[:rule] }
        end

        def initialize
          @applied_rules = []
          @failed_rules = []
          @skipped_rules = []
          @total_duration = 0
          @errors = []
          @start_time = nil
          @end_time = nil
        end

        def start!
          @start_time = Time.now
        end

        def finish!
          @end_time = Time.now
          @total_duration = @end_time - @start_time if @start_time
        end

        def add_applied_rule(rule)
          @applied_rules << rule
        end

        def add_failed_rule(rule, error)
          @failed_rules << rule
          @errors << { rule: rule.name, error: error }
        end

        def add_skipped_rule(rule, reason)
          @skipped_rules << { rule: rule, reason: reason }
        end

        def add_engine_error(error)
          @errors << { rule: "engine", error: error }
        end

        def success?
          @failed_rules.empty? && @errors.empty?
        end

        def total_rules
          @applied_rules.size + @failed_rules.size + @skipped_rules.size
        end

        def to_h
          {
            success: success?,
            total_rules: total_rules,
            applied_rules: @applied_rules.map(&:name),
            failed_rules: @failed_rules.map(&:name),
            skipped_rules: @skipped_rules.map { |sr| sr[:rule].name },
            total_duration: @total_duration,
            errors: @errors.map { |e| { rule: e[:rule], message: e[:error].message } }
          }
        end
      end

      # Rule type registry mapping type names to classes
      RULE_TYPES = {
        "copy_files" => CopyFilesRule,
        "setup_commands" => SetupCommandsRule,
        "template" => TemplateRule
      }.freeze

      attr_reader :project_path, :session_path, :logger

      # Initialize the rules engine
      #
      # @param project_path [String] Absolute path to the project root
      # @param session_path [String] Absolute path to the session directory
      # @param logger [Logger] Optional logger instance
      def initialize(project_path, session_path, logger: nil)
        @project_path = File.realpath(project_path)
        @session_path = File.realpath(session_path)
        @logger = logger || Sxn.logger
        @applied_rules = []

        validate_paths!
      rescue Errno::ENOENT => e
        raise ArgumentError, "Invalid path provided: #{e.message}"
      end

      # Apply a set of rules with dependency resolution and parallel execution
      #
      # @param rules_config [Hash] Rules configuration hash
      # @param options [Hash] Execution options
      # @option options [Boolean] :parallel (true) Enable parallel execution
      # @option options [Boolean] :continue_on_failure (false) Continue if a rule fails
      # @option options [Integer] :max_parallelism (4) Maximum parallel rule execution
      # @option options [Boolean] :validate_only (false) Only validate, don't execute
      # @return [ExecutionResult] Result of rule execution
      def apply_rules(rules_config, options = {})
        options = default_options.merge(options)
        result = ExecutionResult.new
        result.start!

        begin
          # Load and validate all rules
          all_rules = load_rules(rules_config)
          valid_rules = validate_rules(all_rules)
          
          # Track skipped rules (those that failed validation)
          skipped_rules = all_rules - valid_rules
          skipped_rules.each do |rule|
            result.add_skipped_rule(rule, "Failed validation")
          end

          return result.tap(&:finish!) if options[:validate_only]

          # Resolve execution order based on dependencies
          execution_order = resolve_execution_order(valid_rules)

          @logger&.info("Executing #{valid_rules.size} rules in #{execution_order.size} phases")

          # Execute rules in phases (each phase can run in parallel)
          execution_order.each_with_index do |phase_rules, phase_index|
            execute_phase(phase_rules, phase_index, result, options)

            # Stop if we have failures and not continuing on failure
            break if !options[:continue_on_failure] && !result.failed_rules.empty?
          end
        rescue ValidationError => e
          @logger&.error("Rules validation error: #{e.message}")
          raise
        rescue StandardError => e
          @logger&.error("Rules engine error: #{e.message}")
          result.add_engine_error(e)
        ensure
          result.finish!
        end

        result
      end

      # Rollback all applied rules in reverse order
      #
      # @return [Boolean] true if rollback successful
      def rollback_rules
        return true if @applied_rules.empty?

        @logger&.info("Rolling back #{@applied_rules.size} applied rules")

        @applied_rules.reverse_each do |rule|
          if rule.rollbackable?
            rule.rollback
            @logger&.debug("Rolled back rule: #{rule.name}")
          else
            @logger&.debug("Rule not rollbackable: #{rule.name}")
          end
        rescue StandardError => e
          @logger&.error("Failed to rollback rule #{rule.name}: #{e.message}")
        end

        @applied_rules.clear
        true
      end

      # Validate rules configuration without executing
      #
      # @param rules_config [Hash] Rules configuration hash
      # @return [Array<BaseRule>] Validated rules
      def validate_rules_config(rules_config)
        all_rules = load_rules(rules_config)
        validate_rules_strict(all_rules)
        all_rules
      end

      # Strict validation that raises errors on any validation failure
      def validate_rules_strict(rules)
        rules.each do |rule|
          rule.validate
        rescue StandardError => e
          raise ValidationError, "Rule '#{rule.name}' validation failed: #{e.message}"
        end

        # Validate dependencies exist
        validate_dependencies(rules)

        # Check for circular dependencies
        check_circular_dependencies(rules)
      end

      # Get available rule types
      #
      # @return [Array<String>] Available rule type names
      def available_rule_types
        RULE_TYPES.keys
      end

      private

      # Default execution options
      def default_options
        {
          parallel: true,
          continue_on_failure: false,
          max_parallelism: 4,
          validate_only: false
        }
      end

      # Validate that paths exist and are accessible
      def validate_paths!
        raise ArgumentError, "Project path is not a directory: #{@project_path}" unless File.directory?(@project_path)

        raise ArgumentError, "Session path is not a directory: #{@session_path}" unless File.directory?(@session_path)

        return if File.writable?(@session_path)

        raise ArgumentError, "Session path is not writable: #{@session_path}"
      end

      # Load rules from configuration
      def load_rules(rules_config)
        raise ArgumentError, "Rules config must be a hash" unless rules_config.is_a?(Hash)

        rules = []

        rules_config.each do |rule_name, rule_spec|
          begin
            rule = load_single_rule(rule_name, rule_spec)
            rules << rule
          rescue ArgumentError, ValidationError => e
            # ArgumentError and ValidationError for invalid rule types should bubble up
            raise e
          rescue StandardError => e
            # Other errors during rule creation are logged but don't stop loading
            @logger&.warn("Failed to load rule '#{rule_name}': #{e.message}")
          end
        end

        rules
      end

      # Load a single rule from specification
      def load_single_rule(rule_name, rule_spec)
        raise ArgumentError, "Rule spec for '#{rule_name}' must be a hash" unless rule_spec.is_a?(Hash)

        rule_type = rule_spec["type"]
        config = rule_spec.fetch("config", {})
        dependencies = rule_spec.fetch("dependencies", [])

        create_rule(rule_name, rule_type, config, dependencies, @session_path, @project_path)
      end

      # Create a rule instance
      def create_rule(rule_name, rule_type, config, dependencies, session_path, project_path)
        rule_class = get_rule_class(rule_type)
        if rule_class.nil?
          available_types = RULE_TYPES.keys.join(", ")
          raise ValidationError, "Unknown rule type '#{rule_type}' for rule '#{rule_name}'. Available: #{available_types}"
        end

        rule_class.new(rule_name, config, project_path, session_path, dependencies: dependencies)
      end

      # Get rule class for a given type
      def get_rule_class(rule_type)
        RULE_TYPES[rule_type]
      end

      # Validate all rules
      def validate_rules(rules)
        valid_rules = []
        
        rules.each do |rule|
          begin
            rule.validate
            valid_rules << rule
          rescue StandardError => e
            @logger&.warn("Rule '#{rule.name}' validation failed: #{e.message}")
            # Skip invalid rules but continue processing
          end
        end

        # Validate dependencies exist for valid rules only
        validate_dependencies(valid_rules)

        # Check for circular dependencies for valid rules only
        check_circular_dependencies(valid_rules)
        
        valid_rules
      end

      # Validate that all dependencies exist
      def validate_dependencies(rules)
        rule_names = rules.map(&:name)
        rules.each do |rule|
          rule.dependencies.each do |dep|
            unless rule_names.include?(dep)
              raise ValidationError, "Rule '#{rule.name}' depends on non-existent rule '#{dep}'"
            end
          end
        end
      end

      # Check for circular dependencies
      def check_circular_dependencies(rules)
        detect_circular_dependencies(rules)
      end

      # Detect circular dependencies using DFS
      def detect_circular_dependencies(rules)
        rule_map = rules.to_h { |r| [r.name, r] }
        visited = Set.new
        rec_stack = Set.new

        rules.each do |rule|
          next if visited.include?(rule.name)

          if has_circular_dependency?(rule, rule_map, visited, rec_stack)
            raise ValidationError, "Circular dependency detected involving rule '#{rule.name}'"
          end
        end
      end

      # DFS helper for circular dependency detection
      def has_circular_dependency?(rule, rule_map, visited, rec_stack)
        visited.add(rule.name)
        rec_stack.add(rule.name)

        rule.dependencies.each do |dep_name|
          dep_rule = rule_map[dep_name]
          next unless dep_rule

          if !visited.include?(dep_name)
            return true if has_circular_dependency?(dep_rule, rule_map, visited, rec_stack)
          elsif rec_stack.include?(dep_name)
            return true
          end
        end

        rec_stack.delete(rule.name)
        false
      end

      # Resolve execution order based on dependencies (topological sort)
      def resolve_execution_order(rules)
        rules.to_h { |r| [r.name, r] }
        phases = []
        remaining_rules = rules.dup
        completed_rules = Set.new

        until remaining_rules.empty?
          # Find rules that can be executed (all dependencies satisfied)
          executable_rules = remaining_rules.select do |rule|
            rule.can_execute?(completed_rules.to_a)
          end

          if executable_rules.empty?
            missing_deps = remaining_rules.map do |rule|
              unsatisfied = rule.dependencies.reject { |dep| completed_rules.include?(dep) }
              "#{rule.name} needs: #{unsatisfied.join(", ")}" if unsatisfied.any?
            end.compact

            raise ValidationError, "Cannot resolve dependencies. Missing: #{missing_deps.join("; ")}"
          end

          # Add this phase and mark rules as completed
          phases << executable_rules
          executable_rules.each { |rule| completed_rules.add(rule.name) }
          remaining_rules -= executable_rules
        end

        phases
      end

      # Execute a phase of rules (potentially in parallel)
      def execute_phase(phase_rules, phase_index, result, options)
        @logger&.debug("Executing phase #{phase_index + 1} with #{phase_rules.size} rules")

        if options[:parallel] && phase_rules.size > 1
          execute_phase_parallel(phase_rules, result, options)
        else
          execute_phase_sequential(phase_rules, result, options)
        end
      end

      # Execute rules in a phase sequentially
      def execute_phase_sequential(phase_rules, result, options)
        phase_rules.each do |rule|
          execute_single_rule(rule, result, options)
        end
      end

      # Execute rules in a phase in parallel
      def execute_phase_parallel(phase_rules, result, options)
        max_threads = [phase_rules.size, options[:max_parallelism]].min
        @logger&.debug("Using #{max_threads} threads for parallel execution")

        # Use a thread pool pattern for controlled parallelism
        threads = []
        mutex = Mutex.new

        phase_rules.each do |rule|
          thread = Thread.new do
            execute_single_rule(rule, result, options, mutex)
          rescue StandardError => e
            mutex.synchronize do
              result.add_failed_rule(rule, e)
            end
          end
          threads << thread

          # Limit number of concurrent threads
          threads.shift.join if threads.size >= max_threads
        end

        # Wait for all remaining threads
        threads.each(&:join)
      end

      # Execute a single rule
      def execute_single_rule(rule, result, options, mutex = nil)
        @logger&.debug("Executing rule: #{rule.name}")

        begin
          rule.apply

          # Thread-safe result updates
          if mutex
            mutex.synchronize { result.add_applied_rule(rule) }
          else
            result.add_applied_rule(rule)
          end

          @applied_rules << rule
          @logger&.info("Successfully applied rule: #{rule.name}")
        rescue StandardError => e
          @logger&.error("Failed to apply rule #{rule.name}: #{e.message}")

          if mutex
            mutex.synchronize { result.add_failed_rule(rule, e) }
          else
            result.add_failed_rule(rule, e)
          end

          # Attempt rollback if the rule supports it
          begin
            rule.rollback if rule.rollbackable?
          rescue StandardError => rollback_error
            @logger&.error("Failed to rollback rule #{rule.name}: #{rollback_error.message}")
          end

          raise unless options[:continue_on_failure]
        end
      end
    end
  end
end
