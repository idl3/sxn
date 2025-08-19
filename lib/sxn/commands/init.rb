# frozen_string_literal: true

require "thor"

module Sxn
  module Commands
    # Initialize sxn in a project folder
    class Init < Thor
      include Thor::Actions

      desc "init [FOLDER]", "Initialize sxn in a project folder"
      option :force, type: :boolean, desc: "Force initialization even if already initialized"
      option :auto_detect, type: :boolean, default: true, desc: "Automatically detect and register projects"
      option :quiet, type: :boolean, aliases: "-q", desc: "Suppress interactive prompts"

      def initialize(*)
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
          if options[:auto_detect] && !options[:quiet]
            auto_detect_projects
          end

          display_next_steps

        rescue Sxn::Error => e
          @ui.error("Initialization failed: #{e.message}")
          exit(e.exit_code)
        rescue => e
          @ui.error("Unexpected error: #{e.message}")
          @ui.debug(e.backtrace.join("\n")) if ENV["SXN_DEBUG"]
          exit(1)
        end
      end

      private

      def determine_sessions_folder(folder)
        return folder if folder && !options[:quiet]

        if options[:quiet]
          # Use default folder in quiet mode
          return folder || File.basename(Dir.pwd) + "-sessions"
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
          begin
            result = project_manager.add_project(
              project[:name],
              project[:path],
              type: project[:type]
            )
            
            progress.log("✅ #{project[:name]} (#{project[:type]})")
            result
          rescue => e
            progress.log("❌ #{project[:name]}: #{e.message}")
            nil
          end
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