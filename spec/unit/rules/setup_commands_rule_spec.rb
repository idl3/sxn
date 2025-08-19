# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Rules::SetupCommandsRule do
  let(:project_path) { Dir.mktmpdir("project") }
  let(:session_path) { Dir.mktmpdir("session") }
  let(:rule_name) { "setup_commands_test" }
  
  let(:basic_config) do
    {
      "commands" => [
        {
          "command" => ["bundle", "install"],
          "description" => "Install Ruby dependencies"
        }
      ]
    }
  end

  let(:rule) { described_class.new(rule_name, basic_config, project_path, session_path) }
  let(:mock_executor) { instance_double("Sxn::Security::SecureCommandExecutor") }
  let(:mock_result) { instance_double("Sxn::Security::SecureCommandExecutor::CommandResult") }

  before do
    # Mock the command executor
    allow(Sxn::Security::SecureCommandExecutor).to receive(:new).and_return(mock_executor)
    allow(mock_executor).to receive(:command_allowed?).and_return(true)
    allow(mock_executor).to receive(:execute).and_return(mock_result)
    
    # Mock successful command result
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

  describe "#initialize" do
    it "initializes with SecureCommandExecutor" do
      expect(rule.instance_variable_get(:@command_executor)).to eq(mock_executor)
      expect(rule.instance_variable_get(:@executed_commands)).to be_empty
    end
  end

  describe "#validate" do
    context "with valid configuration" do
      it "validates successfully" do
        expect(rule.validate).to be true
        expect(rule.state).to eq(:validated)
      end
    end

    context "with missing commands configuration" do
      let(:invalid_config) { {} }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /requires 'commands' configuration/)
      end
    end

    context "with non-array commands configuration" do
      let(:invalid_config) { { "commands" => "not-an-array" } }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'commands' must be an array/)
      end
    end

    context "with empty commands array" do
      let(:invalid_config) { { "commands" => [] } }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'commands' cannot be empty/)
      end
    end

    context "with invalid command configuration" do
      let(:invalid_config) do
        {
          "commands" => [
            { "description" => "Missing command field" }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /must have a 'command' field/)
      end
    end

    context "with non-array command" do
      let(:invalid_config) do
        {
          "commands" => [
            { "command" => "string-command" }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'command' must be a non-empty array/)
      end
    end

    context "with disallowed command" do
      let(:invalid_config) do
        {
          "commands" => [
            { "command" => ["disallowed-command"] }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      before do
        allow(mock_executor).to receive(:command_allowed?).with(["disallowed-command"]).and_return(false)
      end

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /command not whitelisted/)
      end
    end

    context "with invalid timeout" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["bundle", "install"],
              "timeout" => -1
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /timeout must be positive integer/)
      end
    end

    context "with timeout exceeding maximum" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["bundle", "install"],
              "timeout" => 2000
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /timeout must be positive integer <= 1800/)
      end
    end

    context "with invalid environment variables" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["bundle", "install"],
              "env" => "not-a-hash"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /env must be a hash/)
      end
    end

    context "with invalid condition format" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["bundle", "install"],
              "condition" => "invalid_condition"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /invalid condition format/)
      end
    end

    context "with invalid working directory" do
      let(:invalid_config) do
        {
          "commands" => [
            {
              "command" => ["bundle", "install"],
              "working_directory" => "../outside-session"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /working_directory must be within session path/)
      end
    end
  end

  describe "#apply" do
    before { rule.validate }

    context "with successful commands" do
      it "executes commands successfully" do
        expect(rule.apply).to be true
        expect(rule.state).to eq(:applied)
        expect(rule.instance_variable_get(:@executed_commands)).not_to be_empty
      end

      it "calls command executor with correct parameters" do
        expect(mock_executor).to receive(:execute).with(
          ["bundle", "install"],
          { chdir: File.realpath(session_path), env: {}, timeout: 60 }
        )
        
        rule.apply
      end

      it "tracks command execution" do
        rule.apply
        
        expect(rule.changes.size).to eq(1)
        change = rule.changes.first
        expect(change.type).to eq(:command_executed)
        expect(change.target).to eq("bundle install")
      end
    end

    context "with custom environment variables" do
      let(:env_config) do
        {
          "commands" => [
            {
              "command" => ["bundle", "install"],
              "env" => { "RAILS_ENV" => "development", "BUNDLE_WITHOUT" => "production" }
            }
          ]
        }
      end
      let(:env_rule) { described_class.new(rule_name, env_config, project_path, session_path) }

      before { env_rule.validate }

      it "passes environment variables to executor" do
        expect(mock_executor).to receive(:execute).with(
          ["bundle", "install"],
          hash_including(env: { "RAILS_ENV" => "development", "BUNDLE_WITHOUT" => "production" })
        )
        
        env_rule.apply
      end
    end

    context "with custom timeout" do
      let(:timeout_config) do
        {
          "commands" => [
            {
              "command" => ["bundle", "install"],
              "timeout" => 120
            }
          ]
        }
      end
      let(:timeout_rule) { described_class.new(rule_name, timeout_config, project_path, session_path) }

      before { timeout_rule.validate }

      it "passes timeout to executor" do
        expect(mock_executor).to receive(:execute).with(
          ["bundle", "install"],
          hash_including(timeout: 120)
        )
        
        timeout_rule.apply
      end
    end

    context "with working directory" do
      let(:workdir_config) do
        {
          "commands" => [
            {
              "command" => ["bundle", "install"],
              "working_directory" => "subdir"
            }
          ]
        }
      end
      let(:workdir_rule) { described_class.new(rule_name, workdir_config, project_path, session_path) }

      before do
        FileUtils.mkdir_p(File.join(session_path, "subdir"))
        workdir_rule.validate
      end

      it "passes working directory to executor" do
        expected_chdir = File.expand_path("subdir", File.realpath(session_path))
        expect(mock_executor).to receive(:execute).with(
          ["bundle", "install"],
          { chdir: expected_chdir, env: {}, timeout: 60 }
        )
        
        workdir_rule.apply
      end
    end

    context "with conditions" do
      before do
        # Create a test file for condition checking
        File.write(File.join(session_path, "Gemfile.lock"), "gem content")
      end

      context "with file_exists condition" do
        let(:condition_config) do
          {
            "commands" => [
              {
                "command" => ["bundle", "install"],
                "condition" => "file_exists:Gemfile.lock"
              }
            ]
          }
        end
        let(:condition_rule) { described_class.new(rule_name, condition_config, project_path, session_path) }

        before { condition_rule.validate }

        it "executes when condition is met" do
          expect(mock_executor).to receive(:execute)
          condition_rule.apply
        end
      end

      context "with file_missing condition" do
        let(:condition_config) do
          {
            "commands" => [
              {
                "command" => ["bundle", "install"],
                "condition" => "file_missing:nonexistent.file"
              }
            ]
          }
        end
        let(:condition_rule) { described_class.new(rule_name, condition_config, project_path, session_path) }

        before { condition_rule.validate }

        it "executes when condition is met" do
          expect(mock_executor).to receive(:execute)
          condition_rule.apply
        end
      end

      context "with failing condition" do
        let(:condition_config) do
          {
            "commands" => [
              {
                "command" => ["bundle", "install"],
                "condition" => "file_exists:nonexistent.file"
              }
            ]
          }
        end
        let(:condition_rule) { described_class.new(rule_name, condition_config, project_path, session_path) }

        before { condition_rule.validate }

        it "skips command when condition fails" do
          expect(mock_executor).not_to receive(:execute)
          condition_rule.apply
        end
      end
    end

    context "with multiple commands" do
      let(:multi_config) do
        {
          "commands" => [
            { "command" => ["bundle", "install"] },
            { "command" => ["bundle", "exec", "rails", "db:create"] }
          ]
        }
      end
      let(:multi_rule) { described_class.new(rule_name, multi_config, project_path, session_path) }

      before { multi_rule.validate }

      it "executes all commands in order" do
        expect(mock_executor).to receive(:execute).twice
        multi_rule.apply
        
        expect(multi_rule.changes.size).to eq(2)
      end
    end

    context "with command failure" do
      before do
        allow(mock_result).to receive(:success?).and_return(false)
        allow(mock_result).to receive(:failure?).and_return(true)
        allow(mock_result).to receive(:exit_status).and_return(1)
        allow(mock_result).to receive(:stderr).and_return("Command failed")
      end

      it "fails with appropriate error" do
        expect {
          rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError, /Command failed/)
        
        expect(rule.state).to eq(:failed)
      end
    end

    context "with continue_on_failure option" do
      let(:continue_config) do
        {
          "commands" => [
            { "command" => ["bundle", "install"] },
            { "command" => ["bundle", "exec", "rails", "db:create"] }
          ],
          "continue_on_failure" => true
        }
      end
      let(:continue_rule) { described_class.new(rule_name, continue_config, project_path, session_path) }

      before do
        continue_rule.validate
        # Make first command fail
        allow(mock_result).to receive(:success?).and_return(false)
        allow(mock_result).to receive(:failure?).and_return(true)
        allow(mock_result).to receive(:exit_status).and_return(1)
      end

      it "continues execution despite failures" do
        expect(mock_executor).to receive(:execute).twice
        
        # Should not raise error
        expect { continue_rule.apply }.not_to raise_error
        expect(continue_rule.state).to eq(:applied)
      end
    end

    context "with command execution exception" do
      before do
        allow(mock_executor).to receive(:execute).and_raise(Sxn::CommandExecutionError, "Execution failed")
      end

      it "handles exceptions gracefully" do
        expect {
          rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError, /Failed to execute command/)
      end
    end
  end

  describe "#execution_summary" do
    before do
      rule.validate
      rule.apply
    end

    it "provides execution summary" do
      summary = rule.execution_summary
      
      expect(summary).to be_an(Array)
      expect(summary.size).to eq(1)
      
      command_summary = summary.first
      expect(command_summary).to include(
        command: ["bundle", "install"],
        success: true,
        duration: 1.5,
        exit_status: 0
      )
    end
  end

  describe "condition evaluation" do
    let(:rule_instance) { rule } # Use instance to access private methods

    before { rule.validate }

    describe "file conditions" do
      before do
        File.write(File.join(session_path, "existing_file.txt"), "content")
      end

      it "evaluates file_exists condition correctly" do
        expect(rule_instance.send(:file_exists?, "existing_file.txt")).to be true
        expect(rule_instance.send(:file_exists?, "nonexistent_file.txt")).to be false
      end

      it "evaluates file_missing condition correctly" do
        expect(rule_instance.send(:file_missing?, "nonexistent_file.txt")).to be true
        expect(rule_instance.send(:file_missing?, "existing_file.txt")).to be false
      end
    end

    describe "directory conditions" do
      before do
        FileUtils.mkdir_p(File.join(session_path, "existing_dir"))
      end

      it "evaluates directory_exists condition correctly" do
        expect(rule_instance.send(:directory_exists?, "existing_dir")).to be true
        expect(rule_instance.send(:directory_exists?, "nonexistent_dir")).to be false
      end

      it "evaluates directory_missing condition correctly" do
        expect(rule_instance.send(:directory_missing?, "nonexistent_dir")).to be true
        expect(rule_instance.send(:directory_missing?, "existing_dir")).to be false
      end
    end

    describe "command availability condition" do
      it "evaluates command_available condition correctly" do
        allow(mock_executor).to receive(:command_allowed?).with(["bundle"]).and_return(true)
        expect(rule_instance.send(:command_available?, "bundle")).to be true
        
        allow(mock_executor).to receive(:command_allowed?).with(["nonexistent-command"]).and_return(false)
        expect(rule_instance.send(:command_available?, "nonexistent-command")).to be false
      end
    end

    describe "environment variable condition" do
      it "evaluates env_var_set condition correctly" do
        ENV["TEST_VAR"] = "value"
        expect(rule_instance.send(:env_var_set?, "TEST_VAR")).to be true
        
        ENV.delete("NONEXISTENT_VAR")
        expect(rule_instance.send(:env_var_set?, "NONEXISTENT_VAR")).to be false
      ensure
        ENV.delete("TEST_VAR")
      end
    end

    describe "always condition" do
      it "always returns true" do
        expect(rule_instance.send(:always_true)).to be true
        expect(rule_instance.send(:always_true, "any_arg")).to be true
      end
    end
  end

  describe "working directory validation" do
    context "with valid working directory" do
      let(:valid_workdir) { "subdir" }
      let(:valid_config) do
        {
          "commands" => [
            {
              "name" => "test_command",
              "command" => ["echo", "test"],
              "working_directory" => valid_workdir
            }
          ]
        }
      end

      before do
        FileUtils.mkdir_p(File.join(session_path, valid_workdir))
      end

      it "validates working directory correctly" do
        rule_instance = described_class.new(rule_name, valid_config, project_path, session_path)
        expect { rule_instance.validate }.not_to raise_error
      end
    end

    context "with directory outside session path" do
      let(:invalid_workdir) { "../outside" }
      let(:invalid_config) do
        {
          "commands" => [
            {
              "name" => "test_command",
              "command" => ["echo", "test"],
              "working_directory" => invalid_workdir
            }
          ]
        }
      end

      it "rejects directory outside session path" do
        rule_instance = described_class.new(rule_name, invalid_config, project_path, session_path)
        expect {
          rule_instance.validate
        }.to raise_error(Sxn::Rules::ValidationError, /working_directory must be within session path/)
      end
    end
  end
end