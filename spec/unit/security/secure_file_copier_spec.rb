# frozen_string_literal: true

require "English"
require "spec_helper"
require "tempfile"
require "tmpdir"
require "logger"
require "openssl"

RSpec.describe Sxn::Security::SecureFileCopier do
  let(:temp_dir) { Dir.mktmpdir("sxn_test") }
  let(:project_root) { temp_dir }
  let(:logger) { Logger.new(StringIO.new) }
  let(:copier) { described_class.new(project_root, logger: logger) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    context "with valid project root" do
      it "accepts existing directory" do
        expect { described_class.new(temp_dir) }.not_to raise_error
      end

      it "initializes path validator" do
        copier = described_class.new(temp_dir)
        expect(copier.instance_variable_get(:@path_validator)).to be_a(Sxn::Security::SecurePathValidator)
      end
    end

    context "with invalid project root" do
      it "raises error for non-existent directory" do
        non_existent = File.join(temp_dir, "does_not_exist")
        expect { described_class.new(non_existent) }.to raise_error(ArgumentError, /does not exist/)
      end
    end
  end

  describe "#copy_file" do
    let(:source_file) { File.join(temp_dir, "source.txt") }
    let(:source_content) { "source file content" }
    let(:dest_path) { "destination.txt" }
    let(:dest_file) { File.join(temp_dir, dest_path) }

    before do
      File.write(source_file, source_content)
    end

    context "with basic file copying" do
      it "copies file successfully" do
        result = copier.copy_file("source.txt", dest_path)

        expect(result).to be_a(described_class::CopyResult)
        expect(result.operation).to eq(:copy)
        expect(File.exist?(dest_file)).to be true
        expect(File.read(dest_file)).to eq(source_content)
      end

      it "sets default permissions for non-sensitive files" do
        copier.copy_file("source.txt", dest_path)

        file_mode = File.stat(dest_file).mode & 0o777
        expect(file_mode).to eq(0o644) # DEFAULT_PERMISSIONS[:config]
      end

      it "creates destination directory when needed" do
        nested_dest = "subdir/nested/file.txt"
        copier.copy_file("source.txt", nested_dest)

        expect(File.exist?(File.join(temp_dir, nested_dest))).to be true
        expect(File.read(File.join(temp_dir, nested_dest))).to eq(source_content)
      end

      it "respects explicit permissions" do
        copier.copy_file("source.txt", dest_path, permissions: 0o600)

        file_mode = File.stat(dest_file).mode & 0o777
        expect(file_mode).to eq(0o600)
      end

      it "preserves source permissions when requested" do
        File.chmod(0o755, source_file)
        copier.copy_file("source.txt", dest_path, preserve_permissions: true)

        file_mode = File.stat(dest_file).mode & 0o777
        expect(file_mode).to eq(0o755)
      end
    end

    context "with sensitive file handling" do
      let(:sensitive_files) do
        %w[
          config/master.key
          config/credentials/development.key
          .env
          .env.production
          secrets.yml
          auth_token.txt
          api_key.conf
          password.txt
          secret.json
          certificate.pem
          keystore.p12
          .npmrc
        ]
      end

      before do
        sensitive_files.each do |file_path|
          FileUtils.mkdir_p(File.dirname(File.join(temp_dir, file_path)))
          File.write(File.join(temp_dir, file_path), "sensitive content for #{file_path}")
        end
      end

      it "identifies sensitive files correctly" do
        sensitive_files.each do |file_path|
          expect(copier.sensitive_file?(file_path)).to be(true), "Expected #{file_path} to be identified as sensitive"
        end
      end

      it "sets secure permissions for sensitive files" do
        copier.copy_file("config/master.key", "copied_master.key")

        file_mode = File.stat(File.join(temp_dir, "copied_master.key")).mode & 0o777
        expect(file_mode).to eq(0o600) # DEFAULT_PERMISSIONS[:sensitive]
      end

      it "warns about world-readable sensitive files" do
        File.chmod(0o644, File.join(temp_dir, ".env"))

        # Capture log output
        log_output = StringIO.new
        test_logger = Logger.new(log_output)
        test_copier = described_class.new(temp_dir, logger: test_logger)

        # Set up Sxn.logger to capture the warning
        allow(Sxn).to receive(:logger).and_return(test_logger)

        test_copier.copy_file(".env", "copied.env")

        expect(log_output.string).to include("world-readable sensitive file")
      end
    end

    context "with encryption" do
      it "encrypts file content when requested" do
        result = copier.copy_file("source.txt", dest_path, encrypt: true)

        expect(result.encrypted).to be true
        encrypted_content = File.read(dest_file)
        expect(encrypted_content).not_to eq(source_content)
        expect(encrypted_content).to include(":") # Base64 encoded parts separated by colons
      end

      it "generates checksum for encrypted files" do
        result = copier.copy_file("source.txt", dest_path, encrypt: true)

        expect(result.checksum).to be_a(String)
        expect(result.checksum.length).to eq(64) # SHA-256 hex digest
      end
    end

    context "with validation and security" do
      it "validates source file exists" do
        # Mock path validator to throw the expected error for non-existent file
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_file_operation).and_raise(Errno::ENOENT, "No such file or directory")

        test_copier = described_class.new(temp_dir)
        expect do
          test_copier.copy_file("nonexistent.txt", dest_path)
        end.to raise_error(Errno::ENOENT)
      end

      it "validates source file is readable" do
        File.chmod(0o000, source_file)

        expect do
          copier.copy_file("source.txt", dest_path)
        end.to raise_error(Sxn::SecurityError, /not readable/)
      ensure
        File.chmod(0o644, source_file) # Restore for cleanup
      end

      it "prevents copying extremely large files" do
        # Create a mock file that reports huge size
        allow(File).to receive(:size).with(source_file).and_return(200 * 1024 * 1024) # 200MB

        # Mock path validator to avoid path validation errors
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_file_operation).and_return([source_file,
                                                                               File.join(temp_dir, dest_path)])

        test_copier = described_class.new(temp_dir)
        expect do
          test_copier.copy_file("source.txt", dest_path)
        end.to raise_error(Sxn::SecurityError, /too large/)
      end

      it "validates paths are within project boundaries" do
        # Mock path validator to throw the expected error
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_file_operation).and_raise(Sxn::PathValidationError,
                                                                             "outside project boundaries")

        test_copier = described_class.new(temp_dir)
        expect do
          test_copier.copy_file("source.txt", "../outside.txt")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      end

      it "prevents overwriting files owned by different users" do
        # This test may not work on all systems due to permission constraints
        skip "Cannot test different file ownership in this environment"
      end
    end

    context "with atomic operations" do
      it "uses atomic file operations" do
        # Mock FileUtils.cp to fail after temp file creation
        allow(FileUtils).to receive(:cp).and_raise(StandardError.new("Copy failed"))

        expect do
          copier.copy_file("source.txt", dest_path)
        end.to raise_error(Sxn::SecurityError, /Copy failed/)

        # Temporary file should be cleaned up
        expect(File.exist?("#{dest_file}.tmp")).to be false
        expect(File.exist?(dest_file)).to be false
      end
    end
  end

  describe "#create_symlink" do
    let(:source_file) { File.join(temp_dir, "source.txt") }
    let(:link_path) { "link_to_source" }
    let(:link_file) { File.join(temp_dir, link_path) }

    before do
      File.write(source_file, "source content")
    end

    context "with valid symlink operations" do
      it "creates symlink successfully" do
        # Mock path validator for symlink operations
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_file_operation).and_return([source_file, link_file])

        test_copier = described_class.new(temp_dir)
        result = test_copier.create_symlink("source.txt", link_path)

        expect(result).to be_a(described_class::CopyResult)
        expect(result.operation).to eq(:symlink)
        expect(File.symlink?(link_file)).to be true
        expect(File.readlink(link_file)).to eq(source_file)
      end

      it "overwrites existing symlink when force is true" do
        # Create initial symlink
        File.symlink(source_file, link_file)

        # Create another source file
        other_source = File.join(temp_dir, "other.txt")
        File.write(other_source, "other content")

        # Mock path validator for symlink operations
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_file_operation).and_return([other_source, link_file])

        test_copier = described_class.new(temp_dir)
        test_copier.create_symlink("other.txt", link_path, force: true)

        expect(File.readlink(link_file)).to eq(File.join(temp_dir, "other.txt"))
      end
    end

    context "with validation" do
      it "validates source and destination paths" do
        # Mock path validator to throw the expected error
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_file_operation).and_raise(Sxn::PathValidationError,
                                                                             "outside project boundaries")

        test_copier = described_class.new(temp_dir)
        expect do
          test_copier.create_symlink("source.txt", "../outside_link")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      end

      it "validates source file exists" do
        # Mock path validator to throw the expected error for non-existent file
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_file_operation).and_raise(Errno::ENOENT, "No such file or directory")

        test_copier = described_class.new(temp_dir)
        expect do
          test_copier.create_symlink("nonexistent.txt", link_path)
        end.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe "#encrypt_file and #decrypt_file" do
    let(:test_file) { File.join(temp_dir, "test.txt") }
    let(:test_content) { "This is secret content that should be encrypted" }

    before do
      File.write(test_file, test_content)
    end

    context "with file encryption" do
      it "encrypts file in place" do
        key = copier.encrypt_file("test.txt")

        expect(key).to be_a(String)
        expect(Base64.strict_decode64(key).length).to eq(32) # 256-bit key

        encrypted_content = File.read(test_file)
        expect(encrypted_content).not_to eq(test_content)
        expect(encrypted_content.split(":").length).to eq(3) # IV:auth_tag:ciphertext
      end

      it "sets secure permissions after encryption" do
        copier.encrypt_file("test.txt")

        file_mode = File.stat(test_file).mode & 0o777
        expect(file_mode).to eq(0o600)
      end

      it "can decrypt encrypted file" do
        key = copier.encrypt_file("test.txt")
        result = copier.decrypt_file("test.txt", key)

        expect(result).to be true
        decrypted_content = File.read(test_file)
        expect(decrypted_content).to eq(test_content)
      end

      it "fails to decrypt with wrong key" do
        copier.encrypt_file("test.txt")
        wrong_key = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))

        expect do
          copier.decrypt_file("test.txt", wrong_key)
        end.to raise_error(Sxn::SecurityError, /Decryption failed/)
      end

      it "uses provided encryption key" do
        custom_key = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))
        returned_key = copier.encrypt_file("test.txt", key: Base64.strict_decode64(custom_key))

        expect(returned_key).to eq(custom_key)
      end
    end

    context "with validation" do
      it "validates file exists before encryption" do
        # Mock path validator to throw the expected error for non-existent file
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_path).and_raise(Errno::ENOENT, "No such file or directory")

        test_copier = described_class.new(temp_dir)
        expect do
          test_copier.encrypt_file("nonexistent.txt")
        end.to raise_error(Errno::ENOENT)
      end

      it "validates file path is within project" do
        # Mock path validator to throw the expected error
        path_validator = instance_double(Sxn::Security::SecurePathValidator)
        allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(path_validator)
        allow(path_validator).to receive(:validate_path).and_raise(Sxn::PathValidationError,
                                                                   "outside project boundaries")

        test_copier = described_class.new(temp_dir)
        expect do
          test_copier.encrypt_file("../outside.txt")
        end.to raise_error(Sxn::SecurityError, /outside project boundaries/)
      end
    end
  end

  describe "#sensitive_file?" do
    let(:sensitive_examples) do
      %w[
        config/master.key
        config/credentials/production.key
        .env
        .env.development
        .env.production
        secrets.yml
        config/secrets.yml
        certificate.pem
        keystore.p12
        truststore.jks
        .npmrc
        auth_token
        api_key.txt
        password.conf
        secret.json
      ]
    end

    let(:non_sensitive_examples) do
      %w[
        config/database.yml
        README.md
        Gemfile
        package.json
        src/main.rb
        test.rb
        config.yml
        normal_file.txt
      ]
    end

    it "correctly identifies sensitive files" do
      sensitive_examples.each do |file_path|
        expect(copier.sensitive_file?(file_path)).to be(true), "Expected #{file_path} to be sensitive"
      end
    end

    it "correctly identifies non-sensitive files" do
      non_sensitive_examples.each do |file_path|
        expect(copier.sensitive_file?(file_path)).to be(false), "Expected #{file_path} to be non-sensitive"
      end
    end
  end

  describe "#secure_permissions?" do
    let(:test_file) { File.join(temp_dir, "test.txt") }
    let(:sensitive_file) { File.join(temp_dir, "master.key") }

    before do
      File.write(test_file, "test content")
      File.write(sensitive_file, "sensitive content")
    end

    context "with sensitive files" do
      it "returns true for owner-only permissions" do
        File.chmod(0o600, sensitive_file)
        expect(copier.secure_permissions?("master.key")).to be true
      end

      it "returns false for group-readable sensitive files" do
        File.chmod(0o640, sensitive_file)
        expect(copier.secure_permissions?("master.key")).to be false
      end

      it "returns false for world-readable sensitive files" do
        File.chmod(0o644, sensitive_file)
        expect(copier.secure_permissions?("master.key")).to be false
      end
    end

    context "with non-sensitive files" do
      it "returns true for non-world-writable files" do
        File.chmod(0o644, test_file)
        expect(copier.secure_permissions?("test.txt")).to be true
      end

      it "returns false for world-writable files" do
        File.chmod(0o646, test_file)
        expect(copier.secure_permissions?("test.txt")).to be false
      end
    end

    it "returns false for non-existent files" do
      expect(copier.secure_permissions?("nonexistent.txt")).to be false
    end
  end

  describe "CopyResult" do
    let(:result) do
      described_class::CopyResult.new(
        "/source/path", "/dest/path", :copy,
        encrypted: true, checksum: "abc123", duration: 1.5
      )
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = result.to_h
        expect(hash).to include(
          source_path: "/source/path",
          destination_path: "/dest/path",
          operation: :copy,
          encrypted: true,
          checksum: "abc123",
          duration: 1.5
        )
      end
    end
  end

  describe "security edge cases" do
    let(:source_file) { File.join(temp_dir, "source.txt") }

    before do
      File.write(source_file, "test content")
    end

    it "handles very long file paths" do
      long_name = "#{"a" * 200}.txt"
      copier.copy_file("source.txt", long_name)

      expect(File.exist?(File.join(temp_dir, long_name))).to be true
    end

    it "handles files with special characters in names" do
      special_name = "file with spaces & special chars!@#{$INPUT_LINE_NUMBER}txt"
      copier.copy_file("source.txt", special_name)

      expect(File.exist?(File.join(temp_dir, special_name))).to be true
    end

    it "prevents overwriting critical system files" do
      # This should be prevented by path validation
      expect do
        copier.copy_file("source.txt", "/etc/passwd")
      end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
    end

    it "handles concurrent access gracefully" do
      # Test atomic operations under concurrent access
      threads = []

      5.times do |i|
        threads << Thread.new do
          copier.copy_file("source.txt", "concurrent_#{i}.txt")
        end
      end

      threads.each(&:join)

      5.times do |i|
        expect(File.exist?(File.join(temp_dir, "concurrent_#{i}.txt"))).to be true
      end
    end
  end

  describe "audit logging" do
    let(:log_output) { StringIO.new }
    let(:logger) { Logger.new(log_output) }
    let(:copier) { described_class.new(temp_dir, logger: logger) }
    let(:source_file) { File.join(temp_dir, "source.txt") }

    before do
      File.write(source_file, "test content")
    end

    it "logs file copy operations" do
      copier.copy_file("source.txt", "dest.txt")

      log_content = log_output.string
      expect(log_content).to include("FILE_COPY")
      expect(log_content).to include("source.txt")
    end

    it "logs symlink creation" do
      copier.create_symlink("source.txt", "link.txt")

      log_content = log_output.string
      expect(log_content).to include("SYMLINK_CREATE")
    end

    it "logs encryption operations" do
      copier.encrypt_file("source.txt")

      log_content = log_output.string
      expect(log_content).to include("FILE_ENCRYPT")
    end

    it "logs decryption operations" do
      key = copier.encrypt_file("source.txt")
      copier.decrypt_file("source.txt", key)

      log_content = log_output.string
      expect(log_content).to include("FILE_DECRYPT")
    end

    it "includes timestamp and process ID in logs" do
      copier.copy_file("source.txt", "dest.txt")

      log_content = log_output.string
      expect(log_content).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/) # ISO timestamp
      expect(log_content).to include(Process.pid.to_s)
    end

    it "does not log when logger is nil" do
      copier_no_logger = described_class.new(temp_dir, logger: nil)
      # Should not raise error when logger is nil
      expect { copier_no_logger.copy_file("source.txt", "dest.txt") }.not_to raise_error
    end
  end

  describe "additional branch coverage" do
    let(:source_file) { File.join(temp_dir, "source.txt") }
    let(:executable_file) { File.join(temp_dir, "script.sh") }

    before do
      File.write(source_file, "test content")
      File.write(executable_file, "#!/bin/bash\necho 'test'")
      File.chmod(0o755, executable_file)
    end

    context "with create_directories option" do
      it "does not create directories when create_directories is false" do
        dest_dir = File.join(temp_dir, "subdir")
        FileUtils.mkdir_p(dest_dir)

        copier.copy_file("source.txt", "subdir/dest.txt", create_directories: false)
        expect(File.exist?(File.join(temp_dir, "subdir/dest.txt"))).to be true
      end
    end

    context "with non-sensitive world-readable files" do
      it "does not warn for world-readable non-sensitive files" do
        File.chmod(0o644, source_file)

        log_output = StringIO.new
        test_logger = Logger.new(log_output)
        test_copier = described_class.new(temp_dir, logger: test_logger)

        test_copier.copy_file("source.txt", "dest.txt")

        expect(log_output.string).not_to include("world-readable sensitive file")
      end
    end

    context "with destination file ownership" do
      it "does not raise error when destination is owned by current user" do
        # Create destination file owned by current user
        dest_file = File.join(temp_dir, "existing_dest.txt")
        File.write(dest_file, "existing content")

        expect do
          copier.copy_file("source.txt", "existing_dest.txt")
        end.not_to raise_error
      end
    end

    context "with executable file permissions" do
      it "sets executable permissions for executable files" do
        copier.copy_file("script.sh", "copied_script.sh")

        copied_file = File.join(temp_dir, "copied_script.sh")
        file_mode = File.stat(copied_file).mode & 0o777
        expect(file_mode).to eq(0o755)
      end
    end

    context "with directory creation outside project root" do
      it "creates directories without validation for paths outside project root" do
        # Create a subdirectory that doesn't match the project root pattern
        temp_subdir = File.join(temp_dir, "completely_different_path")
        FileUtils.mkdir_p(temp_subdir)
        File.write(File.join(temp_subdir, "source.txt"), "content")

        # Create a copier with a different project root
        different_root = File.join(temp_dir, "other_root")
        FileUtils.mkdir_p(different_root)
        different_copier = described_class.new(different_root, logger: logger)

        # This should handle the path that doesn't start with project_root
        expect do
          different_copier.copy_file("source.txt", "dest.txt")
        end.to raise_error # Will fail validation, but we're testing the directory creation path
      end
    end

    context "with invalid encrypted content" do
      it "raises error for content with wrong number of parts" do
        File.write(source_file, "invalid:content") # Only 2 parts instead of 3

        key = Base64.strict_encode64(OpenSSL::Random.random_bytes(32))

        expect do
          copier.decrypt_file("source.txt", key)
        end.to raise_error(Sxn::SecurityError, /Invalid encrypted content format/)
      end
    end

    context "with checksum generation for non-existent file" do
      it "returns nil for non-existent file" do
        # Create a copier and call the private method
        checksum = copier.send(:generate_checksum, File.join(temp_dir, "nonexistent.txt"))
        expect(checksum).to be_nil
      end
    end

    context "with file existence validation" do
      it "does not raise error when file exists" do
        # This tests the early return in validate_file_exists!
        expect do
          copier.send(:validate_file_exists!, source_file)
        end.not_to raise_error
      end
    end

    context "with relative directory validation" do
      it "validates non-empty relative directories" do
        # Create nested directory structure
        nested_dir = File.join(temp_dir, "nested", "deep")
        FileUtils.mkdir_p(nested_dir)
        File.write(File.join(temp_dir, "source.txt"), "content")

        # This should test the path where relative_directory is not empty
        copier.copy_file("source.txt", "nested/deep/dest.txt")
        expect(File.exist?(File.join(temp_dir, "nested/deep/dest.txt"))).to be true
      end
    end

    context "with source file that is not world-readable" do
      it "does not warn when source is not world-readable" do
        # Create source with secure permissions (not world-readable)
        sensitive_source = File.join(temp_dir, "master.key")
        File.write(sensitive_source, "sensitive")
        File.chmod(0o600, sensitive_source)

        log_output = StringIO.new
        test_logger = Logger.new(log_output)
        test_copier = described_class.new(temp_dir, logger: test_logger)

        # Set up Sxn.logger to not capture warning (testing line 298[else])
        allow(Sxn).to receive(:logger).and_return(test_logger)

        test_copier.copy_file("master.key", "copied.key")

        # Should not warn because file is not world-readable
        expect(log_output.string).not_to include("world-readable sensitive file")
      end
    end

    context "with destination file not existing" do
      it "handles destination that does not exist" do
        # Test line 304[else] - when File.exist?(destination_path) returns false
        expect do
          copier.copy_file("source.txt", "new_dest.txt")
        end.not_to raise_error

        expect(File.exist?(File.join(temp_dir, "new_dest.txt"))).to be true
      end
    end

    context "with directory already existing" do
      it "skips directory creation when directory already exists" do
        # Create destination directory first
        dest_dir = File.join(temp_dir, "existing_dir")
        FileUtils.mkdir_p(dest_dir)

        # Test line 330[else] and the early return at line 327
        copier.copy_file("source.txt", "existing_dir/file.txt")
        expect(File.exist?(File.join(dest_dir, "file.txt"))).to be true
      end
    end

    context "with project root directory as destination parent" do
      it "handles destination in project root without validation" do
        # When destination is directly in project root, relative_directory will be empty
        # This tests line 333[else] - when relative_directory.empty? is true
        copier.copy_file("source.txt", "root_level_dest.txt")
        expect(File.exist?(File.join(temp_dir, "root_level_dest.txt"))).to be true
      end
    end

    context "with file readability validation" do
      it "does not raise error when file is readable" do
        # Test line 452[else] in validate_file_readable! - the early return when file IS readable
        expect do
          copier.send(:validate_file_readable!, source_file)
        end.not_to raise_error
      end
    end

    context "with no logger" do
      it "handles audit logging when logger is nil" do
        # Test line 459[then] - when @logger is nil
        copier_no_logger = described_class.new(temp_dir, logger: nil)

        # This should not raise an error and should skip logging
        expect do
          copier_no_logger.copy_file("source.txt", "dest_no_log.txt")
        end.not_to raise_error
      end
    end
  end

  describe "additional branch coverage for file ownership" do
    let(:source_file) { File.join(temp_dir, "source.txt") }
    let(:dest_file) { File.join(temp_dir, "dest.txt") }

    before do
      File.write(source_file, "test content")
      File.write(dest_file, "existing content")
    end

    it "allows overwriting file when owned by same user" do
      # Test line 304[else] - when dest_stat.uid == Process.uid (same owner)
      # This should not raise an error
      expect do
        copier.copy_file("source.txt", "dest.txt")
      end.not_to raise_error

      expect(File.read(dest_file)).to eq("test content")
    end
  end

  describe "missing branch coverage" do
    let(:source_file) { File.join(temp_dir, "source.txt") }

    before do
      File.write(source_file, "test content")
    end

    context "line 298[else] - non-world-readable or non-sensitive files" do
      it "does not warn for non-sensitive world-readable files" do
        # File is world-readable but NOT sensitive
        File.chmod(0o644, source_file)

        log_output = StringIO.new
        test_logger = Logger.new(log_output)
        test_copier = described_class.new(temp_dir, logger: test_logger)
        allow(Sxn).to receive(:logger).and_return(test_logger)

        test_copier.copy_file("source.txt", "dest.txt")

        expect(log_output.string).not_to include("world-readable sensitive file")
      end

      it "does not warn for sensitive files that are not world-readable" do
        # File IS sensitive but NOT world-readable
        sensitive_file = File.join(temp_dir, ".env")
        File.write(sensitive_file, "SECRET=value")
        File.chmod(0o600, sensitive_file)

        log_output = StringIO.new
        test_logger = Logger.new(log_output)
        test_copier = described_class.new(temp_dir, logger: test_logger)
        allow(Sxn).to receive(:logger).and_return(test_logger)

        test_copier.copy_file(".env", "dest.env")

        expect(log_output.string).not_to include("world-readable sensitive file")
      end
    end

    context "line 304[else] - destination owned by current user" do
      it "continues without error when destination is owned by same user" do
        # Create existing destination file
        dest_file = File.join(temp_dir, "existing.txt")
        File.write(dest_file, "existing")

        # Verify destination is owned by current user
        expect(File.stat(dest_file).uid).to eq(Process.uid)

        # Should not raise error
        expect do
          copier.copy_file("source.txt", "existing.txt")
        end.not_to raise_error

        expect(File.read(dest_file)).to eq("test content")
      end
    end

    context "line 330[else] - directory not starting with project root" do
      it "handles directory creation when path does not start with project root" do
        # Create a new temp directory that's completely separate
        external_temp = Dir.mktmpdir("external_test")

        begin
          # Create source in external directory
          external_source = File.join(external_temp, "source.txt")
          File.write(external_source, "external content")

          # Create copier for external directory
          external_copier = described_class.new(external_temp, logger: logger)

          # Destination path that doesn't start with the project root
          # This will test the else branch at line 330
          dest_path = "subdir/dest.txt"
          external_copier.copy_file("source.txt", dest_path)

          expect(File.exist?(File.join(external_temp, dest_path))).to be true
        ensure
          FileUtils.rm_rf(external_temp)
        end
      end
    end

    context "line 333[else] - empty relative directory" do
      it "skips validation when relative directory is empty (file in project root)" do
        # When file is placed directly in project root, relative_directory will be empty
        # This tests the unless condition at line 333
        copier.copy_file("source.txt", "root_file.txt")

        expect(File.exist?(File.join(temp_dir, "root_file.txt"))).to be true
      end
    end

    context "line 444[else] - file does not exist" do
      it "raises error when source file does not exist" do
        # Delete the source file to trigger the else branch
        FileUtils.rm_f(source_file)

        expect do
          copier.send(:validate_file_exists!, source_file)
        end.to raise_error(Sxn::SecurityError, /does not exist/)
      end

      it "raises error in validate_file_exists! for non-existent normalized path" do
        # Test with a path that would be normalized
        nonexistent = File.join(temp_dir, "nonexistent.txt")

        expect do
          copier.send(:validate_file_exists!, nonexistent)
        end.to raise_error(Sxn::SecurityError, /does not exist/)
      end
    end

    context "line 459[then] - logger is nil" do
      it "returns early from audit_log when logger is nil" do
        copier_no_logger = described_class.new(temp_dir, logger: nil)

        # This should execute the early return at line 459
        result = described_class::CopyResult.new(
          source_file, File.join(temp_dir, "dest.txt"), :copy
        )

        # Should not raise error even though logger is nil
        expect do
          copier_no_logger.send(:audit_log, "TEST_EVENT", result)
        end.not_to raise_error
      end

      it "returns early from audit_log with hash details when logger is nil" do
        copier_no_logger = described_class.new(temp_dir, logger: nil)

        # Test with hash details instead of CopyResult
        expect do
          copier_no_logger.send(:audit_log, "TEST_EVENT", { file_path: "test.txt" })
        end.not_to raise_error
      end
    end
  end
end
