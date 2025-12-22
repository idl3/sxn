# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"

RSpec.describe Sxn::MCP::Tools::Projects do
  let(:test_dir) { Dir.mktmpdir("sxn_mcp_test") }
  let(:sxn_dir) { File.join(test_dir, ".sxn") }
  let(:git_repo_path) { create_temp_git_repo }
  let(:config_manager) { Sxn::Core::ConfigManager.new(test_dir) }
  let(:project_manager) { Sxn::Core::ProjectManager.new(config_manager) }
  let(:server_context) do
    {
      config_manager: config_manager,
      project_manager: project_manager,
      session_manager: Sxn::Core::SessionManager.new(config_manager),
      worktree_manager: Sxn::Core::WorktreeManager.new(config_manager),
      template_manager: Sxn::Core::TemplateManager.new(config_manager),
      rules_manager: Sxn::Core::RulesManager.new(config_manager),
      workspace_path: test_dir
    }
  end

  before do
    FileUtils.mkdir_p(sxn_dir)

    config_path = File.join(sxn_dir, "config.yml")
    File.write(config_path, <<~YAML)
      version: 1
      sessions_folder: #{test_dir}/sxn-sessions
      projects: {}
    YAML

    db_path = File.join(sxn_dir, "sessions.db")
    Sxn::Database::SessionDatabase.new(db_path)
  end

  after do
    FileUtils.rm_rf(test_dir)
    FileUtils.rm_rf(git_repo_path) if git_repo_path && File.exist?(git_repo_path)
  end

  describe Sxn::MCP::Tools::Projects::ListProjects do
    describe ".call" do
      context "when no projects exist" do
        it "returns a message indicating no projects are registered" do
          response = described_class.call(server_context: server_context)

          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be false
          expect(response.content.first[:text]).to include("No projects registered")
          expect(response.content.first[:text]).to include("sxn_projects_add")
        end
      end

      context "when projects exist" do
        before do
          project_manager.add_project("test-project", git_repo_path, type: "ruby", default_branch: "main")
          project_manager.add_project("another-project", git_repo_path, type: "rails", default_branch: "master")
        end

        it "lists all registered projects" do
          response = described_class.call(server_context: server_context)

          text = response.content.first[:text]
          expect(response.error?).to be false
          expect(text).to include("Registered projects (2)")
          expect(text).to include("test-project")
          expect(text).to include("ruby")
          expect(text).to include("another-project")
          expect(text).to include("rails")
          expect(text).to include("Default branch: main")
          expect(text).to include("Default branch: master")
          expect(text).to include(git_repo_path)
        end

        it "formats project information correctly" do
          response = described_class.call(server_context: server_context)
          text = response.content.first[:text]

          # Check the format: - name (type)\n  path\n  Default branch: branch
          expect(text).to match(/- test-project \(ruby\)/)
          expect(text).to match(/- another-project \(rails\)/)
        end
      end

      context "when server context is not initialized" do
        it "handles initialization errors" do
          invalid_context = { config_manager: nil }
          response = described_class.call(server_context: invalid_context)

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "when project_manager raises an error" do
        it "wraps the error in an error response" do
          allow(server_context[:project_manager]).to receive(:list_projects)
            .and_raise(Sxn::ProjectNotFoundError, "Some error")

          response = described_class.call(server_context: server_context)

          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("not found")
          expect(response.content.first[:text]).to include("Some error")
        end
      end
    end
  end

  describe Sxn::MCP::Tools::Projects::AddProject do
    describe ".call" do
      context "with all parameters provided" do
        it "successfully registers a new project" do
          response = described_class.call(
            name: "my-project",
            path: git_repo_path,
            type: "ruby",
            default_branch: "main",
            server_context: server_context
          )

          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be false

          text = response.content.first[:text]
          expect(text).to include("Project 'my-project' registered successfully")
          expect(text).to include("Type: ruby")
          expect(text).to include("Path: #{File.expand_path(git_repo_path)}")
          expect(text).to include("Default branch: main")

          # Verify project was actually added
          project = project_manager.get_project("my-project")
          expect(project).not_to be_nil
          expect(project[:name]).to eq("my-project")
          expect(project[:type]).to eq("ruby")
          expect(project[:default_branch]).to eq("main")
        end
      end

      context "with minimal parameters (auto-detection)" do
        it "successfully registers a project with auto-detected type and branch" do
          # Create a Ruby project (Gemfile indicates Ruby project)
          File.write(File.join(git_repo_path, "Gemfile"), "source 'https://rubygems.org'")

          response = described_class.call(
            name: "auto-project",
            path: git_repo_path,
            server_context: server_context
          )

          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Project 'auto-project' registered successfully")
          expect(text).to include("Type: ruby")
          expect(text).to match(/Default branch: (main|master)/)
        end
      end

      context "when project name is invalid" do
        it "returns an error for names with special characters" do
          response = described_class.call(
            name: "invalid name!",
            path: git_repo_path,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/Invalid project name/i)
        end

        it "returns an error for names with spaces" do
          response = described_class.call(
            name: "my project",
            path: git_repo_path,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/Invalid project name/i)
        end
      end

      context "when project path is invalid" do
        it "returns an error for non-existent paths" do
          response = described_class.call(
            name: "test-project",
            path: "/nonexistent/path",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/Invalid project path|not a directory/i)
        end

        it "returns an error when path is a file instead of directory" do
          file_path = File.join(test_dir, "test_file.txt")
          File.write(file_path, "test")

          response = described_class.call(
            name: "test-project",
            path: file_path,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/Invalid project path|not a directory/i)
        end
      end

      context "when project already exists" do
        before do
          project_manager.add_project("existing-project", git_repo_path)
        end

        it "returns an error" do
          response = described_class.call(
            name: "existing-project",
            path: git_repo_path,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/already exists/i)
        end
      end

      context "when server context is not initialized" do
        it "handles initialization errors" do
          invalid_context = { config_manager: nil }
          response = described_class.call(
            name: "test-project",
            path: git_repo_path,
            server_context: invalid_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "when unexpected errors occur" do
        it "wraps unexpected errors in error response" do
          allow(server_context[:project_manager]).to receive(:add_project)
            .and_raise(StandardError, "Unexpected error")

          response = described_class.call(
            name: "test-project",
            path: git_repo_path,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end
    end
  end

  describe Sxn::MCP::Tools::Projects::GetProject do
    describe ".call" do
      context "with a valid project" do
        before do
          project_manager.add_project("valid-project", git_repo_path, type: "ruby", default_branch: "main")
        end

        it "returns detailed project information" do
          response = described_class.call(
            name: "valid-project",
            server_context: server_context
          )

          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be false

          text = response.content.first[:text]
          expect(text).to include("Project: valid-project")
          expect(text).to include("Type: ruby")
          expect(text).to include("Path: #{File.expand_path(git_repo_path)}")
          expect(text).to include("Default branch: main")
          expect(text).to include("Validation: Valid")
        end

        it "includes rules information when rules exist" do
          # Add a Rails project which has default rules
          rails_path = create_temp_git_repo
          File.write(File.join(rails_path, "Gemfile"), "source 'https://rubygems.org'")
          FileUtils.mkdir_p(File.join(rails_path, "config"))
          File.write(File.join(rails_path, "config", "application.rb"), "# Rails app")

          project_manager.add_project("rails-project", rails_path, type: "rails", default_branch: "main")

          response = described_class.call(
            name: "rails-project",
            server_context: server_context
          )

          text = response.content.first[:text]
          expect(text).to include("Rules:")
          expect(text).to match(/copy_files: \d+|setup_commands: \d+/)

          FileUtils.rm_rf(rails_path) if rails_path && File.exist?(rails_path)
        end

        it "indicates when no rules are defined" do
          # Unknown project type has no default rules
          unknown_path = create_temp_git_repo
          project_manager.add_project("unknown-project", unknown_path, type: "unknown", default_branch: "main")

          response = described_class.call(
            name: "unknown-project",
            server_context: server_context
          )

          text = response.content.first[:text]
          expect(text).to include("Rules: (none)")

          FileUtils.rm_rf(unknown_path) if unknown_path && File.exist?(unknown_path)
        end
      end

      context "with an invalid project (validation issues)" do
        it "shows validation issues when path doesn't exist" do
          # Add project, then delete the path
          project_manager.add_project("broken-project", git_repo_path, type: "ruby")
          FileUtils.rm_rf(git_repo_path)

          response = described_class.call(
            name: "broken-project",
            server_context: server_context
          )

          text = response.content.first[:text]
          expect(text).to include("Validation: Invalid")
          expect(text).to include("Project path does not exist")
        end

        it "shows validation issues when path is not a git repository" do
          # Create a directory that's not a git repo
          non_git_path = File.join(test_dir, "non-git")
          FileUtils.mkdir_p(non_git_path)

          project_manager.add_project("non-git-project", non_git_path, type: "ruby")

          response = described_class.call(
            name: "non-git-project",
            server_context: server_context
          )

          text = response.content.first[:text]
          expect(text).to include("Validation: Invalid")
          expect(text).to include("not a git repository")
        end
      end

      context "when project doesn't exist" do
        it "returns an error" do
          response = described_class.call(
            name: "nonexistent-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/not found/i)
          expect(response.content.first[:text]).to include("nonexistent-project")
        end
      end

      context "when server context is not initialized" do
        it "handles initialization errors" do
          invalid_context = { config_manager: nil }
          response = described_class.call(
            name: "test-project",
            server_context: invalid_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "when validation raises an error" do
        before do
          project_manager.add_project("error-project", git_repo_path)
        end

        it "wraps validation errors in error response" do
          allow(server_context[:project_manager]).to receive(:validate_project)
            .and_raise(StandardError, "Validation failed")

          response = described_class.call(
            name: "error-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "when get_project_rules raises an error" do
        before do
          project_manager.add_project("rules-error-project", git_repo_path)
        end

        it "wraps rules errors in error response" do
          allow(server_context[:project_manager]).to receive(:get_project_rules)
            .and_raise(StandardError, "Rules error")

          response = described_class.call(
            name: "rules-error-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "with multiple validation issues" do
        it "displays all validation issues" do
          # Add a valid project first, then mock validation to return multiple issues
          project_manager.add_project("multi-issue-project", git_repo_path, type: "ruby")

          # Mock validate_project to return multiple issues
          allow(server_context[:project_manager]).to receive(:validate_project).and_return({
                                                                                             valid: false,
                                                                                             issues: ["Project path does not exist", "Project path is not readable"],
                                                                                             project: { name: "multi-issue-project", path: git_repo_path, type: "ruby" }
                                                                                           })

          response = described_class.call(
            name: "multi-issue-project",
            server_context: server_context
          )

          text = response.content.first[:text]
          expect(text).to include("Validation: Invalid")
          # Multiple issues should be listed with "  - " prefix
          expect(text).to match(/  - /)
          expect(text).to include("Project path does not exist")
          expect(text).to include("Project path is not readable")
        end
      end

      context "with complex rules structures" do
        it "handles empty rules hash" do
          # Mock get_project_rules to return empty hash
          allow(server_context[:project_manager]).to receive(:get_project_rules)
            .and_return({})

          project_manager.add_project("empty-rules-project", git_repo_path)

          response = described_class.call(
            name: "empty-rules-project",
            server_context: server_context
          )

          text = response.content.first[:text]
          expect(text).to include("Rules: (none)")
        end

        it "handles rules with multiple types" do
          # Mock get_project_rules to return multiple rule types
          allow(server_context[:project_manager]).to receive(:get_project_rules).and_return({
                                                                                              "copy_files" => [{ "source" => ".env" }],
                                                                                              "setup_commands" => [{ "command" => %w[npm install] }],
                                                                                              "templates" => [{ "name" => "default" }]
                                                                                            })

          project_manager.add_project("multi-rules-project", git_repo_path)

          response = described_class.call(
            name: "multi-rules-project",
            server_context: server_context
          )

          text = response.content.first[:text]
          expect(text).to include("Rules:")
          expect(text).to include("copy_files: 1")
          expect(text).to include("setup_commands: 1")
          expect(text).to include("templates: 1")
        end

        it "handles rules with non-array values" do
          # Mock get_project_rules to return non-array rule values
          allow(server_context[:project_manager]).to receive(:get_project_rules).and_return({
                                                                                              "some_setting" => "value",
                                                                                              "another_setting" => 42
                                                                                            })

          project_manager.add_project("scalar-rules-project", git_repo_path)

          response = described_class.call(
            name: "scalar-rules-project",
            server_context: server_context
          )

          text = response.content.first[:text]
          # Non-array values should be converted to array for counting
          expect(text).to include("Rules:")
        end
      end
    end
  end

  describe "error handling integration" do
    describe "BaseTool.ensure_initialized!" do
      it "is called by all tool classes" do
        # Test that ensure_initialized! is called
        expect(Sxn::MCP::Tools::BaseTool).to receive(:ensure_initialized!).at_least(:once).and_call_original

        described_class::ListProjects.call(server_context: server_context)
      end
    end

    describe "BaseTool::ErrorMapping.wrap" do
      it "wraps all tool calls" do
        # Test that ErrorMapping.wrap is used
        expect(Sxn::MCP::Tools::BaseTool::ErrorMapping).to receive(:wrap).at_least(:once).and_call_original

        described_class::ListProjects.call(server_context: server_context)
      end
    end
  end

  describe "branch coverage" do
    describe "ListProjects line 28[else] - when projects list is not empty" do
      it "formats and displays projects correctly" do
        # Add multiple projects to ensure the else branch (line 28) is executed
        project_manager.add_project("project-one", git_repo_path, type: "ruby", default_branch: "main")

        response = described_class::ListProjects.call(server_context: server_context)

        # Verify the else branch was taken (projects not empty)
        text = response.content.first[:text]
        expect(response.error?).to be false
        expect(text).to include("Registered projects (1)")
        expect(text).to include("- project-one (ruby)")
        expect(text).to include("Default branch: main")
      end
    end

    describe "GetProject line 130[then] - when validation is valid" do
      it "displays 'Valid' status for a valid project" do
        project_manager.add_project("valid-proj", git_repo_path, type: "ruby", default_branch: "main")

        response = described_class::GetProject.call(
          name: "valid-proj",
          server_context: server_context
        )

        # Verify the then branch of validation[:valid] ? "Valid" : "Invalid"
        text = response.content.first[:text]
        expect(text).to include("Validation: Valid")
        expect(text).not_to include("Validation: Invalid")
      end
    end

    describe "GetProject line 131[else] - when validation has no issues" do
      it "does not display issues section for valid projects" do
        project_manager.add_project("clean-proj", git_repo_path, type: "ruby", default_branch: "main")

        response = described_class::GetProject.call(
          name: "clean-proj",
          server_context: server_context
        )

        # Verify the else branch (unless validation[:valid] is false, so no issues shown)
        text = response.content.first[:text]
        expect(text).to include("Validation: Valid")
        # The issues list should not appear in the output
        expect(text).not_to match(/  - .*Project path/)
      end
    end

    describe "GetProject line 133[else] - when rules exist" do
      it "displays rules summary when rules are present" do
        # Mock get_project_rules to return rules
        allow(server_context[:project_manager]).to receive(:get_project_rules).and_return({
                                                                                            "copy_files" => [{ "source" => ".env" }],
                                                                                            "setup_commands" => [{ "command" => %w[bundle install] }]
                                                                                          })

        project_manager.add_project("rules-proj", git_repo_path, type: "ruby", default_branch: "main")

        response = described_class::GetProject.call(
          name: "rules-proj",
          server_context: server_context
        )

        # Verify the else branch of rules_summary.empty? ? "(none)" : rules_summary
        text = response.content.first[:text]
        expect(text).to include("Rules: copy_files: 1, setup_commands: 1")
        expect(text).not_to include("Rules: (none)")
      end
    end
  end
end
