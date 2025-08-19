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
        raise ArgumentError, "Path cannot be nil or empty" if path.nil? || path.empty?

        # Check for dangerous patterns in the raw path
        validate_path_components!(path)

        # Convert to absolute path relative to project root
        absolute_path = if Pathname.new(path).absolute?
                          path
                        else
                          File.join(@project_root, path)
                        end

        # Normalize the path and check boundaries
        if File.exist?(absolute_path)
          normalized_path = File.realpath(absolute_path)
        elsif allow_creation
          # For non-existent paths, we need to validate the normalized path manually
          normalized_path = normalize_path_manually(absolute_path)
        else
          # If file doesn't exist and creation isn't allowed, use realpath which will fail
          normalized_path = File.realpath(absolute_path)
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
        if File.exist?(validated_source) && File.directory?(validated_source)
          raise PathValidationError, "Source cannot be a directory: #{source}"
        end

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
        # Check for obvious directory traversal attempts
        if path.include?("../") || path.include?("..\\") || path == ".."
          raise PathValidationError, "Path contains directory traversal sequences: #{path}"
        end

        # Check for null bytes (directory traversal in some filesystems)
        if path.include?("\x00")
          raise PathValidationError, "Path contains null bytes: #{path}"
        end

        # Check for other dangerous patterns
        dangerous_patterns = [
          %r{/\.\.(?:/|\z)},     # /../ or /.. at end
          %r{\A\.\.(?:/|\z)},    # ../ or .. at start
          %r{//+},               # multiple slashes (potential bypass)
        ]

        dangerous_patterns.each do |pattern|
          if path.match?(pattern)
            raise PathValidationError, "Path contains dangerous pattern: #{path}"
          end
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
        # Check if any component in the path is a dangerous symlink
        path_parts = Pathname.new(path).each_filename.to_a
        current_path = Pathname.new(@project_root)

        path_parts.each do |part|
          current_path = current_path.join(part)
          
          if current_path.symlink?
            target = current_path.readlink
            
            # If symlink target is absolute, validate it
            if target.absolute?
              validate_within_boundaries!(target.to_s)
            else
              # If relative, resolve relative to symlink location and validate
              resolved_target = current_path.dirname.join(target).cleanpath
              validate_within_boundaries!(resolved_target.to_s)
            end
          end
        end
      end

      # Manually normalize a path without requiring it to exist
      def normalize_path_manually(path)
        # Convert to Pathname for easier manipulation
        pathname = Pathname.new(path)
        
        # Clean up the path (removes redundant separators, resolves .)
        cleaned = pathname.cleanpath
        
        # Additional manual normalization
        parts = cleaned.to_s.split(File::SEPARATOR)
        normalized_parts = []
        
        parts.each do |part|
          case part
          when ".", ""
            # Skip current directory references and empty parts
            next
          when ".."
            # This should have been caught earlier, but double-check
            if normalized_parts.empty? || normalized_parts.last == ".."
              raise PathValidationError, "Path traversal detected during normalization: #{path}"
            end
            normalized_parts.pop
          else
            normalized_parts << part
          end
        end
        
        # Rebuild the path
        normalized = File.join(*normalized_parts)
        
        # Ensure it starts with / on Unix-like systems if it was absolute
        if pathname.absolute? && !normalized.start_with?(File::SEPARATOR)
          normalized = File::SEPARATOR + normalized
        end
        
        normalized
      end
    end
  end
end