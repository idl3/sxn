# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"

RSpec.describe Sxn::MCP::Resources::SessionResources do
  let(:test_dir) { Dir.mktmpdir("sxn_mcp_test") }
  let(:sxn_dir) { File.join(test_dir, ".sxn") }
  let(:sessions_dir) { File.join(test_dir, "sxn-sessions") }
  let(:config_manager) { Sxn::Core::ConfigManager.new(test_dir) }
  let(:session_manager) { Sxn::Core::SessionManager.new(config_manager) }
  let(:project_manager) { Sxn::Core::ProjectManager.new(config_manager) }
  let(:server_context) do
    {
      config_manager: config_manager,
      session_manager: session_manager,
      project_manager: project_manager,
      workspace_path: test_dir
    }
  end
  let(:empty_context) { {} }

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

  describe ".build_all" do
    it "returns all resources when config_manager is present" do
      resources = described_class.build_all(server_context)

      expect(resources).to be_an(Array)
      expect(resources.length).to eq(3)
      expect(resources.all? { |r| r.is_a?(MCP::Resource) }).to be true
    end

    it "returns compacted array without nils when config_manager is present" do
      resources = described_class.build_all(server_context)

      expect(resources).not_to include(nil)
    end

    it "returns empty array when config_manager is missing" do
      resources = described_class.build_all(empty_context)

      expect(resources).to eq([])
    end

    it "includes current session resource" do
      resources = described_class.build_all(server_context)
      current_session = resources.find { |r| r.uri == "sxn://session/current" }

      expect(current_session).not_to be_nil
      expect(current_session.name).to eq("Current Session")
      expect(current_session.description).to eq("Information about the currently active sxn session")
      expect(current_session.mime_type).to eq("application/json")
    end

    it "includes all sessions resource" do
      resources = described_class.build_all(server_context)
      all_sessions = resources.find { |r| r.uri == "sxn://sessions" }

      expect(all_sessions).not_to be_nil
      expect(all_sessions.name).to eq("All Sessions")
      expect(all_sessions.description).to eq("Summary of all sxn sessions")
      expect(all_sessions.mime_type).to eq("application/json")
    end

    it "includes all projects resource" do
      resources = described_class.build_all(server_context)
      all_projects = resources.find { |r| r.uri == "sxn://projects" }

      expect(all_projects).not_to be_nil
      expect(all_projects.name).to eq("Registered Projects")
      expect(all_projects.description).to eq("All registered projects in the sxn workspace")
      expect(all_projects.mime_type).to eq("application/json")
    end
  end
end

