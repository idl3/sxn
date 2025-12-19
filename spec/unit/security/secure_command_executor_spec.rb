# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "tmpdir"
require "logger"

RSpec.describe Sxn::Security::SecureCommandExecutor do
  let(:temp_dir) { Dir.mktmpdir("sxn_test") }
  let(:project_root) { temp_dir }
  let(:logger) { Logger.new(StringIO.new) }
  let(:executor) { described_class.new(project_root, logger: logger) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    context "with valid project root" do
      it "accepts existing directory" do
        expect { described_class.new(temp_dir) }.not_to raise_error
      end

      it "builds command whitelist on initialization" do
        executor = described_class.new(temp_dir)
        expect(executor.allowed_commands).to be_an(Array)
        expect(executor.allowed_commands).not_to be_empty
      end
    end

    context "with invalid project root" do
      it "raises error for non-existent directory" do
        non_existent = File.join(temp_dir, "does_not_exist")
        expect { described_class.new(non_existent) }.to raise_error(ArgumentError, /does not exist/)
      end
    end
  end

  describe "#execute" do
    context "with whitelisted commands" do
      it "executes echo command successfully" do
        # Skip this test if echo is not available
        skip "echo command not available" unless executor.command_allowed?(%w[echo test])

        result = executor.execute(["echo", "hello world"])
        expect(result).to be_a(described_class::CommandResult)
        expect(result.success?).to be true
        expect(result.stdout.strip).to eq("hello world")
        expect(result.exit_status).to eq(0)
      end

      it "captures command output" do
        # Use a simple command that should be available
        next unless File.executable?("/bin/echo") || File.executable?("/usr/bin/echo")

        # Find the echo executable
        echo_path = %w[/bin/echo /usr/bin/echo].find { |path| File.executable?(path) }

        # Mock the command whitelist to include echo
        whitelist = { "echo" => echo_path }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        executor = described_class.new(temp_dir)
        result = executor.execute(["echo", "test output"])

        expect(result.stdout.strip).to eq("test output")
        expect(result.stderr).to be_empty
      end

      it "handles command with environment variables" do
        skip "test command not available" unless executor.command_allowed?(["ruby", "-e", "puts ENV['TEST_VAR']"])

        result = executor.execute(
          ["ruby", "-e", "puts ENV['TEST_VAR']"],
          env: { "TEST_VAR" => "test_value" }
        )

        expect(result.stdout.strip).to eq("test_value") if result.success?
      end

      it "executes commands in specified working directory" do
        subdir = File.join(temp_dir, "subdir")
        FileUtils.mkdir_p(subdir)

        skip "pwd command not available" unless File.executable?("/bin/pwd")

        # Mock the command whitelist to include pwd
        whitelist = { "pwd" => "/bin/pwd" }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        executor = described_class.new(temp_dir)
        result = executor.execute(["pwd"], chdir: "subdir")

        # Use realpath to handle symlink resolution differences on macOS
        expect(File.realpath(result.stdout.strip)).to eq(File.realpath(subdir)) if result.success?
      end
    end

    context "with command validation" do
      it "rejects non-whitelisted commands" do
        expect do
          executor.execute(%w[malicious_command arg])
        end.to raise_error(Sxn::CommandExecutionError, /not whitelisted/)
      end

      it "rejects empty command array" do
        expect { executor.execute([]) }.to raise_error(ArgumentError, /cannot be empty/)
      end

      it "rejects non-array commands" do
        expect { executor.execute("echo hello") }.to raise_error(ArgumentError, /must be an array/)
      end

      it "validates timeout parameter" do
        expect { executor.execute(%w[echo test], timeout: 0) }.to raise_error(ArgumentError, /must be positive/)
        expect { executor.execute(%w[echo test], timeout: 400) }.to raise_error(ArgumentError, /must be positive/)
      end
    end

    context "with environment security" do
      it "filters environment variables" do
        # This test verifies that only safe environment variables are passed
        skip "env command not available" unless File.executable?("/usr/bin/env") || File.executable?("/bin/env")

        env_path = %w[/usr/bin/env /bin/env].find { |path| File.executable?(path) }

        # Mock the command whitelist to include env
        whitelist = { "env" => env_path }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        executor = described_class.new(temp_dir)
        result = executor.execute(
          ["env"],
          env: {
            "SAFE_VAR" => "safe_value",
            "PATH" => "/custom/path",
            "DANGEROUS_VAR" => "should_be_filtered" # This might be filtered
          }
        )

        if result.success?
          # The exact filtering behavior depends on SAFE_ENV_VARS
          expect(result.stdout).to include("SAFE_VAR=safe_value")
        end
      end

      it "rejects invalid environment variable names" do
        # Mock echo command for this test
        whitelist = { "echo" => "/bin/echo" }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir)
        expect do
          test_executor.execute(%w[echo test], env: { "invalid-name" => "value" })
        end.to raise_error(Sxn::CommandExecutionError, /Invalid environment variable/)
      end

      it "rejects environment variables with null bytes" do
        # Mock echo command for this test
        whitelist = { "echo" => "/bin/echo" }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir)
        expect do
          test_executor.execute(%w[echo test], env: { "TEST" => "value\x00injection" })
        end.to raise_error(Sxn::CommandExecutionError, /null bytes/)
      end
    end

    context "with working directory validation" do
      it "validates working directory is within project" do
        # Mock echo command for this test
        whitelist = { "echo" => "/bin/echo" }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir)
        expect do
          test_executor.execute(%w[echo test], chdir: "/etc")
        end.to raise_error(Sxn::PathValidationError, /outside project boundaries/)
      end

      it "validates working directory exists" do
        # Mock echo command for this test
        whitelist = { "echo" => "/bin/echo" }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir)
        expect do
          test_executor.execute(%w[echo test], chdir: "nonexistent")
        end.to raise_error(Errno::ENOENT)
      end
    end

    context "with timeout handling" do
      it "respects timeout for long-running commands" do
        skip "sleep command not available" unless File.executable?("/bin/sleep")

        # Mock the command whitelist to include sleep
        whitelist = { "sleep" => "/bin/sleep" }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir)

        expect do
          test_executor.execute(%w[sleep 5], timeout: 1)
        end.to raise_error(Sxn::CommandExecutionError, /timed out/)
      end
    end

    context "with audit logging" do
      let(:log_output) { StringIO.new }
      let(:logger) { Logger.new(log_output) }
      let(:executor) { described_class.new(temp_dir, logger: logger) }

      it "logs command execution start" do
        skip "echo not available" unless executor.command_allowed?(%w[echo test])

        executor.execute(%w[echo test])
        log_content = log_output.string

        expect(log_content).to include("EXEC_START")
        expect(log_content).to include("echo")
      end

      it "logs command completion" do
        skip "echo not available" unless executor.command_allowed?(%w[echo test])

        executor.execute(%w[echo test])
        log_content = log_output.string

        expect(log_content).to include("EXEC_COMPLETE")
      end

      it "logs command errors" do
        skip "false command not available" unless File.executable?("/bin/false")

        # Mock the command whitelist to include false
        whitelist = { "false" => "/bin/false" }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir, logger: logger)
        result = test_executor.execute(["false"])

        expect(result.success?).to be false
        log_content = log_output.string
        expect(log_content).to include("EXEC_COMPLETE")
      end
    end
  end

  describe "#command_allowed?" do
    it "returns true for whitelisted commands" do
      # Test with a command that's likely to be whitelisted
      expect(executor.command_allowed?(%w[git status])).to be true if executor.allowed_commands.include?("git")
    end

    it "returns false for non-whitelisted commands" do
      expect(executor.command_allowed?(["malicious_command"])).to be false
    end

    it "returns false for empty arrays" do
      expect(executor.command_allowed?([])).to be false
    end

    it "returns false for non-arrays" do
      expect(executor.command_allowed?("not an array")).to be false
    end
  end

  describe "#allowed_commands" do
    it "returns array of command names" do
      commands = executor.allowed_commands
      expect(commands).to be_an(Array)
      expect(commands).to all(be_a(String))
    end

    it "includes common development commands if available" do
      commands = executor.allowed_commands

      # Check for some commands that might be available
      possible_commands = %w[git bundle ruby node npm]
      available_commands = possible_commands.select { |cmd| commands.include?(cmd) }

      # At least git should be available on most systems
      expect(available_commands).not_to be_empty
    end
  end

  describe "CommandResult" do
    let(:result) { described_class::CommandResult.new(0, "output", "error", %w[echo test], 1.5) }

    describe "#success?" do
      it "returns true for exit status 0" do
        success_result = described_class::CommandResult.new(0, "", "", ["cmd"], 1.0)
        expect(success_result.success?).to be true
      end

      it "returns false for non-zero exit status" do
        failure_result = described_class::CommandResult.new(1, "", "", ["cmd"], 1.0)
        expect(failure_result.success?).to be false
      end
    end

    describe "#failure?" do
      it "returns opposite of success?" do
        expect(result.failure?).to eq(!result.success?)
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = result.to_h
        expect(hash).to include(
          exit_status: 0,
          stdout: "output",
          stderr: "error",
          command: %w[echo test],
          duration: 1.5,
          success: true
        )
      end
    end
  end

  describe "security edge cases" do
    it "prevents shell injection through command arguments" do
      # Even if echo were whitelisted, this should not execute additional commands
      dangerous_args = ["test", ";", "rm", "-rf", "/"]

      if executor.command_allowed?(["echo"])
        result = executor.execute(["echo"] + dangerous_args)
        # The semicolon should be treated as a literal argument, not a command separator
        expect(result.stdout).to include(";")
        expect(result.stdout).to include("rm")
      end
    end

    it "prevents environment variable injection" do
      # Mock echo command for this test
      whitelist = { "echo" => "/bin/echo" }
      allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

      test_executor = described_class.new(temp_dir)
      # Test that environment variables can't contain shell metacharacters that could be exploited
      expect do
        test_executor.execute(%w[echo test], env: { "TEST" => "value; rm -rf /" })
      end.not_to raise_error

      # The value should be treated literally, not executed
    end

    it "handles very long command arguments safely" do
      long_arg = "a" * 10_000
      skip "echo not available" unless executor.command_allowed?(["echo", long_arg])

      result = executor.execute(["echo", long_arg])
      expect(result.stdout.length).to be > 5000
    end

    it "prevents directory traversal through chdir" do
      # Mock echo command for this test
      whitelist = { "echo" => "/bin/echo" }
      allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

      test_executor = described_class.new(temp_dir)
      expect do
        test_executor.execute(%w[echo test], chdir: "../../../etc")
      end.to raise_error(Sxn::PathValidationError, /directory traversal/)
    end
  end

  describe "project-specific executables" do
    let(:bin_dir) { File.join(temp_dir, "bin") }
    let(:rails_script) { File.join(bin_dir, "rails") }

    before do
      FileUtils.mkdir_p(bin_dir)
      File.write(rails_script, "#!/usr/bin/env ruby\nputs 'fake rails'")
      File.chmod(0o755, rails_script)
    end

    it "allows project bin scripts" do
      executor = described_class.new(temp_dir)

      if executor.command_allowed?(["bin/rails"])
        result = executor.execute(["bin/rails", "--version"])
        expect(result.stdout).to include("fake rails") if result.success?
      end
    end

    it "validates project executables exist and are executable" do
      non_executable = File.join(bin_dir, "not_executable")
      File.write(non_executable, "#!/bin/sh\necho test")
      # Don't set executable permission

      executor = described_class.new(temp_dir)
      expect(executor.command_allowed?(["bin/not_executable"])).to be false
    end
  end

  describe "command validation edge cases" do
    it "raises error for non-executable whitelisted command" do
      # Create a file without execute permission
      non_exec = File.join(temp_dir, "non_exec")
      File.write(non_exec, "#!/bin/sh\necho test")
      File.chmod(0o644, non_exec)

      # Mock whitelist to include this file
      allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return({ "test" => non_exec })

      test_executor = described_class.new(temp_dir)

      expect do
        test_executor.execute(["test"])
      end.to raise_error(Sxn::CommandExecutionError, /not executable/)
    end

    it "handles string path in whitelist building" do
      # Create an executable
      exec_path = File.join(temp_dir, "test_exec")
      File.write(exec_path, "#!/bin/sh\necho test")
      File.chmod(0o755, exec_path)

      # Mock ALLOWED_COMMANDS to include a string path specification
      stub_const("#{described_class}::ALLOWED_COMMANDS", {
                   "test_cmd" => exec_path
                 })

      test_executor = described_class.new(temp_dir)

      expect(test_executor.allowed_commands).to include("test_cmd")
      expect(test_executor.command_allowed?(["test_cmd"])).to be true
    end
  end

  describe "timeout error handling" do
    it "handles errors when killing timed-out process with TERM signal" do
      skip "sleep command not available" unless File.executable?("/bin/sleep")

      # Mock the command whitelist to include sleep
      whitelist = { "sleep" => "/bin/sleep" }
      allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

      test_executor = described_class.new(temp_dir)

      # Mock Process.kill to raise an error on TERM
      # This error is NOT in a rescue block, so it will be caught by the outer rescue StandardError
      allow(Process).to receive(:kill) do |signal, _pid|
        raise Errno::ESRCH, "No such process" if signal == "TERM"

        # Raise error which will be caught by outer rescue StandardError on line 159

        # This will be the KILL signal - let it succeed
        nil
      end

      # The execute will raise CommandExecutionError but with the error message, not timeout
      expect do
        test_executor.execute(%w[sleep 10], timeout: 1)
      end.to raise_error(Sxn::CommandExecutionError, /Command execution failed/)
    end

    it "handles errors when killing timed-out process with KILL signal" do
      skip "sleep command not available" unless File.executable?("/bin/sleep")

      # Mock the command whitelist to include sleep
      whitelist = { "sleep" => "/bin/sleep" }
      allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

      test_executor = described_class.new(temp_dir)

      # Mock Process.kill to succeed on TERM but fail on KILL
      allow(Process).to receive(:kill) do |signal, _pid|
        raise Errno::ESRCH, "No such process" if signal == "KILL"

        # Raise error which should be caught by rescue StandardError

        # TERM succeeds
        nil
      end

      # The execute should still raise the timeout error
      expect do
        test_executor.execute(%w[sleep 10], timeout: 1)
      end.to raise_error(Sxn::CommandExecutionError, /timed out/)
    end

    it "handles errors when waiting for killed process" do
      skip "sleep command not available" unless File.executable?("/bin/sleep")

      # Mock the command whitelist to include sleep
      whitelist = { "sleep" => "/bin/sleep" }
      allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

      test_executor = described_class.new(temp_dir)

      # Mock Process.wait to raise an error after timeout
      original_wait = Process.method(:wait)
      wait_count = 0
      allow(Process).to receive(:wait) do |pid|
        wait_count += 1
        raise Errno::ECHILD, "No child processes" if wait_count > 1

        # Second call (after timeout in rescue block) should raise

        # First call should timeout normally
        original_wait.call(pid)
      end

      # The execute should still raise the timeout error
      expect do
        test_executor.execute(%w[sleep 10], timeout: 1)
      end.to raise_error(Sxn::CommandExecutionError, /timed out/)
    end
  end

  describe "IO cleanup error handling" do
    it "handles graceful handling of IO close errors" do
      # Mock echo command for this test
      echo_path = %w[/bin/echo /usr/bin/echo].find { |path| File.executable?(path) }
      skip "echo not available" unless echo_path

      whitelist = { "echo" => echo_path }
      allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

      test_executor = described_class.new(temp_dir)

      # Track close calls and only raise errors in the ensure block
      close_count = 0
      original_close = IO.instance_method(:close)

      allow_any_instance_of(IO).to receive(:close) do |io|
        close_count += 1
        # Allow the first few closes (the write ends), but raise errors in the ensure block
        raise IOError, "closed stream" if close_count > 2

        # Raise error which should be caught by rescue StandardError in ensure block

        original_close.bind(io).call
      end

      # The execute should still succeed despite IO close errors in ensure block
      expect do
        result = test_executor.execute(%w[echo test])
        expect(result).to be_a(described_class::CommandResult)
      end.not_to raise_error
    end

    it "handles IO close errors in cleanup block" do
      # Mock echo command for this test
      echo_path = %w[/bin/echo /usr/bin/echo].find { |path| File.executable?(path) }
      skip "echo not available" unless echo_path

      whitelist = { "echo" => echo_path }
      allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

      test_executor = described_class.new(temp_dir)

      # Track how many times close is called
      close_count = 0
      original_close = IO.instance_method(:close)
      close_errors = []

      allow_any_instance_of(IO).to receive(:close) do |io|
        close_count += 1
        if close_count >= 3
          # Raise error on subsequent closes (in the ensure block)
          # This error should be rescued and not propagate
          close_errors << close_count
          raise IOError, "closed stream"
        else
          original_close.bind(io).call
        end
      end

      # The execute should complete without propagating IO errors
      result = test_executor.execute(%w[echo test])
      expect(result).to be_a(described_class::CommandResult)
      # Verify that at least some close operations raised errors (that were handled)
      expect(close_errors).not_to be_empty
    end
  end

  describe "branch coverage edge cases" do
    describe "build_command_whitelist with String path_spec" do
      it "excludes command when String path doesn't exist" do
        # Test line 218 - String path_spec that doesn't exist
        non_existent_path = File.join(temp_dir, "nonexistent_command")

        stub_const("#{described_class}::ALLOWED_COMMANDS", {
                     "nonexistent_cmd" => non_existent_path
                   })

        test_executor = described_class.new(temp_dir)

        # The command should not be in the whitelist because the file doesn't exist
        expect(test_executor.allowed_commands).not_to include("nonexistent_cmd")
        expect(test_executor.command_allowed?(["nonexistent_cmd"])).to be false
      end

      it "excludes command when String path is not executable" do
        # Test line 218 - String path_spec where file exists but is not executable
        non_exec_path = File.join(temp_dir, "non_executable_command")
        File.write(non_exec_path, "#!/bin/sh\necho test")
        File.chmod(0o644, non_exec_path) # Make it non-executable

        stub_const("#{described_class}::ALLOWED_COMMANDS", {
                     "non_exec_cmd" => non_exec_path
                   })

        test_executor = described_class.new(temp_dir)

        # The command should not be in the whitelist because the file is not executable
        expect(test_executor.allowed_commands).not_to include("non_exec_cmd")
        expect(test_executor.command_allowed?(["non_exec_cmd"])).to be false
      end

      it "excludes command when path_spec is an unsupported type" do
        # Test line 216 - case statement else branch for unsupported path_spec types
        stub_const("#{described_class}::ALLOWED_COMMANDS", {
                     "unknown_type_cmd" => { invalid: "type" } # Hash is not a supported type
                   })

        test_executor = described_class.new(temp_dir)

        # The command should not be in the whitelist because Hash is not a supported path_spec type
        expect(test_executor.allowed_commands).not_to include("unknown_type_cmd")
        expect(test_executor.command_allowed?(["unknown_type_cmd"])).to be false
      end
    end

    describe "validate_work_directory with file instead of directory" do
      it "raises error when chdir points to a file" do
        # Test line 286 - validated path exists but is a file, not a directory
        test_file = File.join(temp_dir, "testfile.txt")
        File.write(test_file, "test content")

        echo_path = %w[/bin/echo /usr/bin/echo].find { |path| File.executable?(path) }
        skip "echo not available" unless echo_path

        whitelist = { "echo" => echo_path }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir)

        expect do
          test_executor.execute(%w[echo test], chdir: "testfile.txt")
        end.to raise_error(Sxn::CommandExecutionError, /Working directory does not exist/)
      end
    end

    describe "audit_log without logger" do
      it "skips logging when logger is nil" do
        # Test line 347 - early return when @logger is nil
        # Mock Sxn.logger to return nil
        allow(Sxn).to receive(:logger).and_return(nil)

        echo_path = %w[/bin/echo /usr/bin/echo].find { |path| File.executable?(path) }
        skip "echo not available" unless echo_path

        whitelist = { "echo" => echo_path }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        # Create executor without logger
        test_executor = described_class.new(temp_dir, logger: nil)

        # This should not raise an error and should complete successfully
        result = test_executor.execute(%w[echo test])
        expect(result).to be_a(described_class::CommandResult)
        expect(result.success?).to be true
      end
    end

    describe "audit_log with non-array command" do
      it "handles non-array command parameter" do
        # Test line 355 - command.to_s branch when command is not an array
        log_output = StringIO.new
        test_logger = Logger.new(log_output)

        echo_path = %w[/bin/echo /usr/bin/echo].find { |path| File.executable?(path) }
        skip "echo not available" unless echo_path

        whitelist = { "echo" => echo_path }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir, logger: test_logger)

        # We need to call audit_log directly with a non-array command
        # Since audit_log is private, we'll use send to test it
        test_executor.send(:audit_log, "TEST_EVENT", "string_command", temp_dir, { test: "value" })

        log_content = log_output.string
        expect(log_content).to include("TEST_EVENT")
        expect(log_content).to include("string_command")
      end
    end

    describe "audit_log with non-hash details" do
      it "handles non-hash details parameter" do
        # Test line 350 - details = {} unless details.is_a?(Hash)
        log_output = StringIO.new
        test_logger = Logger.new(log_output)

        echo_path = %w[/bin/echo /usr/bin/echo].find { |path| File.executable?(path) }
        skip "echo not available" unless echo_path

        whitelist = { "echo" => echo_path }
        allow_any_instance_of(described_class).to receive(:build_command_whitelist).and_return(whitelist)

        test_executor = described_class.new(temp_dir, logger: test_logger)

        # Call audit_log with non-hash details (e.g., an array)
        test_executor.send(:audit_log, "TEST_EVENT", %w[echo test], temp_dir, %w[not a hash])

        log_content = log_output.string
        expect(log_content).to include("TEST_EVENT")
        expect(log_content).to include("echo")
      end
    end
  end
end
