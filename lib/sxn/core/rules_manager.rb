# frozen_string_literal: true

module Sxn
  module Core
    # Manages project rules and their application
    class RulesManager
      def initialize(config_manager = nil, project_manager = nil)
        @config_manager = config_manager || ConfigManager.new
        @project_manager = project_manager || ProjectManager.new(@config_manager)
        @rules_engine = Sxn::Rules::RulesEngine.new("/tmp", "/tmp")
      end

      def add_rule(project_name, rule_type, rule_config)
        project = @project_manager.get_project(project_name)
        raise Sxn::ProjectNotFoundError, "Project '#{project_name}' not found" unless project

        validate_rule_type!(rule_type)
        validate_rule_config!(rule_type, rule_config)

        # Get current config
        config = @config_manager.get_config

        # Initialize project rules if not exists
        config.projects[project_name] ||= {}
        config.projects[project_name]["rules"] ||= {}
        config.projects[project_name]["rules"][rule_type] ||= []

        # Add new rule
        config.projects[project_name]["rules"][rule_type] << rule_config

        # Save updated config
        save_project_config(project_name, config.projects[project_name])

        {
          project: project_name,
          type: rule_type,
          config: rule_config
        }
      end

      def remove_rule(project_name, rule_type, rule_index = nil)
        project = @project_manager.get_project(project_name)
        raise Sxn::ProjectNotFoundError, "Project '#{project_name}' not found" unless project

        config = @config_manager.get_config
        project_rules = config.projects.dig(project_name, "rules", rule_type)

        raise Sxn::RuleNotFoundError, "No #{rule_type} rules found for project '#{project_name}'" unless project_rules

        if rule_index
          raise Sxn::RuleNotFoundError, "Rule index #{rule_index} not found" if rule_index >= project_rules.size

          removed_rule = project_rules.delete_at(rule_index)
        else
          removed_rule = project_rules.clear
        end

        save_project_config(project_name, config.projects[project_name])
        removed_rule
      end

      def list_rules(project_name = nil)
        if project_name
          list_project_rules(project_name)
        else
          list_all_rules
        end
      end

      def apply_rules(project_name, session_name = nil)
        project = @project_manager.get_project(project_name)
        raise Sxn::ProjectNotFoundError, "Project '#{project_name}' not found" unless project

        # Get current session if not specified
        session_name ||= @config_manager.current_session
        raise Sxn::NoActiveSessionError, "No active session specified" unless session_name

        session_manager = SessionManager.new(@config_manager)
        session = session_manager.get_session(session_name)
        raise Sxn::SessionNotFoundError, "Session '#{session_name}' not found" unless session

        # Get worktree for this project in the session
        worktree_manager = WorktreeManager.new(@config_manager, session_manager)
        worktree = worktree_manager.get_worktree(project_name, session_name: session_name)
        unless worktree
          raise Sxn::WorktreeNotFoundError,
                "No worktree found for project '#{project_name}' in session '#{session_name}'"
        end

        # Get project rules
        rules = @project_manager.get_project_rules(project_name)

        # Apply rules to worktree
        @rules_engine.apply_rules(rules)
      end

      def validate_rules(project_name)
        project = @project_manager.get_project(project_name)
        raise Sxn::ProjectNotFoundError, "Project '#{project_name}' not found" unless project

        rules = @project_manager.get_project_rules(project_name)
        validation_results = []

        rules.each do |rule_type, rule_configs|
          Array(rule_configs).each_with_index do |rule_config, index|
            validate_rule_config!(rule_type, rule_config)
            validation_results << {
              type: rule_type,
              index: index,
              config: rule_config,
              valid: true,
              errors: []
            }
          rescue StandardError => e
            validation_results << {
              type: rule_type,
              index: index,
              config: rule_config,
              valid: false,
              errors: [e.message]
            }
          end
        end

        validation_results
      end

      def generate_rule_template(rule_type, project_type = nil)
        case rule_type
        when "copy_files"
          generate_copy_files_template(project_type)
        when "setup_commands"
          generate_setup_commands_template(project_type)
        when "template"
          generate_template_rule_template(project_type)
        else
          raise Sxn::InvalidRuleTypeError, "Unknown rule type: #{rule_type}"
        end
      end

      def get_available_rule_types
        [
          {
            name: "copy_files",
            description: "Copy files from source project to worktree",
            example: { "source" => "config/master.key", "strategy" => "copy" }
          },
          {
            name: "setup_commands",
            description: "Run setup commands in the worktree",
            example: { "command" => %w[bundle install] }
          },
          {
            name: "template",
            description: "Process template files with variable substitution",
            example: { "source" => ".sxn/templates/README.md", "destination" => "README.md" }
          }
        ]
      end

      private

      def validate_rule_type!(rule_type)
        valid_types = %w[copy_files setup_commands template]
        return if valid_types.include?(rule_type)

        raise Sxn::InvalidRuleTypeError, "Invalid rule type: #{rule_type}. Valid types: #{valid_types.join(", ")}"
      end

      def validate_rule_config!(rule_type, rule_config)
        case rule_type
        when "copy_files"
          validate_copy_files_config!(rule_config)
        when "setup_commands"
          validate_setup_commands_config!(rule_config)
        when "template"
          validate_template_config!(rule_config)
        end
      end

      def validate_copy_files_config!(config)
        raise Sxn::InvalidRuleConfigError, "copy_files rule must have 'source' field" unless config.is_a?(Hash) && config["source"]

        return unless config["strategy"] && !%w[copy symlink].include?(config["strategy"])

        raise Sxn::InvalidRuleConfigError, "copy_files strategy must be 'copy' or 'symlink'"
      end

      def validate_setup_commands_config!(config)
        raise Sxn::InvalidRuleConfigError, "setup_commands rule must have 'command' field" unless config.is_a?(Hash) && config["command"]

        return if config["command"].is_a?(Array)

        raise Sxn::InvalidRuleConfigError, "setup_commands command must be an array"
      end

      def validate_template_config!(config)
        return if config.is_a?(Hash) && config["source"] && config["destination"]

        raise Sxn::InvalidRuleConfigError, "template rule must have 'source' and 'destination' fields"
      end

      def list_project_rules(project_name)
        project = @project_manager.get_project(project_name)
        raise Sxn::ProjectNotFoundError, "Project '#{project_name}' not found" unless project

        rules = @project_manager.get_project_rules(project_name)
        format_rules_for_display(project_name, rules)
      end

      def list_all_rules
        projects = @project_manager.list_projects
        all_rules = []

        projects.each do |project|
          rules = @project_manager.get_project_rules(project[:name])
          all_rules.concat(format_rules_for_display(project[:name], rules))
        end

        all_rules
      end

      def format_rules_for_display(project_name, rules)
        formatted_rules = []

        rules.each do |rule_type, rule_configs|
          Array(rule_configs).each_with_index do |rule_config, index|
            formatted_rules << {
              project: project_name,
              type: rule_type,
              index: index,
              config: rule_config,
              enabled: true # Could be extended to support disabled rules
            }
          end
        end

        formatted_rules
      end

      def save_project_config(project_name, _project_config)
        # This would need to be implemented to save back to the config file
        # For now, we'll use the config manager's add_project method to update
        project = @project_manager.get_project(project_name)
        @config_manager.add_project(
          project_name,
          project[:path],
          type: project[:type],
          default_branch: project[:default_branch]
        )

        # TODO: Implement proper rule saving in config system
      end

      def generate_copy_files_template(project_type)
        case project_type
        when "rails"
          [
            { "source" => "config/master.key", "strategy" => "copy" },
            { "source" => ".env", "strategy" => "copy" },
            { "source" => ".env.development", "strategy" => "copy" }
          ]
        when "javascript", "typescript"
          [
            { "source" => ".env", "strategy" => "copy" },
            { "source" => ".env.local", "strategy" => "copy" },
            { "source" => ".npmrc", "strategy" => "copy" }
          ]
        else
          [
            { "source" => "path/to/file", "strategy" => "copy" }
          ]
        end
      end

      def generate_setup_commands_template(project_type)
        case project_type
        when "rails"
          [
            { "command" => %w[bundle install] },
            { "command" => ["bin/rails", "db:create"] },
            { "command" => ["bin/rails", "db:migrate"] }
          ]
        when "javascript", "typescript"
          [
            { "command" => %w[npm install] }
          ]
        else
          [
            { "command" => ["echo", "Replace with your setup command"] }
          ]
        end
      end

      def generate_template_rule_template(_project_type)
        [
          {
            "source" => ".sxn/templates/session-info.md",
            "destination" => "README.md",
            "process" => true
          }
        ]
      end
    end
  end
end
