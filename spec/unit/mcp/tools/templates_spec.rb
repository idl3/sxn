# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"

RSpec.describe Sxn::MCP::Tools::Templates do
  let(:test_dir) { Dir.mktmpdir("sxn_mcp_test") }
  let(:sxn_dir) { File.join(test_dir, ".sxn") }
  let(:sessions_dir) { File.join(test_dir, "sxn-sessions") }
  let(:config_manager) { Sxn::Core::ConfigManager.new(test_dir) }
  let(:session_manager) { Sxn::Core::SessionManager.new(config_manager) }
  let(:template_manager) { Sxn::Core::TemplateManager.new(config_manager) }
  let(:worktree_manager) { Sxn::Core::WorktreeManager.new(config_manager) }
  let(:server_context) do
    {
      config_manager: config_manager,
      session_manager: session_manager,
      project_manager: Sxn::Core::ProjectManager.new(config_manager),
      worktree_manager: worktree_manager,
      template_manager: template_manager,
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

    # Create templates config file
    templates_path = File.join(sxn_dir, "templates.yml")
    File.write(templates_path, <<~YAML)
      version: 1
      templates: {}
    YAML
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe Sxn::MCP::Tools::Templates::ListTemplates do
    describe ".call" do
      it "returns empty message when no templates exist" do
        response = described_class.call(server_context: server_context)

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.error?).to be false
        expect(response.content.first[:text]).to include("No templates defined")
        expect(response.content.first[:text]).to include(".sxn/templates.yml")
      end

      it "lists a single template with description" do
        template_manager.create_template("web-stack", description: "Frontend and backend", projects: [])

        response = described_class.call(server_context: server_context)

        text = response.content.first[:text]
        expect(response.error?).to be false
        expect(text).to include("Available templates:")
        expect(text).to include("web-stack")
        expect(text).to include("(0 projects)")
        expect(text).to include("Frontend and backend")
      end

      it "lists a template without description" do
        template_manager.create_template("simple-stack", projects: [])

        response = described_class.call(server_context: server_context)

        text = response.content.first[:text]
        expect(text).to include("simple-stack")
        expect(text).to include("(0 projects)")
        expect(text).not_to include(" - ")
      end

      it "lists multiple templates" do
        template_manager.create_template("template1", description: "First template", projects: [])
        template_manager.create_template("template2", description: "Second template", projects: [])

        response = described_class.call(server_context: server_context)

        text = response.content.first[:text]
        expect(text).to include("template1")
        expect(text).to include("First template")
        expect(text).to include("template2")
        expect(text).to include("Second template")
      end

      it "shows correct project count for templates with projects" do
        # Create a mock project first
        config_path = File.join(sxn_dir, "config.yml")
        config_data = YAML.load_file(config_path)
        config_data["projects"] = {
          "project1" => { "path" => "/tmp/project1", "default_branch" => "main" },
          "project2" => { "path" => "/tmp/project2", "default_branch" => "main" }
        }
        File.write(config_path, YAML.dump(config_data))

        template_manager.create_template("multi-project", projects: %w[project1 project2])

        response = described_class.call(server_context: server_context)

        text = response.content.first[:text]
        expect(text).to include("multi-project")
        expect(text).to include("(2 projects)")
      end

      it "handles template_manager returning empty array directly" do
        allow(template_manager).to receive(:list_templates).and_return([])

        response = described_class.call(server_context: server_context)

        expect(response.content.first[:text]).to include("No templates defined")
      end

      it "returns error response when ErrorMapping catches an exception" do
        allow(template_manager).to receive(:list_templates).and_raise(StandardError, "Template error")

        response = described_class.call(server_context: server_context)

        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("Unexpected error")
      end
    end
  end

  describe Sxn::MCP::Tools::Templates::ApplyTemplate do
    let(:git_repo_dir) { Dir.mktmpdir("git_repo") }
    let(:project_name) { "test-project" }

    before do
      # Initialize a real git repo for worktree operations
      Dir.chdir(git_repo_dir) do
        `git init`
        `git config user.email "test@example.com"`
        `git config user.name "Test User"`
        File.write("README.md", "# Test Project")
        `git add README.md`
        `git commit -m "Initial commit"`
      end

      # Register the project
      config_path = File.join(sxn_dir, "config.yml")
      config_data = YAML.load_file(config_path)
      config_data["projects"] = {
        project_name => {
          "path" => git_repo_dir,
          "default_branch" => "master"
        }
      }
      File.write(config_path, YAML.dump(config_data))
    end

    after do
      FileUtils.rm_rf(git_repo_dir)
    end

    describe ".call" do
      it "applies template successfully with explicit session_name" do
        session_manager.create_session("test-session", default_branch: "feature-branch")
        template_manager.create_template("test-template", projects: [project_name])

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be false
        text = response.content.first[:text]
        expect(text).to include("Template 'test-template' applied to session 'test-session'")
        expect(text).to include("Created 1 worktree(s)")
        expect(text).to include(project_name)
      end

      it "applies template using current session when session_name not provided" do
        session_manager.create_session("current-session")
        config_manager.update_current_session("current-session")
        template_manager.create_template("test-template", projects: [project_name])

        response = described_class.call(
          template_name: "test-template",
          server_context: server_context
        )

        expect(response.error?).to be false
        text = response.content.first[:text]
        expect(text).to include("current-session")
        expect(text).to include("Created 1 worktree(s)")
      end

      it "returns error when no active session and session_name not provided" do
        template_manager.create_template("test-template", projects: [project_name])

        response = described_class.call(
          template_name: "test-template",
          server_context: server_context
        )

        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("No active session")
      end

      it "returns error when session not found" do
        template_manager.create_template("test-template", projects: [project_name])

        response = described_class.call(
          template_name: "test-template",
          session_name: "nonexistent-session",
          server_context: server_context
        )

        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("Session 'nonexistent-session' not found")
      end

      it "returns error when template validation fails" do
        session_manager.create_session("test-session")

        response = described_class.call(
          template_name: "nonexistent-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("not found")
      end

      it "uses session default_branch when available" do
        session_manager.create_session("test-session", default_branch: "custom-branch")
        template_manager.create_template("test-template", projects: [project_name])

        # Mock session_manager to return a session with default_branch set
        mock_session = {
          id: "test-id",
          name: "test-session",
          path: File.join(sessions_dir, "test-session"),
          default_branch: "custom-branch",
          status: "active",
          projects: [],
          worktrees: {}
        }
        allow(session_manager).to receive(:get_session).with("test-session").and_return(mock_session)

        # Track the actual call arguments
        actual_branch = nil
        allow(worktree_manager).to receive(:add_worktree) do |_name, branch, _opts|
          actual_branch = branch
          { path: "/some/path" }
        end

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be false
        expect(actual_branch).to eq("custom-branch")
      end

      it "uses session_name as default_branch when session has no default_branch" do
        session_manager.create_session("test-session")
        template_manager.create_template("test-template", projects: [project_name])

        # Track the actual call arguments
        actual_branch = nil
        allow(worktree_manager).to receive(:add_worktree) do |_name, branch, _opts|
          actual_branch = branch
          { path: "/some/path" }
        end

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be false
        expect(actual_branch).to eq("test-session")
      end

      it "handles mixed success and failure when creating worktrees" do
        # Add second project
        git_repo_dir2 = Dir.mktmpdir("git_repo2")
        Dir.chdir(git_repo_dir2) do
          `git init`
          `git config user.email "test@example.com"`
          `git config user.name "Test User"`
          File.write("README.md", "# Test Project 2")
          `git add README.md`
          `git commit -m "Initial commit"`
        end

        config_path = File.join(sxn_dir, "config.yml")
        config_data = YAML.load_file(config_path)
        config_data["projects"]["project2"] = {
          "path" => git_repo_dir2,
          "default_branch" => "master"
        }
        File.write(config_path, YAML.dump(config_data))

        session_manager.create_session("test-session")
        template_manager.create_template("test-template", projects: [project_name, "project2"])

        # Mock first succeeds, second fails
        call_count = 0
        allow(worktree_manager).to receive(:add_worktree) do |_name, _branch, _opts|
          call_count += 1
          raise Sxn::WorktreeError, "Failed to create worktree" unless call_count == 1

          { path: "/path/to/worktree1" }
        end

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be false
        text = response.content.first[:text]
        expect(text).to include("Created 1 worktree(s)")
        expect(text).to include("Failed (1)")
        expect(text).to include("Failed to create worktree")

        FileUtils.rm_rf(git_repo_dir2)
      end

      it "handles all worktrees failing" do
        session_manager.create_session("test-session")
        template_manager.create_template("test-template", projects: [project_name])

        allow(worktree_manager).to receive(:add_worktree).and_raise(
          Sxn::WorktreeError, "All worktrees failed"
        )

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be false
        text = response.content.first[:text]
        expect(text).to include("Created 0 worktree(s)")
        expect(text).to include("Failed (1)")
        expect(text).to include("All worktrees failed")
      end

      it "shows all successful worktrees in output" do
        # Add two more projects
        git_repo_dir2 = Dir.mktmpdir("git_repo2")
        git_repo_dir3 = Dir.mktmpdir("git_repo3")

        [git_repo_dir2, git_repo_dir3].each do |dir|
          Dir.chdir(dir) do
            `git init`
            `git config user.email "test@example.com"`
            `git config user.name "Test User"`
            File.write("README.md", "# Test Project")
            `git add README.md`
            `git commit -m "Initial commit"`
          end
        end

        config_path = File.join(sxn_dir, "config.yml")
        config_data = YAML.load_file(config_path)
        config_data["projects"]["project2"] = { "path" => git_repo_dir2, "default_branch" => "master" }
        config_data["projects"]["project3"] = { "path" => git_repo_dir3, "default_branch" => "master" }
        File.write(config_path, YAML.dump(config_data))

        session_manager.create_session("test-session")
        template_manager.create_template("test-template", projects: [project_name, "project2", "project3"])

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be false
        text = response.content.first[:text]
        expect(text).to include("Created 3 worktree(s)")
        expect(text).to include(project_name)
        expect(text).to include("project2")
        expect(text).to include("project3")

        FileUtils.rm_rf(git_repo_dir2)
        FileUtils.rm_rf(git_repo_dir3)
      end

      it "handles StandardError during worktree creation" do
        session_manager.create_session("test-session")
        template_manager.create_template("test-template", projects: [project_name])

        allow(worktree_manager).to receive(:add_worktree).and_raise(
          StandardError, "Unexpected error during creation"
        )

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be false
        text = response.content.first[:text]
        expect(text).to include("Failed (1)")
        expect(text).to include("Unexpected error during creation")
      end

      it "returns error when session is nil after lookup" do
        session_manager.create_session("test-session")
        template_manager.create_template("test-template", projects: [project_name])

        # Mock session_manager to return nil
        allow(session_manager).to receive(:get_session).and_return(nil)

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("Session 'test-session' not found")
      end

      it "validates template before attempting to create worktrees" do
        session_manager.create_session("test-session")

        # Create template with non-existent project
        templates_path = File.join(sxn_dir, "templates.yml")
        File.write(templates_path, <<~YAML)
          version: 1
          templates:
            invalid-template:
              description: "Template with invalid project"
              projects:
                - name: "nonexistent-project"
        YAML

        response = described_class.call(
          template_name: "invalid-template",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response.error?).to be true
        # Should fail at validation, not at worktree creation
        expect(response.content.first[:text]).to include("Invalid session template")
      end

      it "strips whitespace from output" do
        session_manager.create_session("test-session")
        template_manager.create_template("test-template", projects: [project_name])

        response = described_class.call(
          template_name: "test-template",
          session_name: "test-session",
          server_context: server_context
        )

        text = response.content.first[:text]
        expect(text).not_to start_with("\n")
        expect(text).not_to end_with("\n")
      end

      it "handles when current_session returns nil" do
        template_manager.create_template("test-template", projects: [project_name])

        # Ensure no current session
        allow(config_manager).to receive(:current_session).and_return(nil)

        response = described_class.call(
          template_name: "test-template",
          server_context: server_context
        )

        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("No active session")
      end
    end
  end
end
