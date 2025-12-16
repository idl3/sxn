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
  end
end
