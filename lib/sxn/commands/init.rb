# frozen_string_literal: true

require "thor"
require "json"

module Sxn
  module Commands
    # Initialize sxn in a project folder
    class Init < Thor
      include Thor::Actions

      # Shell integration marker - used to identify sxn shell functions
      SHELL_MARKER = "# sxn shell integration"
      SHELL_MARKER_END = "# end sxn shell integration"

      # Claude Code integration paths
      CLAUDE_HELPERS_DIR = File.join(Dir.home, ".claude", "helpers")
      CLAUDE_HOOK_SCRIPT = "sxn-session-check.sh"
      CLAUDE_HOOK_PATH = File.join(CLAUDE_HELPERS_DIR, CLAUDE_HOOK_SCRIPT)

      # Shell function that gets installed
      SHELL_FUNCTION = <<~SHELL.freeze
        #{SHELL_MARKER}
        sxn-enter() {
          local cmd
          cmd="$(sxn enter 2>/dev/null)"
          if [ $? -eq 0 ] && [ -n "$cmd" ]; then
            eval "$cmd"
          else
            sxn enter
          fi
        }
        sxn-up() {
          local cmd
          cmd="$(sxn up 2>/dev/null)"
          if [ $? -eq 0 ] && [ -n "$cmd" ]; then
            eval "$cmd"
          else
            sxn up
          fi
        }
        #{SHELL_MARKER_END}
      SHELL

      desc "init [FOLDER]", "Initialize sxn in a project folder"
      option :force, type: :boolean, desc: "Force initialization even if already initialized"
      option :auto_detect, type: :boolean, default: true, desc: "Automatically detect and register projects"
      option :quiet, type: :boolean, aliases: "-q", desc: "Suppress interactive prompts"
      option :claude_code, type: :boolean, default: true, desc: "Install Claude Code session enforcement hooks"

      def initialize(args = ARGV, local_options = {}, config = {})
        super
        @ui = Sxn::UI::Output.new
        @prompt = Sxn::UI::Prompt.new
        @config_manager = Sxn::Core::ConfigManager.new
      end

      def init(folder = nil)
        @ui.section("Sxn Initialization")

        # Check if already initialized
        if @config_manager.initialized? && !options[:force]
          @ui.warning("Project already initialized")
          @ui.info("Use --force to reinitialize")
          return
        end

        # Get sessions folder
        sessions_folder = determine_sessions_folder(folder)

        begin
          # Initialize configuration
          @ui.progress_start("Creating configuration")
          result_folder = @config_manager.initialize_project(sessions_folder, force: options[:force])
          @ui.progress_done

          @ui.success("Initialized sxn in #{result_folder}")

          # Auto-detect projects if enabled
          auto_detect_projects if options[:auto_detect] && !options[:quiet]

          # Install Claude Code hooks if enabled
          setup_claude_code_hooks if options[:claude_code]

          display_next_steps
        rescue Sxn::Error => e
          @ui.error("Initialization failed: #{e.message}")
          exit(e.exit_code)
        rescue StandardError => e
          @ui.error("Unexpected error: #{e.message}")
          @ui.debug(e.backtrace.join("\n")) if ENV["SXN_DEBUG"]
          exit(1)
        end
      end

      desc "install_claude_hooks", "Install Claude Code session enforcement hooks"
      option :force, type: :boolean, default: false, desc: "Force reinstallation even if already installed"
      option :uninstall, type: :boolean, default: false, desc: "Remove Claude Code hooks"
      def install_claude_hooks
        @ui.section("Claude Code Hooks")

        # Check if sxn is initialized
        unless @config_manager.initialized?
          @ui.error("Project not initialized. Run 'sxn init' first.")
          exit(1)
        end

        if options[:uninstall]
          uninstall_claude_code_hooks
        else
          setup_claude_code_hooks
          @ui.newline
          @ui.recovery_suggestion("Claude Code will now enforce session-based development in this project")
        end
      end

      desc "install_shell", "Install shell integration (sxn-enter function)"
      option :shell_type, type: :string, enum: %w[bash zsh auto], default: "auto",
                          desc: "Shell type (bash, zsh, or auto-detect)"
      option :uninstall, type: :boolean, default: false, desc: "Remove shell integration"
      def install_shell
        @ui.section("Shell Integration")

        shell_type = detect_shell_type
        rc_file = shell_rc_file(shell_type)

        unless rc_file
          @ui.error("Could not determine shell configuration file")
          @ui.info("Supported shells: bash, zsh")
          exit(1)
        end

        if options[:uninstall]
          uninstall_shell_integration(rc_file, shell_type)
        else
          install_shell_integration(rc_file, shell_type)
        end
      end

      private

      def detect_shell_type
        shell_opt = options[:shell_type] || options[:shell] || "auto"
        return shell_opt unless shell_opt == "auto"

        # Check SHELL environment variable
        current_shell = ENV.fetch("SHELL", "")
        if current_shell.include?("zsh")
          "zsh"
        elsif current_shell.include?("bash")
          "bash"
        else
          # Default to bash
          "bash"
        end
      end

      def shell_rc_file(shell_type)
        home = Dir.home
        case shell_type
        when "zsh"
          File.join(home, ".zshrc")
        when "bash"
          # Prefer .bashrc, fall back to .bash_profile on macOS
          bashrc = File.join(home, ".bashrc")
          bash_profile = File.join(home, ".bash_profile")
          File.exist?(bashrc) ? bashrc : bash_profile
        end
      end

      def shell_integration_installed?(rc_file)
        return false unless File.exist?(rc_file)

        content = File.read(rc_file)
        content.include?(SHELL_MARKER)
      end

      def install_shell_integration(rc_file, _shell_type)
        if shell_integration_installed?(rc_file)
          @ui.info("Shell integration already installed in #{rc_file}")
          @ui.info("Use --uninstall to remove it first if you want to reinstall")
          return
        end

        # Ensure rc file exists
        FileUtils.touch(rc_file) unless File.exist?(rc_file)

        # Append shell function
        File.open(rc_file, "a") do |f|
          f.puts "" # Add blank line before
          f.puts SHELL_FUNCTION
        end

        @ui.success("Installed shell integration to #{rc_file}")
        @ui.newline
        @ui.info("The following functions were added:")
        @ui.newline
        puts "  sxn-enter  - Navigate to current session directory"
        puts "  sxn-up     - Navigate to project root from session"
        @ui.newline
        @ui.recovery_suggestion("Run 'source #{rc_file}' or restart your shell to use them")
      end

      def uninstall_shell_integration(rc_file, _shell_type)
        unless File.exist?(rc_file)
          @ui.info("Shell configuration file not found: #{rc_file}")
          return
        end

        unless shell_integration_installed?(rc_file)
          @ui.info("Shell integration not installed in #{rc_file}")
          return
        end

        # Read file and remove sxn block
        content = File.read(rc_file)
        # Remove the block between markers (including blank line before)
        pattern = /\n?#{Regexp.escape(SHELL_MARKER)}.*?#{Regexp.escape(SHELL_MARKER_END)}\n?/m
        new_content = content.gsub(pattern, "\n")

        File.write(rc_file, new_content)

        @ui.success("Removed shell integration from #{rc_file}")
        @ui.recovery_suggestion("Run 'source #{rc_file}' or restart your shell")
      end

      def determine_sessions_folder(folder)
        return folder if folder && !options[:quiet]

        if options[:quiet]
          # Use default folder in quiet mode
          return folder || "#{File.basename(Dir.pwd)}-sessions"
        end

        # Interactive mode
        @prompt.sessions_folder_setup
      end

      def auto_detect_projects
        @ui.subsection("Project Detection")

        detected = @config_manager.detect_projects

        if detected.empty?
          @ui.empty_state("No projects detected in current directory")
          return
        end

        if @prompt.project_detection_confirm(detected)
          register_detected_projects(detected)
        else
          @ui.info("Skipped project registration")
          @ui.info("You can register projects later with: sxn projects add <name> <path>")
        end
      end

      def register_detected_projects(projects)
        project_manager = Sxn::Core::ProjectManager.new(@config_manager)

        Sxn::UI::ProgressBar.with_progress("Registering projects", projects) do |project, progress|
          result = project_manager.add_project(
            project[:name],
            project[:path],
            type: project[:type]
          )

          progress.log("✅ #{project[:name]} (#{project[:type]})")
          result
        rescue StandardError => e
          progress.log("❌ #{project[:name]}: #{e.message}")
          nil
        end

        @ui.success("Project registration completed")
      end

      def display_next_steps
        @ui.newline
        @ui.subsection("Next Steps")

        @ui.command_example(
          "sxn projects list",
          "View registered projects"
        )

        @ui.command_example(
          "sxn add my-session",
          "Create your first session"
        )

        @ui.command_example(
          "sxn worktree add <project> [branch]",
          "Add a worktree to your session"
        )

        if @config_manager.detect_projects.any?
          @ui.info("💡 Detected projects are ready to use!")
        else
          @ui.recovery_suggestion("Register your projects with 'sxn projects add <name> <path>'")
        end
      end

      # Claude Code Integration
      def setup_claude_code_hooks
        @ui.subsection("Claude Code Integration")

        # Step 1: Install global hook script
        install_claude_hook_script

        # Step 2: Setup project-level settings
        setup_project_claude_settings
      end

      def install_claude_hook_script
        # Create helpers directory if needed
        FileUtils.mkdir_p(CLAUDE_HELPERS_DIR)

        if File.exist?(CLAUDE_HOOK_PATH) && !options[:force]
          @ui.info("Global hook script already installed at #{CLAUDE_HOOK_PATH}")
          return
        end

        @ui.progress_start("Installing global hook script")

        # Use template engine to generate hook script
        template_path = File.join(
          File.dirname(__FILE__), "..", "templates", "claude_code", "sxn-session-check.sh.liquid"
        )

        if File.exist?(template_path)
          # Process template with variables
          template_content = File.read(template_path)
          processor = Sxn::Templates::TemplateProcessor.new
          result = processor.process(template_content, { timestamp: Time.now })
          File.write(CLAUDE_HOOK_PATH, result)
        else
          # Fallback: copy from existing global location if available
          @ui.warning("Template not found, skipping hook script installation")
          @ui.progress_done
          return
        end

        # Make executable
        FileUtils.chmod(0o755, CLAUDE_HOOK_PATH)

        @ui.progress_done
        @ui.success("Installed hook script to #{CLAUDE_HOOK_PATH}")
      end

      def setup_project_claude_settings
        project_claude_dir = File.join(Dir.pwd, ".claude")
        project_settings_path = File.join(project_claude_dir, "settings.json")

        # Create .claude directory if needed
        FileUtils.mkdir_p(project_claude_dir)

        @ui.progress_start("Configuring project Claude settings")

        if File.exist?(project_settings_path)
          # Merge hooks into existing settings
          merge_claude_hooks_into_settings(project_settings_path)
        else
          # Create new settings file
          create_claude_settings(project_settings_path)
        end

        @ui.progress_done
        @ui.success("Claude Code session enforcement enabled")
        @ui.info("Hook script: #{CLAUDE_HOOK_PATH}")
      end

      def create_claude_settings(settings_path)
        settings = {
          "hooks" => {
            "UserPromptSubmit" => [
              {
                "matcher" => "",
                "hooks" => [
                  {
                    "type" => "command",
                    "command" => CLAUDE_HOOK_PATH,
                    "timeout" => 15_000
                  }
                ]
              }
            ]
          }
        }

        File.write(settings_path, JSON.pretty_generate(settings))
      end

      def merge_claude_hooks_into_settings(settings_path)
        existing = JSON.parse(File.read(settings_path))

        # Initialize hooks if not present
        existing["hooks"] ||= {}

        # Check if UserPromptSubmit already configured
        if existing["hooks"]["UserPromptSubmit"]
          # Check if our hook is already there
          hooks = existing["hooks"]["UserPromptSubmit"]
          already_installed = hooks.any? do |h|
            h["hooks"]&.any? { |inner| inner["command"]&.include?("sxn-session-check") }
          end

          if already_installed
            @ui.info("Claude Code hooks already configured in project settings")
            return
          end
        end

        # Add our hook
        existing["hooks"]["UserPromptSubmit"] ||= []
        existing["hooks"]["UserPromptSubmit"] << {
          "matcher" => "",
          "hooks" => [
            {
              "type" => "command",
              "command" => CLAUDE_HOOK_PATH,
              "timeout" => 15_000
            }
          ]
        }

        File.write(settings_path, JSON.pretty_generate(existing))
      end

      def uninstall_claude_code_hooks
        @ui.subsection("Removing Claude Code Integration")

        # Remove from project settings
        remove_project_claude_hooks

        # NOTE: We don't remove the global hook script as other projects may use it
        @ui.info("Note: Global hook script at #{CLAUDE_HOOK_PATH} was not removed")
        @ui.info("      (other projects may still use it)")
      end

      def remove_project_claude_hooks
        project_settings_path = File.join(Dir.pwd, ".claude", "settings.json")

        unless File.exist?(project_settings_path)
          @ui.info("No Claude settings file found in this project")
          return
        end

        @ui.progress_start("Removing hooks from project settings")

        existing = JSON.parse(File.read(project_settings_path))

        if existing["hooks"]&.dig("UserPromptSubmit")
          # Remove hooks that reference sxn-session-check
          existing["hooks"]["UserPromptSubmit"].reject! do |h|
            h["hooks"]&.any? { |inner| inner["command"]&.include?("sxn-session-check") }
          end

          # Clean up empty arrays
          existing["hooks"].delete("UserPromptSubmit") if existing["hooks"]["UserPromptSubmit"] && existing["hooks"]["UserPromptSubmit"].empty?
          existing.delete("hooks") if existing["hooks"] && existing["hooks"].empty?

          if existing.empty?
            File.delete(project_settings_path)
            @ui.progress_done
            @ui.success("Removed settings.json (was empty after removing hooks)")
          else
            File.write(project_settings_path, JSON.pretty_generate(existing))
            @ui.progress_done
            @ui.success("Removed sxn hooks from project settings")
          end
        else
          @ui.progress_done
          @ui.info("No sxn hooks found in project settings")
        end
      end
    end
  end
end
