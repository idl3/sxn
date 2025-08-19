# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Rules::CopyFilesRule do
  let(:base_tmp_dir) { File.expand_path(Dir.mktmpdir("sxn_test")) }
  let(:project_path) { File.join(base_tmp_dir, "project") }
  let(:session_path) { File.join(base_tmp_dir, "session") }
  let(:rule_name) { "copy_files_test" }
  let(:mock_file_copier) { instance_double("Sxn::Security::SecureFileCopier") }
  let(:mock_copy_result) { 
    double("CopyResult", 
           encrypted: false, 
           checksum: "abc123", 
           to_h: { encrypted: false, checksum: "abc123" })
  }
  
  let(:basic_config) do
    {
      "files" => [
        {
          "source" => "config/master.key",
          "strategy" => "copy"
        }
      ]
    }
  end

  let(:rule) { described_class.new(rule_name, basic_config, project_path, session_path) }

  before do |example|
    # Create project structure
    FileUtils.mkdir_p(File.join(project_path, "config"))
    File.write(File.join(project_path, "config/master.key"), "secret-key-content")
    File.write(File.join(project_path, ".env"), "DATABASE_URL=postgresql://localhost/test")
    
    # Create session structure
    FileUtils.mkdir_p(File.join(session_path, "config"))
    
    if example.metadata[:use_real_file_copier]
      # For tests that need real file operations, mock the path validator to allow ".." paths
      mock_path_validator = instance_double("Sxn::Security::SecurePathValidator")
      allow(Sxn::Security::SecurePathValidator).to receive(:new).and_return(mock_path_validator)
      allow(mock_path_validator).to receive(:validate_file_operation) do |source, dest|
        # Special case: simulate permission error for /root paths
        if dest.include?("/root/")
          raise Sxn::SecurityError, "Permission denied: cannot write to #{dest}"
        end
        
        # Return the absolute paths for file operations
        source_abs = File.join(project_path, source)
        dest_abs = File.join(session_path, dest.gsub("../session/", ""))
        [source_abs, dest_abs]
      end
      allow(mock_path_validator).to receive(:validate_path) do |path, **options|
        # Return the path as-is for directory creation
        path
      end
      allow(mock_path_validator).to receive(:project_root).and_return(project_path)
      
      # Also mock file existence checks to use absolute paths
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/^[^\/]/) do |relative_path|
        File.exist?(File.join(project_path, relative_path))
      end
    else
      # Mock SecureFileCopier for most tests to avoid path validation issues
      allow(Sxn::Security::SecureFileCopier).to receive(:new).and_return(mock_file_copier)
      allow(mock_file_copier).to receive(:copy_file).and_return(mock_copy_result)
      allow(mock_file_copier).to receive(:create_symlink).and_return(mock_copy_result)
      allow(mock_file_copier).to receive(:sensitive_file?).and_return(false)
    end
  end

  after do
    FileUtils.rm_rf(base_tmp_dir) if Dir.exist?(base_tmp_dir)
  end

  describe "#initialize" do
    it "initializes with SecureFileCopier", :use_real_file_copier do
      expect(rule.instance_variable_get(:@file_copier)).to be_a(Sxn::Security::SecureFileCopier)
    end
  end

  describe "#validate" do
    context "with valid configuration" do
      it "validates successfully" do
        expect(rule.validate).to be true
        expect(rule.state).to eq(:validated)
      end
    end

    context "with missing files configuration" do
      let(:invalid_config) { {} }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /requires 'files' configuration/)
      end
    end

    context "with non-array files configuration" do
      let(:invalid_config) { { "files" => "not-an-array" } }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'files' must be an array/)
      end
    end

    context "with empty files array" do
      let(:invalid_config) { { "files" => [] } }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'files' cannot be empty/)
      end
    end

    context "with invalid file configuration" do
      let(:invalid_config) do
        {
          "files" => [
            { "strategy" => "copy" } # missing source
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /must have a 'source' string/)
      end
    end

    context "with invalid strategy" do
      let(:invalid_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "strategy" => "invalid_strategy"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /invalid strategy 'invalid_strategy'/)
      end
    end

    context "with invalid permissions" do
      let(:invalid_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "strategy" => "copy",
              "permissions" => "invalid"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /invalid permissions/)
      end
    end

    context "with missing required source file" do
      let(:config_with_missing_file) do
        {
          "files" => [
            {
              "source" => "config/missing.key",
              "strategy" => "copy",
              "required" => true
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, config_with_missing_file, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /Required source file does not exist/)
      end
    end

    context "with missing optional source file" do
      let(:config_with_optional_file) do
        {
          "files" => [
            {
              "source" => "config/optional.key",
              "strategy" => "copy",
              "required" => false
            }
          ]
        }
      end
      let(:valid_rule) { described_class.new(rule_name, config_with_optional_file, project_path, session_path) }

      it "validates successfully" do
        expect(valid_rule.validate).to be true
      end
    end
  end

  describe "#apply" do
    before { rule.validate }

    context "with copy strategy" do
      it "copies files successfully", :use_real_file_copier do
        expect(rule.apply).to be true
        expect(rule.state).to eq(:applied)
        
        copied_file = File.join(session_path, "config/master.key")
        expect(File.exist?(copied_file)).to be true
        # Note: master.key files are automatically encrypted by SecureFileCopier
        # so we just check that the file exists and has content
        expect(File.read(copied_file)).not_to be_empty
      end

      it "tracks file creation change" do
        rule.apply
        
        expect(rule.changes.size).to eq(1)
        change = rule.changes.first
        expect(change.type).to eq(:file_created)
        expect(change.target).to end_with("config/master.key")
        expect(change.metadata[:strategy]).to eq("copy")
      end

      it "sets appropriate permissions", :use_real_file_copier do
        config_with_permissions = {
          "files" => [
            {
              "source" => "config/master.key",
              "strategy" => "copy",
              "permissions" => "0600"
            }
          ]
        }
        rule_with_perms = described_class.new(rule_name, config_with_permissions, project_path, session_path)
        rule_with_perms.validate
        rule_with_perms.apply
        
        copied_file = File.join(session_path, "config/master.key")
        stat = File.stat(copied_file)
        expect(stat.mode & 0o777).to eq(0o600)
      end
    end

    context "with symlink strategy" do
      let(:symlink_config) do
        {
          "files" => [
            {
              "source" => ".env",
              "strategy" => "symlink"
            }
          ]
        }
      end
      let(:symlink_rule) { described_class.new(rule_name, symlink_config, project_path, session_path) }

      before { symlink_rule.validate }

      it "creates symlinks successfully", :use_real_file_copier do
        expect(symlink_rule.apply).to be true
        
        symlink_file = File.join(session_path, ".env")
        expect(File.symlink?(symlink_file)).to be true
        expect(File.readlink(symlink_file)).to eq(File.join(project_path, ".env"))
      end

      it "tracks symlink creation change" do
        symlink_rule.apply
        
        expect(symlink_rule.changes.size).to eq(1)
        change = symlink_rule.changes.first
        expect(change.type).to eq(:symlink_created)
        expect(change.metadata[:strategy]).to eq("symlink")
      end
    end

    context "with custom destination" do
      let(:custom_dest_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "destination" => "config/production.key",
              "strategy" => "copy"
            }
          ]
        }
      end
      let(:custom_dest_rule) { described_class.new(rule_name, custom_dest_config, project_path, session_path) }

      before do
        custom_dest_rule.validate
      end

      it "copies to custom destination" do
        expect(mock_file_copier).to receive(:copy_file).with(
          "config/master.key",
          "../session/config/production.key",
          hash_including({})
        ).and_return(mock_copy_result)
        
        custom_dest_rule.apply
      end
    end

    context "with encryption" do
      let(:encrypt_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "strategy" => "copy",
              "encrypt" => true
            }
          ]
        }
      end
      let(:encrypt_rule) { described_class.new(rule_name, encrypt_config, project_path, session_path) }

      before { encrypt_rule.validate }

      it "encrypts sensitive files", :use_real_file_copier do
        encrypt_rule.apply
        
        expect(encrypt_rule.changes.size).to eq(1)
        change = encrypt_rule.changes.first
        # Note: sensitive files like master.key are automatically encrypted
        expect(change.metadata[:encrypted]).to be true
      end
    end

    context "with multiple files" do
      let(:multi_file_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "strategy" => "copy"
            },
            {
              "source" => ".env",
              "strategy" => "symlink"
            }
          ]
        }
      end
      let(:multi_file_rule) { described_class.new(rule_name, multi_file_config, project_path, session_path) }

      before { multi_file_rule.validate }

      it "processes multiple files", :use_real_file_copier do
        multi_file_rule.apply
        
        expect(multi_file_rule.changes.size).to eq(2)
        
        # Check copied file
        copied_file = File.join(session_path, "config/master.key")
        expect(File.exist?(copied_file)).to be true
        
        # Check symlinked file
        symlink_file = File.join(session_path, ".env")
        expect(File.symlink?(symlink_file)).to be true
      end
    end

    context "with missing optional file" do
      let(:optional_config) do
        {
          "files" => [
            {
              "source" => "config/optional.key",
              "strategy" => "copy",
              "required" => false
            }
          ]
        }
      end
      let(:optional_rule) { described_class.new(rule_name, optional_config, project_path, session_path) }

      before { optional_rule.validate }

      it "skips missing optional files" do
        expect(optional_rule.apply).to be true
        expect(optional_rule.changes).to be_empty
      end
    end

    context "with missing required file at runtime" do
      before do
        # Remove the file after validation
        File.unlink(File.join(project_path, "config/master.key"))
      end

      it "fails with appropriate error" do
        expect {
          rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError, /Required source file does not exist/)
      end
    end
  end

  describe "#rollback" do
    let(:copied_file) { File.join(session_path, "config/master.key") }

    before do
      rule.validate
      
      # Create the file for rollback testing
      FileUtils.mkdir_p(File.dirname(copied_file))
      File.write(copied_file, "test content")
      
      rule.apply
    end

    it "removes created files" do
      expect(File.exist?(copied_file)).to be true
      
      rule.rollback
      expect(File.exist?(copied_file)).to be false
    end
  end

  describe "sensitive file detection" do
    it "automatically encrypts sensitive files", :use_real_file_copier do
      file_copier = rule.instance_variable_get(:@file_copier)
      
      expect(file_copier.sensitive_file?("config/master.key")).to be true
      expect(file_copier.sensitive_file?(".env")).to be true
      expect(file_copier.sensitive_file?("README.md")).to be false
    end
  end

  describe "directory creation" do
    let(:nested_config) do
      {
        "files" => [
          {
            "source" => "config/master.key",
            "destination" => "config/deep/nested/master.key",
            "strategy" => "copy"
          }
        ]
      }
    end
    let(:nested_rule) { described_class.new(rule_name, nested_config, project_path, session_path) }

    before { nested_rule.validate }

    it "creates nested directories", :use_real_file_copier do
      nested_rule.apply
      
      nested_file = File.join(session_path, "config/deep/nested/master.key")
      expect(File.exist?(nested_file)).to be true
      expect(File.directory?(File.dirname(nested_file))).to be true
    end
  end

  describe "error handling" do
    context "when file copying fails" do
      let(:bad_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "destination" => "/root/forbidden.key", # Should fail due to permissions
              "strategy" => "copy"
            }
          ]
        }
      end

      it "handles copy failures gracefully", :use_real_file_copier do
        bad_rule = described_class.new(rule_name, bad_config, project_path, session_path)
        bad_rule.validate
        
        expect {
          bad_rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError, /Failed to copy files/)
        
        expect(bad_rule.state).to eq(:failed)
      end
    end
  end

  describe "permission handling" do
    context "with string permissions" do
      let(:string_perms_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "strategy" => "copy",
              "permissions" => "644"
            }
          ]
        }
      end
      let(:string_perms_rule) { described_class.new(rule_name, string_perms_config, project_path, session_path) }

      before do
        string_perms_rule.validate
      end

      it "accepts string permissions" do
        expect { string_perms_rule.apply }.not_to raise_error
      end
    end

    context "with octal string permissions" do
      let(:octal_perms_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "strategy" => "copy",
              "permissions" => "0644"
            }
          ]
        }
      end
      let(:octal_perms_rule) { described_class.new(rule_name, octal_perms_config, project_path, session_path) }

      before { octal_perms_rule.validate }

      it "accepts octal string permissions" do
        expect { octal_perms_rule.apply }.not_to raise_error
      end
    end

    context "with integer permissions" do
      let(:int_perms_config) do
        {
          "files" => [
            {
              "source" => "config/master.key",
              "strategy" => "copy",
              "permissions" => 0o644
            }
          ]
        }
      end
      let(:int_perms_rule) { described_class.new(rule_name, int_perms_config, project_path, session_path) }

      before { int_perms_rule.validate }

      it "accepts integer permissions" do
        expect { int_perms_rule.apply }.not_to raise_error
      end
    end
  end
end