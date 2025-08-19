# frozen_string_literal: true

require "pathname"

module Sxn
  module Security
    # SecurePathValidator provides security controls for file system path operations.
    # It prevents directory traversal attacks, validates paths stay within project boundaries,
    # checks for dangerous symlinks, and ensures no ".." components in paths.
    #
    # @example
    #   validator = SecurePathValidator.new("/path/to/project")
    #   validator.validate_path("config/database.yml")  # => "/path/to/project/config/database.yml"
    #   validator.validate_path("../etc/passwd")        # => raises PathValidationError
    #
    class SecurePathValidator
      # @param project_root [String] The absolute path to the project root directory
      # @raise [ArgumentError] if project_root is nil, empty, or not an absolute path
      def initialize(project_root)
        raise ArgumentError, "Project root cannot be nil or empty" if project_root.nil? || project_root.empty?

        # Resolve relative paths to absolute paths
        absolute_root = if Pathname.new(project_root).absolute?
                          project_root
                        else
                          File.expand_path(project_root)
                        end

        @project_root = File.realpath(absolute_root)
        @project_root_pathname = Pathname.new(@project_root)
      rescue Errno::ENOENT
        raise PathValidationError, "Project root does not exist: #{project_root}"
      end

      # Validates that a path is safe and within project boundaries
      #
      # @param path [String] The path to validate (can be relative or absolute)
      # @param allow_creation [Boolean] Whether to allow validation of non-existent paths
      # @return [String] The absolute, validated path
      # @raise [PathValidationError] if the path is unsafe or outside project boundaries
      def validate_path(path, allow_creation: false)
        raise ArgumentError, "Path cannot be nil or empty" if path.nil? || (path.respond_to?(:empty?) && path.empty?)
        raise ArgumentError, "Path must be a string" unless path.is_a?(String)

        # Check for dangerous patterns in the raw path
        validate_path_components!(path)

        # Convert to absolute path relative to project root
        absolute_path = if Pathname.new(path).absolute?
                          path
                        else
                          File.join(@project_root, path)
                        end

        # Normalize the path and check boundaries
        normalized_path = if File.exist?(absolute_path)
                            File.realpath(absolute_path)
                          elsif allow_creation
                            # For non-existent paths, we need to validate the normalized path manually
                            normalize_path_manually(absolute_path)
                          else
                            # If file doesn't exist and creation isn't allowed, use realpath which will fail
                            File.realpath(absolute_path)
                          end

        validate_within_boundaries!(normalized_path)
        validate_symlink_safety!(normalized_path) if File.exist?(normalized_path)

        normalized_path
      end

      # Validates a source and destination pair for file operations
      #
      # @param source [String] The source path
      # @param destination [String] The destination path
      # @param allow_creation [Boolean] Whether to allow validation of non-existent destination
      # @return [Array<String>] Array containing [validated_source, validated_destination]
      # @raise [PathValidationError] if either path is unsafe
      def validate_file_operation(source, destination, allow_creation: true)
        validated_source = validate_path(source, allow_creation: false)
        validated_destination = validate_path(destination, allow_creation: allow_creation)

        # Additional checks for file operations
        raise PathValidationError, "Source cannot be a directory: #{source}" if File.exist?(validated_source) && File.directory?(validated_source)

        [validated_source, validated_destination]
      end

      # Checks if a path is within the project boundaries without full validation
      #
      # @param path [String] The path to check
      # @return [Boolean] true if the path appears to be within boundaries
      def within_boundaries?(path)
        return false if path.nil? || path.empty?

        begin
          validate_path(path, allow_creation: true)
          true
        rescue PathValidationError
          false
        end
      end

      # Returns the project root path
      #
      # @return [String] The absolute project root path
      attr_reader :project_root

      private

      # Validates individual path components for dangerous patterns
      def validate_path_components!(path)
        # Check for null bytes (directory traversal in some filesystems)
        if path.include?("\x00")
          # Also check if it contains directory traversal
          if path.include?("../") || path.include?("..\\") || path.include?("..")
            raise PathValidationError, "Path contains directory traversal sequences: #{path}"
          end

          raise PathValidationError, "Path contains null bytes: #{path}"

        end

        # Check for obvious directory traversal attempts
        if path.include?("../") || path.include?("..\\") || path == ".."
          raise PathValidationError, "Path contains directory traversal sequences: #{path}"
        end

        # Check for other dangerous patterns
        dangerous_patterns = [
          %r{/\.\.(?:/|\z)},     # /../ or /.. at end
          %r{\A\.\.(?:/|\z)},    # ../ or .. at start
          %r{//+} # multiple slashes (potential bypass)
        ]

        dangerous_patterns.each do |pattern|
          raise PathValidationError, "Path contains dangerous pattern: #{path}" if path.match?(pattern)
        end
      end

      # Validates that a normalized path is within project boundaries
      def validate_within_boundaries!(absolute_path)
        absolute_pathname = Pathname.new(absolute_path)

        # Check if the path is under the project root
        begin
          relative_path = absolute_pathname.relative_path_from(@project_root_pathname)

          # relative_path_from raises ArgumentError if paths don't share a common ancestor
          # Additional check: ensure the relative path doesn't start with ../
          if relative_path.to_s.start_with?("../") || relative_path.to_s == ".."
            raise PathValidationError, "Path is outside project boundaries: #{absolute_path}"
          end
        rescue ArgumentError
          # This means the paths don't share a common ancestor
          raise PathValidationError, "Path is outside project boundaries: #{absolute_path}"
        end
      end

      # Validates symlink safety to prevent symlink attacks
      def validate_symlink_safety!(path)
        # Convert path to Pathname for manipulation
        pathname = Pathname.new(path)

        # For absolute paths, we need to check each component from the path itself
        # For relative paths, build from project root
        if pathname.absolute?
          # Ensure both paths are resolved consistently to avoid symlink resolution issues
          resolved_path = File.exist?(path) ? File.realpath(path) : path
          resolved_pathname = Pathname.new(resolved_path)
          project_root_pathname = Pathname.new(@project_root)

          # Make path relative to project root to get the components to check
          begin
            relative_path = resolved_pathname.relative_path_from(project_root_pathname)
            path_parts = relative_path.each_filename.to_a
            current_path = Pathname.new(@project_root)
          rescue ArgumentError
            # Path is not within project boundaries, but this should have been caught earlier
            raise PathValidationError, "Path is outside project boundaries: #{path}"
          end
        else
          # For relative paths, use them directly
          path_parts = pathname.each_filename.to_a
          current_path = Pathname.new(@project_root)
        end

        path_parts.each do |part|
          current_path = current_path.join(part)

          next unless current_path.symlink?

          target = current_path.readlink

          # If symlink target is absolute, validate it
          if target.absolute?
            # Resolve absolute symlink targets to handle symlink chains
            resolved_absolute = File.exist?(target.to_s) ? File.realpath(target.to_s) : target.to_s
            validate_within_boundaries!(resolved_absolute)
          else
            # If relative, resolve relative to symlink location and validate
            resolved_target = current_path.dirname.join(target).cleanpath
            # Ensure consistent path resolution by using realpath if the target exists
            final_target = File.exist?(resolved_target.to_s) ? File.realpath(resolved_target.to_s) : resolved_target.to_s
            validate_within_boundaries!(final_target)
          end
        end
      end

      # Manually normalize a path without requiring it to exist
      def normalize_path_manually(path)
        # Convert to Pathname for easier manipulation
        pathname = Pathname.new(path)

        # Special check for the dangerous traversal case we need to catch:
        # Paths like "/a/../../../etc/passwd" where we have more .. than directories to back out of

        # First, let's check the cleaned path to see if it results in something that goes outside the root
        cleaned = pathname.cleanpath

        # For absolute paths, check for dangerous traversal patterns
        if pathname.absolute?
          # Use cleanpath first to see what the path actually resolves to
          cleaned = pathname.cleanpath

          # If cleanpath results in going to parent of root, check if it's truly dangerous
          if cleaned.to_s == "/"
            # This is fine - just resolves to root
          else
            # Now simulate the original path resolution to detect dangerous traversal
            parts = path.split(File::SEPARATOR).reject { |p| p.empty? || p == "." }
            stack = []
            exceeded_root = false

            parts.each do |part|
              if part == ".."
                if stack.empty?
                  # This would go above root, track it
                  exceeded_root = true
                else
                  stack.pop
                end
              else
                stack << part
              end
            end

            # Only raise error if we exceeded root AND there are still meaningful path components
            raise PathValidationError, "path traversal detected: #{path}" if exceeded_root && !stack.empty?
          end
        end

        # For all paths, use cleanpath for the actual normalization
        cleaned.to_s
      end
    end
  end
end
