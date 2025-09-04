# frozen_string_literal: true

require "English"
require "shellwords"
require "fileutils"

module Sxn
  module Core
    # Manages git worktree operations
    class WorktreeManager
      def initialize(config_manager = nil, session_manager = nil)
        @config_manager = config_manager || ConfigManager.new
        @session_manager = session_manager || SessionManager.new(@config_manager)
        @project_manager = ProjectManager.new(@config_manager)
      end

      def add_worktree(project_name, branch = nil, session_name: nil)
        # Use current session if not specified
        session_name ||= @config_manager.current_session
        raise Sxn::NoActiveSessionError, "No active session. Use 'sxn use <session>' first." unless session_name

        session = @session_manager.get_session(session_name)
        raise Sxn::SessionNotFoundError, "Session '#{session_name}' not found" unless session

        project = @project_manager.get_project(project_name)
        raise Sxn::ProjectNotFoundError, "Project '#{project_name}' not found" unless project

        # Use default branch if not specified
        branch ||= project[:default_branch] || "master"
        
        if ENV["SXN_DEBUG"]
          puts "[DEBUG] Adding worktree:"
          puts "  Project: #{project_name}"
          puts "  Project path: #{project[:path]}"
          puts "  Session: #{session_name}"
          puts "  Session path: #{session[:path]}"
          puts "  Branch: #{branch}"
        end

        # Check if worktree already exists in this session
        existing_worktrees = @session_manager.get_session_worktrees(session_name)
        if existing_worktrees[project_name]
          raise Sxn::WorktreeExistsError,
                "Worktree for '#{project_name}' already exists in session '#{session_name}'"
        end

        # Create worktree path
        worktree_path = File.join(session[:path], project_name)
        
        if ENV["SXN_DEBUG"]
          puts "  Worktree path: #{worktree_path}"
        end

        begin
          # Create the worktree
          create_git_worktree(project[:path], worktree_path, branch)

          # Register worktree with session
          @session_manager.add_worktree_to_session(session_name, project_name, worktree_path, branch)

          {
            project: project_name,
            branch: branch,
            path: worktree_path,
            session: session_name
          }
        rescue StandardError => e
          # Clean up on failure
          FileUtils.rm_rf(worktree_path)
          raise Sxn::WorktreeCreationError, "Failed to create worktree: #{e.message}"
        end
      end

      def remove_worktree(project_name, session_name: nil)
        # Use current session if not specified
        session_name ||= @config_manager.current_session
        raise Sxn::NoActiveSessionError, "No active session. Use 'sxn use <session>' first." unless session_name

        session = @session_manager.get_session(session_name)
        raise Sxn::SessionNotFoundError, "Session '#{session_name}' not found" unless session

        worktrees = @session_manager.get_session_worktrees(session_name)
        worktree_info = worktrees[project_name]
        unless worktree_info
          raise Sxn::WorktreeNotFoundError,
                "Worktree for '#{project_name}' not found in session '#{session_name}'"
        end

        worktree_path = worktree_info[:path] || worktree_info["path"]

        begin
          # Remove git worktree
          project = @project_manager.get_project(project_name)
          if project
            remove_git_worktree(project[:path], worktree_path)
          else
            # Project might have been removed, try to find parent repo
            remove_git_worktree_by_path(worktree_path)
          end

          # Remove from session
          @session_manager.remove_worktree_from_session(session_name, project_name)

          true
        rescue StandardError => e
          raise Sxn::WorktreeRemovalError, "Failed to remove worktree: #{e.message}"
        end
      end

      def list_worktrees(session_name: nil)
        # Use current session if not specified
        session_name ||= @config_manager.current_session
        return [] unless session_name

        session = @session_manager.get_session(session_name)
        return [] unless session

        worktrees_data = @session_manager.get_session_worktrees(session_name)

        worktrees_data.map do |project_name, worktree_info|
          {
            project: project_name,
            branch: worktree_info[:branch] || worktree_info["branch"],
            path: worktree_info[:path] || worktree_info["path"],
            created_at: worktree_info[:created_at] || worktree_info["created_at"],
            exists: File.directory?(worktree_info[:path] || worktree_info["path"]),
            status: get_worktree_status(worktree_info[:path] || worktree_info["path"])
          }
        end
      end

      def get_worktree(project_name, session_name: nil)
        worktrees = list_worktrees(session_name: session_name)
        worktrees.find { |w| w[:project] == project_name }
      end

      # Check if a worktree exists for a project
      def worktree_exists?(project_name, session_name: nil)
        get_worktree(project_name, session_name: session_name) != nil
      end

      # Get the path to a worktree for a project
      def worktree_path(project_name, session_name: nil)
        worktree = get_worktree(project_name, session_name: session_name)
        worktree&.fetch(:path, nil)
      end

      # Validate worktree name (expected by tests)
      def validate_worktree_name(name)
        return true if name.match?(/\A[a-zA-Z0-9_-]+\z/)

        raise Sxn::WorktreeError, "Invalid worktree name: #{name}"
      end

      # Execute git command (mock point for tests)
      def execute_git_command(*)
        system(*)
      end

      def validate_worktree(project_name, session_name: nil)
        worktree = get_worktree(project_name, session_name: session_name)
        return { valid: false, issues: ["Worktree not found"] } unless worktree

        issues = []

        # Check if directory exists
        issues << "Worktree directory does not exist: #{worktree[:path]}" unless File.directory?(worktree[:path])

        # Check if it's a valid git worktree
        issues << "Directory is not a valid git worktree" unless valid_git_worktree?(worktree[:path])

        # Check for git issues
        git_issues = check_git_status(worktree[:path])
        issues.concat(git_issues)

        {
          valid: issues.empty?,
          issues: issues,
          worktree: worktree
        }
      end

      private

      def create_git_worktree(project_path, worktree_path, branch)
        Dir.chdir(project_path) do
          # Check if branch exists
          branch_exists = system("git show-ref --verify --quiet refs/heads/#{Shellwords.escape(branch)}",
                                 out: File::NULL, err: File::NULL)

          cmd = if branch_exists
                  # Branch exists, create worktree from existing branch
                  ["git", "worktree", "add", worktree_path, branch]
                else
                  # Branch doesn't exist, create new branch
                  ["git", "worktree", "add", "-b", branch, worktree_path]
                end

          # Capture stderr for better error messages
          require 'open3'
          stdout, stderr, status = Open3.capture3(*cmd)
          
          unless status.success?
            error_msg = stderr.empty? ? stdout : stderr
            error_msg = "Git worktree command failed" if error_msg.strip.empty?
            
            # Add more context to common errors
            if error_msg.include?("already exists")
              error_msg += "\nTry removing the existing worktree first with: sxn worktree remove #{File.basename(worktree_path)}"
            elsif error_msg.include?("is already checked out")
              error_msg += "\nThis branch is already checked out in another worktree"
            elsif error_msg.include?("not a git repository")
              error_msg = "Project '#{File.basename(project_path)}' is not a git repository"
            elsif error_msg.include?("fatal: invalid reference")
              # This typically means the branch doesn't exist and we're trying to create from a non-existent base
              error_msg += "\nMake sure the repository has at least one commit or specify an existing branch"
            elsif error_msg.include?("fatal:")
              # Extract just the fatal error message for cleaner output
              error_msg = error_msg.lines.grep(/fatal:/).first&.strip || error_msg
            end
            
            if ENV["SXN_DEBUG"]
              puts "[DEBUG] Git worktree command failed:"
              puts "  Command: #{cmd.join(' ')}"
              puts "  Directory: #{project_path}"
              puts "  STDOUT: #{stdout}"
              puts "  STDERR: #{stderr}"
            end
            
            raise error_msg
          end
        end
      end

      def remove_git_worktree(project_path, worktree_path)
        Dir.chdir(project_path) do
          # Remove worktree
          cmd = ["git", "worktree", "remove", "--force", worktree_path]
          system(*cmd, out: File::NULL, err: File::NULL)
        end

        # Clean up directory if it still exists
        FileUtils.rm_rf(worktree_path)
      end

      def remove_git_worktree_by_path(worktree_path)
        # Try to find parent repository from .git file
        git_file = File.join(worktree_path, ".git")
        if File.exist?(git_file)
          content = File.read(git_file).strip
          if content.start_with?("gitdir:")
            git_dir = content.sub(/^gitdir:\s*/, "")
            parent_repo = git_dir.split("/worktrees/").first if git_dir.include?("/worktrees/")

            # Ensure parent_repo is a valid absolute path and the directory exists
            if parent_repo && File.absolute_path?(parent_repo) && File.directory?(parent_repo)
              begin
                Dir.chdir(parent_repo) do
                  cmd = ["git", "worktree", "remove", "--force", worktree_path]
                  system(*cmd, out: File::NULL, err: File::NULL)
                end
              rescue Errno::ENOENT
                # Directory doesn't exist or can't be accessed, skip git command
              end
            end
          end
        end

        # Clean up directory
        FileUtils.rm_rf(worktree_path)
      end

      def get_worktree_status(path)
        return "missing" unless File.directory?(path)
        return "invalid" unless valid_git_worktree?(path)

        Dir.chdir(path) do
          # Check for staged changes
          staged = !system("git diff-index --quiet --cached HEAD", out: File::NULL, err: File::NULL)
          return "staged" if staged

          # Check for unstaged changes
          unstaged = !system("git diff-files --quiet", out: File::NULL, err: File::NULL)
          return "modified" if unstaged

          # Check for untracked files
          untracked = !system("git ls-files --others --exclude-standard --quiet", out: File::NULL, err: File::NULL)
          return "untracked" if untracked

          "clean"
        end
      rescue StandardError
        "error"
      end

      def valid_git_worktree?(path)
        File.exist?(File.join(path, ".git"))
      end

      def check_git_status(path)
        return ["Directory does not exist"] unless File.directory?(path)
        return ["Not a git repository"] unless valid_git_worktree?(path)

        issues = []

        begin
          Dir.chdir(path) do
            # Check if we can access git status
            unless system("git status --porcelain", out: File::NULL, err: File::NULL)
              issues << "Cannot access git status (possible repository corruption)"
            end

            # Check for detached HEAD
            `git symbolic-ref -q HEAD 2>/dev/null`
            issues << "Repository is in detached HEAD state" if $CHILD_STATUS.exitstatus != 0
          end
        rescue StandardError => e
          issues << "Error checking git status: #{e.message}"
        end

        issues
      end
    end
  end
end
