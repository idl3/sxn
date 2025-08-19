# frozen_string_literal: true

require "json"
require "fileutils"
require "digest"

module Sxn
  module Config
    # Caches discovered configurations with TTL and file change invalidation
    #
    # Features:
    # - Time-based cache expiration (TTL)
    # - File modification time checking for cache invalidation
    # - Atomic cache file operations
    # - Cache storage in .sxn/.cache/config.json
    class ConfigCache
      CACHE_DIR = ".sxn/.cache"
      CACHE_FILE = "config.json"
      DEFAULT_TTL = 300 # 5 minutes in seconds

      attr_reader :cache_dir, :cache_file_path, :ttl

      def initialize(cache_dir: nil, ttl: DEFAULT_TTL)
        @cache_dir = cache_dir || File.join(Dir.pwd, CACHE_DIR)
        @cache_file_path = File.join(@cache_dir, CACHE_FILE)
        @ttl = ttl
        @write_mutex = Mutex.new
        ensure_cache_directory
      end

      # Get cached configuration or nil if invalid/missing
      # @param config_files [Array<String>] List of config file paths to check
      # @return [Hash, nil] Cached configuration or nil
      def get(config_files)
        return nil unless cache_exists?

        cache_data = load_cache
        return nil unless cache_data

        return nil unless cache_valid?(cache_data, config_files)

        cache_data["config"]
      rescue StandardError => e
        warn "Warning: Failed to load cache: #{e.message}"
        nil
      end

      # Store configuration in cache
      # @param config [Hash] Configuration to cache
      # @param config_files [Array<String>] List of config file paths
      # @return [Boolean] Success status
      def set(config, config_files)
        cache_data = {
          "config" => config,
          "cached_at" => Time.now.to_f,
          "config_files" => build_file_metadata(config_files),
          "cache_version" => 1
        }

        save_cache(cache_data)
        true
      rescue StandardError => e
        warn "Warning: Failed to save cache: #{e.message}"
        false
      end

      # Invalidate the cache by removing the cache file
      # @return [Boolean] Success status
      def invalidate
        return true unless cache_exists?

        File.delete(cache_file_path)
        true
      rescue StandardError => e
        warn "Warning: Failed to invalidate cache: #{e.message}"
        false
      end

      # Check if cache is valid without loading the full configuration
      # @param config_files [Array<String>] List of config file paths to check
      # @return [Boolean] True if cache is valid
      def valid?(config_files)
        return false unless cache_exists?

        cache_data = load_cache
        return false unless cache_data

        cache_valid?(cache_data, config_files)
      rescue StandardError
        false
      end

      # Get cache statistics
      # @param config_files [Array<String>] List of config file paths to check validity against
      # @return [Hash] Cache statistics
      def stats(config_files = [])
        return { exists: false, valid: false } unless cache_exists?

        cache_data = load_cache
        return { exists: true, valid: false, invalid: true } unless cache_data

        is_valid = cache_valid?(cache_data, config_files || [])

        {
          exists: true,
          valid: is_valid,
          cached_at: Time.at(cache_data["cached_at"]),
          age_seconds: Time.now.to_f - cache_data["cached_at"],
          file_count: cache_data["config_files"]&.length || 0,
          cache_version: cache_data["cache_version"]
        }
      rescue StandardError
        { exists: true, valid: false, invalid: true, error: true }
      end

      private

      # Ensure cache directory exists
      def ensure_cache_directory
        return if Dir.exist?(cache_dir)

        # Thread-safe directory creation
        FileUtils.mkdir_p(cache_dir)
      rescue SystemCallError
        # Directory might have been created by another thread/process
        # Only re-raise if directory still doesn't exist
        raise unless Dir.exist?(cache_dir)
      end

      # Check if cache file exists
      # @return [Boolean] True if cache file exists
      def cache_exists?
        File.exist?(cache_file_path)
      end

      # Load cache data from file
      # @return [Hash, nil] Cache data or nil if invalid
      def load_cache
        return nil unless cache_exists?

        content = File.read(cache_file_path)
        JSON.parse(content)
      rescue JSON::ParserError => e
        warn "Warning: Invalid cache file JSON: #{e.message}"
        nil
      end

      # Save cache data to file atomically
      # @param cache_data [Hash] Cache data to save
      def save_cache(cache_data)
        @write_mutex.synchronize do
          # Ensure cache directory exists before any file operations
          ensure_cache_directory

          # Use a more unique temp file name to avoid collisions
          temp_file = "#{cache_file_path}.#{Process.pid}.#{Thread.current.object_id}.tmp"

          begin
            File.write(temp_file, JSON.pretty_generate(cache_data))
          rescue SystemCallError => e
            # Directory might have been removed, recreate and retry once
            ensure_cache_directory
            begin
              File.write(temp_file, JSON.pretty_generate(cache_data))
            rescue SystemCallError
              # If still failing, give up gracefully
              warn "Warning: Failed to write cache: #{e.message}"
              return false
            end
          end

          # Retry logic for rename operation in case of race conditions
          retries = 0
          begin
            # Ensure the cache directory still exists before rename
            ensure_cache_directory

            # Use atomic rename with proper error handling
            File.rename(temp_file, cache_file_path)
          rescue Errno::ENOENT
            retries += 1
            return false unless retries <= 3

            # Directory or temp file might have issues, recreate and retry
            ensure_cache_directory

            # If temp file is missing, recreate it
            unless File.exist?(temp_file)
              begin
                File.write(temp_file, JSON.pretty_generate(cache_data))
              rescue SystemCallError
                # Can't recreate, give up
                return false
              end
            end

            retry

          # Give up after 3 retries, but don't crash - caching is optional
          # Don't warn here as it's expected in concurrent scenarios
          rescue SystemCallError
            # Handle other system errors gracefully - don't warn as it's expected
            return false
          ensure
            # Clean up temp file if it exists
            FileUtils.rm_f(temp_file) if temp_file && File.exist?(temp_file)
          end

          true
        end
      end

      # Check if cache is still valid
      # @param cache_data [Hash] Loaded cache data
      # @param config_files [Array<String>] Current config file paths
      # @return [Boolean] True if cache is valid
      def cache_valid?(cache_data, config_files)
        # Check TTL expiration
        return false if ttl_expired?(cache_data)

        # Check if any config files have changed
        return false if files_changed?(cache_data, config_files)

        true
      end

      # Check if cache has expired based on TTL
      # @param cache_data [Hash] Cache data
      # @return [Boolean] True if cache has expired
      def ttl_expired?(cache_data)
        cached_at = cache_data["cached_at"]
        return true unless cached_at

        Time.now.to_f - cached_at > ttl
      end

      # Check if any config files have changed
      # @param cache_data [Hash] Cache data
      # @param config_files [Array<String>] Current config file paths
      # @return [Boolean] True if files have changed
      def files_changed?(cache_data, config_files)
        cached_files = cache_data["config_files"] || {}
        current_files = build_file_metadata(config_files)

        # Quick check: different number of files
        return true if cached_files.keys.sort != current_files.keys.sort

        # Check each file's metadata
        current_files.each do |file_path, metadata|
          cached_metadata = cached_files[file_path]
          return true unless cached_metadata

          # Check if mtime or size changed
          return true if metadata["mtime"] != cached_metadata["mtime"]
          return true if metadata["size"] != cached_metadata["size"]

          # Always check checksum for content changes (most reliable method)
          return true if metadata["checksum"] != cached_metadata["checksum"]
        end

        false
      end

      # Build metadata for config files
      # @param config_files [Array<String>] List of config file paths
      # @return [Hash] File metadata hash
      def build_file_metadata(config_files)
        metadata = {}

        config_files.each do |file_path|
          next unless File.exist?(file_path)

          stat = File.stat(file_path)
          metadata[file_path] = {
            "mtime" => stat.mtime.to_f,
            "size" => stat.size,
            "checksum" => file_checksum(file_path)
          }
        end

        metadata
      end

      # Calculate file checksum for additional validation
      # @param file_path [String] Path to file
      # @return [String] SHA256 checksum
      def file_checksum(file_path)
        Digest::SHA256.file(file_path).hexdigest
      rescue StandardError
        # If we can't read the file, use a placeholder
        "unreadable"
      end
    end
  end
end
