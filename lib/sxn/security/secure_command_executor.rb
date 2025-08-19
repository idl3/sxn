# frozen_string_literal: true

require "English"
require "open3"
require "ostruct"
require "timeout"
require "json"

module Sxn
  module Security
    # SecureCommandExecutor provides secure command execution with strict controls.
    # It prevents shell interpolation by using Process.spawn with arrays,
    # whitelists allowed commands, cleans environment variables, and logs all executions.
    #
    # @example
    #   executor = SecureCommandExecutor.new("/path/to/project")
    #   result = executor.execute(["bundle", "install"], env: {"RAILS_ENV" => "development"})
    #   puts result.success? # => true/false
    #   puts result.stdout   # => command output
    #
    class SecureCommandExecutor
      # Command execution result
      class CommandResult
        attr_reader :exit_status, :stdout, :stderr, :command, :duration

        def initialize(exit_status, stdout, stderr, command, duration)
          @exit_status = exit_status
          @stdout = stdout || ""
          @stderr = stderr || ""
          @command = command
          @duration = duration
        end

        def success?
          @exit_status.zero?
        end

        def failure?
          !success?
        end

        def to_h
          {
            exit_status: @exit_status,
            stdout: @stdout,
            stderr: @stderr,
            command: @command,
            duration: @duration,
            success: success?
          }
        end
      end

      # Whitelist of allowed commands with their expected paths
      # Commands are mapped to either:
      # - String: exact path to executable
      # - Array: list of possible paths (first existing one is used)
      # - Symbol: special handling required
      ALLOWED_COMMANDS = {
        # Ruby/Rails commands
        "bundle" => %w[bundle /usr/local/bin/bundle /opt/homebrew/bin/bundle],
        "gem" => %w[gem /usr/local/bin/gem /opt/homebrew/bin/gem],
        "ruby" => %w[ruby /usr/local/bin/ruby /opt/homebrew/bin/ruby],
        "rails" => :rails_command, # Special handling for bin/rails vs rails

        # Node.js commands
        "npm" => %w[npm /usr/local/bin/npm /opt/homebrew/bin/npm],
        "yarn" => %w[yarn /usr/local/bin/yarn /opt/homebrew/bin/yarn],
        "pnpm" => %w[pnpm /usr/local/bin/pnpm /opt/homebrew/bin/pnpm],
        "node" => %w[node /usr/local/bin/node /opt/homebrew/bin/node],

        # Git commands
        "git" => %w[git /usr/bin/git /usr/local/bin/git /opt/homebrew/bin/git],

        # Database commands
        "psql" => %w[psql /usr/local/bin/psql /opt/homebrew/bin/psql],
        "mysql" => %w[mysql /usr/local/bin/mysql /opt/homebrew/bin/mysql],
        "sqlite3" => %w[sqlite3 /usr/bin/sqlite3 /usr/local/bin/sqlite3],

        # Development tools
        "make" => %w[make /usr/bin/make],
        "curl" => %w[curl /usr/bin/curl /usr/local/bin/curl],
        "wget" => %w[wget /usr/bin/wget /usr/local/bin/wget],

        # Project-specific executables (resolved relative to project)
        "bin/rails" => :project_executable,
        "bin/setup" => :project_executable,
        "bin/dev" => :project_executable,
        "bin/test" => :project_executable,
        "./bin/rails" => :project_executable,
        "./bin/setup" => :project_executable
      }.freeze

      # Environment variables that are safe to preserve
      SAFE_ENV_VARS = %w[
        PATH
        HOME
        USER
        LANG
        LC_ALL
        TZ
        TMPDIR
        RAILS_ENV
        NODE_ENV
        BUNDLE_GEMFILE
        GEM_HOME
        GEM_PATH
        RBENV_VERSION
        NVM_DIR
        NVM_BIN
        SSL_CERT_FILE
        SSL_CERT_DIR
      ].freeze

      # Maximum command execution timeout (in seconds)
      MAX_TIMEOUT = 300 # 5 minutes

      # @param project_root [String] The absolute path to the project root directory
      # @param logger [Logger] Optional logger for audit trail
      def initialize(project_root, logger: nil)
        @project_root = File.realpath(project_root)
        @logger = logger || Sxn.logger
        @command_whitelist = build_command_whitelist
      rescue Errno::ENOENT
        raise ArgumentError, "Project root does not exist: #{project_root}"
      end

      # Executes a command securely with strict controls
      #
      # @param command [Array<String>] Command and arguments as an array
      # @param env [Hash] Environment variables to set
      # @param timeout [Integer] Maximum execution time in seconds
      # @param chdir [String] Directory to run command in (must be within project)
      # @return [CommandResult] The execution result
      # @raise [CommandExecutionError] if command is not allowed or execution fails
      def execute(command, env: {}, timeout: 30, chdir: nil)
        raise ArgumentError, "Command must be an array" unless command.is_a?(Array)
        raise ArgumentError, "Command cannot be empty" if command.empty?
        raise ArgumentError, "Timeout must be positive" unless timeout.positive? && timeout <= MAX_TIMEOUT

        validated_command = validate_and_resolve_command(command)
        safe_env = build_safe_environment(env)
        work_dir = chdir ? validate_work_directory(chdir) : @project_root

        start_time = Time.now
        audit_log("EXEC_START", validated_command, work_dir, safe_env.keys)

        begin
          result = execute_with_timeout(validated_command, safe_env, work_dir, timeout)
          duration = Time.now - start_time

          audit_log("EXEC_COMPLETE", validated_command, work_dir, {
                      exit_status: result.exit_status,
                      duration: duration,
                      success: result.success?
                    })

          CommandResult.new(result.exit_status, result.stdout, result.stderr, validated_command, duration)
        rescue StandardError => e
          duration = Time.now - start_time
          audit_log("EXEC_ERROR", validated_command, work_dir, {
                      error: e.class.name,
                      message: e.message,
                      duration: duration
                    })
          raise CommandExecutionError, "Command execution failed: #{e.message}"
        end
      end

      # Checks if a command is allowed without executing it
      #
      # @param command [Array<String>] Command and arguments as an array
      # @return [Boolean] true if the command is whitelisted
      def command_allowed?(command)
        return false unless command.is_a?(Array) && !command.empty?

        begin
          validate_and_resolve_command(command)
          true
        rescue CommandExecutionError
          false
        end
      end

      # Returns the list of allowed commands
      #
      # @return [Array<String>] List of allowed command names
      def allowed_commands
        @command_whitelist.keys.sort
      end

      private

      # Validates that a command is whitelisted and resolves its path
      def validate_and_resolve_command(command)
        command_name = command.first

        unless @command_whitelist.key?(command_name)
          raise CommandExecutionError, "Command not whitelisted: #{command_name}"
        end

        executable_path = @command_whitelist[command_name]

        # Validate that the executable exists and is executable
        unless File.exist?(executable_path) && File.executable?(executable_path)
          raise CommandExecutionError, "Command executable not found or not executable: #{executable_path}"
        end

        # Return command with resolved executable path
        [executable_path] + command[1..]
      end

      # Builds the command whitelist by resolving paths
      def build_command_whitelist
        whitelist = {}

        ALLOWED_COMMANDS.each do |cmd_name, path_spec|
          resolved_path = case path_spec
                          when String
                            path_spec if File.exist?(path_spec) && File.executable?(path_spec)
                          when Array
                            path_spec.find { |path| File.exist?(path) && File.executable?(path) }
                          when :rails_command
                            resolve_rails_command
                          when :project_executable
                            resolve_project_executable(cmd_name)
                          end

          whitelist[cmd_name] = resolved_path if resolved_path
        end

        whitelist
      end

      # Special handling for Rails command (bin/rails vs global rails)
      def resolve_rails_command
        bin_rails = File.join(@project_root, "bin", "rails")
        return bin_rails if File.exist?(bin_rails) && File.executable?(bin_rails)

        # Fall back to global rails command
        %w[rails /usr/local/bin/rails /opt/homebrew/bin/rails].find do |path|
          File.exist?(path) && File.executable?(path)
        end
      end

      # Resolves project-specific executables
      def resolve_project_executable(cmd_name)
        # Remove leading ./ if present
        clean_cmd = cmd_name.sub(%r{\A\./}, "")
        executable_path = File.join(@project_root, clean_cmd)

        return executable_path if File.exist?(executable_path) && File.executable?(executable_path)

        nil
      end

      # Builds a safe environment by filtering and cleaning variables
      def build_safe_environment(user_env)
        safe_env = {}

        # Start with safe environment variables from current environment
        SAFE_ENV_VARS.each do |var|
          safe_env[var] = ENV[var] if ENV.key?(var)
        end

        # Add user-provided environment variables (with validation)
        user_env.each do |key, value|
          key_str = key.to_s
          value_str = value.to_s

          # Validate environment variable names (only alphanumeric and underscore)
          unless key_str.match?(/\A[A-Z_][A-Z0-9_]*\z/)
            raise CommandExecutionError, "Invalid environment variable name: #{key_str}"
          end

          # Validate environment variable values (no null bytes)
          if value_str.include?("\x00")
            raise CommandExecutionError, "Environment variable contains null bytes: #{key_str}"
          end

          safe_env[key_str] = value_str
        end

        safe_env
      end

      # Validates the working directory
      def validate_work_directory(chdir)
        path_validator = SecurePathValidator.new(@project_root)
        validated_path = path_validator.validate_path(chdir)

        raise CommandExecutionError, "Working directory does not exist: #{chdir}" unless File.directory?(validated_path)

        validated_path
      end

      # Executes command with timeout and captures output
      def execute_with_timeout(command, env, chdir, timeout)
        stdout_r, stdout_w = IO.pipe
        stderr_r, stderr_w = IO.pipe

        begin
          pid = Process.spawn(
            env,
            *command,
            chdir: chdir,
            out: stdout_w,
            err: stderr_w,
            unsetenv_others: true, # Clear all other environment variables
            close_others: true     # Close other file descriptors
          )

          stdout_w.close
          stderr_w.close

          # Wait for process with timeout
          begin
            Timeout.timeout(timeout) do
              Process.wait(pid)
            end
          rescue Timeout::Error
            Process.kill("TERM", pid)
            sleep(1)
            begin
              Process.kill("KILL", pid)
            rescue StandardError
              nil
            end
            begin
              Process.wait(pid)
            rescue StandardError
              nil
            end
            raise CommandExecutionError, "Command timed out after #{timeout} seconds"
          end

          exit_status = $CHILD_STATUS.exitstatus
          stdout = stdout_r.read
          stderr = stderr_r.read

          OpenStruct.new(exit_status: exit_status, stdout: stdout, stderr: stderr)
        ensure
          [stdout_r, stdout_w, stderr_r, stderr_w].each do |io|
            io.close
          rescue StandardError
            nil
          end
        end
      end

      # Logs command execution for audit trail
      def audit_log(event, command, chdir, details = {})
        return unless @logger

        # Ensure details is a hash
        details = {} unless details.is_a?(Hash)

        log_entry = {
          timestamp: Time.now.iso8601,
          event: event,
          command: command.is_a?(Array) ? command.first : command.to_s, # Only log the executable, not full command for security
          chdir: chdir,
          pid: Process.pid
        }.merge(details)

        @logger.info("SECURITY_AUDIT: #{log_entry.to_json}")
      end
    end
  end
end
