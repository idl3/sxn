# frozen_string_literal: true

require "securerandom"
require "time"

module Sxn
  module Core
    # Manages session lifecycle and operations
    class SessionManager
      def initialize(config_manager = nil)
        @config_manager = config_manager || ConfigManager.new
        @database = initialize_database
      end

      def create_session(name, description: nil, linear_task: nil)
        validate_session_name!(name)
        ensure_sessions_folder_exists!
        
        if session_exists?(name)
          raise Sxn::SessionExistsError, "Session '#{name}' already exists"
        end

        session_id = SecureRandom.uuid
        session_path = File.join(@config_manager.sessions_folder_path, name)
        
        # Create session directory
        FileUtils.mkdir_p(session_path)
        
        # Create session record
        session_data = {
          id: session_id,
          name: name,
          path: session_path,
          created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601,
          status: "active",
          description: description,
          linear_task: linear_task,
          projects: [],
          worktrees: {}
        }
        
        @database.create_session(session_data)
        session_data
      end

      def remove_session(name, force: false)
        session = get_session(name)
        raise Sxn::SessionNotFoundError, "Session '#{name}' not found" unless session

        unless force
          # Check for uncommitted changes in worktrees
          uncommitted_worktrees = find_uncommitted_worktrees(session)
          unless uncommitted_worktrees.empty?
            raise Sxn::SessionHasChangesError, 
                  "Session has uncommitted changes in: #{uncommitted_worktrees.join(", ")}"
          end
        end

        # Remove worktrees first
        remove_session_worktrees(session)
        
        # Remove session directory
        FileUtils.rm_rf(session[:path]) if File.exist?(session[:path])
        
        # Remove from database
        @database.delete_session(session[:id])
        
        # Clear current session if it was this one
        if @config_manager.current_session == name
          @config_manager.update_current_session(nil)
        end
        
        true
      end

      def list_sessions(status: nil, limit: 100)
        filters = {}
        filters[:status] = status if status
        sessions = @database.list_sessions(filters: filters, limit: limit)
        sessions.map { |s| format_session_data(s) }
      end

      def get_session(name)
        session = @database.get_session_by_name(name)
        session ? format_session_data(session) : nil
      end

      def use_session(name)
        session = get_session(name)
        raise Sxn::SessionNotFoundError, "Session '#{name}' not found" unless session

        @config_manager.update_current_session(name)
        
        # Update session status to active
        update_session_status(session[:id], "active")
        
        session
      end

      def current_session
        current_name = @config_manager.current_session
        return nil unless current_name
        
        get_session(current_name)
      end

      def session_exists?(name)
        !get_session(name).nil?
      end

      def add_worktree_to_session(session_name, project_name, worktree_path, branch)
        session = get_session(session_name)
        raise Sxn::SessionNotFoundError, "Session '#{session_name}' not found" unless session

        # Update session metadata
        session_data = @database.get_session_by_id(session[:id])
        worktrees = session_data[:worktrees] || {}
        worktrees[project_name] = {
          path: worktree_path,
          branch: branch,
          created_at: Time.now.iso8601
        }

        projects = session_data[:projects] || []
        projects << project_name unless projects.include?(project_name)

        @database.update_session(session[:id], {
          worktrees: worktrees,
          projects: projects.uniq,
          updated_at: Time.now.iso8601
        })
      end

      def remove_worktree_from_session(session_name, project_name)
        session = get_session(session_name)
        raise Sxn::SessionNotFoundError, "Session '#{session_name}' not found" unless session

        session_data = @database.get_session_by_id(session[:id])
        worktrees = session_data[:worktrees] || {}
        worktrees.delete(project_name)

        projects = session_data[:projects] || []
        projects.delete(project_name)

        @database.update_session(session[:id], {
          worktrees: worktrees,
          projects: projects,
          updated_at: Time.now.iso8601
        })
      end

      def get_session_worktrees(session_name)
        session = get_session(session_name)
        return {} unless session

        session_data = @database.get_session_by_id(session[:id])
        session_data[:worktrees] || {}
      end

      def archive_session(name)
        update_session_status_by_name(name, "archived")
      end

      def activate_session(name)
        update_session_status_by_name(name, "active")
      end

      private

      def initialize_database
        unless @config_manager.initialized?
          raise Sxn::ConfigurationError, "Project not initialized. Run 'sxn init' first."
        end
        
        db_path = File.join(File.dirname(@config_manager.config_path), "sessions.db")
        Sxn::Database::SessionDatabase.new(db_path)
      end

      def validate_session_name!(name)
        unless name.match?(/\A[a-zA-Z0-9_-]+\z/)
          raise Sxn::InvalidSessionNameError, 
                "Session name must contain only letters, numbers, hyphens, and underscores"
        end
      end

      def ensure_sessions_folder_exists!
        sessions_folder = @config_manager.sessions_folder_path
        unless sessions_folder
          raise Sxn::ConfigurationError, "Sessions folder not configured"
        end

        FileUtils.mkdir_p(sessions_folder) unless File.exist?(sessions_folder)
      end

      def format_session_data(db_row)
        metadata = db_row[:metadata] || {}
        
        {
          id: db_row[:id],
          name: db_row[:name],
          path: File.join(@config_manager.sessions_folder_path, db_row[:name]),
          created_at: db_row[:created_at],
          updated_at: db_row[:updated_at],
          status: db_row[:status],
          description: metadata["description"],
          linear_task: metadata["linear_task"],
          projects: metadata["projects"] || [],
          worktrees: metadata["worktrees"] || {}
        }
      end

      def update_session_status(session_id, status)
        @database.update_session(session_id, { 
          status: status, 
          updated_at: Time.now.iso8601 
        })
      end

      def update_session_status_by_name(name, status)
        session = get_session(name)
        raise Sxn::SessionNotFoundError, "Session '#{name}' not found" unless session
        
        update_session_status(session[:id], status)
      end

      def find_uncommitted_worktrees(session)
        worktrees = session[:worktrees] || {}
        uncommitted = []

        worktrees.each do |project, worktree_info|
          path = worktree_info[:path] || worktree_info["path"]
          next unless File.directory?(path)

          begin
            Dir.chdir(path) do
              # Check for staged changes
              staged = !system("git diff-index --quiet --cached HEAD", out: File::NULL, err: File::NULL)
              # Check for unstaged changes
              unstaged = !system("git diff-files --quiet", out: File::NULL, err: File::NULL)
              # Check for untracked files
              untracked = !system("git ls-files --others --exclude-standard --quiet", out: File::NULL, err: File::NULL)

              uncommitted << project if staged || unstaged || untracked
            end
          rescue => e
            # If we can't check git status, assume it has changes to be safe
            uncommitted << project
          end
        end

        uncommitted
      end

      def remove_session_worktrees(session)
        worktrees = session[:worktrees] || {}
        
        worktrees.each do |project, worktree_info|
          path = worktree_info[:path] || worktree_info["path"]
          next unless File.directory?(path)

          begin
            # Remove git worktree
            parent_repo = find_parent_repository(path)
            if parent_repo
              Dir.chdir(parent_repo) do
                system("git worktree remove #{Shellwords.escape(path)}", 
                       out: File::NULL, err: File::NULL)
              end
            end
          rescue => e
            # Log error but continue with removal
            warn "Warning: Could not cleanly remove git worktree for #{project}: #{e.message}"
          end

          # Remove directory if it still exists
          FileUtils.rm_rf(path) if File.exist?(path)
        end
      end

      def find_parent_repository(worktree_path)
        # Try to find the parent repository by looking for .git/worktrees reference
        git_file = File.join(worktree_path, ".git")
        return nil unless File.exist?(git_file)

        content = File.read(git_file).strip
        if content.start_with?("gitdir:")
          git_dir = content.sub(/^gitdir:\s*/, "")
          # Extract parent repo from worktrees path
          if git_dir.include?("/worktrees/")
            git_dir.split("/worktrees/").first
          end
        end
      rescue
        nil
      end
    end
  end
end