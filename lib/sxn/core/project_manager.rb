# frozen_string_literal: true

require "English"
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
        project = @config_manager.get_project(name)
        raise Sxn::ProjectNotFoundError, "Project '#{name}' not found" unless project

        project
      end

      def project_exists?(name)
        project = @config_manager.get_project(name)
        !project.nil?
      end

      def scan_projects(_base_path = nil)
        @config_manager.detect_projects
      end

      def detect_projects(base_path = nil)
        base_path ||= Dir.pwd
        detected = []

        # Scan for common project types
        Dir.glob(File.join(base_path, "*")).each do |path|
          next unless File.directory?(path)
          next if File.basename(path).start_with?(".")

          project_type = detect_project_type(path)
          next if project_type == "unknown"

          detected << {
            name: File.basename(path),
            path: path,
            type: project_type
          }
        end

        detected
      end

      def detect_project_type(path)
        path = Pathname.new(path)

        # Rails detection
        return "rails" if (path / "Gemfile").exist? &&
                          (path / "config" / "application.rb").exist?

        # Ruby gem detection
        return "ruby" if (path / "Gemfile").exist? || Dir.glob((path / "*.gemspec").to_s).any?

        # Node.js/JavaScript detection
        if (path / "package.json").exist?
          begin
            package_json = JSON.parse((path / "package.json").read)
            return "nextjs" if package_json.dig("dependencies", "next")
            return "react" if package_json.dig("dependencies", "react")
            return "typescript" if (path / "tsconfig.json").exist?

            return "javascript"
          rescue StandardError
            return "javascript"
          end
        end

        "unknown"
      end

      def update_project(name, updates = {})
        project = get_project(name)
        raise Sxn::ProjectNotFoundError, "Project '#{name}' not found" unless project

        # Validate updates
        raise Sxn::InvalidProjectPathError, "Path is not a directory" if updates[:path] && !File.directory?(updates[:path])

        @config_manager.update_project(name, updates)
        @config_manager.get_project(name) || raise(Sxn::ProjectNotFoundError,
                                                   "Project '#{name}' was deleted during update")
      end

      def validate_projects
        projects = list_projects
        results = []

        projects.each do |project|
          result = validate_project(project[:name])
          results << result
        end

        results
      end

      def auto_register_projects(detected_projects)
        results = []

        detected_projects.each do |project|
          result = add_project(
            project[:name],
            project[:path],
            type: project[:type]
          )
          results << { status: :success, project: result }
        rescue StandardError => e
          results << {
            status: :error,
            project: project,
            error: e.message
          }
        end

        results
      end

      def validate_project(name)
        project = get_project(name)
        raise Sxn::ProjectNotFoundError, "Project '#{name}' not found" unless project

        issues = []

        # Check if path exists
        issues << "Project path does not exist: #{project[:path]}" unless File.directory?(project[:path])

        # Check if it's a git repository
        issues << "Project path is not a git repository" unless git_repository?(project[:path])

        # Check if path is readable
        issues << "Project path is not readable" unless File.readable?(project[:path])

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

        # Handle both OpenStruct and Hash for projects config
        projects = config.projects
        project_config = if projects.is_a?(OpenStruct)
                           projects.to_h[name.to_sym] || projects.to_h[name]
                         elsif projects.is_a?(Hash)
                           projects[name]
                         end

        # Extract rules, handling both OpenStruct and Hash
        rules = if project_config.is_a?(OpenStruct)
                  project_config.to_h[:rules] || project_config.to_h["rules"] || {}
                elsif project_config.is_a?(Hash)
                  project_config["rules"] || project_config[:rules] || {}
                else
                  {}
                end

        # Convert OpenStruct rules to hash if needed
        rules = rules.to_h if rules.is_a?(OpenStruct)

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

        return unless @config_manager.get_project(name)

        raise Sxn::ProjectAlreadyExistsError, "Project '#{name}' already exists"
      end

      def validate_project_path!(path)
        expanded_path = File.expand_path(path)

        raise Sxn::InvalidProjectPathError, "Path is not a directory" unless File.directory?(expanded_path)

        return if File.readable?(expanded_path)

        raise Sxn::InvalidProjectPathError, "Path is not readable"
      end

      def detect_default_branch(path)
        return "master" unless git_repository?(path)

        begin
          Dir.chdir(path) do
            # Try to get the default branch from remote
            result = `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null`.strip
            return result.split("/").last if $CHILD_STATUS.success? && !result.empty?

            # Fall back to current branch
            result = `git branch --show-current 2>/dev/null`.strip
            return result unless result.empty?

            # Final fallback
            "master"
          end
        rescue StandardError
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
              { "command" => %w[bundle install] },
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
              { "command" => %w[npm install] }
            ]
          }
        else
          {}
        end
      end

      def merge_rules(default_rules, custom_rules)
        result = default_rules.dup

        custom_rules.each do |rule_type, rule_config|
          result[rule_type] = if result[rule_type]
                                # Merge arrays for rules like copy_files and setup_commands
                                if result[rule_type].is_a?(Array) && rule_config.is_a?(Array)
                                  result[rule_type] + rule_config
                                else
                                  rule_config
                                end
                              else
                                rule_config
                              end
        end

        result
      end
    end
  end
end
