# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Rules::SetupCommandsRule, "edge cases and missing coverage" do
  let(:project_path) { Dir.mktmpdir("project") }
  let(:session_path) { Dir.mktmpdir("session") }
  let(:rule_name) { "setup_commands_edge_test" }
  let(:mock_executor) { instance_double("Sxn::Security::SecureCommandExecutor") }
  let(:mock_result) { instance_double("Sxn::Security::SecureCommandExecutor::CommandResult") }

  before do
    allow(Sxn::Security::SecureCommandExecutor).to receive(:new).and_return(mock_executor)
    allow(mock_executor).to receive(:command_allowed?).and_return(true)
    allow(mock_executor).to receive(:execute).and_return(mock_result)
    
    allow(mock_result).to receive(:success?).and_return(true)
    allow(mock_result).to receive(:failure?).and_return(false)
    allow(mock_result).to receive(:exit_status).and_return(0)
    allow(mock_result).to receive(:stdout).and_return("Command output")
    allow(mock_result).to receive(:stderr).and_return("")
    allow(mock_result).to receive(:duration).and_return(1.5)
  end

  after do
    FileUtils.rm_rf(project_path)
    FileUtils.rm_rf(session_path)
  end

  describe "validation edge cases" do
    context "with invalid continue_on_failure type" do
      let(:invalid_config) do
        {
          "commands" => [{ "command" => ["echo", "test"] }],
          "continue_on_failure" => "invalid"
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation with specific error message" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /continue_on_failure must be true or false/)
      end
    end

    context "with non-hash command config" do
      let(:invalid_config) do
        {
          "commands" => ["not-a-hash"]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation with index-specific error" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /Command config 0 must be a hash/)
      end
    end

    context "with empty command array" do
      let(:invalid_config) do
        {
          "commands" => [{ "command" => [] }]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation for empty command array" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'command' must be a non-empty array/)
      end
    end

    context "with non-string environment variable keys" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["echo", "test"],
              "env" => { 123 => "value" }
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation for non-string env keys" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /env keys and values must be strings/)
      end
    end

    context "with non-string environment variable values" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["echo", "test"],
              "env" => { "KEY" => 123 }
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation for non-string env values" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /env keys and values must be strings/)
      end
    end

    context "with non-string working directory" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["echo", "test"],
              "working_directory" => 123
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation for non-string working directory" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /working_directory must be a string/)
      end
    end
  end

  describe "condition validation edge cases" do
    context "with unsupported condition type" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["echo", "test"],
              "condition" => "unsupported_type:value"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation for unsupported condition type" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /invalid condition format/)
      end
    end

    context "with malformed condition string" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["echo", "test"],
              "condition" => "no_colon_separator"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation for malformed condition" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /invalid condition format/)
      end
    end
  end

  describe "application edge cases" do
    let(:valid_config) do
      {
        "commands" => [{ "command" => ["echo", "test"] }]
      }
    end
    let(:rule) { described_class.new(rule_name, valid_config, project_path, session_path) }

    before { rule.validate }

    context "with command execution exception and continue_on_failure" do
      let(:continue_config) do
        {
          "commands" => [
            { "command" => ["echo", "test1"] },
            { "command" => ["echo", "test2"] }
          ],
          "continue_on_failure" => true
        }
      end
      let(:continue_rule) { described_class.new(rule_name, continue_config, project_path, session_path) }

      before do
        continue_rule.validate
        allow(mock_executor).to receive(:execute).and_raise(StandardError, "Execution failed")
      end

      it "continues execution despite exceptions when continue_on_failure is true" do
        expect(mock_executor).to receive(:execute).twice
        
        expect { continue_rule.apply }.not_to raise_error
        expect(continue_rule.state).to eq(:applied)
      end
    end

    context "with failing command and stderr output" do
      before do
        allow(mock_result).to receive(:success?).and_return(false)
        allow(mock_result).to receive(:failure?).and_return(true)
        allow(mock_result).to receive(:exit_status).and_return(1)
        allow(mock_result).to receive(:stderr).and_return("Error details")
      end

      it "includes stderr in error message" do
        expect {
          rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError, /STDERR: Error details/)
      end
    end

    context "with failing command and empty stderr" do
      before do
        allow(mock_result).to receive(:success?).and_return(false)
        allow(mock_result).to receive(:failure?).and_return(true)
        allow(mock_result).to receive(:exit_status).and_return(1)
        allow(mock_result).to receive(:stderr).and_return("")
      end

      it "does not include stderr section when empty" do
        expect {
          rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError) do |error|
          expect(error.message).not_to include("STDERR:")
        end
      end
    end
  end

  describe "condition evaluation comprehensive coverage" do
    let(:rule) { described_class.new(rule_name, { "commands" => [{ "command" => ["echo", "test"] }] }, project_path, session_path) }

    before { rule.validate }

    describe "edge cases for condition evaluation" do
      it "returns true for unknown condition type" do
        # This tests the fallback behavior in should_execute_command?
        command_config = { "condition" => "unknown_type:value" }
        
        # Mock the condition type lookup to return nil
        allow(rule).to receive(:send).and_call_original
        allow(rule).to receive(:send).with(:unknown_method, "value").and_return(nil)
        
        result = rule.send(:should_execute_command?, command_config)
        expect(result).to be true
      end

      it "handles env_var_set with empty string value" do
        ENV["EMPTY_VAR"] = ""
        expect(rule.send(:env_var_set?, "EMPTY_VAR")).to be false
      ensure
        ENV.delete("EMPTY_VAR")
      end

      it "handles env_var_set with whitespace-only value" do
        ENV["WHITESPACE_VAR"] = "   "
        expect(rule.send(:env_var_set?, "WHITESPACE_VAR")).to be true # to_s.empty? is false for whitespace
      ensure
        ENV.delete("WHITESPACE_VAR")
      end
    end
  end

  describe "working directory determination" do
    let(:rule) { described_class.new(rule_name, { "commands" => [{ "command" => ["echo", "test"] }] }, project_path, session_path) }

    before { rule.validate }

    it "returns session path when no working directory specified" do
      command_config = {}
      result = rule.send(:determine_working_directory, command_config)
      expect(result).to end_with(File.basename(session_path))
    end

    it "expands relative working directory relative to session path" do
      command_config = { "working_directory" => "subdir" }
      result = rule.send(:determine_working_directory, command_config)
      expect(result).to end_with("/subdir")
    end
  end

  describe "validation helper methods" do
    let(:rule) { described_class.new(rule_name, { "commands" => [{ "command" => ["echo", "test"] }] }, project_path, session_path) }

    it "validates nil condition as valid" do
      expect(rule.send(:valid_condition?, nil)).to be true
    end

    it "validates 'always' condition as valid" do
      expect(rule.send(:valid_condition?, "always")).to be true
    end

    it "validates proper condition format" do
      expect(rule.send(:valid_condition?, "file_exists:test.txt")).to be true
    end

    it "rejects invalid condition format" do
      expect(rule.send(:valid_condition?, "invalid")).to be false
    end

    it "rejects non-string conditions" do
      expect(rule.send(:valid_condition?, 123)).to be false
    end
  end

  describe "condition evaluation methods comprehensive coverage" do
    let(:rule) { described_class.new(rule_name, { "commands" => [{ "command" => ["echo", "test"] }] }, project_path, session_path) }

    before do
      rule.validate
      # Create test directory structure
      FileUtils.mkdir_p(File.join(session_path, "test_dir"))
      File.write(File.join(session_path, "test_file.txt"), "content")
    end

    it "evaluates all condition types correctly" do
      # Test all condition evaluation methods
      expect(rule.send(:file_exists?, "test_file.txt")).to be true
      expect(rule.send(:file_exists?, "nonexistent.txt")).to be false
      
      expect(rule.send(:file_missing?, "nonexistent.txt")).to be true
      expect(rule.send(:file_missing?, "test_file.txt")).to be false
      
      expect(rule.send(:directory_exists?, "test_dir")).to be true
      expect(rule.send(:directory_exists?, "nonexistent_dir")).to be false
      
      expect(rule.send(:directory_missing?, "nonexistent_dir")).to be true
      expect(rule.send(:directory_missing?, "test_dir")).to be false
      
      expect(rule.send(:always_true)).to be true
      expect(rule.send(:always_true, "any_argument")).to be true
    end
  end

  describe "metadata and change tracking" do
    let(:config_with_metadata) do
      {
        "commands" => [
          {
            "command" => ["echo", "test"],
            "description" => "Test command with metadata",
            "env" => { "TEST_VAR" => "value" },
            "timeout" => 120,
            "working_directory" => "."
          }
        ]
      }
    end
    let(:rule) { described_class.new(rule_name, config_with_metadata, project_path, session_path) }

    before { rule.validate }

    it "tracks detailed command execution metadata" do
      rule.apply
      
      expect(rule.changes).not_to be_empty
      change = rule.changes.first
      
      expect(change.type).to eq(:command_executed)
      expect(change.target).to eq("echo test")
      # Use any_args for working_directory since it could have different path resolution
      expect(change.metadata).to include(
        env: { "TEST_VAR" => "value" },
        exit_status: 0,
        duration: 1.5
      )
      expect(change.metadata[:working_directory]).to include("session")
    end
  end
end