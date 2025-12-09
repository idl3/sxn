# frozen_string_literal: true

require "thor"

module Sxn
  module Commands
    # Initialize sxn in a project folder
    class Init < Thor
      include Thor::Actions

      # Shell integration marker - used to identify sxn shell functions
      SHELL_MARKER = "# sxn shell integration"
      SHELL_MARKER_END = "# end sxn shell integration"

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
    end
  end
end
