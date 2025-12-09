# frozen_string_literal: true

require "securerandom"
require "time"
require "shellwords"

module Sxn
  module Core
    # Manages session lifecycle and operations
    class SessionManager
      def initialize(config_manager = nil)
        @config_manager = config_manager || ConfigManager.new
        @database = initialize_database
      end

      def create_session(name, description: nil, linear_task: nil, default_branch: nil)
        validate_session_name!(name)
        ensure_sessions_folder_exists!

        raise Sxn::SessionAlreadyExistsError, "Session '#{name}' already exists" if session_exists?(name)

        session_id = SecureRandom.uuid
        session_path = File.join(@config_manager.sessions_folder_path, name)
        branch = default_branch || name

        # Create session directory
        FileUtils.mkdir_p(session_path)

        # Create .sxnrc configuration file
        session_config = SessionConfig.new(session_path)
        session_config.create(
          parent_sxn_path: @config_manager.sxn_folder_path,
          default_branch: branch,
          session_name: name
        )

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
          default_branch: branch,
          projects: [],
          worktrees: {}
        }

        @database.create_session(session_data)
        session_data
      rescue Sxn::Database::DuplicateSessionError => e
        raise Sxn::SessionAlreadyExistsError, e.message
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
        FileUtils.rm_rf(session[:path])

        # Remove from database
        @database.delete_session(session[:id])

        # Clear current session if it was this one
        @config_manager.update_current_session(nil) if @config_manager.current_session == name

        true
      end

      def list_sessions(status: nil, limit: 100, filters: nil, **options)
        # Support both the filters parameter and individual status parameter
        filter_hash = filters || {}
        filter_hash[:status] = status if status

        # Merge any other options
        filter_hash.merge!(options) if options.any?

        sessions = @database.list_sessions(filters: filter_hash, limit: limit)
        sessions.map { |s| format_session_data(s) }
      end

      def get_session(name)
        session = @database.get_session_by_name(name)
        session ? format_session_data(session) : nil
      rescue Sxn::Database::SessionNotFoundError
        nil
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
                                   projects: projects.uniq
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
                                   projects: projects
                                 })
      end

      def get_session_worktrees(session_name)
        session = get_session(session_name)
        return {} unless session

        session_data = @database.get_session_by_id(session[:id])
        session_data[:worktrees] || {}
      end

      def get_session_default_branch(session_name)
        session = get_session(session_name)
        return nil unless session

        # Read from .sxnrc file in session directory
        session_config = SessionConfig.new(session[:path])
        session_config.default_branch
      end

      def archive_session(name)
        update_session_status_by_name(name, "archived")
        true
      end

      def activate_session(name)
        update_session_status_by_name(name, "active")
        true
      end

      def cleanup_old_sessions(days_old = 30)
        cutoff_date = Time.now.utc - (days_old * 24 * 60 * 60)
        old_sessions = @database.list_sessions.select do |session|
          session_time = Time.parse(session[:updated_at]).utc
          session_time < cutoff_date
        rescue ArgumentError
          # If we can't parse the time, err on the side of caution and don't delete
          false
        end

        old_sessions.each do |session|
          remove_session(session[:name], force: true)
        end

        old_sessions.length
      end

      private

      def initialize_database
        raise Sxn::ConfigurationError, "Project not initialized. Run 'sxn init' first." unless @config_manager.initialized?

        db_path = File.join(File.dirname(@config_manager.config_path), "sessions.db")
        Sxn::Database::SessionDatabase.new(db_path)
      end

      def validate_session_name!(name)
        return if name.match?(/\A[a-zA-Z0-9_-]+\z/)

        raise Sxn::InvalidSessionNameError,
              "Session name must contain only letters, numbers, hyphens, and underscores"
      end

      def ensure_sessions_folder_exists!
        sessions_folder = @config_manager.sessions_folder_path
        raise Sxn::ConfigurationError, "Sessions folder not configured" unless sessions_folder

        FileUtils.mkdir_p(sessions_folder)
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
          description: metadata["description"] || db_row[:description],
          linear_task: metadata["linear_task"] || db_row[:linear_task],
          default_branch: metadata["default_branch"] || db_row[:default_branch],
          # Support both metadata and database columns for backward compatibility
          projects: db_row[:projects] || metadata["projects"] || [],
          worktrees: db_row[:worktrees] || metadata["worktrees"] || {}
        }
      end

      def update_session_status(session_id, status, **additional_options)
        updates = { status: status }

        # Put additional options into metadata if provided
        if additional_options.any?
          current_session = @database.get_session(session_id)
          current_metadata = current_session[:metadata] || {}
          updates[:metadata] = current_metadata.merge(additional_options)
        end

        @database.update_session(session_id, updates)
      end

      def update_session_status_by_name(name, status, **additional_options)
        session = get_session(name)
        raise Sxn::SessionNotFoundError, "Session '#{name}' not found" unless session

        updates = { status: status }

        # Put additional options into metadata if provided
        if additional_options.any?
          current_session = @database.get_session(session[:id])
          current_metadata = current_session[:metadata] || {}
          updates[:metadata] = current_metadata.merge(additional_options)
        end

        @database.update_session(session[:id], updates)
      end

      def find_uncommitted_worktrees(session)
        worktrees = session[:worktrees] || {}
        uncommitted = []

        worktrees.each do |project, worktree_info|
          path = worktree_info[:path] || worktree_info["path"]

          # If directory doesn't exist, skip it (not uncommitted, just missing)
          next unless File.directory?(path)

          begin
            Dir.chdir(path) do
              # Check for staged changes
              staged = !system("git diff-index --quiet --cached HEAD", out: File::NULL, err: File::NULL)
              # Check for unstaged changes
              unstaged = !system("git diff-files --quiet", out: File::NULL, err: File::NULL)
              # Check for untracked files
              untracked_output = `git ls-files --others --exclude-standard 2>/dev/null`
              untracked = !untracked_output.empty?

              uncommitted << project if staged || unstaged || untracked
            end
          rescue StandardError
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
                success = system("git worktree remove #{Shellwords.escape(path)}",
                                 out: File::NULL, err: File::NULL)
                warn "Warning: Could not cleanly remove git worktree for #{project}: git command failed" unless success
              end
            end
          rescue StandardError => e
            # Log error but continue with removal
            warn "Warning: Could not cleanly remove git worktree for #{project}: #{e.message}"
          end

          # Remove directory if it still exists
          FileUtils.rm_rf(path)
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
          git_dir.split("/worktrees/").first if git_dir.include?("/worktrees/")
        end
      rescue StandardError
        nil
      end
    end
  end
end
