# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"

RSpec.describe Sxn::MCP::Tools::Worktrees do
  let(:test_dir) { Dir.mktmpdir("sxn_mcp_test") }
  let(:sxn_dir) { File.join(test_dir, ".sxn") }
  let(:sessions_dir) { File.join(test_dir, "sxn-sessions") }
  let(:config_manager) { Sxn::Core::ConfigManager.new(test_dir) }
  let(:session_manager) { Sxn::Core::SessionManager.new(config_manager) }
  let(:worktree_manager) { Sxn::Core::WorktreeManager.new(config_manager, session_manager) }
  let(:rules_manager) { Sxn::Core::RulesManager.new(config_manager) }
  let(:server_context) do
    {
      config_manager: config_manager,
      session_manager: session_manager,
      project_manager: Sxn::Core::ProjectManager.new(config_manager),
      worktree_manager: worktree_manager,
      template_manager: Sxn::Core::TemplateManager.new(config_manager),
      rules_manager: rules_manager,
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

  describe Sxn::MCP::Tools::Worktrees::ListWorktrees do
    describe ".call" do
      context "when no worktrees exist" do
        before do
          session_manager.create_session("test-session")
          allow(worktree_manager).to receive(:list_worktrees).and_return([])
        end

        it "returns empty message" do
          response = described_class.call(
            server_context: server_context,
            session_name: "test-session"
          )

          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be false
          expect(response.content.first[:text]).to eq("No worktrees found in the session.")
        end
      end

      context "when worktrees exist" do
        let(:worktrees) do
          [
            {
              project: "project-a",
              branch: "main",
              status: "clean",
              path: "/path/to/worktree-a"
            },
            {
              project: "project-b",
              branch: "feature",
              status: "modified",
              path: "/path/to/worktree-b"
            },
            {
              project: "project-c",
              branch: "develop",
              status: "staged",
              path: "/path/to/worktree-c"
            }
          ]
        end

        before do
          allow(worktree_manager).to receive(:list_worktrees).and_return(worktrees)
        end

        it "returns formatted list of worktrees" do
          response = described_class.call(server_context: server_context)

          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Worktrees (3):")
          expect(text).to include("project-a (main) [clean]")
          expect(text).to include("/path/to/worktree-a")
          expect(text).to include("project-b (feature) [modified]")
          expect(text).to include("/path/to/worktree-b")
          expect(text).to include("project-c (develop) [staged]")
          expect(text).to include("/path/to/worktree-c")
        end
      end

      context "with different status values" do
        it "formats clean status correctly" do
          worktrees = [{ project: "test", branch: "main", status: "clean", path: "/path" }]
          allow(worktree_manager).to receive(:list_worktrees).and_return(worktrees)

          response = described_class.call(server_context: server_context)
          expect(response.content.first[:text]).to include("[clean]")
        end

        it "formats modified status correctly" do
          worktrees = [{ project: "test", branch: "main", status: "modified", path: "/path" }]
          allow(worktree_manager).to receive(:list_worktrees).and_return(worktrees)

          response = described_class.call(server_context: server_context)
          expect(response.content.first[:text]).to include("[modified]")
        end

        it "formats staged status correctly" do
          worktrees = [{ project: "test", branch: "main", status: "staged", path: "/path" }]
          allow(worktree_manager).to receive(:list_worktrees).and_return(worktrees)

          response = described_class.call(server_context: server_context)
          expect(response.content.first[:text]).to include("[staged]")
        end

        it "formats untracked status correctly" do
          worktrees = [{ project: "test", branch: "main", status: "untracked", path: "/path" }]
          allow(worktree_manager).to receive(:list_worktrees).and_return(worktrees)

          response = described_class.call(server_context: server_context)
          expect(response.content.first[:text]).to include("[untracked]")
        end

        it "formats missing status correctly" do
          worktrees = [{ project: "test", branch: "main", status: "missing", path: "/path" }]
          allow(worktree_manager).to receive(:list_worktrees).and_return(worktrees)

          response = described_class.call(server_context: server_context)
          expect(response.content.first[:text]).to include("[missing]")
        end

        it "formats unknown status correctly" do
          worktrees = [{ project: "test", branch: "main", status: "unknown", path: "/path" }]
          allow(worktree_manager).to receive(:list_worktrees).and_return(worktrees)

          response = described_class.call(server_context: server_context)
          expect(response.content.first[:text]).to include("[unknown]")
        end
      end

      context "with session_name parameter" do
        it "passes session_name to worktree_manager" do
          allow(worktree_manager).to receive(:list_worktrees).and_return([])

          described_class.call(server_context: server_context, session_name: "custom-session")

          expect(worktree_manager).to have_received(:list_worktrees).with(session_name: "custom-session")
        end
      end

      context "without session_name parameter" do
        it "passes nil session_name to worktree_manager" do
          allow(worktree_manager).to receive(:list_worktrees).and_return([])

          described_class.call(server_context: server_context)

          expect(worktree_manager).to have_received(:list_worktrees).with(session_name: nil)
        end
      end

      context "when not initialized" do
        let(:uninitialized_context) { { config_manager: nil, worktree_manager: nil } }

        it "returns error response" do
          response = described_class.call(server_context: uninitialized_context)

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "when errors occur" do
        it "handles SessionNotFoundError" do
          allow(worktree_manager).to receive(:list_worktrees)
            .and_raise(Sxn::SessionNotFoundError, "Session 'test' not found")

          response = described_class.call(server_context: server_context, session_name: "test")

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("not found")
          expect(response.content.first[:text]).to include("Session 'test' not found")
        end

        it "handles unexpected errors" do
          allow(worktree_manager).to receive(:list_worktrees)
            .and_raise(StandardError, "Something went wrong")

          response = described_class.call(server_context: server_context)

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
          expect(response.content.first[:text]).to include("Something went wrong")
        end
      end
    end
  end

  describe Sxn::MCP::Tools::Worktrees::AddWorktree do
    let(:worktree_result) do
      {
        project: "test-project",
        branch: "main",
        path: "/path/to/worktree",
        session: "test-session"
      }
    end

    describe ".call" do
      before do
        allow(worktree_manager).to receive(:add_worktree).and_return(worktree_result)
      end

      context "with default parameters" do
        it "creates a worktree successfully" do
          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Worktree created successfully:")
          expect(text).to include("Project: test-project")
          expect(text).to include("Branch: main")
          expect(text).to include("Path: /path/to/worktree")
          expect(text).to include("Session: test-session")
        end

        it "calls worktree_manager with correct parameters" do
          described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(worktree_manager).to have_received(:add_worktree)
            .with("test-project", nil, session_name: nil)
        end
      end

      context "with all parameters" do
        it "passes all parameters to worktree_manager" do
          described_class.call(
            project_name: "test-project",
            branch: "feature-branch",
            session_name: "custom-session",
            server_context: server_context
          )

          expect(worktree_manager).to have_received(:add_worktree)
            .with("test-project", "feature-branch", session_name: "custom-session")
        end
      end

      context "with apply_rules=true and rules_manager present" do
        let(:rules_result) do
          {
            success: true,
            applied_count: 2,
            errors: []
          }
        end

        before do
          allow(rules_manager).to receive(:apply_rules).and_return(rules_result)
        end

        it "applies rules after creating worktree" do
          response = described_class.call(
            project_name: "test-project",
            server_context: server_context,
            apply_rules: true
          )

          expect(rules_manager).to have_received(:apply_rules)
            .with("test-project", "test-session")
          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Rules applied: 2 rule(s)")
        end

        it "includes error messages when rules have errors" do
          rules_result[:errors] = ["Error 1", "Error 2"]
          allow(rules_manager).to receive(:apply_rules).and_return(rules_result)

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context,
            apply_rules: true
          )

          text = response.content.first[:text]
          expect(text).to include("Rule errors: Error 1, Error 2")
        end

        it "does not include error section when no errors" do
          response = described_class.call(
            project_name: "test-project",
            server_context: server_context,
            apply_rules: true
          )

          text = response.content.first[:text]
          expect(text).not_to include("Rule errors:")
        end
      end

      context "with apply_rules=false" do
        it "does not apply rules" do
          allow(rules_manager).to receive(:apply_rules)

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context,
            apply_rules: false
          )

          expect(rules_manager).not_to have_received(:apply_rules)
          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).not_to include("Rules applied:")
        end
      end

      context "when rules_manager is nil" do
        let(:context_without_rules) do
          server_context.merge(rules_manager: nil)
        end

        it "skips rule application without error" do
          response = described_class.call(
            project_name: "test-project",
            server_context: context_without_rules,
            apply_rules: true
          )

          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).not_to include("Rules applied:")
        end
      end

      context "when rule application fails" do
        before do
          allow(rules_manager).to receive(:apply_rules)
            .and_raise(StandardError, "Rule execution failed")
        end

        it "does not fail worktree creation" do
          response = described_class.call(
            project_name: "test-project",
            server_context: server_context,
            apply_rules: true
          )

          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Worktree created successfully:")
          expect(text).to include("Rules applied: 0 rule(s)")
          expect(text).to include("Rule errors: Rule execution failed")
        end
      end

      context "when not initialized" do
        let(:uninitialized_context) { { config_manager: nil, worktree_manager: nil, rules_manager: nil } }

        it "returns error response" do
          response = described_class.call(
            project_name: "test-project",
            server_context: uninitialized_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "when errors occur" do
        it "handles ProjectNotFoundError" do
          allow(worktree_manager).to receive(:add_worktree)
            .and_raise(Sxn::ProjectNotFoundError, "Project 'test' not found")

          response = described_class.call(
            project_name: "test",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("not found")
          expect(response.content.first[:text]).to include("Project 'test' not found")
        end

        it "handles SessionNotFoundError" do
          allow(worktree_manager).to receive(:add_worktree)
            .and_raise(Sxn::SessionNotFoundError, "Session 'test' not found")

          response = described_class.call(
            project_name: "test-project",
            session_name: "test",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("not found")
        end

        it "handles WorktreeExistsError" do
          allow(worktree_manager).to receive(:add_worktree)
            .and_raise(Sxn::WorktreeExistsError, "Worktree already exists")

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("already exists")
        end

        it "handles WorktreeCreationError" do
          allow(worktree_manager).to receive(:add_worktree)
            .and_raise(Sxn::WorktreeCreationError, "Failed to create")

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Failed to create")
        end

        it "handles unexpected errors" do
          allow(worktree_manager).to receive(:add_worktree)
            .and_raise(StandardError, "Something went wrong")

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end
    end
  end

  describe Sxn::MCP::Tools::Worktrees::RemoveWorktree do
    describe ".call" do
      before do
        allow(worktree_manager).to receive(:remove_worktree).and_return(true)
      end

      context "with default parameters" do
        it "removes a worktree successfully" do
          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be false
          expect(response.content.first[:text]).to eq("Worktree for 'test-project' removed successfully.")
        end

        it "calls worktree_manager with correct parameters" do
          described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(worktree_manager).to have_received(:remove_worktree)
            .with("test-project", session_name: nil)
        end
      end

      context "with session_name parameter" do
        it "passes session_name to worktree_manager" do
          described_class.call(
            project_name: "test-project",
            session_name: "custom-session",
            server_context: server_context
          )

          expect(worktree_manager).to have_received(:remove_worktree)
            .with("test-project", session_name: "custom-session")
        end
      end

      context "when not initialized" do
        let(:uninitialized_context) { { config_manager: nil, worktree_manager: nil } }

        it "returns error response" do
          response = described_class.call(
            project_name: "test-project",
            server_context: uninitialized_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "when errors occur" do
        it "handles WorktreeNotFoundError" do
          allow(worktree_manager).to receive(:remove_worktree)
            .and_raise(Sxn::WorktreeNotFoundError, "Worktree not found")

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("not found")
        end

        it "handles SessionNotFoundError" do
          allow(worktree_manager).to receive(:remove_worktree)
            .and_raise(Sxn::SessionNotFoundError, "Session 'test' not found")

          response = described_class.call(
            project_name: "test-project",
            session_name: "test",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("not found")
        end

        it "handles WorktreeRemovalError" do
          allow(worktree_manager).to receive(:remove_worktree)
            .and_raise(Sxn::WorktreeRemovalError, "Failed to remove")

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Failed to remove")
        end

        it "handles unexpected errors" do
          allow(worktree_manager).to receive(:remove_worktree)
            .and_raise(StandardError, "Something went wrong")

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end
    end
  end
end
