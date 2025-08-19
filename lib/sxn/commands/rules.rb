# frozen_string_literal: true

require "thor"
require "json"

module Sxn
  module Commands
    # Manage project setup rules
    class Rules < Thor
      include Thor::Actions

      def initialize(args = ARGV, local_options = {}, config = {})
        super
        @ui = Sxn::UI::Output.new
        @prompt = Sxn::UI::Prompt.new
        @table = Sxn::UI::Table.new
        @config_manager = Sxn::Core::ConfigManager.new
        @project_manager = Sxn::Core::ProjectManager.new(@config_manager)
        @rules_manager = Sxn::Core::RulesManager.new(@config_manager, @project_manager)
      end

      desc "add PROJECT TYPE CONFIG", "Add a setup rule for project"
      option :interactive, type: :boolean, aliases: "-i", desc: "Interactive mode"

      def add(project_name = nil, rule_type = nil, rule_config = nil)
        ensure_initialized!

        # Interactive mode
        if options[:interactive] || project_name.nil?
          project_name = select_project("Select project for rule:")
          return if project_name.nil?
        end

        rule_type = @prompt.rule_type if options[:interactive] || rule_type.nil?

        if options[:interactive] || rule_config.nil?
          rule_config = prompt_rule_config(rule_type)
        else
          # Parse JSON config from command line
          begin
            rule_config = JSON.parse(rule_config)
          rescue JSON::ParserError => e
            @ui.error("Invalid JSON config: #{e.message}")
            exit(1)
          end
        end

        begin
          @ui.progress_start("Adding #{rule_type} rule for #{project_name}")

          rule = @rules_manager.add_rule(project_name, rule_type, rule_config)

          @ui.progress_done
          @ui.success("Added #{rule_type} rule for #{project_name}")

          display_rule_info(rule)
        rescue Sxn::Error => e
          @ui.progress_failed
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "remove PROJECT TYPE [INDEX]", "Remove a rule"
      option :all, type: :boolean, aliases: "-a", desc: "Remove all rules of this type"

      def remove(project_name = nil, rule_type = nil, rule_index = nil)
        ensure_initialized!

        # Interactive selection
        if project_name.nil?
          project_name = select_project("Select project:")
          return if project_name.nil?
        end

        if rule_type.nil?
          rules = @rules_manager.list_rules(project_name)
          if rules.empty?
            @ui.empty_state("No rules configured for project #{project_name}")
            return
          end

          rule_types = rules.map { |r| r[:type] }.uniq
          rule_type = @prompt.select("Select rule type to remove:", rule_types)
        end

        # Convert index to integer
        rule_index = rule_index.to_i if rule_index && !options[:all]

        unless @prompt.confirm_deletion("#{rule_type} rule(s)", "rule")
          @ui.info("Cancelled")
          return
        end

        begin
          @ui.progress_start("Removing #{rule_type} rule(s)")

          if options[:all]
            @rules_manager.remove_rule(project_name, rule_type)
            @ui.progress_done
            @ui.success("Removed all #{rule_type} rules for #{project_name}")
          else
            @rules_manager.remove_rule(project_name, rule_type, rule_index)
            @ui.progress_done
            @ui.success("Removed #{rule_type} rule ##{rule_index} for #{project_name}")
          end
        rescue Sxn::Error => e
          @ui.progress_failed
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "list [PROJECT]", "List all rules or rules for specific project"
      option :type, type: :string, desc: "Filter by rule type"
      option :validate, type: :boolean, aliases: "-v", desc: "Validate rules"

      def list(project_name = nil)
        ensure_initialized!

        begin
          rules = @rules_manager.list_rules(project_name)

          # Filter by type if specified
          rules = rules.select { |r| r[:type] == options[:type] } if options[:type]

          @ui.section("Project Rules")

          if rules.empty?
            if project_name
              @ui.empty_state("No rules configured for project #{project_name}")
            else
              @ui.empty_state("No rules configured")
            end
            suggest_add_rule
          elsif options[:validate]
            list_with_validation(rules, project_name)
          else
            @table.rules(rules, project_name)
            @ui.newline
            @ui.info("Total: #{rules.size} rules")
          end
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "apply [PROJECT]", "Apply rules to current session"
      option :session, type: :string, aliases: "-s", desc: "Target session (defaults to current)"
      option :dry_run, type: :boolean, aliases: "-d", desc: "Show what would be done without executing"

      def apply(project_name = nil)
        ensure_initialized!

        session_name = options[:session] || @config_manager.current_session
        unless session_name
          @ui.error("No active session")
          @ui.recovery_suggestion("Use 'sxn use <session>' or specify --session")
          exit(1)
        end

        # Interactive selection if project not provided
        if project_name.nil?
          worktree_manager = Sxn::Core::WorktreeManager.new(@config_manager)
          worktrees = worktree_manager.list_worktrees(session_name: session_name)

          if worktrees.empty?
            @ui.empty_state("No worktrees in current session")
            @ui.recovery_suggestion("Add worktrees with 'sxn worktree add <project>'")
            exit(1)
          end

          choices = worktrees.map do |w|
            { name: "#{w[:project]} (#{w[:branch]})", value: w[:project] }
          end
          project_name = @prompt.select("Select project to apply rules:", choices)
        end

        begin
          if options[:dry_run]
            @ui.info("Dry run mode - showing rules that would be applied")
            show_rules_preview(project_name)
          else
            @ui.progress_start("Applying rules for #{project_name}")

            results = @rules_manager.apply_rules(project_name, session_name)

            @ui.progress_done

            if results[:success]
              @ui.success("Applied #{results[:applied_count]} rules successfully")
            else
              @ui.warning("Some rules failed to apply")
              results[:errors].each { |error| @ui.error("  #{error}") }
            end
          end
        rescue Sxn::Error => e
          @ui.progress_failed if options[:dry_run]
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "validate PROJECT", "Validate rules for a project"
      def validate(project_name = nil)
        ensure_initialized!

        if project_name.nil?
          project_name = select_project("Select project to validate:")
          return if project_name.nil?
        end

        begin
          results = @rules_manager.validate_rules(project_name)

          @ui.section("Rule Validation: #{project_name}")

          if results.nil?
            @ui.error("No validation results returned")
            return
          end

          valid_count = 0
          invalid_count = 0

          results.each do |result|
            if result[:valid]
              status = "✅"
              valid_count += 1
            else
              status = "❌"
              invalid_count += 1
            end
            @ui.list_item("#{status} #{result[:type]} ##{result[:index]}")

            # Show errors for invalid rules
            result[:errors].each { |error| @ui.list_item("  #{error}") } unless result[:valid]
          end

          @ui.newline
          @ui.info("Valid: #{valid_count}, Invalid: #{invalid_count}")

          @ui.success("All rules are valid") if invalid_count.zero?
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        rescue NoMethodError => e
          # Handle case where validate_rules is not fully implemented
          @ui.warning("Validation not yet fully implemented: #{e.message}")
        end
      end

      desc "template TYPE [PROJECT_TYPE]", "Generate rule template"
      def template(rule_type = nil, project_type = nil)
        ensure_initialized!

        if rule_type.nil?
          available_types = @rules_manager.get_available_rule_types
          choices = available_types.map do |type|
            { name: "#{type[:name]} - #{type[:description]}", value: type[:name] }
          end
          rule_type = @prompt.select("Select rule type:", choices)
        end

        begin
          template_data = @rules_manager.generate_rule_template(rule_type, project_type)

          @ui.section("Rule Template: #{rule_type}")

          puts JSON.pretty_generate(template_data)

          @ui.newline
          @ui.info("Copy this template and customize for your project")
          @ui.command_example(
            "sxn rules add <project> #{rule_type} '#{JSON.generate(template_data.first)}'",
            "Add this rule to a project"
          )
        rescue Sxn::Error => e
          @ui.error(e.message)
          exit(e.exit_code)
        end
      end

      desc "types", "List available rule types"
      def types
        available_types = @rules_manager.get_available_rule_types

        @ui.section("Available Rule Types")

        available_types.each do |type|
          @ui.subsection(type[:name])
          @ui.info(type[:description])
          @ui.newline

          puts "Example:"
          puts JSON.pretty_generate(type[:example])
          @ui.newline
        end
      end

      private

      def ensure_initialized!
        return if @config_manager.initialized?

        @ui.error("Project not initialized")
        @ui.recovery_suggestion("Run 'sxn init' to initialize sxn in this project")
        exit(1)
      end

      def select_project(message)
        projects = @project_manager.list_projects
        if projects.empty?
          @ui.empty_state("No projects configured")
          @ui.recovery_suggestion("Add projects with 'sxn projects add <name> <path>'")
          return nil
        end

        choices = projects.map do |p|
          { name: "#{p[:name]} (#{p[:type]})", value: p[:name] }
        end
        @prompt.select(message, choices)
      end

      def prompt_rule_config(rule_type)
        case rule_type
        when "copy_files"
          prompt_copy_files_config
        when "setup_commands"
          prompt_setup_commands_config
        when "template"
          prompt_template_config
        else
          @ui.error("Unknown rule type: #{rule_type}")
          exit(1)
        end
      end

      def prompt_copy_files_config
        source = @prompt.ask("Source file path:")
        strategy = @prompt.select("Copy strategy:", %w[copy symlink])

        config = { "source" => source, "strategy" => strategy }

        if @prompt.ask_yes_no("Set custom permissions?", default: false)
          permissions = @prompt.ask("Permissions (octal, e.g., 0600):")
          config["permissions"] = permissions.to_i(8)
        end

        config
      end

      def prompt_setup_commands_config
        command_str = @prompt.ask("Command (space-separated):")
        command = command_str.split

        config = { "command" => command }

        if @prompt.ask_yes_no("Set environment variables?", default: false)
          env = {}
          loop do
            key = @prompt.ask("Environment variable name (blank to finish):")
            break if key.empty?

            value = @prompt.ask("Value for #{key}:")
            env[key] = value
          end
          config["environment"] = env unless env.empty?
        end

        config
      end

      def prompt_template_config
        source = @prompt.ask("Template source path:")
        destination = @prompt.ask("Destination path:")

        {
          "source" => source,
          "destination" => destination,
          "process" => true
        }
      end

      def display_rule_info(rule)
        return unless rule

        @ui.newline
        @ui.key_value("Project", rule[:project] || "Unknown")
        @ui.key_value("Type", rule[:type] || "Unknown")

        config = rule[:config] || {}
        @ui.key_value("Config", JSON.pretty_generate(config))
        @ui.newline
      end

      def list_with_validation(rules, project_name)
        if project_name
          validation_results = @rules_manager.validate_rules(project_name)

          @ui.subsection("Rule Validation")
          validation_results.each do |result|
            status = result[:valid] ? "✅" : "❌"
            @ui.list_item("#{status} #{result[:type]} ##{result[:index]}")

            result[:errors].each { |error| @ui.list_item("  #{error}") } unless result[:valid]
          end
          @ui.newline
        end

        @table.rules(rules, project_name)
      end

      def show_rules_preview(project_name)
        rules = @rules_manager.list_rules(project_name)

        if rules.empty?
          @ui.empty_state("No rules configured for project #{project_name}")
          return
        end

        @ui.subsection("Rules that would be applied:")
        rules.each do |rule|
          @ui.list_item("#{rule[:type]}: #{rule[:config]}")
        end
      end

      def suggest_add_rule
        @ui.newline
        @ui.recovery_suggestion("Add rules with 'sxn rules add <project> <type> <config>' or use 'sxn rules template <type>' for examples")
      end
    end
  end
end
