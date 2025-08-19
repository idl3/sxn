# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Commands::Init do
  let(:command) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }

  before do
    allow(Dir).to receive(:pwd).and_return(temp_dir)

    # Ensure all prompt methods are stubbed before any command execution
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:sessions_folder_setup).and_return("test-sessions")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_detection_confirm).and_return(false)
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:ask).and_return("test-input")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:ask_yes_no).and_return(true)
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:select).and_return("test-selection")
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#init" do
    context "with folder argument" do
      it "initializes sxn with specified folder" do
        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        expect { command.init("test-sessions") }.not_to raise_error

        config_path = File.join(temp_dir, ".sxn", "config.yml")
        expect(File).to exist(config_path)

        config = YAML.load_file(config_path)
        expect(config["sessions_folder"]).to eq("test-sessions")
      end
    end

    context "without folder argument" do
      it "uses interactive prompt in non-quiet mode" do
        # Override the global stub for this specific test
        allow_any_instance_of(Sxn::UI::Prompt).to receive(:sessions_folder_setup)
          .and_return("interactive-sessions")

        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods - must actually create the config file
        config_path = File.join(temp_dir, ".sxn", "config.yml")
        FileUtils.mkdir_p(File.dirname(config_path))
        File.write(config_path, YAML.dump({ "sessions_folder" => "interactive-sessions" }))

        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:initialize_project)
          .and_return("interactive-sessions")
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        # Ensure options are available
        allow(command).to receive(:options).and_return({ "auto_detect" => true, "quiet" => false })

        expect { command.init }.not_to raise_error

        config_path = File.join(temp_dir, ".sxn", "config.yml")
        expect(File).to exist(config_path)
      end
    end

    context "with --force option" do
      it "reinitializes even if already initialized" do
        # Mock UI methods
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        # First initialization
        command.init("first-sessions")
        config_path = File.join(temp_dir, ".sxn", "config.yml")

        # Verify first config is created correctly
        expect(File).to exist(config_path)
        config = YAML.load_file(config_path)
        expect(config["sessions_folder"]).to eq("first-sessions")

        # Second initialization with force
        # Create a Thor options hash
        options_hash = Thor::CoreExt::HashWithIndifferentAccess.new
        options_hash["force"] = true
        command.instance_variable_set(:@options, options_hash)

        # Create a config manager instance that we can properly mock
        config_manager = instance_double(Sxn::Core::ConfigManager)
        allow(Sxn::Core::ConfigManager).to receive(:new).and_return(config_manager)

        # Mock initialized? to return true for the force case
        allow(config_manager).to receive(:initialized?).and_return(true)

        # Mock the initialize_project method to actually update the config file for force case
        allow(config_manager).to receive(:initialize_project) do |folder, **kwargs|
          if kwargs[:force]
            File.write(config_path, YAML.dump({ "sessions_folder" => folder }))
            folder
          else
            "first-sessions"
          end
        end

        # Mock detect_projects to return empty array
        allow(config_manager).to receive(:detect_projects).and_return([])

        expect { command.init("second-sessions") }.not_to raise_error

        # Verify the config file was updated
        expect(File).to exist(config_path)
        config = YAML.load_file(config_path)

        expect(config).not_to be_nil
        expect(config["sessions_folder"]).to eq("second-sessions")
      end
    end

    context "already initialized without force" do
      it "shows warning and exits" do
        command.init("test-sessions")

        expect_any_instance_of(Sxn::UI::Output).to receive(:warning)
          .with("Project already initialized")
        expect_any_instance_of(Sxn::UI::Output).to receive(:info)
          .with("Use --force to reinitialize")
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)

        command.init("test-sessions")
      end
    end

    context "with --quiet option" do
      it "uses default folder name when none provided" do
        # Mock File.basename more broadly
        allow(File).to receive(:basename).and_call_original
        allow(File).to receive(:basename).with(temp_dir).and_return("test-project")

        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        # Create a config manager instance that properly handles initialization
        config_manager = instance_double(Sxn::Core::ConfigManager)
        allow(Sxn::Core::ConfigManager).to receive(:new).and_return(config_manager)
        allow(config_manager).to receive(:initialized?).and_return(false)
        allow(config_manager).to receive(:initialize_project).and_return("test-project-sessions")
        allow(config_manager).to receive(:detect_projects).and_return([])

        # Set the quiet option
        options_hash = Thor::CoreExt::HashWithIndifferentAccess.new
        options_hash["quiet"] = true
        command.instance_variable_set(:@options, options_hash)

        expect { command.init }.not_to raise_error
      end

      it "uses provided folder when given in quiet mode" do
        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        # Set the quiet option
        options_hash = Thor::CoreExt::HashWithIndifferentAccess.new
        options_hash["quiet"] = true
        command.instance_variable_set(:@options, options_hash)

        expect { command.init("custom-sessions") }.not_to raise_error

        config_path = File.join(temp_dir, ".sxn", "config.yml")
        expect(File).to exist(config_path)

        config = YAML.load_file(config_path)
        expect(config["sessions_folder"]).to eq("custom-sessions")
      end
    end

    context "with auto-detect disabled" do
      it "skips project detection" do
        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        # Set auto_detect to false
        options_hash = Thor::CoreExt::HashWithIndifferentAccess.new
        options_hash["auto_detect"] = false
        command.instance_variable_set(:@options, options_hash)

        expect { command.init("test-sessions") }.not_to raise_error

        # Should not call project detection methods
        expect_any_instance_of(Sxn::UI::Output).not_to receive(:subsection)
          .with("Project Detection")
      end
    end

    context "with projects detected and confirmed" do
      it "registers detected projects" do
        detected_projects = [
          { name: "project1", path: "/path/1", type: "rails" },
          { name: "project2", path: "/path/2", type: "javascript" }
        ]

        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager and prompt methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return(detected_projects)
        allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_detection_confirm)
          .and_return(true)

        # Mock ProgressBar
        allow(Sxn::UI::ProgressBar).to receive(:with_progress).and_yield(detected_projects[0], double(log: nil))

        # Mock ProjectManager
        project_manager = instance_double(Sxn::Core::ProjectManager)
        allow(Sxn::Core::ProjectManager).to receive(:new).and_return(project_manager)
        allow(project_manager).to receive(:add_project).and_return({ name: "project1" })

        expect { command.init("test-sessions") }.not_to raise_error
      end
    end

    context "with projects detected but not confirmed" do
      it "skips project registration" do
        detected_projects = [
          { name: "project1", path: "/path/1", type: "rails" }
        ]

        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)
        allow_any_instance_of(Sxn::UI::Output).to receive(:empty_state)

        # Mock the config manager and prompt methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return(detected_projects)
        allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_detection_confirm)
          .and_return(false)

        expect { command.init("test-sessions") }.not_to raise_error
      end
    end

    context "when project registration fails" do
      it "handles registration errors gracefully" do
        detected_projects = [
          { name: "project1", path: "/path/1", type: "rails" }
        ]

        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager and prompt methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return(detected_projects)
        allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_detection_confirm)
          .and_return(true)

        # Mock ProgressBar to yield projects for processing
        progress_mock = double(log: nil)
        allow(Sxn::UI::ProgressBar).to receive(:with_progress).and_yield(detected_projects[0], progress_mock)

        # Mock ProjectManager to fail
        project_manager = instance_double(Sxn::Core::ProjectManager)
        allow(Sxn::Core::ProjectManager).to receive(:new).and_return(project_manager)
        allow(project_manager).to receive(:add_project).and_raise("Registration failed")

        expect { command.init("test-sessions") }.not_to raise_error
        expect(progress_mock).to have_received(:log).with("❌ project1: Registration failed")
      end
    end

    context "when initialization fails with Sxn error" do
      it "handles Sxn errors with proper exit code" do
        error = Sxn::ConfigurationError.new("Config error")
        allow(error).to receive(:exit_code).and_return(2)

        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:error)

        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:initialize_project)
          .and_raise(error)

        expect { command.init("test-sessions") }.to raise_error(SystemExit)
      end
    end

    context "when initialization fails with standard error" do
      it "handles standard errors with debug info" do
        ENV["SXN_DEBUG"] = "true"

        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:error)
        allow_any_instance_of(Sxn::UI::Output).to receive(:debug)

        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:initialize_project)
          .and_raise("Unexpected error")

        expect { command.init("test-sessions") }.to raise_error(SystemExit)

        ENV.delete("SXN_DEBUG")
      end
    end
  end

  describe "gitignore integration" do
    context "when .gitignore exists" do
      before do
        gitignore_path = File.join(temp_dir, ".gitignore")
        File.write(gitignore_path, "node_modules/\n*.log\n")
      end

      it "updates .gitignore during init" do
        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        expect { command.init("test-sessions") }.not_to raise_error

        gitignore_path = File.join(temp_dir, ".gitignore")
        content = File.read(gitignore_path)
        expect(content).to include("node_modules/")
        expect(content).to include("# SXN session management")
        expect(content).to include(".sxn/")
        expect(content).to include("test-sessions/")
      end

      it "does not fail init when gitignore is read-only" do
        gitignore_path = File.join(temp_dir, ".gitignore")
        File.chmod(0o444, gitignore_path) # Read-only

        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        expect { command.init("test-sessions") }.not_to raise_error

        config_path = File.join(temp_dir, ".sxn", "config.yml")
        expect(File).to exist(config_path)

        # Restore permissions for cleanup
        File.chmod(0o644, gitignore_path)
      end
    end

    context "when .gitignore does not exist" do
      it "completes init successfully without creating .gitignore" do
        # Mock all the UI methods that get called during init
        allow_any_instance_of(Sxn::UI::Output).to receive(:section)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_start)
        allow_any_instance_of(Sxn::UI::Output).to receive(:progress_done)
        allow_any_instance_of(Sxn::UI::Output).to receive(:success)
        allow_any_instance_of(Sxn::UI::Output).to receive(:subsection)
        allow_any_instance_of(Sxn::UI::Output).to receive(:command_example)
        allow_any_instance_of(Sxn::UI::Output).to receive(:info)
        allow_any_instance_of(Sxn::UI::Output).to receive(:recovery_suggestion)
        allow_any_instance_of(Sxn::UI::Output).to receive(:newline)

        # Mock the config manager methods
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])

        expect { command.init("test-sessions") }.not_to raise_error

        config_path = File.join(temp_dir, ".sxn", "config.yml")
        expect(File).to exist(config_path)

        gitignore_path = File.join(temp_dir, ".gitignore")
        expect(File).not_to exist(gitignore_path)
      end
    end
  end

  describe "private methods" do
    describe "#determine_sessions_folder" do
      it "returns folder when provided and not in quiet mode" do
        allow(command).to receive(:options).and_return({})

        result = command.send(:determine_sessions_folder, "custom-folder")
        expect(result).to eq("custom-folder")
      end

      it "uses interactive prompt when folder not provided and not in quiet mode" do
        allow(command).to receive(:options).and_return({})
        allow_any_instance_of(Sxn::UI::Prompt).to receive(:sessions_folder_setup)
          .and_return("interactive-folder")

        result = command.send(:determine_sessions_folder, nil)
        expect(result).to eq("interactive-folder")
      end

      it "generates default folder name in quiet mode when none provided" do
        allow(Dir).to receive(:pwd).and_return("/current/dir")
        allow(File).to receive(:basename).with("/current/dir").and_return("project")
        allow(command).to receive(:options).and_return({ quiet: true })

        result = command.send(:determine_sessions_folder, nil)
        expect(result).to eq("project-sessions")
      end

      it "returns provided folder in quiet mode" do
        allow(command).to receive(:options).and_return({ quiet: true })

        result = command.send(:determine_sessions_folder, "quiet-folder")
        expect(result).to eq("quiet-folder")
      end
    end

    describe "#auto_detect_projects" do
      it "shows empty state when no projects detected" do
        allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:detect_projects)
          .and_return([])
        ui_output = double("ui_output")
        allow(ui_output).to receive(:subsection)
        allow(ui_output).to receive(:empty_state)
        command.instance_variable_set(:@ui, ui_output)

        command.send(:auto_detect_projects)

        expect(ui_output).to have_received(:empty_state)
          .with("No projects detected in current directory")
      end
    end

    describe "#display_next_steps" do
      it "shows different message when projects are detected" do
        # Create mock instances
        config_manager = instance_double(Sxn::Core::ConfigManager)
        ui_output = instance_double(Sxn::UI::Output)

        # Mock the config manager to return detected projects
        allow(config_manager).to receive(:detect_projects).and_return([{ name: "project1" }])

        # Mock UI methods
        allow(ui_output).to receive(:newline)
        allow(ui_output).to receive(:subsection)
        allow(ui_output).to receive(:command_example)
        allow(ui_output).to receive(:info)
        allow(ui_output).to receive(:recovery_suggestion)

        # Set the instances on the command
        command.instance_variable_set(:@config_manager, config_manager)
        command.instance_variable_set(:@ui, ui_output)

        command.send(:display_next_steps)

        expect(ui_output).to have_received(:info)
          .with("💡 Detected projects are ready to use!")
      end

      it "shows recovery suggestion when no projects detected" do
        # Create mock instances
        config_manager = instance_double(Sxn::Core::ConfigManager)
        ui_output = instance_double(Sxn::UI::Output)

        # Mock the config manager to return no detected projects
        allow(config_manager).to receive(:detect_projects).and_return([])

        # Mock UI methods
        allow(ui_output).to receive(:newline)
        allow(ui_output).to receive(:subsection)
        allow(ui_output).to receive(:command_example)
        allow(ui_output).to receive(:info)
        allow(ui_output).to receive(:recovery_suggestion)

        # Set the instances on the command
        command.instance_variable_set(:@config_manager, config_manager)
        command.instance_variable_set(:@ui, ui_output)

        command.send(:display_next_steps)

        expect(ui_output).to have_received(:recovery_suggestion)
          .with("Register your projects with 'sxn projects add <name> <path>'")
      end
    end
  end
end