RSpec.describe Sxn::MCP::Resources::ResourceContentReader do
  let(:test_dir) { Dir.mktmpdir("sxn_mcp_test") }
  let(:sxn_dir) { File.join(test_dir, ".sxn") }
  let(:sessions_dir) { File.join(test_dir, "sxn-sessions") }
  let(:config_manager) { Sxn::Core::ConfigManager.new(test_dir) }
  let(:session_manager) { Sxn::Core::SessionManager.new(config_manager) }
  let(:project_manager) { Sxn::Core::ProjectManager.new(config_manager) }
  let(:server_context) do
    {
      config_manager: config_manager,
      session_manager: session_manager,
      project_manager: project_manager,
      workspace_path: test_dir
    }
  end
  let(:empty_context) { {} }

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

  describe ".read_content" do
    it "routes to read_current_session for sxn://session/current" do
      result = described_class.read_content("sxn://session/current", server_context)
      data = JSON.parse(result)

      expect(data).to have_key("current_session").or have_key("error")
    end

    it "routes to read_all_sessions for sxn://sessions" do
      result = described_class.read_content("sxn://sessions", server_context)
      data = JSON.parse(result)

      expect(data).to have_key("total")
      expect(data).to have_key("sessions")
    end

    it "routes to read_all_projects for sxn://projects" do
      result = described_class.read_content("sxn://projects", server_context)
      data = JSON.parse(result)

      expect(data).to have_key("total")
      expect(data).to have_key("projects")
    end

    it "returns error for unknown URI" do
      result = described_class.read_content("sxn://unknown", server_context)
      data = JSON.parse(result)

      expect(data).to have_key("error")
      expect(data["error"]).to eq("Unknown resource: sxn://unknown")
    end
  end

  describe ".read_current_session (private method via read_content)" do
    context "when config_manager is missing" do
      it "returns sxn not initialized error" do
        result = described_class.read_content("sxn://session/current", empty_context)
        data = JSON.parse(result)

        expect(data).to have_key("error")
        expect(data["error"]).to eq("sxn not initialized")
      end
    end

    context "when no session is active" do
      it "returns null current session with message" do
        result = described_class.read_content("sxn://session/current", server_context)
        data = JSON.parse(result)

        expect(data["current_session"]).to be_nil
        expect(data["message"]).to eq("No active session")
      end
    end

    context "when a session exists" do
      before do
        session_manager.create_session("test-session", description: "Test session")
      end

      it "returns session details" do
        # Set current session
        allow(session_manager).to receive(:current_session).and_return(
          session_manager.get_session("test-session")
        )

        result = described_class.read_content("sxn://session/current", server_context)
        data = JSON.parse(result)

        expect(data).to have_key("name")
        expect(data["name"]).to eq("test-session")
        expect(data).to have_key("status")
        expect(data).to have_key("path")
        expect(data).to have_key("created_at")
        expect(data).to have_key("default_branch")
        expect(data).to have_key("worktrees")
        expect(data).to have_key("projects")
      end
    end

    context "when an error occurs" do
      it "returns error message" do
        # Force an error by making session_manager raise
        allow(server_context[:session_manager]).to receive(:current_session).and_raise(StandardError, "Test error")

        result = described_class.read_content("sxn://session/current", server_context)
        data = JSON.parse(result)

        expect(data).to have_key("error")
        expect(data["error"]).to eq("Test error")
      end
    end
  end

  describe ".read_all_sessions (private method via read_content)" do
    context "when config_manager is missing" do
      it "returns sxn not initialized error" do
        result = described_class.read_content("sxn://sessions", empty_context)
        data = JSON.parse(result)

        expect(data).to have_key("error")
        expect(data["error"]).to eq("sxn not initialized")
      end
    end

    context "when no sessions exist" do
      it "returns empty sessions list" do
        result = described_class.read_content("sxn://sessions", server_context)
        data = JSON.parse(result)

        expect(data["total"]).to eq(0)
        expect(data["sessions"]).to eq([])
      end
    end

    context "when sessions exist" do
      before do
        session_manager.create_session("session-1", description: "First session")
        session_manager.create_session("session-2", description: "Second session")
      end

      it "returns all sessions with correct structure" do
        result = described_class.read_content("sxn://sessions", server_context)
        data = JSON.parse(result)

        expect(data["total"]).to eq(2)
        expect(data["sessions"].length).to eq(2)

        first_session = data["sessions"].first
        expect(first_session).to have_key("name")
        expect(first_session).to have_key("status")
        expect(first_session).to have_key("worktree_count")
      end

      it "correctly counts worktrees" do
        result = described_class.read_content("sxn://sessions", server_context)
        data = JSON.parse(result)

        data["sessions"].each do |session|
          expect(session["worktree_count"]).to eq(0)
        end
      end
    end

    context "when an error occurs" do
      it "returns error message" do
        # Force an error by making session_manager raise
        allow(server_context[:session_manager]).to receive(:list_sessions).and_raise(StandardError, "Test error")

        result = described_class.read_content("sxn://sessions", server_context)
        data = JSON.parse(result)

        expect(data).to have_key("error")
        expect(data["error"]).to eq("Test error")
      end
    end
  end

  describe ".read_all_projects (private method via read_content)" do
    context "when config_manager is missing" do
      it "returns sxn not initialized error" do
        result = described_class.read_content("sxn://projects", empty_context)
        data = JSON.parse(result)

        expect(data).to have_key("error")
        expect(data["error"]).to eq("sxn not initialized")
      end
    end

    context "when no projects exist" do
      it "returns empty projects list" do
        result = described_class.read_content("sxn://projects", server_context)
        data = JSON.parse(result)

        expect(data["total"]).to eq(0)
        expect(data["projects"]).to eq([])
      end
    end

    context "when projects exist" do
      let(:project_path) { create_temp_git_repo }

      before do
        project_manager.add_project("project-1", project_path, type: "rails")
      end

      after do
        FileUtils.rm_rf(project_path) if project_path && File.exist?(project_path)
      end

      it "returns all projects with correct structure" do
        result = described_class.read_content("sxn://projects", server_context)
        data = JSON.parse(result)

        expect(data["total"]).to eq(1)
        expect(data["projects"].length).to eq(1)

        first_project = data["projects"].first
        expect(first_project).to have_key("name")
        expect(first_project).to have_key("type")
        expect(first_project).to have_key("path")
        expect(first_project["name"]).to eq("project-1")
        expect(first_project["type"]).to eq("rails")
      end
    end

    context "when an error occurs" do
      it "returns error message" do
        # Force an error by making project_manager raise
        allow(server_context[:project_manager]).to receive(:list_projects).and_raise(StandardError, "Test error")

        result = described_class.read_content("sxn://projects", server_context)
        data = JSON.parse(result)

        expect(data).to have_key("error")
        expect(data["error"]).to eq("Test error")
      end
    end
  end
end
