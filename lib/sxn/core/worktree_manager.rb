# frozen_string_literal: true

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

        # Check if worktree already exists in this session
        existing_worktrees = @session_manager.get_session_worktrees(session_name)
        if existing_worktrees[project_name]
          raise Sxn::WorktreeExistsError, 
                "Worktree for '#{project_name}' already exists in session '#{session_name}'"
        end

        # Create worktree path
        worktree_path = File.join(session[:path], project_name)

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
        rescue => e
          # Clean up on failure
          FileUtils.rm_rf(worktree_path) if File.exist?(worktree_path)
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
        raise Sxn::WorktreeNotFoundError, "Worktree for '#{project_name}' not found in session '#{session_name}'" unless worktree_info

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
        rescue => e
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

      def validate_worktree(project_name, session_name: nil)
        worktree = get_worktree(project_name, session_name: session_name)
        return { valid: false, issues: ["Worktree not found"] } unless worktree

        issues = []
        
        # Check if directory exists
        unless File.directory?(worktree[:path])
          issues << "Worktree directory does not exist: #{worktree[:path]}"
        end
        
        # Check if it's a valid git worktree
        unless valid_git_worktree?(worktree[:path])
          issues << "Directory is not a valid git worktree"
        end
        
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
          
          if branch_exists
            # Branch exists, create worktree from existing branch
            cmd = ["git", "worktree", "add", worktree_path, branch]
          else
            # Branch doesn't exist, create new branch
            cmd = ["git", "worktree", "add", "-b", branch, worktree_path]
          end
          
          success = system(*cmd, out: File::NULL, err: File::NULL)
          raise "Git worktree command failed" unless success
        end
      end

      def remove_git_worktree(project_path, worktree_path)
        Dir.chdir(project_path) do
          # Remove worktree
          cmd = ["git", "worktree", "remove", "--force", worktree_path]
          system(*cmd, out: File::NULL, err: File::NULL)
        end
        
        # Clean up directory if it still exists
        FileUtils.rm_rf(worktree_path) if File.exist?(worktree_path)
      end

      def remove_git_worktree_by_path(worktree_path)
        # Try to find parent repository from .git file
        git_file = File.join(worktree_path, ".git")
        if File.exist?(git_file)
          content = File.read(git_file).strip
          if content.start_with?("gitdir:")
            git_dir = content.sub(/^gitdir:\s*/, "")
            parent_repo = git_dir.split("/worktrees/").first if git_dir.include?("/worktrees/")
            
            if parent_repo && File.directory?(parent_repo)
              Dir.chdir(parent_repo) do
                cmd = ["git", "worktree", "remove", "--force", worktree_path]
                system(*cmd, out: File::NULL, err: File::NULL)
              end
            end
          end
        end
        
        # Clean up directory
        FileUtils.rm_rf(worktree_path) if File.exist?(worktree_path)
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
      rescue
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
            result = `git symbolic-ref -q HEAD 2>/dev/null`
            if $?.exitstatus != 0
              issues << "Repository is in detached HEAD state"
            end
          end
        rescue => e
          issues << "Error checking git status: #{e.message}"
        end
        
        issues
      end
    end
  end
end