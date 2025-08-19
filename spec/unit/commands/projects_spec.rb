# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Commands::Projects do
  let(:mock_ui) { instance_double(Sxn::UI::Output) }
  let(:mock_prompt) { instance_double(Sxn::UI::Prompt) }
  let(:mock_table) { instance_double(Sxn::UI::Table) }
  let(:mock_config_manager) { instance_double(Sxn::Core::ConfigManager) }
  let(:mock_project_manager) { instance_double(Sxn::Core::ProjectManager) }
  let(:mock_rules_manager) { instance_double(Sxn::Core::RulesManager) }

  let(:sample_project) do
    {
      name: "test-project",
      path: "/path/to/project",
      type: "rails",
      default_branch: "main"
    }
  end

  let(:projects_command) { described_class.new }

  before do
    allow(Sxn::UI::Output).to receive(:new).and_return(mock_ui)
    allow(Sxn::UI::Prompt).to receive(:new).and_return(mock_prompt)
    allow(Sxn::UI::Table).to receive(:new).and_return(mock_table)
    allow(Sxn::Core::ConfigManager).to receive(:new).and_return(mock_config_manager)
    allow(Sxn::Core::ProjectManager).to receive(:new).and_return(mock_project_manager)
    allow(Sxn::Core::RulesManager).to receive(:new).and_return(mock_rules_manager)

    # Default mock responses
    allow(mock_config_manager).to receive(:initialized?).and_return(true)
    allow(mock_ui).to receive(:progress_start)
    allow(mock_ui).to receive(:progress_done)
    allow(mock_ui).to receive(:progress_failed)
    allow(mock_ui).to receive(:success)
    allow(mock_ui).to receive(:error)
    allow(mock_ui).to receive(:info)
    allow(mock_ui).to receive(:warning)
    allow(mock_ui).to receive(:section)
    allow(mock_ui).to receive(:subsection)
    allow(mock_ui).to receive(:empty_state)
    allow(mock_ui).to receive(:newline)
    allow(mock_ui).to receive(:key_value)
    allow(mock_ui).to receive(:list_item)
    allow(mock_ui).to receive(:command_example)
    allow(mock_ui).to receive(:recovery_suggestion)
    allow(mock_ui).to receive(:debug)
    allow(mock_table).to receive(:projects)
    allow(mock_table).to receive(:rules)

    # Ensure all prompt methods are stubbed
    allow(mock_prompt).to receive(:project_name).and_return("test-project")
    allow(mock_prompt).to receive(:project_path).and_return("/test/path")
    allow(mock_prompt).to receive(:select).and_return("test-selection")
    allow(mock_prompt).to receive(:confirm_deletion).and_return(true)
    allow(mock_prompt).to receive(:ask_yes_no).and_return(true)
  end

  describe "#add" do
    context "with direct arguments" do
      it "adds a project successfully" do
        allow(mock_project_manager).to receive(:add_project).and_return(sample_project)

        projects_command.add("test-project", "/path/to/project")

        expect(mock_project_manager).to have_received(:add_project).with(
          "test-project",
          "/path/to/project",
          type: nil,
          default_branch: nil
        )
        expect(mock_ui).to have_received(:success).with("Added project 'test-project'")
      end

      it "adds a project with options" do
        allow(mock_project_manager).to receive(:add_project).and_return(sample_project)

        projects_command.options = { type: "rails", default_branch: "main" }
        projects_command.add("test-project", "/path/to/project")

        expect(mock_project_manager).to have_received(:add_project).with(
          "test-project",
          "/path/to/project",
          type: "rails",
          default_branch: "main"
        )
      end
    end

    context "in interactive mode" do
      it "prompts for missing information" do
        allow(mock_prompt).to receive(:project_name).and_return("interactive-project")
        allow(mock_prompt).to receive(:project_path).and_return("/interactive/path")
        allow(mock_project_manager).to receive(:add_project).and_return(sample_project)

        projects_command.options = { interactive: true }
        projects_command.add

        expect(mock_prompt).to have_received(:project_name)
        expect(mock_prompt).to have_received(:project_path)
        expect(mock_project_manager).to have_received(:add_project).with(
          "interactive-project",
          "/interactive/path",
          type: nil,
          default_branch: nil
        )
      end

      it "prompts when name is missing" do
        allow(mock_prompt).to receive(:project_name).and_return("prompted-project")
        allow(mock_project_manager).to receive(:add_project).and_return(sample_project)

        projects_command.add(nil, "/path/to/project")

        expect(mock_prompt).to have_received(:project_name)
      end
    end

    context "when not initialized" do
      it "shows error and exits" do
        allow(mock_config_manager).to receive(:initialized?).and_return(false)

        expect { projects_command.add("test", "/path") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Project not initialized")
        expect(mock_ui).to have_received(:recovery_suggestion)
      end
    end

    context "when project manager raises error" do
      it "handles errors gracefully" do
        error = Sxn::ProjectExistsError.new("Project already exists")
        allow(error).to receive(:exit_code).and_return(10)
        allow(mock_project_manager).to receive(:add_project).and_raise(error)

        expect { projects_command.add("test", "/path") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:progress_failed)
        expect(mock_ui).to have_received(:error).with("Project already exists")
      end

      it "handles StandardError with debug output when SXN_DEBUG is set" do
        ENV["SXN_DEBUG"] = "true"
        error = StandardError.new("Unexpected error")
        allow(error).to receive(:backtrace).and_return(%w[line1 line2 line3])
        allow(mock_project_manager).to receive(:add_project).and_raise(error)

        expect { projects_command.add("test", "/path") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:progress_failed)
        expect(mock_ui).to have_received(:error).with("Unexpected error: Unexpected error")
        expect(mock_ui).to have_received(:debug).with("line1\nline2\nline3")
      ensure
        ENV.delete("SXN_DEBUG")
      end

      it "handles StandardError without debug output when SXN_DEBUG is not set" do
        error = StandardError.new("Unexpected error")
        allow(mock_project_manager).to receive(:add_project).and_raise(error)

        expect { projects_command.add("test", "/path") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:progress_failed)
        expect(mock_ui).to have_received(:error).with("Unexpected error: Unexpected error")
        expect(mock_ui).not_to have_received(:debug)
      end
    end
  end

  describe "#remove" do
    context "with project name" do
      it "removes project after confirmation" do
        allow(mock_prompt).to receive(:confirm_deletion).and_return(true)
        allow(mock_project_manager).to receive(:remove_project)

        projects_command.remove("test-project")

        expect(mock_prompt).to have_received(:confirm_deletion).with("test-project", "project")
        expect(mock_project_manager).to have_received(:remove_project).with("test-project")
        expect(mock_ui).to have_received(:success).with("Removed project 'test-project'")
      end

      it "cancels when user doesn't confirm" do
        allow(mock_prompt).to receive(:confirm_deletion).and_return(false)
        allow(mock_project_manager).to receive(:remove_project)

        projects_command.remove("test-project")

        expect(mock_project_manager).not_to have_received(:remove_project)
        expect(mock_ui).to have_received(:info).with("Cancelled")
      end
    end

    context "without project name" do
      it "prompts for project selection" do
        projects = [sample_project]
        allow(mock_project_manager).to receive(:list_projects).and_return(projects)
        allow(mock_prompt).to receive(:select).and_return("test-project")
        allow(mock_prompt).to receive(:confirm_deletion).and_return(true)
        allow(mock_project_manager).to receive(:remove_project)

        projects_command.remove

        expect(mock_prompt).to have_received(:select).with(
          "Select project to remove:",
          [{ name: "test-project (rails)", value: "test-project" }]
        )
      end

      it "shows empty state when no projects exist" do
        allow(mock_project_manager).to receive(:list_projects).and_return([])

        projects_command.remove

        expect(mock_ui).to have_received(:empty_state).with("No projects configured")
      end
    end

    context "when project is in use" do
      it "handles ProjectInUseError" do
        error = Sxn::ProjectInUseError.new("Project in use")
        allow(error).to receive(:exit_code).and_return(11)
        allow(mock_prompt).to receive(:confirm_deletion).and_return(true)
        allow(mock_project_manager).to receive(:remove_project).and_raise(error)

        expect { projects_command.remove("test-project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Project in use")
        expect(mock_ui).to have_received(:recovery_suggestion).with(/Archive or remove/)
      end

      it "handles general Sxn::Error during removal" do
        error = Sxn::Error.new("General error")
        allow(error).to receive(:exit_code).and_return(12)
        allow(mock_prompt).to receive(:confirm_deletion).and_return(true)
        allow(mock_project_manager).to receive(:remove_project).and_raise(error)

        expect { projects_command.remove("test-project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("General error")
      end
    end
  end

  describe "#list" do
    context "with projects" do
      it "displays projects table" do
        projects = [sample_project]
        allow(mock_project_manager).to receive(:list_projects).and_return(projects)

        projects_command.list

        expect(mock_table).to have_received(:projects).with(projects)
        expect(mock_ui).to have_received(:info).with("Total: 1 projects")
      end

      it "displays projects with validation when --validate option" do
        projects = [sample_project]
        validation_result = { valid: true, issues: [] }
        allow(mock_project_manager).to receive(:list_projects).and_return(projects)
        allow(mock_project_manager).to receive(:validate_project).and_return(validation_result)
        allow(Sxn::UI::ProgressBar).to receive(:with_progress).and_yield(sample_project, double(log: nil))

        projects_command.options = { validate: true }
        projects_command.list

        expect(mock_project_manager).to have_received(:validate_project).with("test-project")
      end
    end

    context "without projects" do
      it "shows empty state" do
        allow(mock_project_manager).to receive(:list_projects).and_return([])

        projects_command.list

        expect(mock_ui).to have_received(:empty_state).with("No projects configured")
        expect(mock_ui).to have_received(:recovery_suggestion)
      end
    end

    context "when errors occur" do
      it "handles Sxn::Error during list" do
        error = Sxn::Error.new("List error")
        allow(error).to receive(:exit_code).and_return(15)
        allow(mock_project_manager).to receive(:list_projects).and_raise(error)

        expect { projects_command.list }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("List error")
      end
    end
  end

  describe "#scan" do
    let(:detected_projects) do
      [
        { name: "project1", path: "/path/1", type: "rails" },
        { name: "project2", path: "/path/2", type: "javascript" }
      ]
    end

    it "scans and displays detected projects" do
      allow(mock_project_manager).to receive(:scan_projects).and_return(detected_projects)

      projects_command.scan("/base/path")

      expect(mock_project_manager).to have_received(:scan_projects).with("/base/path")
      expect(mock_ui).to have_received(:list_item).with("project1 (rails)", "/path/1")
      expect(mock_ui).to have_received(:list_item).with("project2 (javascript)", "/path/2")
      expect(mock_ui).to have_received(:info).with("Total: 2 projects detected")
    end

    it "uses current directory when no path provided" do
      allow(Dir).to receive(:pwd).and_return("/current/dir")
      allow(mock_project_manager).to receive(:scan_projects).and_return([])

      projects_command.scan

      expect(mock_project_manager).to have_received(:scan_projects).with("/current/dir")
    end

    context "with --register option" do
      it "automatically registers detected projects" do
        allow(mock_project_manager).to receive(:scan_projects).and_return(detected_projects)
        allow(mock_project_manager).to receive(:auto_register_projects).and_return([
                                                                                     { status: :success,
                                                                                       project: detected_projects[0] },
                                                                                     { status: :success,
                                                                                       project: detected_projects[1] }
                                                                                   ])

        projects_command.options = { register: true }
        projects_command.scan

        expect(mock_project_manager).to have_received(:auto_register_projects).with(detected_projects)
        expect(mock_ui).to have_received(:success).with("✅ project1")
        expect(mock_ui).to have_received(:success).with("✅ project2")
      end
    end

    context "in interactive mode" do
      it "prompts before registering" do
        allow(mock_project_manager).to receive(:scan_projects).and_return(detected_projects)
        allow(mock_prompt).to receive(:ask_yes_no).and_return(true)
        allow(mock_project_manager).to receive(:auto_register_projects).and_return([])

        projects_command.options = { interactive: true }
        projects_command.scan

        expect(mock_prompt).to have_received(:ask_yes_no).with("Register detected projects?", default: true)
        expect(mock_project_manager).to have_received(:auto_register_projects)
      end

      it "skips registration when user declines" do
        allow(mock_project_manager).to receive(:scan_projects).and_return(detected_projects)
        allow(mock_prompt).to receive(:ask_yes_no).and_return(false)
        allow(mock_project_manager).to receive(:auto_register_projects)

        projects_command.options = { interactive: true }
        projects_command.scan

        expect(mock_project_manager).not_to have_received(:auto_register_projects)
      end
    end

    context "when no projects detected" do
      it "shows empty state" do
        allow(mock_project_manager).to receive(:scan_projects).and_return([])

        projects_command.scan

        expect(mock_ui).to have_received(:empty_state).with("No projects detected")
      end
    end

    context "when scan encounters errors" do
      it "handles Sxn::Error during scan" do
        error = Sxn::Error.new("Scan error")
        allow(error).to receive(:exit_code).and_return(16)
        allow(mock_project_manager).to receive(:scan_projects).and_raise(error)

        expect { projects_command.scan }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Scan error")
      end
    end
  end

  describe "#validate" do
    context "with project name" do
      it "validates project successfully" do
        validation_result = { valid: true, issues: [], project: sample_project }
        allow(mock_project_manager).to receive(:validate_project).and_return(validation_result)

        projects_command.validate("test-project")

        expect(mock_project_manager).to have_received(:validate_project).with("test-project")
        expect(mock_ui).to have_received(:success).with("Project is valid")
      end

      it "shows validation issues" do
        validation_result = {
          valid: false,
          issues: ["Path does not exist", "Not a git repository"],
          project: sample_project
        }
        allow(mock_project_manager).to receive(:validate_project).and_return(validation_result)

        projects_command.validate("test-project")

        expect(mock_ui).to have_received(:error).with("Project has issues:")
        expect(mock_ui).to have_received(:list_item).with("Path does not exist")
        expect(mock_ui).to have_received(:list_item).with("Not a git repository")
      end
    end

    context "without project name" do
      it "prompts for project selection" do
        projects = [sample_project]
        validation_result = { valid: true, issues: [], project: sample_project }

        allow(mock_project_manager).to receive(:list_projects).and_return(projects)
        allow(mock_prompt).to receive(:select).and_return("test-project")
        allow(mock_project_manager).to receive(:validate_project).and_return(validation_result)

        projects_command.validate

        expect(mock_prompt).to have_received(:select).with(
          "Select project to validate:",
          [{ name: "test-project (rails)", value: "test-project" }]
        )
      end

      it "shows empty state when no projects for validation" do
        allow(mock_project_manager).to receive(:list_projects).and_return([])

        projects_command.validate

        expect(mock_ui).to have_received(:empty_state).with("No projects configured")
      end
    end

    context "when validation encounters errors" do
      it "handles Sxn::Error during validate" do
        error = Sxn::Error.new("Validation error")
        allow(error).to receive(:exit_code).and_return(17)
        allow(mock_project_manager).to receive(:validate_project).and_raise(error)

        expect { projects_command.validate("test-project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Validation error")
      end
    end
  end

  describe "#info" do
    context "with project name" do
      it "displays detailed project information" do
        rules = [{ type: "copy_files", config: { source: "test.txt" } }]
        allow(mock_project_manager).to receive(:get_project).and_return(sample_project)
        allow(mock_project_manager).to receive(:validate_project).and_return({ valid: true, issues: [] })
        allow(mock_rules_manager).to receive(:list_rules).and_return(rules)

        projects_command.info("test-project")

        expect(mock_ui).to have_received(:key_value).with("Name", "test-project")
        expect(mock_ui).to have_received(:key_value).with("Type", "rails")
        expect(mock_ui).to have_received(:key_value).with("Status", "✅ Valid")
        expect(mock_table).to have_received(:rules).with(rules, "test-project")
      end

      it "shows validation issues in detailed view" do
        validation_result = { valid: false, issues: ["Issue 1", "Issue 2"] }
        allow(mock_project_manager).to receive(:get_project).and_return(sample_project)
        allow(mock_project_manager).to receive(:validate_project).and_return(validation_result)
        allow(mock_rules_manager).to receive(:list_rules).and_return([])

        projects_command.info("test-project")

        expect(mock_ui).to have_received(:key_value).with("Status", "❌ Invalid")
        expect(mock_ui).to have_received(:list_item).with("Issue 1")
        expect(mock_ui).to have_received(:list_item).with("Issue 2")
      end

      it "handles missing project" do
        allow(mock_project_manager).to receive(:get_project).and_return(nil)

        expect { projects_command.info("non-existent") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Project 'non-existent' not found")
      end

      it "handles rules loading errors gracefully" do
        allow(mock_project_manager).to receive(:get_project).and_return(sample_project)
        allow(mock_project_manager).to receive(:validate_project).and_return({ valid: true, issues: [] })
        allow(mock_rules_manager).to receive(:list_rules).and_raise("Rules error")

        projects_command.info("test-project")

        expect(mock_ui).to have_received(:debug).with("Could not load rules: Rules error")
      end

      it "shows message when no rules configured" do
        allow(mock_project_manager).to receive(:get_project).and_return(sample_project)
        allow(mock_project_manager).to receive(:validate_project).and_return({ valid: true, issues: [] })
        allow(mock_rules_manager).to receive(:list_rules).and_return([])

        projects_command.info("test-project")

        expect(mock_ui).to have_received(:info).with("No rules configured for this project")
      end
    end

    context "without project name" do
      it "prompts for project selection" do
        projects = [sample_project]
        allow(mock_project_manager).to receive(:list_projects).and_return(projects)
        allow(mock_prompt).to receive(:select).and_return("test-project")
        allow(mock_project_manager).to receive(:get_project).and_return(sample_project)
        allow(mock_project_manager).to receive(:validate_project).and_return({ valid: true, issues: [] })
        allow(mock_rules_manager).to receive(:list_rules).and_return([])

        projects_command.info

        expect(mock_prompt).to have_received(:select).with(
          "Select project:",
          [{ name: "test-project (rails)", value: "test-project" }]
        )
      end

      it "shows empty state when no projects for info" do
        allow(mock_project_manager).to receive(:list_projects).and_return([])

        projects_command.info

        expect(mock_ui).to have_received(:empty_state).with("No projects configured")
      end
    end

    context "when info encounters errors" do
      it "handles Sxn::Error during info" do
        error = Sxn::Error.new("Info error")
        allow(error).to receive(:exit_code).and_return(18)
        allow(mock_project_manager).to receive(:get_project).and_raise(error)

        expect { projects_command.info("test-project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Info error")
      end
    end
  end

  describe "private helper methods" do
    describe "#display_project_info" do
      it "displays basic project information" do
        projects_command.send(:display_project_info, sample_project)

        expect(mock_ui).to have_received(:key_value).with("Name", "test-project")
        expect(mock_ui).to have_received(:key_value).with("Type", "rails")
        expect(mock_ui).to have_received(:key_value).with("Path", "/path/to/project")
        expect(mock_ui).to have_received(:key_value).with("Default Branch", "main")
      end

      it "displays detailed information when requested" do
        validation_result = { valid: true, issues: [] }
        allow(mock_project_manager).to receive(:validate_project).and_return(validation_result)

        projects_command.send(:display_project_info, sample_project, detailed: true)

        expect(mock_ui).to have_received(:key_value).with("Status", "✅ Valid")
      end
    end

    describe "#register_projects" do
      let(:detected_projects) do
        [
          { name: "project1", path: "/path/1", type: "rails" },
          { name: "project2", path: "/path/2", type: "javascript" }
        ]
      end

      it "registers projects and shows results" do
        results = [
          { status: :success, project: { name: "project1" } },
          { status: :error, project: { name: "project2" }, error: "Path not found" }
        ]
        allow(mock_project_manager).to receive(:auto_register_projects).and_return(results)

        projects_command.send(:register_projects, detected_projects)

        expect(mock_ui).to have_received(:success).with("✅ project1")
        expect(mock_ui).to have_received(:error).with("❌ project2: Path not found")
        expect(mock_ui).to have_received(:info).with("Registered 1 projects successfully")
        expect(mock_ui).to have_received(:warning).with("1 projects failed")
      end

      it "handles empty project list" do
        allow(mock_project_manager).to receive(:auto_register_projects)

        projects_command.send(:register_projects, [])

        expect(mock_project_manager).not_to have_received(:auto_register_projects)
      end
    end
  end
end
