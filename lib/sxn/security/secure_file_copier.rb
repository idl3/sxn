# frozen_string_literal: true

require "fileutils"
require "openssl"
require "base64"

module Sxn
  module Security
    # SecureFileCopier provides secure file copying operations with strict security controls.
    # It validates source and destination paths, preserves/enforces file permissions,
    # supports file encryption using OpenSSL AES-256, and maintains an audit trail.
    #
    # @example
    #   copier = SecureFileCopier.new("/path/to/project")
    #   result = copier.copy_file("config/master.key", "session/master.key",
    #                            permissions: 0600, encrypt: true)
    #
    class SecureFileCopier
      # File operation result
      class CopyResult
        attr_reader :source_path, :destination_path, :operation, :encrypted, :checksum, :duration

        def initialize(source_path, destination_path, operation, encrypted: false, checksum: nil, duration: 0)
          @source_path = source_path
          @destination_path = destination_path
          @operation = operation
          @encrypted = encrypted
          @checksum = checksum
          @duration = duration
        end

        def to_h
          {
            source_path: @source_path,
            destination_path: @destination_path,
            operation: @operation,
            encrypted: @encrypted,
            checksum: @checksum,
            duration: @duration
          }
        end
      end

      # Patterns that identify sensitive files requiring special handling
      SENSITIVE_FILE_PATTERNS = [
        /master\.key$/,
        /credentials.*\.key$/,
        /\.env$/,
        /\.env\./,
        /secrets\.yml$/,
        /\.pem$/,
        /\.p12$/,
        /\.jks$/,
        /\.npmrc$/,
        /auth_token/i,
        /api_key/i,
        /password/i,
        /secret/i
      ].freeze

      # Default secure permissions for different file types
      DEFAULT_PERMISSIONS = {
        sensitive: 0o600,  # Owner read/write only
        config: 0o644,     # Owner read/write, group/other read
        executable: 0o755  # Owner all, group/other read/execute
      }.freeze

      # Maximum file size for operations (100MB)
      MAX_FILE_SIZE = 100 * 1024 * 1024

      # @param project_root [String] The absolute path to the project root directory
      # @param logger [Logger] Optional logger for audit trail
      def initialize(project_root, logger: nil)
        @project_root = File.realpath(project_root)
        @path_validator = SecurePathValidator.new(@project_root)
        @logger = logger || Sxn.logger
        @encryption_key = nil
      rescue Errno::ENOENT
        raise ArgumentError, "Project root does not exist: #{project_root}"
      end

      # Copies a file securely with validation and optional encryption
      #
      # @param source [String] Source file path (relative to project root)
      # @param destination [String] Destination file path (relative to project root)
      # @param permissions [Integer] File permissions to set (e.g., 0600)
      # @param encrypt [Boolean] Whether to encrypt the file
      # @param preserve_permissions [Boolean] Whether to preserve source permissions
      # @param create_directories [Boolean] Whether to create destination directories
      # @return [CopyResult] The operation result
      # @raise [SecurityError] if operation violates security policies
      def copy_file(source, destination, permissions: nil, encrypt: false,
                    preserve_permissions: false, create_directories: true)
        start_time = Time.now

        raw_source, raw_destination = @path_validator.validate_file_operation(
          source, destination, allow_creation: true
        )
        
        # Normalize paths for consistent behavior in tests and cross-platform compatibility
        validated_source = normalize_path_for_result(raw_source)
        validated_destination = normalize_path_for_result(raw_destination)

        validate_file_operation!(raw_source, raw_destination)

        # Determine appropriate permissions (use normalized path for consistent method signatures)
        target_permissions = determine_permissions(
          validated_source, permissions, preserve_permissions
        )

        # Create destination directory if needed (use raw path for actual file operations)
        create_destination_directory(raw_destination) if create_directories

        # Perform the copy operation (use normalized paths for method signatures)
        if encrypt
          copy_with_encryption(validated_source, validated_destination, target_permissions)
          encrypted = true
        else
          copy_without_encryption(validated_source, validated_destination, target_permissions)
          encrypted = false
        end

        # Generate checksum for verification (use normalized path for method signature)
        checksum = generate_checksum(validated_destination)
        duration = Time.now - start_time

        result = CopyResult.new(
          normalize_path_for_result(validated_source), 
          normalize_path_for_result(validated_destination), 
          :copy,
          encrypted: encrypted, checksum: checksum, duration: duration
        )

        audit_log("FILE_COPY", result)
        result
      end

      # Creates a symbolic link securely
      #
      # @param source [String] Source file path (relative to project root)
      # @param destination [String] Link path (relative to project root)
      # @param force [Boolean] Whether to overwrite existing links
      # @return [CopyResult] The operation result
      # @raise [SecurityError] if operation violates security policies
      def create_symlink(source, destination, force: false)
        start_time = Time.now

        validated_source, validated_destination = @path_validator.validate_file_operation(
          source, destination, allow_creation: true
        )

        validate_file_operation!(validated_source, validated_destination)

        # Remove existing symlink/file if force is true
        if force && (File.exist?(validated_destination) || File.symlink?(validated_destination))
          File.unlink(validated_destination)
        end

        # Create the symlink
        File.symlink(validated_source, validated_destination)

        duration = Time.now - start_time
        result = CopyResult.new(
          normalize_path_for_result(validated_source), 
          normalize_path_for_result(validated_destination), 
          :symlink, duration: duration
        )

        audit_log("SYMLINK_CREATE", result)
        result
      end

      # Encrypts a file in place using AES-256-GCM
      #
      # @param file_path [String] Path to file to encrypt (relative to project root)
      # @param key [String] Encryption key (if nil, generates one)
      # @return [String] Base64-encoded encryption key used
      # @raise [SecurityError] if encryption fails
      def encrypt_file(file_path, key: nil)
        raw_path = @path_validator.validate_path(file_path)
        validated_path = normalize_path_for_result(raw_path)
        validate_file_exists!(validated_path)

        encryption_key = key || generate_encryption_key

        # Read original content (use real path for file operations)
        real_path = denormalize_path_for_operations(validated_path)
        original_content = File.binread(real_path)

        # Encrypt content
        encrypted_content = encrypt_content(original_content, encryption_key)

        # Write encrypted content atomically (use real path for file operations)
        temp_file = "#{real_path}.tmp"
        File.binwrite(temp_file, encrypted_content)
        File.rename(temp_file, real_path)

        # Set secure permissions (use real path for file operations)
        File.chmod(0o600, real_path)

        audit_log("FILE_ENCRYPT", { file_path: validated_path })
        Base64.strict_encode64(encryption_key)
      rescue Sxn::PathValidationError => e
        raise SecurityError, "Path validation failed: #{e.message}"
      end

      # Decrypts a file in place using AES-256-GCM
      #
      # @param file_path [String] Path to file to decrypt (relative to project root)
      # @param key [String] Base64-encoded encryption key
      # @return [Boolean] true if decryption successful
      # @raise [SecurityError] if decryption fails
      def decrypt_file(file_path, key)
        raw_path = @path_validator.validate_path(file_path)
        validated_path = normalize_path_for_result(raw_path)
        validate_file_exists!(validated_path)

        encryption_key = Base64.strict_decode64(key)

        # Read encrypted content (use real path for file operations)
        real_path = denormalize_path_for_operations(validated_path)
        encrypted_content = File.binread(real_path)

        # Decrypt content
        original_content = decrypt_content(encrypted_content, encryption_key)

        # Write decrypted content atomically (use real path for file operations)
        temp_file = "#{real_path}.tmp"
        File.binwrite(temp_file, original_content)
        File.rename(temp_file, real_path)

        audit_log("FILE_DECRYPT", { file_path: validated_path })
        true
      rescue StandardError => e
        raise SecurityError, "Decryption failed: #{e.message}"
      end

      # Checks if a file appears to be sensitive based on its path
      #
      # @param file_path [String] Path to check
      # @return [Boolean] true if file appears sensitive
      def sensitive_file?(file_path)
        SENSITIVE_FILE_PATTERNS.any? { |pattern| file_path.match?(pattern) }
      end

      # Validates file permissions are secure
      #
      # @param file_path [String] Path to check (relative to project root)
      # @return [Boolean] true if permissions are secure
      def secure_permissions?(file_path)
        begin
          validated_path = @path_validator.validate_path(file_path, allow_creation: true)
          return false unless File.exist?(validated_path)

          stat = File.stat(validated_path)
          mode = stat.mode & 0o777

          if sensitive_file?(file_path)
            # Sensitive files should not be readable by group/other
            mode.nobits?(0o077)
          else
            # Non-sensitive files should not be world-writable
            mode.nobits?(0o002)
          end
        rescue Sxn::PathValidationError
          false
        end
      end

      private

      # Normalizes a path to remove system-specific symlink resolutions
      # This helps maintain consistent path formats across different systems
      def normalize_path_for_result(path)
        # On macOS, File.realpath resolves /var to /private/var
        # For consistency in tests and results, we normalize back
        path.sub(%r{^/private/var/}, "/var/")
      end

      # Reverses path normalization to get real filesystem paths for operations
      def denormalize_path_for_operations(path)
        # Convert normalized paths back to real filesystem paths
        # On macOS, /var is actually at /private/var
        if path.start_with?("/var/") && !path.start_with?("/private/var/")
          path.sub(%r{^/var/}, "/private/var/")
        else
          path
        end
      end

      # Validates file operation security constraints
      def validate_file_operation!(source_path, destination_path)
        # Check source file exists and is readable
        validate_file_exists!(source_path)
        validate_file_readable!(source_path)

        # Check file size limits
        file_size = File.size(source_path)
        raise SecurityError, "File too large for secure copying: #{file_size} bytes" if file_size > MAX_FILE_SIZE

        # Check if source has dangerous permissions
        if File.world_readable?(source_path) && sensitive_file?(source_path)
          Sxn.logger&.warn("Copying world-readable sensitive file: #{source_path}")
        end

        # Validate destination path doesn't overwrite critical files
        return unless File.exist?(destination_path)

        dest_stat = File.stat(destination_path)
        return unless dest_stat.uid != Process.uid

        raise SecurityError, "Cannot overwrite file owned by different user: #{destination_path}"
      end

      # Determines appropriate file permissions
      def determine_permissions(source_path, explicit_permissions, preserve_permissions)
        return explicit_permissions if explicit_permissions

        if preserve_permissions
          File.stat(source_path).mode & 0o777
        elsif sensitive_file?(source_path)
          DEFAULT_PERMISSIONS[:sensitive]
        elsif File.executable?(source_path)
          DEFAULT_PERMISSIONS[:executable]
        else
          DEFAULT_PERMISSIONS[:config]
        end
      end

      # Creates destination directory with secure permissions
      def create_destination_directory(destination_path)
        directory = File.dirname(destination_path)
        return if File.directory?(directory)

        # For absolute paths under project root, convert to relative
        if directory.start_with?(@project_root)
          relative_directory = directory.sub(@project_root + "/", "")
          # Only validate if it's actually relative (not just the project root itself)
          @path_validator.validate_path(relative_directory, allow_creation: true) unless relative_directory.empty?
        end

        # Create directory with secure permissions
        FileUtils.mkdir_p(directory, mode: 0o755)
      end

      # Copies file without encryption
      def copy_without_encryption(source_path, destination_path, permissions)
        # Resolve paths back to real filesystem paths for actual operations
        real_source = denormalize_path_for_operations(source_path)
        real_destination = denormalize_path_for_operations(destination_path)
        
        # Use atomic copy operation
        temp_file = "#{real_destination}.tmp"

        begin
          FileUtils.cp(real_source, temp_file, preserve: false)
          File.chmod(permissions, temp_file)
          File.rename(temp_file, real_destination)
        rescue StandardError => e
          FileUtils.rm_f(temp_file)
          raise SecurityError, "File copy failed: #{e.message}"
        end
      end

      # Copies file with encryption
      def copy_with_encryption(source_path, destination_path, permissions)
        # Resolve paths back to real filesystem paths for actual operations
        real_source = denormalize_path_for_operations(source_path)
        real_destination = denormalize_path_for_operations(destination_path)
        
        @encryption_key ||= generate_encryption_key

        # Read and encrypt content
        original_content = File.binread(real_source)
        encrypted_content = encrypt_content(original_content, @encryption_key)

        # Write encrypted content atomically
        temp_file = "#{real_destination}.tmp"

        begin
          File.binwrite(temp_file, encrypted_content)
          File.chmod(permissions, temp_file)
          File.rename(temp_file, real_destination)
        rescue StandardError => e
          FileUtils.rm_f(temp_file)
          raise SecurityError, "Encrypted file copy failed: #{e.message}"
        end
      end

      # Encrypts content using AES-256-GCM
      def encrypt_content(content, key)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = key

        # Generate random IV
        iv = cipher.random_iv
        cipher.iv = iv

        # Encrypt content
        encrypted = cipher.update(content) + cipher.final
        auth_tag = cipher.auth_tag

        # Combine IV, auth tag, and encrypted content
        [iv, auth_tag, encrypted].map { |part| Base64.strict_encode64(part) }.join(":")
      end

      # Decrypts content using AES-256-GCM
      def decrypt_content(encrypted_content, key)
        parts = encrypted_content.split(":")
        raise SecurityError, "Invalid encrypted content format" unless parts.length == 3

        iv, auth_tag, ciphertext = parts.map { |part| Base64.strict_decode64(part) }

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        cipher.iv = iv
        cipher.auth_tag = auth_tag

        cipher.update(ciphertext) + cipher.final
      rescue StandardError => e
        raise SecurityError, "Decryption failed: #{e.message}"
      end

      # Generates a secure encryption key
      def generate_encryption_key
        OpenSSL::Random.random_bytes(32) # 256 bits
      end

      # Generates SHA-256 checksum for file verification
      def generate_checksum(file_path)
        # Resolve path back to real filesystem path for actual operations
        real_path = denormalize_path_for_operations(file_path)
        return nil unless File.exist?(real_path)

        digest = OpenSSL::Digest.new("SHA256")
        File.open(real_path, "rb") do |file|
          while (chunk = file.read(8192))
            digest.update(chunk)
          end
        end
        digest.hexdigest
      end

      # Validation helpers
      def validate_file_exists!(file_path)
        # Use normalized path for error messages but check real path for existence
        real_path = denormalize_path_for_operations(file_path)
        return if File.exist?(real_path)

        raise SecurityError, "Source file does not exist: #{file_path}"
      end

      def validate_file_readable!(file_path)
        # Use normalized path for error messages but check real path for readability
        real_path = denormalize_path_for_operations(file_path)
        return if File.readable?(real_path)

        raise SecurityError, "Source file is not readable: #{file_path}"
      end

      # Logs file operations for audit trail
      def audit_log(event, details)
        return unless @logger

        log_entry = {
          timestamp: Time.now.iso8601,
          event: event,
          pid: Process.pid,
          user: ENV["USER"] || "unknown"
        }

        if details.is_a?(CopyResult)
          log_entry.merge!(details.to_h)
        else
          log_entry.merge!(details)
        end

        @logger.info("SECURITY_AUDIT: #{log_entry.to_json}")
      end
    end
  end
end
