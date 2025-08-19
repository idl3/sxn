# frozen_string_literal: true

require_relative 'config/config_discovery'
require_relative 'config/config_cache'
require_relative 'config/config_validator'

module Sxn
  module Config
    # Main configuration manager that integrates discovery, caching, and validation
    #
    # Features:
    # - Hierarchical configuration loading with caching
    # - Configuration validation and migration
    # - Environment variable overrides
    # - Thread-safe configuration access
    class Manager
      DEFAULT_CACHE_TTL = 300 # 5 minutes

      attr_reader :discovery, :cache, :validator, :current_config

      def initialize(start_directory: Dir.pwd, cache_ttl: DEFAULT_CACHE_TTL)
        @discovery = ConfigDiscovery.new(start_directory)
        @cache = ConfigCache.new(ttl: cache_ttl)
        @validator = ConfigValidator.new
        @current_config = nil
        @config_mutex = Mutex.new
      end

      # Get the current configuration with caching
      # @param cli_options [Hash] Command-line options to override
      # @param force_reload [Boolean] Force reload ignoring cache
      # @return [Hash] Merged and validated configuration
      def config(cli_options: {}, force_reload: false)
        @config_mutex.synchronize do
          # Check if we need to reload due to file changes
          if @current_config && !force_reload
            config_files = discovery.find_config_files
            unless cache.valid?(config_files)
              @current_config = nil # Invalidate memory cache
            end
          end
          
          return @current_config if @current_config && !force_reload

          @current_config = load_and_validate_config(cli_options, force_reload)
        end
      end

      # Reload configuration from disk
      # @param cli_options [Hash] Command-line options to override
      # @return [Hash] Reloaded configuration
      def reload(cli_options: {})
        config(cli_options: cli_options, force_reload: true)
      end

      # Get configuration value by key path
      # @param key_path [String] Dot-separated key path (e.g., 'settings.auto_cleanup')
      # @param default [Object] Default value if key not found
      # @return [Object] Configuration value
      def get(key_path, default: nil)
        current_config = config
        keys = key_path.split('.')
        
        keys.reduce(current_config) do |current, key|
          break default unless current.is_a?(Hash) && current.key?(key)
          current[key]
        end
      end

      # Set configuration value by key path (for runtime modifications)
      # @param key_path [String] Dot-separated key path
      # @param value [Object] Value to set
      # @return [Object] The set value
      def set(key_path, value)
        @config_mutex.synchronize do
          # Don't call config() here as it would cause deadlock
          # Get the current config directly if it exists
          current_config = @current_config || load_and_validate_config({}, false)
          keys = key_path.split('.')
          target = keys[0..-2].reduce(current_config) do |current, key|
            current[key] ||= {}
          end
          target[keys.last] = value
          value
        end
      end

      # Check if configuration is valid
      # @param cli_options [Hash] Command-line options to override
      # @return [Boolean] True if configuration is valid
      def valid?(cli_options: {})
        begin
          config(cli_options: cli_options)
          true
        rescue ConfigurationError
          false
        end
      end

      # Get validation errors for current configuration
      # @param cli_options [Hash] Command-line options to override
      # @return [Array<String>] List of validation errors
      def errors(cli_options: {})
        begin
          # Try to load the actual configuration that would be used
          config(cli_options: cli_options)
          [] # If config() succeeds, there are no errors
        rescue ConfigurationError => e
          # Parse the validation errors from the exception message
          error_message = e.message
          if error_message.include?("Configuration validation failed:")
            # Extract the numbered error list
            lines = error_message.split("\n")
            errors = lines[1..-1].map { |line| line.strip.sub(/^\d+\.\s*/, '') }
            errors.reject(&:empty?)
          else
            [e.message]
          end
        rescue => e
          [e.message]
        end
      end

      # Get cache statistics
      # @return [Hash] Cache statistics
      def cache_stats
        config_files = discovery.find_config_files
        cache.stats(config_files).merge(
          config_files: config_files,
          discovery_time: measure_discovery_time
        )
      end

      # Invalidate configuration cache
      # @return [Boolean] Success status
      def invalidate_cache
        @config_mutex.synchronize do
          @current_config = nil
          cache.invalidate
        end
      end

      # Get all configuration file paths in precedence order
      # @return [Array<String>] Configuration file paths
      def config_file_paths
        discovery.find_config_files
      end

      # Get configuration summary for debugging
      # @return [Hash] Configuration debug information
      def debug_info
        config_files = discovery.find_config_files
        
        {
          start_directory: discovery.start_directory.to_s,
          config_files: config_files,
          cache_stats: cache.stats,
          validation_errors: validator.errors,
          environment_variables: discovery.send(:load_env_config),
          discovery_performance: measure_discovery_time
        }
      end

      private

      # Load and validate configuration with caching
      # @param cli_options [Hash] Command-line options
      # @param force_reload [Boolean] Force reload ignoring cache
      # @return [Hash] Validated configuration
      def load_and_validate_config(cli_options, force_reload)
        config_files = discovery.find_config_files
        
        # Try to load from cache first
        unless force_reload
          cached_config = cache.get(config_files)
          if cached_config
            # Still need to merge with CLI options and validate
            merged_config = discovery.send(:deep_merge!, cached_config.dup, cli_options)
            return validator.validate_and_migrate(merged_config)
          end
        end

        # Load fresh configuration
        raw_config = discovery.discover_config(cli_options)
        validated_config = validator.validate_and_migrate(raw_config)
        
        # Cache the configuration (without CLI options)
        cache_config = discovery.discover_config({})
        cache.set(cache_config, config_files)
        
        validated_config
      end

      # Measure discovery time for performance monitoring
      # @return [Float] Discovery time in seconds
      def measure_discovery_time
        start_time = Time.now
        discovery.discover_config({})
        Time.now - start_time
      rescue
        -1.0 # Indicate error
      end
    end

    # Convenience class methods for global access
    class << self
      # Global configuration manager instance
      # @return [Manager] Configuration manager
      def manager
        @manager ||= Manager.new
      end

      # Get configuration value
      # @param key_path [String] Dot-separated key path
      # @param default [Object] Default value
      # @return [Object] Configuration value
      def get(key_path, default: nil)
        manager.get(key_path, default: default)
      end

      # Set configuration value
      # @param key_path [String] Dot-separated key path
      # @param value [Object] Value to set
      # @return [Object] The set value
      def set(key_path, value)
        manager.set(key_path, value)
      end

      # Get current configuration
      # @param cli_options [Hash] Command-line options
      # @return [Hash] Current configuration
      def current(cli_options: {})
        manager.config(cli_options: cli_options)
      end

      # Reload configuration
      # @param cli_options [Hash] Command-line options
      # @return [Hash] Reloaded configuration
      def reload(cli_options: {})
        manager.reload(cli_options: cli_options)
      end

      # Check if configuration is valid
      # @param cli_options [Hash] Command-line options
      # @return [Boolean] True if valid
      def valid?(cli_options: {})
        manager.valid?(cli_options: cli_options)
      end

      # Invalidate cache
      # @return [Boolean] Success status
      def invalidate_cache
        manager.invalidate_cache
      end

      # Reset global manager (for testing)
      def reset!
        @manager = nil
      end
    end
  end
end