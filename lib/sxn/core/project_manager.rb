# frozen_string_literal: true

module Sxn
  module Core
    # Manages project registration and configuration
    class ProjectManager
      def initialize(config_manager = nil)
        @config_manager = config_manager || ConfigManager.new
      end

      def add_project(name, path, type: nil, default_branch: nil)
        validate_project_name!(name)
        validate_project_path!(path)
        
        # Detect project type if not provided
        type ||= Sxn::Rules::ProjectDetector.new(path).detect_project_type.to_s
        
        # Detect default branch if not provided
        default_branch ||= detect_default_branch(path)
        
        @config_manager.add_project(name, path, type: type, default_branch: default_branch)
        
        {
          name: name,
          path: File.expand_path(path),
          type: type,
          default_branch: default_branch
        }
      end

      def remove_project(name)
        project = @config_manager.get_project(name)
        raise Sxn::ProjectNotFoundError, "Project '#{name}' not found" unless project
        
        # Check if project is used in any active sessions
        session_manager = SessionManager.new(@config_manager)
        active_sessions = session_manager.list_sessions(status: "active")
        
        sessions_using_project = active_sessions.select do |session|
          session[:projects].include?(name)
        end
        
        unless sessions_using_project.empty?
          session_names = sessions_using_project.map { |s| s[:name] }.join(", ")
          raise Sxn::ProjectInUseError, 
                "Project '#{name}' is used in active sessions: #{session_names}"
        end
        
        @config_manager.remove_project(name)
        true
      end

      def list_projects
        @config_manager.list_projects
      end

      def get_project(name)
        @config_manager.get_project(name)
      end

      def project_exists?(name)
        !get_project(name).nil?
      end

      def scan_projects(base_path = nil)
        base_path ||= File.dirname(@config_manager.config_path)
        @config_manager.detect_projects
      end

      def auto_register_projects(detected_projects)
        results = []
        
        detected_projects.each do |project|
          begin
            result = add_project(
              project[:name], 
              project[:path], 
              type: project[:type]
            )
            results << { status: :success, project: result }
          rescue => e
            results << { 
              status: :error, 
              project: project, 
              error: e.message 
            }
          end
        end
        
        results
      end

      def validate_project(name)
        project = get_project(name)
        raise Sxn::ProjectNotFoundError, "Project '#{name}' not found" unless project
        
        issues = []
        
        # Check if path exists
        unless File.directory?(project[:path])
          issues << "Project path does not exist: #{project[:path]}"
        end
        
        # Check if it's a git repository
        unless git_repository?(project[:path])
          issues << "Project path is not a git repository"
        end
        
        # Check if path is readable
        unless File.readable?(project[:path])
          issues << "Project path is not readable"
        end
        
        {
          valid: issues.empty?,
          issues: issues,
          project: project
        }
      end

      def get_project_rules(name)
        project = get_project(name)
        raise Sxn::ProjectNotFoundError, "Project '#{name}' not found" unless project
        
        # Get project-specific rules from config
        config = @config_manager.get_config
        project_config = config.projects[name]
        
        rules = project_config&.dig("rules") || {}
        
        # Add default rules based on project type
        default_rules = get_default_rules_for_type(project[:type])
        
        merge_rules(default_rules, rules)
      end

      private

      def validate_project_name!(name)
        unless name.match?(/\A[a-zA-Z0-9_-]+\z/)
          raise Sxn::InvalidProjectNameError, 
                "Project name must contain only letters, numbers, hyphens, and underscores"
        end
        
        if @config_manager.get_project(name)
          raise Sxn::ProjectExistsError, "Project '#{name}' already exists"
        end
      end

      def validate_project_path!(path)
        expanded_path = File.expand_path(path)
        
        unless File.directory?(expanded_path)
          raise Sxn::InvalidProjectPathError, "Path is not a directory"
        end
        
        unless File.readable?(expanded_path)
          raise Sxn::InvalidProjectPathError, "Path is not readable"
        end
      end

      def detect_default_branch(path)
        return "master" unless git_repository?(path)
        
        begin
          Dir.chdir(path) do
            # Try to get the default branch from remote
            result = `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null`.strip
            if $?.success? && !result.empty?
              return result.split("/").last
            end
            
            # Fall back to current branch
            result = `git branch --show-current 2>/dev/null`.strip
            return result unless result.empty?
            
            # Final fallback
            "master"
          end
        rescue
          "master"
        end
      end

      def git_repository?(path)
        File.directory?(File.join(path, ".git"))
      end

      def get_default_rules_for_type(type)
        case type
        when "rails"
          {
            "copy_files" => [
              { "source" => "config/master.key", "strategy" => "copy" },
              { "source" => "config/credentials/*.key", "strategy" => "copy" },
              { "source" => ".env", "strategy" => "copy" },
              { "source" => ".env.development", "strategy" => "copy" },
              { "source" => ".env.test", "strategy" => "copy" }
            ],
            "setup_commands" => [
              { "command" => ["bundle", "install"] },
              { "command" => ["bin/rails", "db:create"] },
              { "command" => ["bin/rails", "db:migrate"] }
            ]
          }
        when "javascript", "typescript", "nextjs", "react"
          {
            "copy_files" => [
              { "source" => ".env", "strategy" => "copy" },
              { "source" => ".env.local", "strategy" => "copy" },
              { "source" => ".npmrc", "strategy" => "copy" }
            ],
            "setup_commands" => [
              { "command" => ["npm", "install"] }
            ]
          }
        else
          {}
        end
      end

      def merge_rules(default_rules, custom_rules)
        result = default_rules.dup
        
        custom_rules.each do |rule_type, rule_config|
          if result[rule_type]
            # Merge arrays for rules like copy_files and setup_commands
            if result[rule_type].is_a?(Array) && rule_config.is_a?(Array)
              result[rule_type] = result[rule_type] + rule_config
            else
              result[rule_type] = rule_config
            end
          else
            result[rule_type] = rule_config
          end
        end
        
        result
      end
    end
  end
end