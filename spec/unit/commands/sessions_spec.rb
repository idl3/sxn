# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Commands::Sessions do
  let(:command) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }
  let(:mock_ui) { instance_double(Sxn::UI::Output) }
  let(:mock_prompt) { instance_double(Sxn::UI::Prompt) }
  let(:mock_table) { instance_double(Sxn::UI::Table) }
  let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
  let(:session_manager) { instance_double(Sxn::Core::SessionManager) }
  let(:project_manager) { instance_double(Sxn::Core::ProjectManager) }
  let(:worktree_manager) { instance_double(Sxn::Core::WorktreeManager) }
  let(:template_manager) { instance_double(Sxn::Core::TemplateManager) }

  let(:sample_session) do
    {
      id: "test-id",
      name: "test-session",
      path: "/path/to/session",
      status: "active",
      description: "Test session",
      linear_task: "ATL-123",
      default_branch: "test-session",
      created_at: Time.now.iso8601,
      updated_at: Time.now.iso8601,
      projects: %w[project1 project2]
    }
  end

  before do
    allow(Dir).to receive(:pwd).and_return(temp_dir)
    allow(Sxn::UI::Output).to receive(:new).and_return(mock_ui)
    allow(Sxn::UI::Prompt).to receive(:new).and_return(mock_prompt)
    allow(Sxn::UI::Table).to receive(:new).and_return(mock_table)
    allow(Sxn::Core::ConfigManager).to receive(:new).and_return(config_manager)
    allow(Sxn::Core::SessionManager).to receive(:new).and_return(session_manager)
    allow(Sxn::Core::ProjectManager).to receive(:new).and_return(project_manager)
    allow(Sxn::Core::WorktreeManager).to receive(:new).and_return(worktree_manager)
    allow(Sxn::Core::TemplateManager).to receive(:new).and_return(template_manager)

    # Default project manager setup - empty projects means wizard is skipped
    allow(project_manager).to receive(:list_projects).and_return([])

    # Default mock setup
    allow(config_manager).to receive(:initialized?).and_return(true)
    allow(config_manager).to receive(:sxn_folder_path).and_return(temp_dir)
    allow(mock_ui).to receive(:section)
    allow(mock_ui).to receive(:subsection)
    allow(mock_ui).to receive(:progress_start)
    allow(mock_ui).to receive(:progress_done)
    allow(mock_ui).to receive(:progress_failed)
    allow(mock_ui).to receive(:success)
    allow(mock_ui).to receive(:error)
    allow(mock_ui).to receive(:warning)
    allow(mock_ui).to receive(:info)
    allow(mock_ui).to receive(:empty_state)
    allow(mock_ui).to receive(:newline)
    allow(mock_ui).to receive(:key_value)
    allow(mock_ui).to receive(:list_item)
    allow(mock_ui).to receive(:command_example)
    allow(mock_ui).to receive(:recovery_suggestion)
    allow(mock_ui).to receive(:debug)
    allow(mock_table).to receive(:sessions)
    allow(mock_prompt).to receive(:confirm_deletion).and_return(true)
    allow(mock_prompt).to receive(:session_name).and_return("test-session")
    allow(mock_prompt).to receive(:select).and_return("test-selection")
    allow(mock_prompt).to receive(:ask).and_return("test-input")
    allow(mock_prompt).to receive(:ask_yes_no).and_return(true)
    allow(mock_prompt).to receive(:default_branch).and_return("test-session")
    allow(command).to receive(:options).and_return(Thor::CoreExt::HashWithIndifferentAccess.new)

    # Default session manager spies for methods that might not be called
    allow(session_manager).to receive(:create_session)
    allow(session_manager).to receive(:use_session)
    allow(session_manager).to receive(:remove_session)
    allow(session_manager).to receive(:archive_session)
    allow(session_manager).to receive(:activate_session)
    allow(session_manager).to receive(:list_sessions)
    allow(session_manager).to receive(:current_session)
    allow(session_manager).to receive(:get_session)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#add" do
    context "with direct session name" do
      it "creates a new session with activation by default" do
        allow(session_manager).to receive(:create_session).and_return(sample_session)
        allow(session_manager).to receive(:use_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:activate] = true
        options[:description] = nil
        options[:linear_task] = nil
        allow(command).to receive(:options).and_return(options)

        command.add("test-session")

        expect(session_manager).to have_received(:create_session).with(
          "test-session",
          description: nil,
          linear_task: nil,
          default_branch: "test-session",
          template_id: nil
        )
        expect(session_manager).to have_received(:use_session).with("test-session")
        expect(mock_ui).to have_received(:success).with("Created session 'test-session'")
        expect(mock_ui).to have_received(:success).with("Switched to session 'test-session'")
      end

      it "always activates session even when --no-activate option is used" do
        # New behavior: sessions are always activated when created
        allow(session_manager).to receive(:create_session).and_return(sample_session)
        allow(session_manager).to receive(:use_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:activate] = false
        options[:description] = nil
        options[:linear_task] = nil
        options[:branch] = nil
        allow(command).to receive(:options).and_return(options)

        command.add("test-session")

        expect(session_manager).to have_received(:create_session)
        expect(session_manager).to have_received(:use_session).with("test-session")
        expect(mock_ui).to have_received(:success).with("Created session 'test-session'")
        expect(mock_ui).to have_received(:success).with("Switched to session 'test-session'")
      end

      it "creates session with description and linear task options" do
        allow(session_manager).to receive(:create_session).and_return(sample_session)
        allow(session_manager).to receive(:use_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:description] = "Test description"
        options[:linear_task] = "ATL-456"
        options[:activate] = true
        options[:branch] = nil
        allow(command).to receive(:options).and_return(options)

        command.add("test-session")

        expect(session_manager).to have_received(:create_session).with(
          "test-session",
          description: "Test description",
          linear_task: "ATL-456",
          default_branch: "test-session",
          template_id: nil
        )
      end
    end

    context "without session name (interactive mode)" do
      it "prompts for session name" do
        existing_sessions = [{ name: "existing1" }, { name: "existing2" }]
        allow(session_manager).to receive(:list_sessions).and_return(existing_sessions)
        allow(mock_prompt).to receive(:session_name).and_return("interactive-session")
        allow(mock_prompt).to receive(:default_branch).with(session_name: "interactive-session").and_return("interactive-session")
        allow(session_manager).to receive(:create_session).and_return(sample_session)
        allow(session_manager).to receive(:use_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:activate] = true
        options[:description] = nil
        options[:linear_task] = nil
        options[:branch] = nil
        allow(command).to receive(:options).and_return(options)

        command.add

        expect(mock_prompt).to have_received(:session_name).with(
          existing_sessions: %w[existing1 existing2]
        )
        expect(session_manager).to have_received(:create_session).with(
          "interactive-session",
          description: nil,
          linear_task: nil,
          default_branch: "interactive-session",
          template_id: nil
        )
      end
    end

    context "when not initialized" do
      it "shows error and exits" do
        allow(config_manager).to receive(:initialized?).and_return(false)

        expect { command.add("test-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Project not initialized")
        expect(mock_ui).to have_received(:recovery_suggestion)
      end
    end

    context "when session creation fails" do
      it "handles Sxn errors gracefully" do
        error = Sxn::SessionExistsError.new("Session already exists")
        allow(error).to receive(:exit_code).and_return(20)
        allow(session_manager).to receive(:create_session).and_raise(error)

        expect { command.add("existing-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:progress_failed)
        expect(mock_ui).to have_received(:error).with("Session already exists")
      end
    end

    context "with worktree wizard" do
      let(:sample_projects) do
        [
          { name: "project1", type: "rails", path: "/path/to/project1" },
          { name: "project2", type: "node", path: "/path/to/project2" }
        ]
      end

      let(:sample_worktree) do
        { project: "project1", branch: "test-session", path: "/path/to/worktree" }
      end

      before do
        allow(session_manager).to receive(:create_session).and_return(sample_session)
        allow(session_manager).to receive(:use_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)
      end

      it "offers worktree wizard when projects exist" do
        allow(project_manager).to receive(:list_projects).and_return(sample_projects)
        allow(mock_prompt).to receive(:ask_yes_no).and_return(false)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:activate] = true
        allow(command).to receive(:options).and_return(options)

        command.add("test-session")

        expect(mock_ui).to have_received(:section).with("Add Worktree")
        expect(mock_prompt).to have_received(:ask_yes_no).with(
          "Would you like to add a worktree to this session?",
          default: true
        )
      end

      it "skips wizard when no projects configured" do
        allow(project_manager).to receive(:list_projects).and_return([])

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        allow(command).to receive(:options).and_return(options)

        command.add("test-session")

        expect(mock_ui).to have_received(:info).with("No projects configured yet.")
        expect(mock_ui).to have_received(:recovery_suggestion).with("Add projects with 'sxn projects add <name> <path>'")
      end

      it "skips wizard when --skip-worktree option is used" do
        allow(project_manager).to receive(:list_projects).and_return(sample_projects)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:skip_worktree] = true
        allow(command).to receive(:options).and_return(options)

        command.add("test-session")

        expect(mock_ui).not_to have_received(:section).with("Add Worktree")
      end

      it "creates worktree when user confirms" do
        allow(project_manager).to receive(:list_projects).and_return(sample_projects)
        allow(mock_prompt).to receive(:ask_yes_no).and_return(true, false) # yes to first, no to "add more"
        allow(mock_prompt).to receive(:select).and_return("project1")
        allow(mock_prompt).to receive(:branch_name).and_return("test-session")
        allow(worktree_manager).to receive(:add_worktree).and_return(sample_worktree)

        rules_manager = instance_double(Sxn::Core::RulesManager)
        allow(Sxn::Core::RulesManager).to receive(:new).and_return(rules_manager)
        allow(rules_manager).to receive(:apply_rules).and_return({ success: true, applied_count: 0 })

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        allow(command).to receive(:options).and_return(options)

        command.add("test-session")

        expect(worktree_manager).to have_received(:add_worktree).with(
          "project1",
          "test-session",
          session_name: "test-session"
        )
        expect(mock_ui).to have_received(:success).with("Created worktree for project1")
      end

      it "allows adding multiple worktrees" do
        allow(project_manager).to receive(:list_projects).and_return(sample_projects)
        allow(mock_prompt).to receive(:ask_yes_no).and_return(true, true, false) # yes, yes to add more, then no
        allow(mock_prompt).to receive(:select).and_return("project1", "project2")
        allow(mock_prompt).to receive(:branch_name).and_return("test-session")
        allow(worktree_manager).to receive(:add_worktree).and_return(sample_worktree)

        rules_manager = instance_double(Sxn::Core::RulesManager)
        allow(Sxn::Core::RulesManager).to receive(:new).and_return(rules_manager)
        allow(rules_manager).to receive(:apply_rules).and_return({ success: true, applied_count: 0 })

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        allow(command).to receive(:options).and_return(options)

        command.add("test-session")

        expect(worktree_manager).to have_received(:add_worktree).twice
      end

      it "handles worktree creation errors gracefully" do
        allow(project_manager).to receive(:list_projects).and_return(sample_projects)
        allow(mock_prompt).to receive(:ask_yes_no).and_return(true, false)
        allow(mock_prompt).to receive(:select).and_return("project1")
        allow(mock_prompt).to receive(:branch_name).and_return("test-session")

        error = Sxn::WorktreeCreationError.new("Failed to create worktree")
        allow(worktree_manager).to receive(:add_worktree).and_raise(error)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        allow(command).to receive(:options).and_return(options)

        # Should not raise - error is handled gracefully
        command.add("test-session")

        expect(mock_ui).to have_received(:progress_failed)
        expect(mock_ui).to have_received(:error).with("Failed to create worktree")
        expect(mock_ui).to have_received(:recovery_suggestion).with("You can try again with 'sxn worktree add project1'")
      end
    end

    context "with --template option" do
      it "validates template exists before creating session" do
        allow(template_manager).to receive(:validate_template)
          .with("my-template")
          .and_raise(Sxn::SessionTemplateNotFoundError.new("my-template"))

        options = Thor::CoreExt::HashWithIndifferentAccess.new(template: "my-template", branch: "main")
        allow(command).to receive(:options).and_return(options)

        expect { command.add("test-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with(/not found/i)
      end

      it "creates session with template_id when template is valid" do
        allow(template_manager).to receive(:validate_template).with("my-template")
        allow(template_manager).to receive(:get_template).with("my-template").and_return({
                                                                                           "name" => "my-template",
                                                                                           "projects" => [
                                                                                             { "name" => "project1", "branch" => "feature-branch" },
                                                                                             { "name" => "project2" }
                                                                                           ]
                                                                                         })

        allow(session_manager).to receive(:create_session)
          .with("test-session", description: nil, linear_task: nil, default_branch: "feature-branch", template_id: "my-template")
          .and_return(sample_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        allow(worktree_manager).to receive(:add_worktree).and_return({ path: "/path/to/worktree", project: "project1", branch: "feature-branch" })
        allow(command).to receive(:apply_project_rules)

        options = Thor::CoreExt::HashWithIndifferentAccess.new(template: "my-template", branch: "feature-branch")
        allow(command).to receive(:options).and_return(options)

        expect { command.add("test-session") }.not_to raise_error

        expect(session_manager).to have_received(:create_session)
          .with("test-session", hash_including(template_id: "my-template"))
        expect(mock_ui).to have_received(:success).at_least(:once)
      end

      it "handles template validation error" do
        allow(template_manager).to receive(:validate_template)
          .with("invalid-template")
          .and_raise(Sxn::SessionTemplateValidationError.new("invalid-template", "has no projects"))

        options = Thor::CoreExt::HashWithIndifferentAccess.new(template: "invalid-template", branch: "main")
        allow(command).to receive(:options).and_return(options)

        expect { command.add("test-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with(/Invalid session template/i)
      end

      it "applies project rules for each project in template" do
        allow(template_manager).to receive(:validate_template).with("my-template")
        allow(template_manager).to receive(:get_template).with("my-template").and_return({
                                                                                           "name" => "my-template",
                                                                                           "projects" => [
                                                                                             { "name" => "project1" },
                                                                                             { "name" => "project2" }
                                                                                           ]
                                                                                         })

        allow(session_manager).to receive(:create_session).and_return(sample_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)
        allow(worktree_manager).to receive(:add_worktree).and_return({
                                                                       path: "/path/to/worktree",
                                                                       project: "project1",
                                                                       branch: "main"
                                                                     })

        # Stub apply_project_rules to verify it's called
        allow(command).to receive(:apply_project_rules)

        options = Thor::CoreExt::HashWithIndifferentAccess.new(template: "my-template", branch: "main")
        allow(command).to receive(:options).and_return(options)

        expect { command.add("test-session") }.not_to raise_error

        # Verify apply_project_rules is called for each project in the template
        expect(command).to have_received(:apply_project_rules).with("project1", "test-session")
        expect(command).to have_received(:apply_project_rules).with("project2", "test-session")
      end

      it "accepts template names with hyphens" do
        allow(template_manager).to receive(:validate_template).with("kiosk-full")
        allow(template_manager).to receive(:get_template).with("kiosk-full").and_return({
                                                                                          "name" => "kiosk-full",
                                                                                          "projects" => [
                                                                                            { "name" => "project1" }
                                                                                          ]
                                                                                        })

        allow(session_manager).to receive(:create_session).and_return(sample_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)
        allow(worktree_manager).to receive(:add_worktree).and_return({
                                                                       path: "/path/to/worktree",
                                                                       project: "project1",
                                                                       branch: "main"
                                                                     })
        allow(command).to receive(:apply_project_rules)

        options = Thor::CoreExt::HashWithIndifferentAccess.new(template: "kiosk-full", branch: "main")
        allow(command).to receive(:options).and_return(options)

        expect { command.add("test-session") }.not_to raise_error

        expect(template_manager).to have_received(:validate_template).with("kiosk-full")
        expect(template_manager).to have_received(:get_template).with("kiosk-full")
        expect(mock_ui).to have_received(:success).at_least(:once)
      end
    end
  end

  describe "#list" do
    context "with sessions" do
      let(:sessions) do
        [
          {
            name: "session1",
            status: "active",
            projects: ["project1"],
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          },
          {
            name: "session2",
            status: "archived",
            projects: ["project2"],
            created_at: Time.now.iso8601,
            updated_at: Time.now.iso8601
          }
        ]
      end

      it "displays sessions in a table with default options" do
        allow(session_manager).to receive(:list_sessions).and_return(sessions)
        allow(session_manager).to receive(:current_session).and_return({ name: "session1" })

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:status] = nil
        options[:limit] = 50
        allow(command).to receive(:options).and_return(options)

        command.list

        expect(session_manager).to have_received(:list_sessions).with(
          status: nil,
          limit: 50
        )
        expect(mock_table).to have_received(:sessions).with(sessions)
        expect(mock_ui).to have_received(:info).with("Total: 2 sessions")
        expect(mock_ui).to have_received(:info).with("Current: session1")
      end

      it "applies status filter when provided" do
        active_sessions = [sessions[0]]
        allow(session_manager).to receive(:list_sessions).and_return(active_sessions)
        allow(session_manager).to receive(:current_session).and_return(nil)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:status] = "active"
        options[:limit] = 50
        allow(command).to receive(:options).and_return(options)

        command.list

        expect(session_manager).to have_received(:list_sessions).with(
          status: "active",
          limit: 50
        )
      end

      it "applies custom limit when provided" do
        allow(session_manager).to receive(:list_sessions).and_return(sessions)
        allow(session_manager).to receive(:current_session).and_return(nil)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:status] = nil
        options[:limit] = 10
        allow(command).to receive(:options).and_return(options)

        command.list

        expect(session_manager).to have_received(:list_sessions).with(
          status: nil,
          limit: 10
        )
      end

      it "shows recovery suggestion when no current session" do
        allow(session_manager).to receive(:list_sessions).and_return(sessions)
        allow(session_manager).to receive(:current_session).and_return(nil)

        command.list

        expect(mock_ui).to have_received(:recovery_suggestion)
          .with("Use 'sxn use <session>' to activate a session")
      end
    end

    context "without sessions" do
      it "shows empty state and suggests creating session" do
        allow(session_manager).to receive(:list_sessions).and_return([])

        command.list

        expect(mock_ui).to have_received(:empty_state).with("No sessions found")
        expect(mock_ui).to have_received(:recovery_suggestion)
          .with("Create your first session with 'sxn add <session-name>'")
      end
    end

    context "when not initialized" do
      it "shows error and exits" do
        allow(config_manager).to receive(:initialized?).and_return(false)

        expect { command.list }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Project not initialized")
      end
    end

    context "when listing fails" do
      it "handles errors gracefully" do
        error = Sxn::Error.new("Database error")
        allow(error).to receive(:exit_code).and_return(21)
        allow(session_manager).to receive(:list_sessions).and_raise(error)

        expect { command.list }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Database error")
      end
    end
  end

  describe "#use" do
    context "with session name" do
      it "activates the specified session" do
        allow(session_manager).to receive(:use_session).and_return(sample_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        command.use("test-session")

        expect(session_manager).to have_received(:use_session).with("test-session")
        expect(mock_ui).to have_received(:success).with("Activated session 'test-session'")
      end
    end

    context "without session name (interactive mode)" do
      it "prompts for session selection from active sessions" do
        active_sessions = [
          { name: "session1", description: "Test session 1" },
          { name: "session2", description: nil }
        ]
        allow(session_manager).to receive(:list_sessions).and_return(active_sessions)
        allow(mock_prompt).to receive(:select).and_return("session1")
        allow(session_manager).to receive(:use_session).and_return(sample_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        command.use

        expect(session_manager).to have_received(:list_sessions).with(status: "active")
        expect(mock_prompt).to have_received(:select).with(
          "Select session to activate:",
          [
            { name: "session1 - Test session 1", value: "session1" },
            { name: "session2 - No description", value: "session2" }
          ]
        )
        expect(session_manager).to have_received(:use_session).with("session1")
      end

      it "shows empty state when no active sessions exist" do
        allow(session_manager).to receive(:list_sessions).and_return([])

        command.use

        expect(mock_ui).to have_received(:empty_state).with("No active sessions found")
        expect(mock_ui).to have_received(:recovery_suggestion)
          .with("Create your first session with 'sxn add <session-name>'")
      end
    end

    context "when session activation fails" do
      it "handles Sxn errors gracefully" do
        error = Sxn::SessionNotFoundError.new("Session not found")
        allow(error).to receive(:exit_code).and_return(22)
        allow(session_manager).to receive(:use_session).and_raise(error)

        expect { command.use("nonexistent-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Session not found")
      end
    end
  end

  describe "#current" do
    context "with active session" do
      it "displays current session info" do
        allow(session_manager).to receive(:current_session).and_return(sample_session)
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        command.current

        expect(mock_ui).to have_received(:section).with("Current Session")
        expect(mock_ui).to have_received(:key_value).with("Name", "test-session")
        expect(mock_ui).to have_received(:key_value).with("Status", "Active")
      end

      it "displays verbose information when --verbose option" do
        verbose_session = sample_session.merge(projects: %w[project1 project2])
        allow(session_manager).to receive(:current_session).and_return(verbose_session)
        allow(session_manager).to receive(:get_session).and_return(verbose_session)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:verbose] = true
        allow(command).to receive(:options).and_return(options)

        command.current

        expect(mock_ui).to have_received(:subsection).with("Projects")
        expect(mock_ui).to have_received(:list_item).with("project1")
        expect(mock_ui).to have_received(:list_item).with("project2")
      end
    end

    context "without active session" do
      it "shows message when no active session" do
        allow(session_manager).to receive(:current_session).and_return(nil)

        command.current

        expect(mock_ui).to have_received(:info).with("No active session")
        expect(mock_ui).to have_received(:recovery_suggestion)
          .with("Create your first session with 'sxn add <session-name>'")
      end
    end

    context "when current session lookup fails" do
      it "handles errors gracefully" do
        error = Sxn::Error.new("Session lookup failed")
        allow(error).to receive(:exit_code).and_return(23)
        allow(session_manager).to receive(:current_session).and_raise(error)

        expect { command.current }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Session lookup failed")
      end
    end

    context "with enter subcommand" do
      it "outputs cd command for active session" do
        session_with_real_path = sample_session.merge(path: temp_dir)
        allow(session_manager).to receive(:current_session).and_return(session_with_real_path)

        expect { command.current("enter") }.to output("cd #{temp_dir}\n").to_stdout
      end

      it "exits with error when no active session" do
        allow(session_manager).to receive(:current_session).and_return(nil)

        expect { command.current("enter") }.to raise_error(SystemExit).and output(/No active session/).to_stderr
      end

      it "exits with error for unknown subcommand" do
        expect { command.current("unknown") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Unknown subcommand: unknown")
      end
    end

    context "with --path option" do
      it "outputs only the session path" do
        session_with_path = sample_session.merge(path: "/some/session/path")
        allow(session_manager).to receive(:current_session).and_return(session_with_path)

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:path] = true
        allow(command).to receive(:options).and_return(options)

        expect { command.current }.to output("/some/session/path\n").to_stdout
      end
    end
  end

  describe "#enter" do
    context "with active session" do
      it "outputs cd command to session directory" do
        session_with_real_path = sample_session.merge(path: temp_dir)
        allow(session_manager).to receive(:current_session).and_return(session_with_real_path)

        expect { command.enter }.to output("cd #{temp_dir}\n").to_stdout
      end

      it "escapes paths with spaces" do
        path_with_spaces = File.join(temp_dir, "path with spaces")
        FileUtils.mkdir_p(path_with_spaces)
        session_with_spaces = sample_session.merge(path: path_with_spaces)
        allow(session_manager).to receive(:current_session).and_return(session_with_spaces)

        expect { command.enter }.to output(/cd .*path\\ with\\ spaces/).to_stdout
      end
    end

    context "without active session" do
      it "exits with error and shows helpful message" do
        allow(session_manager).to receive(:current_session).and_return(nil)

        expect { command.enter }.to raise_error(SystemExit).and output(/No active session/).to_stderr
      end

      it "shows shell function tip" do
        allow(session_manager).to receive(:current_session).and_return(nil)

        expect { command.enter }.to raise_error(SystemExit).and output(/sxn-enter/).to_stderr
      end
    end

    context "when session directory does not exist" do
      it "exits with error" do
        session_with_missing_path = sample_session.merge(path: "/nonexistent/path")
        allow(session_manager).to receive(:current_session).and_return(session_with_missing_path)

        expect { command.enter }.to raise_error(SystemExit).and output(/does not exist/).to_stderr
      end
    end
  end

  describe "#remove" do
    context "with session name" do
      it "removes session after confirmation" do
        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:force] = false
        allow(command).to receive(:options).and_return(options)

        command.remove("test-session")

        expect(mock_prompt).to have_received(:confirm_deletion).with("test-session", "session")
        expect(session_manager).to have_received(:remove_session).with("test-session", force: false)
        expect(mock_ui).to have_received(:success).with("Removed session 'test-session'")
      end

      it "removes session with force option" do
        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:force] = true
        allow(command).to receive(:options).and_return(options)

        command.remove("test-session")

        expect(session_manager).to have_received(:remove_session).with("test-session", force: true)
      end

      it "cancels removal when user declines confirmation" do
        allow(mock_prompt).to receive(:confirm_deletion).and_return(false)
        allow(session_manager).to receive(:remove_session)

        command.remove("test-session")

        expect(session_manager).not_to have_received(:remove_session)
        expect(mock_ui).to have_received(:info).with("Cancelled")
      end
    end

    context "without session name (interactive mode)" do
      it "prompts for session selection" do
        sessions = [{ name: "session1" }, { name: "session2" }]
        allow(session_manager).to receive(:list_sessions).and_return(sessions)
        allow(mock_prompt).to receive(:select).and_return("session1")

        options = Thor::CoreExt::HashWithIndifferentAccess.new
        options[:force] = nil
        allow(command).to receive(:options).and_return(options)

        command.remove

        expect(mock_prompt).to have_received(:select).with(
          "Select session to remove:",
          [{ name: "session1", value: "session1" }, { name: "session2", value: "session2" }]
        )
        expect(session_manager).to have_received(:remove_session).with("session1", force: nil)
      end

      it "shows empty state when no sessions exist" do
        allow(session_manager).to receive(:list_sessions).and_return([])

        command.remove

        expect(mock_ui).to have_received(:empty_state).with("No sessions found")
        expect(session_manager).not_to have_received(:remove_session)
      end
    end

    context "when session has uncommitted changes" do
      it "handles SessionHasChangesError with recovery suggestion" do
        allow(session_manager).to receive(:remove_session).and_raise(
          Sxn::SessionHasChangesError.new("Session has uncommitted changes")
        )

        error = Sxn::SessionHasChangesError.new("Session has uncommitted changes")
        allow(error).to receive(:exit_code).and_return(24)
        allow(session_manager).to receive(:remove_session).and_raise(error)

        expect { command.remove("test-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:progress_failed)
        expect(mock_ui).to have_received(:error).with("Session has uncommitted changes")
        expect(mock_ui).to have_received(:recovery_suggestion)
          .with("Use --force to remove anyway, or commit/stash changes first")
      end
    end

    context "when removal fails" do
      it "handles other Sxn errors gracefully" do
        error = Sxn::SessionNotFoundError.new("Session not found")
        allow(error).to receive(:exit_code).and_return(25)
        allow(session_manager).to receive(:remove_session).and_raise(error)

        expect { command.remove("test-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:progress_failed)
        expect(mock_ui).to have_received(:error).with("Session not found")
      end
    end
  end

  describe "#archive" do
    context "with session name" do
      it "archives the specified session" do
        allow(session_manager).to receive(:archive_session)

        command.archive("test-session")

        expect(session_manager).to have_received(:archive_session).with("test-session")
        expect(mock_ui).to have_received(:success).with("Archived session 'test-session'")
      end
    end

    context "without session name (interactive mode)" do
      it "prompts for session selection from active sessions" do
        active_sessions = [{ name: "session1" }, { name: "session2" }]
        allow(session_manager).to receive(:list_sessions).and_return(active_sessions)
        allow(mock_prompt).to receive(:select).and_return("session1")
        allow(session_manager).to receive(:archive_session)

        command.archive

        expect(session_manager).to have_received(:list_sessions).with(status: "active")
        expect(mock_prompt).to have_received(:select).with(
          "Select session to archive:",
          [{ name: "session1", value: "session1" }, { name: "session2", value: "session2" }]
        )
        expect(session_manager).to have_received(:archive_session).with("session1")
      end

      it "shows empty state when no active sessions exist" do
        allow(session_manager).to receive(:list_sessions).and_return([])

        command.archive

        expect(mock_ui).to have_received(:empty_state).with("No active sessions to archive")
        expect(session_manager).not_to have_received(:archive_session)
      end
    end

    context "when archiving fails" do
      it "handles Sxn errors gracefully" do
        error = Sxn::SessionNotFoundError.new("Session not found")
        allow(error).to receive(:exit_code).and_return(26)
        allow(session_manager).to receive(:archive_session).and_raise(error)

        expect { command.archive("test-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Session not found")
      end
    end
  end

  describe "#activate" do
    context "with session name" do
      it "activates the specified archived session" do
        allow(session_manager).to receive(:activate_session)

        command.activate("test-session")

        expect(session_manager).to have_received(:activate_session).with("test-session")
        expect(mock_ui).to have_received(:success).with("Activated session 'test-session'")
      end
    end

    context "without session name (interactive mode)" do
      it "prompts for session selection from archived sessions" do
        archived_sessions = [{ name: "session1" }, { name: "session2" }]
        allow(session_manager).to receive(:list_sessions).and_return(archived_sessions)
        allow(mock_prompt).to receive(:select).and_return("session1")
        allow(session_manager).to receive(:activate_session)

        command.activate

        expect(session_manager).to have_received(:list_sessions).with(status: "archived")
        expect(mock_prompt).to have_received(:select).with(
          "Select session to activate:",
          [{ name: "session1", value: "session1" }, { name: "session2", value: "session2" }]
        )
        expect(session_manager).to have_received(:activate_session).with("session1")
      end

      it "shows empty state when no archived sessions exist" do
        allow(session_manager).to receive(:list_sessions).and_return([])

        command.activate

        expect(mock_ui).to have_received(:empty_state).with("No archived sessions to activate")
        expect(session_manager).not_to have_received(:activate_session)
      end
    end

    context "when activation fails" do
      it "handles Sxn errors gracefully" do
        error = Sxn::SessionNotFoundError.new("Session not found")
        allow(error).to receive(:exit_code).and_return(27)
        allow(session_manager).to receive(:activate_session).and_raise(error)

        expect { command.activate("test-session") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Session not found")
      end
    end
  end

  describe "private methods" do
    describe "#ensure_initialized!" do
      it "passes when initialized" do
        allow(config_manager).to receive(:initialized?).and_return(true)

        expect do
          command.send(:ensure_initialized!)
        end.not_to raise_error
      end

      it "exits when not initialized" do
        allow(config_manager).to receive(:initialized?).and_return(false)

        expect do
          command.send(:ensure_initialized!)
        end.to raise_error(SystemExit)

        expect(mock_ui).to have_received(:error).with("Project not initialized")
        expect(mock_ui).to have_received(:recovery_suggestion)
      end
    end

    describe "#display_session_info" do
      it "displays basic session information" do
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        command.send(:display_session_info, sample_session)

        expect(mock_ui).to have_received(:key_value).with("Name", "test-session")
        expect(mock_ui).to have_received(:key_value).with("Status", "Active")
        expect(mock_ui).to have_received(:key_value).with("Path", "/path/to/session")
        expect(mock_ui).to have_received(:key_value).with("Description", "Test session")
        expect(mock_ui).to have_received(:key_value).with("Linear Task", "ATL-123")
      end

      it "displays projects in verbose mode" do
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        command.send(:display_session_info, sample_session, verbose: true)

        expect(mock_ui).to have_received(:subsection).with("Projects")
        expect(mock_ui).to have_received(:list_item).with("project1")
        expect(mock_ui).to have_received(:list_item).with("project2")
      end

      it "skips optional fields when not present" do
        minimal_session = sample_session.merge(description: nil, linear_task: nil)
        allow(session_manager).to receive(:get_session).and_return(minimal_session)

        command.send(:display_session_info, minimal_session)

        expect(mock_ui).not_to have_received(:key_value).with("Description", anything)
        expect(mock_ui).not_to have_received(:key_value).with("Linear Task", anything)
      end
    end

    describe "#display_session_commands" do
      it "shows available commands for session" do
        allow(session_manager).to receive(:get_session).and_return(sample_session)

        command.send(:display_session_commands, "test-session")

        expect(mock_ui).to have_received(:subsection).with("Available Commands")
        expect(mock_ui).to have_received(:command_example).with(
          "sxn worktree add <project> [branch]",
          "Add a worktree to this session"
        )
        expect(mock_ui).to have_received(:command_example).with(
          "sxn worktree list",
          "List worktrees in this session"
        )
        expect(mock_ui).to have_received(:command_example).with(
          "cd /path/to/session",
          "Navigate to session directory"
        )
      end
    end

    describe "#suggest_create_session" do
      it "shows recovery suggestion for creating session" do
        command.send(:suggest_create_session)

        expect(mock_ui).to have_received(:recovery_suggestion)
          .with("Create your first session with 'sxn add <session-name>'")
      end
    end
  end
end
