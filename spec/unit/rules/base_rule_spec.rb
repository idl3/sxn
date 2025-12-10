# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Rules::BaseRule do
  let(:project_path) { Dir.mktmpdir("project") }
  let(:session_path) { Dir.mktmpdir("session") }
  let(:rule_name) { "test_rule" }
  let(:config) { { "test_param" => "value" } }
  let(:dependencies) { [] }

  # Create a concrete test rule class
  let(:test_rule_class) do
    klass = Class.new(described_class) do
      def apply
        change_state!(Sxn::Rules::BaseRule::APPLYING)
        track_change(:test_action, "test_target")
        change_state!(Sxn::Rules::BaseRule::APPLIED)
        true
      end

      protected

      def validate_rule_specific!
        raise Sxn::Rules::ValidationError, "Test validation error" if @config["fail_validation"]
      end

      # Override to handle test-specific rollback
      def rollback_changes!
        @changes.reverse_each do |change|
          # Handle test actions in rollback
          if change.type == :test_action
            # Test action rollback is a no-op for testing purposes
          else
            change.rollback
          end
        end
        @changes.clear
      end
    end
    # Set a proper class name for the dynamic class
    stub_const("TestRuleClass", klass)
    klass
  end

  let(:rule) { test_rule_class.new(project_path, session_path, config, dependencies: dependencies) }

  after do
    FileUtils.rm_rf(project_path)
    FileUtils.rm_rf(session_path)
  end

  describe "#initialize" do
    it "initializes with valid parameters" do
      expect(rule.name).to eq("base_rule")
      expect(rule.config).to eq(config)
      expect(rule.project_path).to eq(File.realpath(project_path))
      expect(rule.session_path).to eq(File.realpath(session_path))
      expect(rule.dependencies).to eq(dependencies)
      expect(rule.state).to eq(:pending)
      expect(rule.changes).to be_empty
      expect(rule.errors).to be_empty
    end

    it "initializes with alternative constructor signature (config, project_path, session_path, name)" do
      alt_rule = test_rule_class.new(config, project_path, session_path, "custom_name")
      expect(alt_rule.name).to eq("custom_name")
      expect(alt_rule.config).to eq(config)
      expect(alt_rule.project_path).to eq(File.realpath(project_path))
      expect(alt_rule.session_path).to eq(File.realpath(session_path))
    end

    it "raises error with invalid argument combinations" do
      expect do
        test_rule_class.new("invalid", 123, "args", "here")
      end.to raise_error(ArgumentError, /Invalid arguments/)
    end

    it "raises error for non-existent project path" do
      expect do
        test_rule_class.new("/non/existent", session_path, config)
      end.to raise_error(ArgumentError, /Invalid path provided/)
    end

    it "raises error for non-existent session path" do
      expect do
        test_rule_class.new(project_path, "/non/existent", config)
      end.to raise_error(ArgumentError, /Invalid path provided/)
    end

    it "raises error for non-directory project path" do
      file_path = File.join(project_path, "file.txt")
      File.write(file_path, "test")

      expect do
        test_rule_class.new(file_path, session_path, config)
      end.to raise_error(ArgumentError, /Project path is not a directory/)
    end

    it "raises error for non-writable session path" do
      # Make session path read-only
      File.chmod(0o444, session_path)

      expect do
        test_rule_class.new(project_path, session_path, config)
      end.to raise_error(ArgumentError, /Session path is not writable/)
    ensure
      File.chmod(0o755, session_path)
    end

    it "freezes configuration to prevent mutation" do
      expect(rule.config).to be_frozen
    end

    it "freezes dependencies to prevent mutation" do
      expect(rule.dependencies).to be_frozen
    end
  end

  describe "#validate" do
    it "validates successfully with valid configuration" do
      expect(rule.validate).to be true
      expect(rule.state).to eq(:validated)
    end

    it "fails validation with invalid configuration" do
      invalid_rule = test_rule_class.new(project_path, session_path, { "fail_validation" => true })

      expect do
        invalid_rule.validate
      end.to raise_error(Sxn::Rules::ValidationError, "Test validation error")

      expect(invalid_rule.state).to eq(:failed)
      expect(invalid_rule.errors).not_to be_empty
    end

    it "validates dependencies" do
      rule_with_deps = test_rule_class.new(project_path, session_path, config, dependencies: %w[dep1 dep2])

      expect(rule_with_deps.validate).to be true
      expect(rule_with_deps.dependencies).to eq(%w[dep1 dep2])
    end

    it "fails validation with invalid dependencies" do
      rule_with_invalid_deps = test_rule_class.new(project_path, session_path, config, dependencies: [123, nil])

      expect do
        rule_with_invalid_deps.validate
      end.to raise_error(Sxn::Rules::ValidationError, /Invalid dependency/)
    end

    it "changes state during validation" do
      expect(rule.state).to eq(:pending)
      rule.validate
      expect(rule.state).to eq(:validated)
    end
  end

  describe "#apply" do
    before { rule.validate }

    it "applies the rule successfully" do
      expect(rule.apply).to be true
      expect(rule.state).to eq(:applied)
      expect(rule.applied?).to be true
      expect(rule.changes).not_to be_empty
    end

    it "tracks changes during application" do
      rule.apply

      expect(rule.changes.size).to eq(1)
      change = rule.changes.first
      expect(change.type).to eq(:test_action)
      expect(change.target).to eq("test_target")
    end

    it "calculates duration" do
      rule.apply
      expect(rule.duration).to be_a(Float)
      expect(rule.duration).to be > 0
    end

    it "raises NotImplementedError when calling apply on BaseRule directly" do
      # Create a BaseRule instance directly (not a subclass)
      base_rule = described_class.new(project_path, session_path, config)
      base_rule.validate

      expect do
        base_rule.apply
      end.to raise_error(NotImplementedError, /must implement #apply/)
    end
  end

  describe "#rollback" do
    before do
      rule.validate
      rule.apply
    end

    it "rolls back successfully" do
      expect(rule.rollback).to be true
      expect(rule.state).to eq(:rolled_back)
    end

    it "clears changes after rollback" do
      expect(rule.changes).not_to be_empty
      rule.rollback
      expect(rule.changes).to be_empty
    end

    it "does nothing if rule is pending" do
      pending_rule = test_rule_class.new(project_path, session_path, config)
      expect(pending_rule.rollback).to be true
      expect(pending_rule.state).to eq(:pending)
    end
  end

  describe "#can_execute?" do
    let(:rule_with_deps) do
      test_rule_class.new(project_path, session_path, config, dependencies: %w[dep1 dep2])
    end

    it "returns true when all dependencies are satisfied" do
      completed_rules = %w[dep1 dep2 other]
      expect(rule_with_deps.can_execute?(completed_rules)).to be true
    end

    it "returns false when dependencies are missing" do
      completed_rules = ["dep1"]
      expect(rule_with_deps.can_execute?(completed_rules)).to be false
    end

    it "returns true when no dependencies exist" do
      expect(rule.can_execute?([])).to be true
    end
  end

  describe "#rollbackable?" do
    before { rule.validate }

    it "returns false for unapplied rule" do
      expect(rule.rollbackable?).to be false
    end

    it "returns true for applied rule with changes" do
      rule.apply
      expect(rule.rollbackable?).to be true
    end
  end

  describe "#to_h" do
    before do
      rule.validate
      rule.apply
    end

    it "returns hash representation" do
      hash = rule.to_h

      expect(hash).to include(
        name: "base_rule",
        type: "TestRuleClass",
        state: :applied,
        config: config,
        dependencies: dependencies
      )
      expect(hash[:changes]).to be_an(Array)
      expect(hash[:errors]).to be_an(Array)
      expect(hash[:duration]).to be_a(Float)
      expect(hash[:applied_at]).to be_a(String)
    end
  end

  describe "RuleChange" do
    let(:change) { described_class::RuleChange.new(:file_created, "/path/to/file", { backup: true }) }

    describe "#initialize" do
      it "initializes with required parameters" do
        expect(change.type).to eq(:file_created)
        expect(change.target).to eq("/path/to/file")
        expect(change.metadata).to eq({ backup: true })
        expect(change.timestamp).to be_a(Time)
      end

      it "freezes metadata" do
        expect(change.metadata).to be_frozen
      end
    end

    describe "#rollback" do
      let(:temp_file) { File.join(session_path, "test_file.txt") }
      let(:temp_dir) { File.join(session_path, "test_dir") }

      it "removes created files" do
        File.write(temp_file, "test content")
        change = described_class::RuleChange.new(:file_created, temp_file)

        expect(File.exist?(temp_file)).to be true
        change.rollback
        expect(File.exist?(temp_file)).to be false
      end

      it "removes created directories" do
        Dir.mkdir(temp_dir)
        change = described_class::RuleChange.new(:directory_created, temp_dir)

        expect(File.directory?(temp_dir)).to be true
        change.rollback
        expect(File.directory?(temp_dir)).to be false
      end

      it "restores modified files from backup" do
        original_content = "original"
        backup_file = "#{temp_file}.backup"

        File.write(temp_file, "modified")
        File.write(backup_file, original_content)

        change = described_class::RuleChange.new(:file_modified, temp_file, { backup_path: backup_file })
        change.rollback

        expect(File.read(temp_file)).to eq(original_content)
        expect(File.exist?(backup_file)).to be false
      end

      it "removes symlinks" do
        source_file = File.join(project_path, "source.txt")
        File.write(source_file, "test")
        File.symlink(source_file, temp_file)

        change = described_class::RuleChange.new(:symlink_created, temp_file)

        expect(File.symlink?(temp_file)).to be true
        change.rollback
        expect(File.exist?(temp_file)).to be false
      end

      it "handles command execution rollback" do
        change = described_class::RuleChange.new(:command_executed, "test command")

        # Should not raise error (commands can't be rolled back)
        expect { change.rollback }.not_to raise_error
      end

      it "raises error for unknown change type" do
        change = described_class::RuleChange.new(:unknown_type, "target")

        expect do
          change.rollback
        end.to raise_error(Sxn::Rules::RollbackError, /Unknown change type/)
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = change.to_h

        expect(hash).to include(
          type: :file_created,
          target: "/path/to/file",
          metadata: { backup: true }
        )
        expect(hash[:timestamp]).to be_a(String)
      end
    end
  end

  describe "error handling and edge cases" do
    it "handles rollback errors gracefully" do
      # Apply the rule first to have something to rollback
      rule.validate
      rule.apply

      # Add a non-test change that will actually trigger rollback
      rule.send(:track_change, :file_created, "/tmp/test_file")

      # Mock a rollback failure
      allow_any_instance_of(described_class::RuleChange).to receive(:rollback).and_raise(StandardError,
                                                                                         "Rollback failed")

      expect do
        rule.rollback
      end.to raise_error(Sxn::Rules::RollbackError, /Failed to rollback rule/)

      expect(rule.state).to eq(:failed)
      expect(rule.errors).not_to be_empty
    end

    it "validates config hash correctly" do
      valid_rule = test_rule_class.new(project_path, session_path, { "valid" => true })
      empty_rule = test_rule_class.new(project_path, session_path, {})
      nil_rule = test_rule_class.new(project_path, session_path, nil)
      invalid_rule = test_rule_class.new(project_path, session_path, "not a hash")

      expect(valid_rule.send(:validate_config_hash)).to be true
      expect(empty_rule.send(:validate_config_hash)).to be true
      expect(nil_rule.send(:validate_config_hash)).to be true
      expect(invalid_rule.send(:validate_config_hash)).to be false
    end

    it "enforces session path writability" do
      readonly_session_path = Dir.mktmpdir
      File.chmod(0o444, readonly_session_path) # Read-only

      expect do
        test_rule_class.new(project_path, readonly_session_path, config)
      end.to raise_error(ArgumentError, /Session path is not writable/)
    ensure
      File.chmod(0o755, readonly_session_path)
      FileUtils.rm_rf(readonly_session_path)
    end
  end

  describe "state management" do
    it "tracks state changes" do
      expect(rule.state).to eq(:pending)

      rule.validate
      expect(rule.state).to eq(:validated)

      rule.apply
      expect(rule.state).to eq(:applied)

      rule.rollback
      expect(rule.state).to eq(:rolled_back)
    end

    it "sets failed state on errors" do
      invalid_rule = test_rule_class.new(project_path, session_path, { "fail_validation" => true })

      expect do
        invalid_rule.validate
      end.to raise_error(Sxn::Rules::ValidationError)

      expect(invalid_rule.state).to eq(:failed)
      expect(invalid_rule.failed?).to be true
    end
  end

  describe "logging" do
    # Create fresh logger mock for each test to prevent leakage
    let(:logger) { instance_double("Logger", debug: nil, info: nil, warn: nil, error: nil, level: nil) }

    before do
      # Reset Sxn logger state and set up fresh mock
      Sxn.instance_variable_set(:@logger, nil)
      allow(Sxn).to receive(:logger).and_return(logger)
    end

    it "logs state changes" do
      expect(logger).to receive(:debug).with(/State changed from pending to validating/)
      expect(logger).to receive(:debug).with(/State changed from validating to validated/)

      rule.validate
    end

    it "provides rule context in logs" do
      rule.validate
      rule.apply

      # Verify logger was called with rule context
      expect(logger).to have_received(:debug).at_least(:once)
    end
  end
end
