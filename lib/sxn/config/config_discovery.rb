# frozen_string_literal: true

require 'yaml'
require 'pathname'

module Sxn
  module Config
    # Handles hierarchical configuration discovery and loading
    #
    # Configuration precedence (highest to lowest):
    # 1. Command-line flags
    # 2. Environment variables (SXN_*)
    # 3. Local project config (.sxn/config.yml)
    # 4. Workspace config (.sxn-workspace/config.yml)
    # 5. Global user config (~/.sxn/config.yml)
    # 6. System defaults
    class ConfigDiscovery
      CONFIG_FILE_NAME = 'config.yml'
      LOCAL_CONFIG_DIR = '.sxn'
      WORKSPACE_CONFIG_DIR = '.sxn-workspace'
      GLOBAL_CONFIG_DIR = File.expand_path('~/.sxn')
      ENV_PREFIX = 'SXN_'

      attr_reader :start_directory

      def initialize(start_directory = Dir.pwd)
        @start_directory = Pathname.new(start_directory).expand_path
      end

      # Discover and load configuration from all sources
      # @param cli_options [Hash] Command-line options
      # @return [Hash] Merged configuration
      def discover_config(cli_options = {})
        config_sources = load_all_configs
        merge_configs(config_sources, cli_options)
      end

      # Find all configuration files in the hierarchy
      # @return [Array<String>] Paths to configuration files
      def find_config_files
        config_files = []
        
        # Local project config (.sxn/config.yml)
        local_config = find_local_config
        config_files << local_config if local_config

        # Workspace config (.sxn-workspace/config.yml)
        workspace_config = find_workspace_config
        config_files << workspace_config if workspace_config

        # Global user config (~/.sxn/config.yml)
        global_config = find_global_config
        config_files << global_config if global_config

        config_files
      end

      private

      # Load configurations from all sources
      # @return [Hash] Hash of config sources
      def load_all_configs
        {
          system_defaults: load_system_defaults,
          global_config: load_global_config,
          workspace_config: load_workspace_config,
          local_config: load_local_config,
          env_config: load_env_config
        }
      end

      # Find local project config by walking up directory tree
      # @return [String, nil] Path to local config file
      def find_local_config
        current_dir = start_directory
        
        loop do
          config_path = current_dir.join(LOCAL_CONFIG_DIR, CONFIG_FILE_NAME)
          return config_path.to_s if config_path.exist?
          
          parent = current_dir.parent
          break if parent == current_dir # Reached filesystem root
          current_dir = parent
        end
        
        nil
      end

      # Find workspace config by walking up directory tree
      # @return [String, nil] Path to workspace config file
      def find_workspace_config
        current_dir = start_directory
        
        loop do
          config_path = current_dir.join(WORKSPACE_CONFIG_DIR, CONFIG_FILE_NAME)
          return config_path.to_s if config_path.exist?
          
          parent = current_dir.parent
          break if parent == current_dir # Reached filesystem root
          current_dir = parent
        end
        
        nil
      end

      # Find global user config
      # @return [String, nil] Path to global config file
      def find_global_config
        global_config_path = File.join(GLOBAL_CONFIG_DIR, CONFIG_FILE_NAME)
        File.exist?(global_config_path) ? global_config_path : nil
      end

      # Load system default configuration
      # @return [Hash] Default configuration
      def load_system_defaults
        {
          'version' => 1,
          'sessions_folder' => '.sessions',
          'current_session' => nil,
          'projects' => {},
          'settings' => {
            'auto_cleanup' => true,
            'max_sessions' => 10,
            'worktree_cleanup_days' => 30,
            'default_rules' => {
              'templates' => []
            }
          }
        }
      end

      # Load global user configuration
      # @return [Hash] Global configuration
      def load_global_config
        config_path = find_global_config
        return {} unless config_path

        load_yaml_file(config_path)
      rescue => e
        warn "Warning: Failed to load global config #{config_path}: #{e.message}"
        {}
      end

      # Load workspace configuration
      # @return [Hash] Workspace configuration
      def load_workspace_config
        config_path = find_workspace_config
        return {} unless config_path

        load_yaml_file(config_path)
      rescue => e
        warn "Warning: Failed to load workspace config #{config_path}: #{e.message}"
        {}
      end

      # Load local project configuration
      # @return [Hash] Local configuration
      def load_local_config
        config_path = find_local_config
        return {} unless config_path

        load_yaml_file(config_path)
      rescue => e
        warn "Warning: Failed to load local config #{config_path}: #{e.message}"
        {}
      end

      # Load environment variable configuration
      # @return [Hash] Environment configuration
      def load_env_config
        env_config = {}
        
        ENV.each do |key, value|
          next unless key.start_with?(ENV_PREFIX)
          
          # Convert SXN_SESSIONS_FOLDER to sessions_folder
          config_key = key[ENV_PREFIX.length..-1].downcase
          
          # Parse boolean values
          parsed_value = case value.downcase
                        when 'true' then true
                        when 'false' then false
                        else value
                        end
          
          env_config[config_key] = parsed_value
        end
        
        env_config
      end

      # Load and parse YAML file safely
      # @param file_path [String] Path to YAML file
      # @return [Hash] Parsed YAML content
      def load_yaml_file(file_path)
        content = File.read(file_path)
        YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
      rescue Psych::SyntaxError => e
        raise ConfigurationError, "Invalid YAML in #{file_path}: #{e.message}"
      rescue => e
        raise ConfigurationError, "Failed to load config file #{file_path}: #{e.message}"
      end

      # Merge configurations with proper precedence
      # @param configs [Hash] Hash of configuration sources
      # @param cli_options [Hash] Command-line options
      # @return [Hash] Merged configuration
      def merge_configs(configs, cli_options)
        # Start with system defaults and merge up the precedence chain
        result = configs[:system_defaults].dup
        
        # Deep merge each config level
        deep_merge!(result, configs[:global_config])
        deep_merge!(result, configs[:workspace_config]) 
        deep_merge!(result, configs[:local_config])
        deep_merge!(result, configs[:env_config])
        deep_merge!(result, cli_options)
        
        result
      end

      # Deep merge configuration hashes
      # @param target [Hash] Target hash to merge into
      # @param source [Hash] Source hash to merge from
      def deep_merge!(target, source)
        return target unless source.is_a?(Hash)
        
        source.each do |key, value|
          if target[key].is_a?(Hash) && value.is_a?(Hash)
            deep_merge!(target[key], value)
          else
            target[key] = value
          end
        end
        
        target
      end
    end
  end
end