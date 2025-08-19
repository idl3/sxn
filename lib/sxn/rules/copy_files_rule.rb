# frozen_string_literal: true

require_relative "base_rule"
require_relative "../security/secure_file_copier"

module Sxn
  module Rules
    # CopyFilesRule handles secure copying and linking of files from the project root
    # to the session directory. It uses the SecureFileCopier from the security layer
    # to ensure safe file operations with proper permission handling and optional encryption.
    #
    # Configuration format:
    # {
    #   "files" => [
    #     {
    #       "source" => "config/master.key",
    #       "destination" => "config/master.key",  # optional, defaults to source
    #       "strategy" => "copy",                  # or "symlink"
    #       "permissions" => "0600",               # optional, uses secure defaults
    #       "encrypt" => false,                    # optional, default false
    #       "required" => true                     # optional, default true
    #     }
    #   ]
    # }
    #
    # @example Basic usage
    #   rule = CopyFilesRule.new(
    #     "copy_secrets",
    #     {
    #       "files" => [
    #         { "source" => "config/master.key", "strategy" => "copy" },
    #         { "source" => ".env", "strategy" => "symlink" }
    #       ]
    #     },
    #     "/path/to/project",
    #     "/path/to/session"
    #   )
    #   rule.validate
    #   rule.apply
    #
    class CopyFilesRule < BaseRule
      # Supported file operation strategies
      VALID_STRATEGIES = %w[copy symlink].freeze

      # File patterns that should always be encrypted if copied
      REQUIRE_ENCRYPTION_PATTERNS = [
        /master\.key$/,
        /credentials.*\.key$/,
        /\.env\..*key/,
        /auth.*token/i,
        /secret/i
      ].freeze

      # Initialize the copy files rule
      def initialize(name, config, project_path, session_path, dependencies: [])
        super(name, config, project_path, session_path, dependencies: dependencies)
        @file_copier = Security::SecureFileCopier.new(@project_path, logger: logger)
      end

      # Validate the rule configuration
      def validate
        super
      end

      # Apply the file copying operations
      def apply
        change_state!(APPLYING)
        
        begin
          @config["files"].each do |file_config|
            apply_file_operation(file_config)
          end
          
          change_state!(APPLIED)
          log(:info, "Successfully copied #{@config['files'].size} files")
          true
        rescue => e
          @errors << e
          change_state!(FAILED)
          raise ApplicationError, "Failed to copy files: #{e.message}"
        end
      end

      protected

      # Validate rule-specific configuration
      def validate_rule_specific!
        unless @config.key?("files")
          raise ValidationError, "CopyFilesRule requires 'files' configuration"
        end

        unless @config["files"].is_a?(Array)
          raise ValidationError, "CopyFilesRule 'files' must be an array"
        end

        if @config["files"].empty?
          raise ValidationError, "CopyFilesRule 'files' cannot be empty"
        end

        @config["files"].each_with_index do |file_config, index|
          validate_file_config!(file_config, index)
        end
      end

      private

      # Validate individual file configuration
      def validate_file_config!(file_config, index)
        unless file_config.is_a?(Hash)
          raise ValidationError, "File config #{index} must be a hash"
        end

        unless file_config.key?("source") && file_config["source"].is_a?(String)
          raise ValidationError, "File config #{index} must have a 'source' string"
        end

        if file_config.key?("strategy")
          strategy = file_config["strategy"]
          unless VALID_STRATEGIES.include?(strategy)
            raise ValidationError, "File config #{index} has invalid strategy '#{strategy}'. Valid: #{VALID_STRATEGIES.join(', ')}"
          end
        end

        if file_config.key?("permissions")
          permissions = file_config["permissions"]
          unless valid_permissions?(permissions)
            raise ValidationError, "File config #{index} has invalid permissions '#{permissions}'"
          end
        end

        # Validate that source file exists if required
        source_path = File.join(@project_path, file_config["source"])
        required = file_config.fetch("required", true)
        
        if required && !File.exist?(source_path)
          raise ValidationError, "Required source file does not exist: #{file_config['source']}"
        end

        # Warn about potentially dangerous operations
        if file_config["strategy"] == "symlink" && file_config["encrypt"]
          log(:warn, "File config #{index}: encryption is not supported with symlink strategy")
        end
      end

      # Check if permissions string is valid
      def valid_permissions?(permissions)
        case permissions
        when String
          # Support octal string format like "0600" or "600"
          permissions.match?(/\A0?[0-7]{3}\z/)
        when Integer
          # Support integer format
          permissions >= 0 && permissions <= 0o777
        else
          false
        end
      end

      # Convert permissions to integer format
      def normalize_permissions(permissions)
        case permissions
        when String
          permissions.to_i(8) # Parse as octal
        when Integer
          permissions
        else
          nil
        end
      end

      # Apply a single file operation
      def apply_file_operation(file_config)
        source = file_config["source"]
        destination = file_config.fetch("destination", source)
        strategy = file_config.fetch("strategy", "copy")
        required = file_config.fetch("required", true)
        
        source_path = File.join(@project_path, source)
        destination_path = File.join(@session_path, destination)

        # Skip if source doesn't exist and is not required
        unless File.exist?(source_path)
          if required
            raise ApplicationError, "Required source file does not exist: #{source}"
          else
            log(:debug, "Skipping optional missing file: #{source}")
            return
          end
        end

        log(:debug, "Applying #{strategy} operation: #{source} -> #{destination}")

        case strategy
        when "copy"
          apply_copy_operation(source_path, destination_path, file_config)
        when "symlink"
          apply_symlink_operation(source_path, destination_path, file_config)
        else
          raise ApplicationError, "Unknown strategy: #{strategy}"
        end
      end

      # Apply a copy operation
      def apply_copy_operation(source_path, destination_path, file_config)
        options = build_copy_options(file_config)
        
        # Check if file should be encrypted
        if should_encrypt_file?(source_path, file_config)
          options[:encrypt] = true
          log(:info, "Encrypting sensitive file: #{source_path}")
        end

        result = @file_copier.copy_file(
          relative_path(source_path),
          relative_path(destination_path),
          **options
        )

        track_change(:file_created, destination_path, {
          source: source_path,
          strategy: "copy",
          encrypted: result.encrypted,
          checksum: result.checksum
        })

        log(:debug, "File copied successfully", result.to_h)
      end

      # Apply a symlink operation
      def apply_symlink_operation(source_path, destination_path, file_config)
        result = @file_copier.create_symlink(
          relative_path(source_path),
          relative_path(destination_path),
          force: true
        )

        track_change(:symlink_created, destination_path, {
          source: source_path,
          strategy: "symlink"
        })

        log(:debug, "Symlink created successfully", result.to_h)
      end

      # Build options hash for file copying
      def build_copy_options(file_config)
        options = {}

        if file_config.key?("permissions")
          options[:permissions] = normalize_permissions(file_config["permissions"])
        end

        if file_config.key?("encrypt")
          options[:encrypt] = file_config["encrypt"]
        end

        options[:preserve_permissions] = file_config.fetch("preserve_permissions", false)
        options[:create_directories] = file_config.fetch("create_directories", true)

        options
      end

      # Check if a file should be encrypted based on patterns and configuration
      def should_encrypt_file?(file_path, file_config)
        # Explicit configuration takes precedence
        return file_config["encrypt"] if file_config.key?("encrypt")

        # Check if file matches patterns requiring encryption
        relative_file_path = relative_path(file_path)
        sensitive = @file_copier.sensitive_file?(relative_file_path)
        
        if sensitive
          log(:debug, "File matches sensitive pattern: #{relative_file_path}")
        end

        sensitive
      end

      # Convert absolute path to relative path from project root
      def relative_path(absolute_path)
        Pathname.new(absolute_path).relative_path_from(Pathname.new(@project_path)).to_s
      end
    end
  end
end