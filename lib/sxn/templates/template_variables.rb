# frozen_string_literal: true

require "pathname"
require "time"

module Sxn
  module Templates
    # TemplateVariables collects and prepares variables for template processing.
    # It gathers context from sessions, git repositories, projects, and environment.
    #
    # Variable Categories:
    # - session: Current session information (name, path, created_at, etc.)
    # - git: Git repository information (branch, author, last_commit, etc.)
    # - project: Project details (name, type, path, etc.)
    # - environment: Runtime environment (ruby version, rails version, etc.)
    # - user: User preferences and git configuration
    #
    # Example:
    #   collector = TemplateVariables.new(session, project)
    #   variables = collector.collect
    #   # => {
    #   #   session: { name: "ATL-1234", path: "/path/to/session" },
    #   #   git: { branch: "feature/cart", author: "John Doe" },
    #   #   project: { name: "atlas-core", type: "rails" }
    #   # }
    class TemplateVariables
      # Git command timeout in seconds
      GIT_TIMEOUT = 5

      def initialize(session = nil, project = nil, config = nil)
        @session = session
        @project = project
        @config = config
        @cached_variables = {}
      end

      # Collect all template variables
      #
      # @return [Hash] Complete set of variables for template processing
      def collect
        return @cached_variables unless @cached_variables.empty?

        @cached_variables = {
          session: collect_session_variables,
          git: collect_git_variables,
          project: collect_project_variables,
          environment: collect_environment_variables,
          user: collect_user_variables,
          timestamp: collect_timestamp_variables
        }.compact

        @cached_variables
      end

      # Alias for collect method to maintain backwards compatibility with tests
      alias_method :build_variables, :collect

      # Refresh cached variables (useful for long-running processes)
      def refresh!
        @cached_variables = {}
        collect
      end

      # Get variables for a specific category
      #
      # @param category [Symbol] The variable category (:session, :git, :project, etc.)
      # @return [Hash] Variables for the specified category
      def get_category(category)
        collect[category] || {}
      end

      # Add custom variables that will be merged with collected variables
      #
      # @param custom_vars [Hash] Custom variables to add
      def add_custom_variables(custom_vars)
        return unless custom_vars.is_a?(Hash)

        # Merge custom variables, with custom taking precedence
        @cached_variables = collect.deep_merge(custom_vars)
      end

      private

      # Collect session-related variables
      def collect_session_variables
        return {} unless @session

        session_vars = {
          name: @session.name,
          path: @session.path.to_s,
          created_at: format_timestamp(@session.created_at),
          updated_at: format_timestamp(@session.updated_at),
          status: @session.status
        }

        # Add optional session fields if present
        session_vars[:linear_task] = @session.linear_task if @session.respond_to?(:linear_task) && @session.linear_task
        session_vars[:description] = @session.description if @session.respond_to?(:description) && @session.description
        session_vars[:projects] = @session.projects if @session.respond_to?(:projects) && @session.projects
        session_vars[:tags] = @session.tags if @session.respond_to?(:tags) && @session.tags

        # Add worktree information if available
        if @session.respond_to?(:worktrees) && @session.worktrees
          session_vars[:worktrees] = @session.worktrees.map do |worktree|
            {
              name: worktree.name,
              path: worktree.path.to_s,
              branch: worktree.branch,
              created_at: format_timestamp(worktree.created_at)
            }
          end
        end

        session_vars
      rescue StandardError => e
        { error: "Failed to collect session variables: #{e.message}" }
      end

      # Collect git repository variables
      def collect_git_variables
        git_vars = {}
        
        # Determine git directory - prefer project path, fall back to session path
        git_dir = find_git_directory
        return {} unless git_dir

        # Collect git information with timeout protection
        git_vars.merge!(collect_git_branch_info(git_dir))
        git_vars.merge!(collect_git_author_info(git_dir))
        git_vars.merge!(collect_git_commit_info(git_dir))
        git_vars.merge!(collect_git_remote_info(git_dir))
        git_vars.merge!(collect_git_status_info(git_dir))

        git_vars
      rescue StandardError => e
        { error: "Failed to collect git variables: #{e.message}" }
      end

      # Collect project-related variables
      def collect_project_variables
        return {} unless @project

        project_vars = {
          name: @project.name,
          path: @project.path.to_s,
          type: detect_project_type(@project.path)
        }

        # Add language-specific information
        case project_vars[:type]
        when "rails"
          project_vars.merge!(collect_rails_project_info)
        when "javascript", "typescript", "nodejs"
          project_vars.merge!(collect_js_project_info)
        when "ruby"
          project_vars.merge!(collect_ruby_project_info)
        end

        project_vars
      rescue StandardError => e
        { error: "Failed to collect project variables: #{e.message}" }
      end

      # Collect environment variables
      def collect_environment_variables
        env_vars = {}

        # Ruby environment
        env_vars[:ruby] = {
          version: RUBY_VERSION,
          platform: RUBY_PLATFORM,
          patchlevel: RUBY_PATCHLEVEL
        }

        # Rails information if in Rails project
        env_vars[:rails] = collect_rails_version if rails_available?

        # Node.js information if available
        env_vars[:node] = collect_node_version if node_available?

        # Database information
        env_vars[:database] = collect_database_info

        # Operating system
        env_vars[:os] = {
          name: RbConfig::CONFIG["host_os"],
          arch: RbConfig::CONFIG["host_cpu"]
        }

        env_vars
      rescue StandardError => e
        { error: "Failed to collect environment variables: #{e.message}" }
      end

      # Collect user preferences and configuration
      def collect_user_variables
        user_vars = {}

        # Git user configuration
        user_vars.merge!(collect_git_user_config)

        # User preferences from sxn config
        if @config
          user_vars[:editor] = @config.default_editor if @config.respond_to?(:default_editor)
          user_vars[:preferences] = @config.user_preferences if @config.respond_to?(:user_preferences)
        end

        # System user information
        user_vars[:username] = ENV["USER"] || ENV["USERNAME"]
        user_vars[:home] = Dir.home

        user_vars.compact
      rescue StandardError => e
        { error: "Failed to collect user variables: #{e.message}" }
      end

      # Collect timestamp variables for template generation
      def collect_timestamp_variables
        now = Time.now
        {
          now: format_timestamp(now),
          today: now.strftime("%Y-%m-%d"),
          year: now.year,
          month: now.month,
          day: now.day,
          iso8601: now.iso8601,
          epoch: now.to_i
        }
      end

      # Format timestamp for template display
      def format_timestamp(timestamp)
        return nil unless timestamp
        
        timestamp = Time.parse(timestamp.to_s) unless timestamp.is_a?(Time)
        timestamp.strftime("%Y-%m-%d %H:%M:%S %Z")
      rescue StandardError
        timestamp.to_s
      end

      # Find the git directory for the current context
      def find_git_directory
        candidates = []
        
        # Try project path first
        candidates << @project.path if @project&.path
        
        # Try session path
        candidates << @session.path if @session&.path
        
        # Try current directory
        candidates << Pathname.pwd

        candidates.find { |path| git_repository?(path) }
      end

      # Check if directory is a git repository
      def git_repository?(path)
        return false unless path
        
        path = Pathname.new(path) unless path.is_a?(Pathname)
        (path / ".git").exist? || 
          execute_git_command(path, "rev-parse", "--git-dir") { |output| !output.strip.empty? }
      end

      # Collect git branch information
      def collect_git_branch_info(git_dir)
        branch_info = {}
        
        # Current branch
        execute_git_command(git_dir, "branch", "--show-current") do |output|
          branch_info[:branch] = output.strip
        end
        
        # Remote tracking branch
        execute_git_command(git_dir, "rev-parse", "--abbrev-ref", "@{upstream}") do |output|
          branch_info[:upstream] = output.strip
        end
        
        # Check if working directory is clean
        execute_git_command(git_dir, "status", "--porcelain") do |output|
          branch_info[:clean] = output.strip.empty?
          branch_info[:has_changes] = !output.strip.empty?
        end

        branch_info
      end

      # Collect git author information
      def collect_git_author_info(git_dir)
        author_info = {}
        
        # Author name and email from config
        execute_git_command(git_dir, "config", "user.name") do |output|
          author_info[:author_name] = output.strip
        end
        
        execute_git_command(git_dir, "config", "user.email") do |output|
          author_info[:author_email] = output.strip
        end

        author_info
      end

      # Collect git commit information
      def collect_git_commit_info(git_dir)
        commit_info = {}
        
        # Last commit information
        execute_git_command(git_dir, "log", "-1", "--format=%H|%s|%an|%ae|%ai") do |output|
          parts = output.strip.split("|", 5)
          if parts.length >= 4
            commit_info[:last_commit] = {
              sha: parts[0],
              message: parts[1],
              author_name: parts[2],
              author_email: parts[3],
              date: parts[4]
            }
          end
        end
        
        # Short SHA
        execute_git_command(git_dir, "rev-parse", "--short", "HEAD") do |output|
          commit_info[:short_sha] = output.strip
        end

        commit_info
      end

      # Collect git remote information
      def collect_git_remote_info(git_dir)
        remote_info = {}
        
        # Default remote (usually origin)
        execute_git_command(git_dir, "remote") do |output|
          remotes = output.strip.split("\n")
          remote_info[:remotes] = remotes
          remote_info[:default_remote] = remotes.include?("origin") ? "origin" : remotes.first
        end
        
        # Remote URL
        if remote_info[:default_remote]
          execute_git_command(git_dir, "remote", "get-url", remote_info[:default_remote]) do |output|
            remote_info[:remote_url] = output.strip
          end
        end

        remote_info
      end

      # Collect git status information
      def collect_git_status_info(git_dir)
        status_info = {}
        
        # Count of modified, added, deleted files
        execute_git_command(git_dir, "status", "--porcelain") do |output|
          lines = output.strip.split("\n")
          status_info[:modified_files] = lines.select { |line| line.start_with?(" M", "MM") }.length
          status_info[:added_files] = lines.select { |line| line.start_with?("A ", "AM") }.length
          status_info[:deleted_files] = lines.select { |line| line.start_with?(" D", "AD") }.length
          status_info[:untracked_files] = lines.select { |line| line.start_with?("??") }.length
          status_info[:total_changes] = lines.length
        end

        status_info
      end

      # Collect git user configuration
      def collect_git_user_config
        config = {}
        
        execute_git_command(nil, "config", "--global", "user.name") do |output|
          config[:git_name] = output.strip
        end
        
        execute_git_command(nil, "config", "--global", "user.email") do |output|
          config[:git_email] = output.strip
        end

        config
      end

      # Execute git command with timeout and error handling
      def execute_git_command(directory, *args)
        cmd = ["git"] + args
        options = { timeout: GIT_TIMEOUT }
        options[:chdir] = directory.to_s if directory

        output = ""
        
        begin
          require "open3"
          
          Open3.popen3(*cmd, **options) do |stdin, stdout, stderr, wait_thr|
            stdin.close
            
            # Wait for command with timeout
            if wait_thr.join(GIT_TIMEOUT)
              if wait_thr.value.success?
                output = stdout.read
                yield output if block_given?
              end
            else
              Process.kill("TERM", wait_thr.pid)
            end
          end
        rescue StandardError
          # Silently ignore git command failures - templates should still work
          # even if git information is unavailable
        end

        output
      end

      # Detect project type based on file patterns
      def detect_project_type(project_path)
        return "unknown" unless project_path
        
        path = Pathname.new(project_path)
        
        # Rails detection
        return "rails" if (path / "Gemfile").exist? && 
                         (path / "config" / "application.rb").exist?
        
        # Ruby gem detection
        return "ruby" if (path / "Gemfile").exist? || Dir.glob((path / "*.gemspec").to_s).any?
        
        # Node.js/JavaScript detection
        if (path / "package.json").exist?
          package_json = JSON.parse((path / "package.json").read)
          return "nextjs" if package_json.dig("dependencies", "next")
          return "react" if package_json.dig("dependencies", "react")
          return "typescript" if (path / "tsconfig.json").exist?
          return "javascript"
        end
        
        "unknown"
      rescue StandardError
        "unknown"
      end

      # Collect Rails-specific project information
      def collect_rails_project_info
        rails_info = {}
        
        # Database configuration
        if @project&.path && (Pathname.new(@project.path) / "config" / "database.yml").exist?
          begin
            require "yaml"
            db_config = YAML.load_file(Pathname.new(@project.path) / "config" / "database.yml")
            rails_info[:database] = {
              adapter: db_config.dig("development", "adapter"),
              name: db_config.dig("development", "database")
            }
          rescue StandardError
            # Ignore database config parsing errors
          end
        end
        
        rails_info
      end

      # Collect JavaScript/Node.js project information
      def collect_js_project_info
        js_info = {}
        
        if @project&.path && (Pathname.new(@project.path) / "package.json").exist?
          begin
            package_json = JSON.parse((Pathname.new(@project.path) / "package.json").read)
            js_info[:package_manager] = detect_package_manager
            js_info[:scripts] = package_json["scripts"] || {}
            js_info[:dependencies] = package_json["dependencies"]&.keys || []
            js_info[:dev_dependencies] = package_json["devDependencies"]&.keys || []
          rescue StandardError
            # Ignore package.json parsing errors
          end
        end
        
        js_info
      end

      # Collect Ruby project information
      def collect_ruby_project_info
        ruby_info = {}
        
        if @project&.path && (Pathname.new(@project.path) / "Gemfile").exist?
          # Try to detect bundler version and gems, but don't fail if we can't
          begin
            ruby_info[:bundler_version] = `bundle version`.strip.split.last
          rescue StandardError
            # Ignore bundler detection errors
          end
        end
        
        ruby_info
      end

      # Detect package manager for Node.js projects
      def detect_package_manager
        return "pnpm" if @project&.path && (Pathname.new(@project.path) / "pnpm-lock.yaml").exist?
        return "yarn" if @project&.path && (Pathname.new(@project.path) / "yarn.lock").exist?
        return "npm" if @project&.path && (Pathname.new(@project.path) / "package-lock.json").exist?
        
        "npm" # default
      end

      # Check if Rails is available in the environment
      def rails_available?
        collect_rails_version
        true
      rescue StandardError
        false
      end

      # Collect Rails version information
      def collect_rails_version
        require "rails"
        { version: Rails::VERSION::STRING }
      rescue LoadError
        {}
      end

      # Check if Node.js is available
      def node_available?
        collect_node_version
        true
      rescue StandardError
        false
      end

      # Collect Node.js version information
      def collect_node_version
        output = `node --version 2>/dev/null`.strip
        version = output.gsub(/^v/, "")
        { version: version }
      rescue StandardError
        {}
      end

      # Collect database information
      def collect_database_info
        db_info = {}
        
        # PostgreSQL
        begin
          pg_version = `psql --version 2>/dev/null`.strip
          db_info[:postgresql] = pg_version.split.last if pg_version
        rescue StandardError
          # Ignore PostgreSQL detection errors
        end
        
        # MySQL
        begin
          mysql_version = `mysql --version 2>/dev/null`.strip
          db_info[:mysql] = mysql_version.split.find { |part| part.match(/\d+\.\d+/) } if mysql_version
        rescue StandardError
          # Ignore MySQL detection errors
        end
        
        # SQLite
        begin
          sqlite_version = `sqlite3 --version 2>/dev/null`.strip
          db_info[:sqlite3] = sqlite_version.split.first if sqlite_version
        rescue StandardError
          # Ignore SQLite detection errors
        end
        
        db_info
      end
    end
  end
end

# Add deep_merge helper method to Hash class if not already present
class Hash
  def deep_merge(other_hash)
    self.merge(other_hash) do |key, oldval, newval|
      oldval.is_a?(Hash) && newval.is_a?(Hash) ? oldval.deep_merge(newval) : newval
    end
  end
end