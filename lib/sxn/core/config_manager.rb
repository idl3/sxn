# frozen_string_literal: true

require "fileutils"
require "yaml"
require "pathname"

module Sxn
  module Core
    # Manages configuration initialization and access
    class ConfigManager
      attr_reader :config_path, :sessions_folder

      def initialize(base_path = Dir.pwd)
        @base_path = File.expand_path(base_path)
        @config_path = File.join(@base_path, ".sxn", "config.yml")
        @sessions_folder = nil
        load_config if initialized?
      end

      def initialized?
        File.exist?(@config_path)
      end

      def initialize_project(sessions_folder, force: false)
        if initialized? && !force
          raise Sxn::ConfigurationError, "Project already initialized. Use --force to reinitialize."
        end

        @sessions_folder = File.expand_path(sessions_folder, @base_path)
        
        create_directories
        create_config_file
        setup_database
        
        @sessions_folder
      end

      def get_config
        unless initialized?
          raise Sxn::ConfigurationError, "Project not initialized. Run 'sxn init' first."
        end
        
        discovery = Sxn::Config::ConfigDiscovery.new(@base_path)
        discovery.discover_config
      end

      def update_current_session(session_name)
        config = load_config_file
        config["current_session"] = session_name
        save_config_file(config)
      end

      def current_session
        config = load_config_file
        config["current_session"]
      end

      def sessions_folder_path
        @sessions_folder || (load_config && @sessions_folder)
      end

      def add_project(name, path, type: nil, default_branch: nil)
        config = load_config_file
        config["projects"] ||= {}
        
        # Convert absolute path to relative for portability
        relative_path = Pathname.new(path).relative_path_from(Pathname.new(@base_path)).to_s
        
        config["projects"][name] = {
          "path" => relative_path,
          "type" => type,
          "default_branch" => default_branch || "master"
        }
        
        save_config_file(config)
      end

      def remove_project(name)
        config = load_config_file
        config["projects"]&.delete(name)
        save_config_file(config)
      end

      def list_projects
        config = load_config_file
        projects = config["projects"] || {}
        
        projects.map do |name, details|
          {
            name: name,
            path: File.expand_path(details["path"], @base_path),
            type: details["type"],
            default_branch: details["default_branch"]
          }
        end
      end

      def get_project(name)
        projects = list_projects
        projects.find { |p| p[:name] == name }
      end

      def detect_projects
        detector = Sxn::Rules::ProjectDetector.new(@base_path)
        
        Dir.glob("*", base: @base_path).filter_map do |entry|
          path = File.join(@base_path, entry)
          next unless File.directory?(path)
          next if entry.start_with?(".")
          
          type = detector.detect_type(path)
          next if type == :unknown
          
          {
            name: entry,
            path: path,
            type: type.to_s
          }
        end
      end

      private

      def load_config
        return unless initialized?
        
        config = load_config_file
        @sessions_folder = File.expand_path(config["sessions_folder"], @base_path)
      end

      def load_config_file
        YAML.safe_load(File.read(@config_path)) || {}
      rescue Psych::SyntaxError => e
        raise Sxn::ConfigurationError, "Invalid configuration file: #{e.message}"
      end

      def save_config_file(config)
        File.write(@config_path, YAML.dump(config))
      end

      def create_directories
        sxn_dir = File.dirname(@config_path)
        FileUtils.mkdir_p(sxn_dir)
        FileUtils.mkdir_p(@sessions_folder)
        FileUtils.mkdir_p(File.join(sxn_dir, "cache"))
        FileUtils.mkdir_p(File.join(sxn_dir, "templates"))
      end

      def create_config_file
        relative_sessions = Pathname.new(@sessions_folder).relative_path_from(Pathname.new(@base_path)).to_s
        
        default_config = {
          "version" => 1,
          "sessions_folder" => relative_sessions,
          "current_session" => nil,
          "projects" => {},
          "settings" => {
            "auto_cleanup" => true,
            "max_sessions" => 10,
            "worktree_cleanup_days" => 30
          }
        }
        
        save_config_file(default_config)
      end

      def setup_database
        db_path = File.join(File.dirname(@config_path), "sessions.db")
        Sxn::Database::SessionDatabase.new(db_path)
      end
    end
  end
end