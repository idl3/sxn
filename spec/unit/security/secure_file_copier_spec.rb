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
  end
end
