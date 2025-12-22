# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"

RSpec.describe Sxn::MCP::Tools::Sessions do
  let(:test_dir) { Dir.mktmpdir("sxn_mcp_test") }
  let(:sxn_dir) { File.join(test_dir, ".sxn") }
  let(:sessions_dir) { File.join(test_dir, "sxn-sessions") }
  let(:config_manager) { Sxn::Core::ConfigManager.new(test_dir) }
  let(:session_manager) { Sxn::Core::SessionManager.new(config_manager) }
  let(:server_context) do
    {
      config_manager: config_manager,
      session_manager: session_manager,
      project_manager: Sxn::Core::ProjectManager.new(config_manager),
      worktree_manager: Sxn::Core::WorktreeManager.new(config_manager),
      template_manager: Sxn::Core::TemplateManager.new(config_manager),
      rules_manager: Sxn::Core::RulesManager.new(config_manager),
      workspace_path: test_dir
    }
  end

  before do
    FileUtils.mkdir_p(sxn_dir)
    FileUtils.mkdir_p(sessions_dir)

    config_path = File.join(sxn_dir, "config.yml")
    File.write(config_path, <<~YAML)
      version: 1
      sessions_folder: #{sessions_dir}
      projects: {}
    YAML

    db_path = File.join(sxn_dir, "sessions.db")
    Sxn::Database::SessionDatabase.new(db_path)
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe Sxn::MCP::Tools::Sessions::ListSessions do
    it "returns empty message when no sessions exist" do
      response = described_class.call(server_context: server_context)
      expect(response).to be_a(MCP::Tool::Response)
      expect(response.error?).to be false
      expect(response.content.first[:text]).to include("No sessions found")
    end

    it "lists existing sessions" do
      session_manager.create_session("test-session", description: "Test")

      response = described_class.call(server_context: server_context)
      expect(response.content.first[:text]).to include("test-session")
      expect(response.content.first[:text]).to include("Found 1 session")
    end

    it "filters by status" do
      session_manager.create_session("active-session")
      session_manager.create_session("archived-session")
      session_manager.archive_session("archived-session")

      response = described_class.call(server_context: server_context, status: "archived")
      expect(response.content.first[:text]).to include("archived-session")
      expect(response.content.first[:text]).not_to include("active-session")
    end
  end

  describe Sxn::MCP::Tools::Sessions::CreateSession do
    it "creates a new session" do
      response = described_class.call(
        name: "new-session",
        description: "Test description",
        server_context: server_context
      )

      expect(response.error?).to be false
      expect(response.content.first[:text]).to include("created successfully")
      expect(response.content.first[:text]).to include("new-session")

      # Verify session exists
      session = session_manager.get_session("new-session")
      expect(session).not_to be_nil
      expect(session[:description]).to eq("Test description")
    end

    it "returns error for duplicate session" do
      session_manager.create_session("existing-session")

      response = described_class.call(name: "existing-session", server_context: server_context)
      expect(response.error?).to be true
      expect(response.content.first[:text]).to match(/already exists/i)
    end

    it "returns error for invalid session name" do
      response = described_class.call(name: "invalid name!", server_context: server_context)
      expect(response.error?).to be true
      expect(response.content.first[:text]).to match(/invalid session name/i)
    end

    it "creates session with template_id and applies template" do
      # Mock template manager to return projects
      template_manager = server_context[:template_manager]

      allow(template_manager).to receive(:get_template_projects).with("test-template", default_branch: "template-session") do
        [
          { name: "project1", branch: "template-session" },
          { name: "project2", branch: "template-session" }
        ]
      end

      # Spy on worktree manager to count calls
      worktree_manager = server_context[:worktree_manager]
      call_count = 0
      allow(worktree_manager).to receive(:add_worktree) do |*_args|
        call_count += 1
        # Don't actually create worktrees in this test
      end

      response = described_class.call(
        name: "template-session",
        template_id: "test-template",
        server_context: server_context
      )

      expect(response.error?).to be false
      expect(response.content.first[:text]).to include("created successfully")

      # Verify template was applied
      expect(template_manager).to have_received(:get_template_projects).with("test-template", default_branch: "template-session")
      expect(call_count).to eq(2)
    end

    it "creates session successfully even if template application fails" do
      # Mock template manager to raise an error
      template_manager = server_context[:template_manager]
      allow(template_manager).to receive(:get_template_projects).and_raise(StandardError.new("Template not found"))

      # Mock logger to verify warning
      logger = instance_double(Logger)
      allow(Sxn).to receive(:logger).and_return(logger)
      allow(logger).to receive(:warn)

      response = described_class.call(
        name: "template-fail-session",
        template_id: "nonexistent-template",
        server_context: server_context
      )

      # Session should still be created successfully
      expect(response.error?).to be false
      expect(response.content.first[:text]).to include("created successfully")

      # Verify warning was logged
      expect(logger).to have_received(:warn).with(/Failed to apply template/)

      # Verify session exists
      session = session_manager.get_session("template-fail-session")
      expect(session).not_to be_nil
    end
  end

  describe Sxn::MCP::Tools::Sessions::GetSession do
    it "returns session details" do
      session_manager.create_session("my-session", description: "My session", linear_task: "ATL-123")

      response = described_class.call(name: "my-session", server_context: server_context)
      text = response.content.first[:text]

      expect(response.error?).to be false
      expect(text).to include("my-session")
      expect(text).to include("My session")
      expect(text).to include("ATL-123")
    end

    it "returns session details with all optional fields populated" do
      session_manager.create_session(
        "full-session",
        description: "Full session with all fields",
        linear_task: "ATL-456",
        template_id: "my-template"
      )

      response = described_class.call(name: "full-session", server_context: server_context)
      text = response.content.first[:text]

      expect(response.error?).to be false
      expect(text).to include("full-session")
      expect(text).to include("Full session with all fields")
      expect(text).to include("ATL-456")
      expect(text).to include("my-template")
      expect(text).to include("Description:")
      expect(text).to include("Linear Task:")
      expect(text).to include("Template:")
    end

    it "returns error for non-existent session" do
      response = described_class.call(name: "nonexistent", server_context: server_context)
      expect(response.error?).to be true
      expect(response.content.first[:text]).to match(/not found/i)
    end
  end

  describe Sxn::MCP::Tools::Sessions::DeleteSession do
    it "deletes a session" do
      session_manager.create_session("to-delete")

      response = described_class.call(name: "to-delete", server_context: server_context, force: true)
      expect(response.error?).to be false
      expect(response.content.first[:text]).to include("deleted successfully")

      # Verify session is gone
      expect(session_manager.get_session("to-delete")).to be_nil
    end

    it "returns error for non-existent session" do
      response = described_class.call(name: "nonexistent", server_context: server_context)
      expect(response.error?).to be true
      expect(response.content.first[:text]).to match(/not found/i)
    end
  end

  describe Sxn::MCP::Tools::Sessions::ArchiveSession do
    it "archives a session" do
      session_manager.create_session("to-archive")

      response = described_class.call(name: "to-archive", server_context: server_context)
      expect(response.error?).to be false
      expect(response.content.first[:text]).to include("archived successfully")

      session = session_manager.get_session("to-archive")
      expect(session[:status]).to eq("archived")
    end
  end

  describe Sxn::MCP::Tools::Sessions::ActivateSession do
    it "activates an archived session" do
      session_manager.create_session("to-activate")
      session_manager.archive_session("to-activate")

      response = described_class.call(name: "to-activate", server_context: server_context)
      expect(response.error?).to be false
      expect(response.content.first[:text]).to include("activated successfully")

      session = session_manager.get_session("to-activate")
      expect(session[:status]).to eq("active")
    end
  end

  describe Sxn::MCP::Tools::Sessions::SwapSession do
    it "swaps to a session and returns navigation info" do
      session_manager.create_session("target-session")

      response = described_class.call(name: "target-session", server_context: server_context)
      text = response.content.first[:text]

      expect(response.error?).to be false
      expect(text).to include("Switched to session")
      expect(text).to include("target-session")
      expect(text).to include("Session path:")
      expect(text).to include("Navigation")
    end

    it "returns error for non-existent session" do
      response = described_class.call(name: "nonexistent", server_context: server_context)
      expect(response.error?).to be true
      expect(response.content.first[:text]).to match(/not found/i)
    end

    it "swaps to specific project worktree when project parameter provided" do
      # Create session and add worktrees
      session_manager.create_session("multi-project-session")

      # Mock worktree addition to simulate having worktrees
      project1_path = File.join(sessions_dir, "multi-project-session", "project1")
      project2_path = File.join(sessions_dir, "multi-project-session", "project2")

      # Get session and its id
      session = session_manager.get_session("multi-project-session")

      # Update session in database with worktrees
      database = session_manager.instance_variable_get(:@database)
      database.update_session(
        session[:id],
        {
          worktrees: {
            "project1" => { path: project1_path, branch: "main" },
            "project2" => { path: project2_path, branch: "feature" }
          }
        }
      )

      response = described_class.call(
        name: "multi-project-session",
        project: "project1",
        server_context: server_context
      )
      text = response.content.first[:text]

      expect(response.error?).to be false
      expect(text).to include("Switched to session")
      expect(text).to include("Target path: #{project1_path}")
      expect(text).to include("project1")
      expect(text).to include("project2")
    end

    it "uses session path when project not found in worktrees" do
      session_manager.create_session("session-with-worktrees")

      # Add a worktree
      session = session_manager.get_session("session-with-worktrees")
      project_path = File.join(sessions_dir, "session-with-worktrees", "existing-project")

      database = session_manager.instance_variable_get(:@database)
      database.update_session(
        session[:id],
        {
          worktrees: {
            "existing-project" => { path: project_path, branch: "main" }
          }
        }
      )

      response = described_class.call(
        name: "session-with-worktrees",
        project: "nonexistent-project",
        server_context: server_context
      )
      text = response.content.first[:text]

      expect(response.error?).to be false
      # Should fall back to session path
      expect(text).to include("Target path: #{session[:path]}")
    end

    it "displays empty worktrees list when session has no worktrees" do
      session_manager.create_session("empty-worktrees-session")

      response = described_class.call(name: "empty-worktrees-session", server_context: server_context)
      text = response.content.first[:text]

      expect(response.error?).to be false
      expect(text).to include("Switched to session")
      expect(text).to include("Worktrees:")
      expect(text).to include("(none)")
    end

    it "uses new_instance navigation strategy when session is outside workspace" do
      # Create a session normally
      session_manager.create_session("external-session")

      # Create a modified server_context with a different workspace_path
      # that doesn't contain the session path
      different_workspace = Dir.mktmpdir("sxn_different_workspace")

      begin
        modified_context = server_context.merge(workspace_path: different_workspace)

        response = described_class.call(name: "external-session", server_context: modified_context)
        text = response.content.first[:text]

        expect(response.error?).to be false
        expect(text).to include("Navigation (new_instance)")
        expect(text).to include("Session is outside current workspace")
        expect(text).to include("claude --cwd")
      ensure
        FileUtils.rm_rf(different_workspace)
      end
    end
  end

  # Branch coverage tests - specifically targeting uncovered branches
  describe "Branch coverage for uncovered paths" do
    describe "CreateSession template handling" do
      it "creates session without applying template when template_manager is nil" do
        # Create context without template_manager
        context_without_template = server_context.dup
        context_without_template.delete(:template_manager)

        response = Sxn::MCP::Tools::Sessions::CreateSession.call(
          name: "no-template-manager",
          template_id: "some-template",
          server_context: context_without_template
        )

        expect(response.error?).to be false
        expect(response.content.first[:text]).to include("created successfully")

        # Verify session was created but template was not applied
        session = session_manager.get_session("no-template-manager")
        expect(session).not_to be_nil
        expect(session[:template_id]).to eq("some-template")
      end

      it "logs warning when template application raises error during worktree creation" do
        template_manager = server_context[:template_manager]
        worktree_manager = server_context[:worktree_manager]

        # Mock template manager to return projects
        allow(template_manager).to receive(:get_template_projects).and_return([
                                                                                { name: "failing-project", branch: "main" }
                                                                              ])

        # Mock worktree manager to raise error
        allow(worktree_manager).to receive(:add_worktree).and_raise(StandardError.new("Disk full"))

        # Mock logger
        logger = instance_double(Logger)
        allow(Sxn).to receive(:logger).and_return(logger)
        allow(logger).to receive(:warn)

        response = Sxn::MCP::Tools::Sessions::CreateSession.call(
          name: "template-worktree-fail",
          template_id: "test-template",
          server_context: server_context
        )

        # Session should still be created
        expect(response.error?).to be false
        expect(response.content.first[:text]).to include("created successfully")

        # Verify warning was logged
        expect(logger).to have_received(:warn).with(/Failed to apply template.*Disk full/)
      end
    end

    describe "GetSession optional field rendering" do
      it "renders only description when other optional fields are absent" do
        session_manager.create_session(
          "desc-only-session",
          description: "Only has description"
        )

        response = Sxn::MCP::Tools::Sessions::GetSession.call(
          name: "desc-only-session",
          server_context: server_context
        )
        text = response.content.first[:text]

        expect(text).to include("Description: Only has description")
        expect(text).not_to include("Linear Task:")
        expect(text).not_to include("Template:")
      end

      it "renders only linear_task when other optional fields are absent" do
        session_manager.create_session(
          "linear-only-session",
          linear_task: "PROJ-999"
        )

        response = Sxn::MCP::Tools::Sessions::GetSession.call(
          name: "linear-only-session",
          server_context: server_context
        )
        text = response.content.first[:text]

        expect(text).to include("Linear Task: PROJ-999")
        expect(text).not_to include("Description:")
        expect(text).not_to include("Template:")
      end

      it "renders only template_id when other optional fields are absent" do
        session_manager.create_session(
          "template-only-session",
          template_id: "feature-template"
        )

        response = Sxn::MCP::Tools::Sessions::GetSession.call(
          name: "template-only-session",
          server_context: server_context
        )
        text = response.content.first[:text]

        expect(text).to include("Template: feature-template")
        expect(text).not_to include("Description:")
        expect(text).not_to include("Linear Task:")
      end

      it "renders no optional fields when all are absent" do
        session_manager.create_session("minimal-session")

        response = Sxn::MCP::Tools::Sessions::GetSession.call(
          name: "minimal-session",
          server_context: server_context
        )
        text = response.content.first[:text]

        expect(text).not_to include("Description:")
        expect(text).not_to include("Linear Task:")
        expect(text).not_to include("Template:")
        expect(text).to include("Session: minimal-session")
        expect(text).to include("Status:")
      end
    end

    describe "SwapSession project parameter branches" do
      it "uses session path as target when project parameter is nil" do
        session_manager.create_session("project-nil-session")

        response = Sxn::MCP::Tools::Sessions::SwapSession.call(
          name: "project-nil-session",
          project: nil,
          server_context: server_context
        )
        text = response.content.first[:text]

        session = session_manager.get_session("project-nil-session")
        expect(text).to include("Target path: #{session[:path]}")
        expect(response.error?).to be false
      end

      it "navigates to worktree path when project exists in worktrees" do
        session_manager.create_session("worktree-exists-session")
        session = session_manager.get_session("worktree-exists-session")

        # Add worktree with both symbol and string keys to test path lookup
        worktree_path = File.join(sessions_dir, "worktree-exists-session", "webapp")
        database = session_manager.instance_variable_get(:@database)
        database.update_session(
          session[:id],
          {
            worktrees: {
              "webapp" => { path: worktree_path, branch: "develop" }
            }
          }
        )

        response = Sxn::MCP::Tools::Sessions::SwapSession.call(
          name: "worktree-exists-session",
          project: "webapp",
          server_context: server_context
        )
        text = response.content.first[:text]

        expect(text).to include("Target path: #{worktree_path}")
        expect(response.error?).to be false
      end

      it "falls back to session path when project specified but worktrees is empty" do
        session_manager.create_session("empty-worktree-session")
        session = session_manager.get_session("empty-worktree-session")

        response = Sxn::MCP::Tools::Sessions::SwapSession.call(
          name: "empty-worktree-session",
          project: "any-project",
          server_context: server_context
        )
        text = response.content.first[:text]

        # Should use session path since worktrees hash is empty
        expect(text).to include("Target path: #{session[:path]}")
        expect(response.error?).to be false
      end
    end

    describe "SwapSession navigation strategy branches" do
      it "uses bash_cd strategy when target is within workspace" do
        session_manager.create_session("within-workspace-session")

        response = Sxn::MCP::Tools::Sessions::SwapSession.call(
          name: "within-workspace-session",
          server_context: server_context
        )
        text = response.content.first[:text]

        expect(text).to include("Navigation (bash_cd)")
        expect(text).to include("Run: cd")
        expect(response.error?).to be false
      end

      it "uses bash_cd strategy when workspace is within target (target contains workspace)" do
        session_manager.create_session("contains-workspace-session")
        session = session_manager.get_session("contains-workspace-session")

        # Create a modified context where workspace is inside session
        nested_workspace = File.join(session[:path], "nested")
        modified_context = server_context.merge(workspace_path: nested_workspace)

        response = Sxn::MCP::Tools::Sessions::SwapSession.call(
          name: "contains-workspace-session",
          server_context: modified_context
        )
        text = response.content.first[:text]

        expect(text).to include("Navigation (bash_cd)")
        expect(text).to include("Run: cd")
        expect(response.error?).to be false
      end

      it "uses new_instance strategy when target is completely outside workspace tree" do
        # Create external directory outside test_dir
        external_dir = Dir.mktmpdir("sxn_external_sessions")

        begin
          # Create a new session manager with external sessions folder
          external_config_dir = File.join(external_dir, ".sxn")
          FileUtils.mkdir_p(external_config_dir)

          external_config_path = File.join(external_config_dir, "config.yml")
          File.write(external_config_path, <<~YAML)
            version: 1
            sessions_folder: #{external_dir}/sessions
            projects: {}
          YAML

          external_db_path = File.join(external_config_dir, "sessions.db")
          Sxn::Database::SessionDatabase.new(external_db_path)

          external_config = Sxn::Core::ConfigManager.new(external_dir)
          external_session_mgr = Sxn::Core::SessionManager.new(external_config)

          # Create session in external location
          external_session_mgr.create_session("external-session")
          external_session = external_session_mgr.get_session("external-session")

          # Create modified context with external session but original workspace
          modified_context = {
            config_manager: external_config,
            session_manager: external_session_mgr,
            project_manager: Sxn::Core::ProjectManager.new(external_config),
            worktree_manager: Sxn::Core::WorktreeManager.new(external_config),
            template_manager: Sxn::Core::TemplateManager.new(external_config),
            rules_manager: Sxn::Core::RulesManager.new(external_config),
            workspace_path: test_dir # Original workspace, not containing external session
          }

          response = Sxn::MCP::Tools::Sessions::SwapSession.call(
            name: "external-session",
            server_context: modified_context
          )
          text = response.content.first[:text]

          expect(text).to include("Navigation (new_instance)")
          expect(text).to include("outside current workspace")
          expect(text).to include("claude --cwd #{external_session[:path]}")
          expect(response.error?).to be false
        ensure
          FileUtils.rm_rf(external_dir)
        end
      end
    end
  end
end
