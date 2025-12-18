# frozen_string_literal: true

require "spec_helper"
require "sxn/mcp"
require "yaml"

RSpec.describe Sxn::MCP::Tools::Rules do
  let(:test_dir) { Dir.mktmpdir("sxn_mcp_test") }
  let(:sxn_dir) { File.join(test_dir, ".sxn") }
  let(:sessions_dir) { File.join(test_dir, "sxn-sessions") }
  let(:config_manager) { Sxn::Core::ConfigManager.new(test_dir) }
  let(:project_manager) { Sxn::Core::ProjectManager.new(config_manager) }
  let(:session_manager) { Sxn::Core::SessionManager.new(config_manager) }
  let(:worktree_manager) { Sxn::Core::WorktreeManager.new(config_manager, session_manager) }
  let(:rules_manager) { Sxn::Core::RulesManager.new(config_manager, project_manager) }
  let(:server_context) do
    {
      config_manager: config_manager,
      session_manager: session_manager,
      project_manager: project_manager,
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

  # Helper method to add rules to config file
  def add_rules_to_config(project_name, rules_hash)
    config_path = File.join(sxn_dir, "config.yml")
    config_data = YAML.load_file(config_path)
    config_data["projects"] ||= {}
    config_data["projects"][project_name] ||= {}
    config_data["projects"][project_name]["rules"] = rules_hash
    File.write(config_path, YAML.dump(config_data))
  end

  describe Sxn::MCP::Tools::Rules::ListRules do
    describe ".call" do
      context "when no rules are defined" do
        it "returns empty message" do
          response = described_class.call(server_context: server_context)

          expect(response).to be_a(MCP::Tool::Response)
          expect(response.error?).to be false
          expect(response.content.first[:text]).to include("No rules defined")
        end
      end

      context "when rules exist for projects" do
        let(:project_dir) { File.join(test_dir, "test-project") }

        before do
          FileUtils.mkdir_p(project_dir)
          File.write(File.join(project_dir, ".git"), "")
          project_manager.add_project("test-project", project_dir)
        end

        context "with copy_files rules" do
          before do
            add_rules_to_config("test-project", {
                                  "copy_files" => [
                                    { "source" => "config/master.key", "strategy" => "copy" }
                                  ]
                                })
          end

          it "lists all rules when no project_name is specified" do
            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            expect(text).to include("Project rules:")
            expect(text).to include("test-project:")
            expect(text).to include("[copy_files]")
            expect(text).to include("config/master.key")
          end

          it "lists rules for specific project when project_name is provided" do
            response = described_class.call(
              server_context: server_context,
              project_name: "test-project"
            )

            expect(response.error?).to be false
            text = response.content.first[:text]
            expect(text).to include("test-project:")
            expect(text).to include("[copy_files]")
            expect(text).to include("config/master.key")
          end
        end

        context "with setup_commands rules" do
          before do
            add_rules_to_config("test-project", {
                                  "setup_commands" => [
                                    { "command" => %w[bundle install] }
                                  ]
                                })
          end

          it "displays command as joined string" do
            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            expect(text).to include("[setup_commands]")
            expect(text).to include("bundle")
            expect(text).to include("install")
          end
        end

        context "with template rules" do
          before do
            add_rules_to_config("test-project", {
                                  "template" => [
                                    {
                                      "source" => ".sxn/templates/README.md",
                                      "destination" => "README.md"
                                    }
                                  ]
                                })
          end

          it "displays template source and destination" do
            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            expect(text).to include("[template]")
            expect(text).to include(".sxn/templates/README.md")
            expect(text).to include("README.md")
          end
        end

        context "with multiple projects and rules" do
          let(:project2_dir) { File.join(test_dir, "project2") }

          before do
            FileUtils.mkdir_p(project2_dir)
            File.write(File.join(project2_dir, ".git"), "")
            project_manager.add_project("project2", project2_dir)

            add_rules_to_config("test-project", {
                                  "copy_files" => [
                                    { "source" => "file1.txt", "strategy" => "copy" }
                                  ]
                                })
            add_rules_to_config("project2", {
                                  "copy_files" => [
                                    { "source" => "file2.txt", "strategy" => "symlink" }
                                  ]
                                })
          end

          it "groups rules by project" do
            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            expect(text).to include("test-project:")
            expect(text).to include("project2:")
            expect(text).to include("file1.txt")
            expect(text).to include("file2.txt")
          end
        end

        context "with unknown rule type" do
          before do
            # Add rules with unknown type directly to config file
            add_rules_to_config("test-project", {
                                  "unknown_type" => [{ "some_config" => "value" }]
                                })
          end

          it "displays the config as a string" do
            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            expect(text).to include("[unknown_type]")
            # Should fall through to the else branch and call .to_s
            expect(text).to include("some_config")
          end
        end

        context "with setup_commands rule with nil command" do
          it "handles nil command gracefully with safe navigation" do
            # Mock list_rules to return a setup_commands rule with nil command
            # This tests the &. safe navigation operator on line 43
            allow(rules_manager).to receive(:list_rules).and_return([
                                                                      {
                                                                        project: "test-project",
                                                                        type: :setup_commands,
                                                                        index: 0,
                                                                        config: { "command" => nil },
                                                                        enabled: true
                                                                      }
                                                                    ])

            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            expect(text).to include("test-project:")
            expect(text).to include("[setup_commands]")
            # When command is nil, &.join returns nil, which should be displayed
            expect(text).to match(/\[setup_commands\]\s*$/)
          end
        end

        context "verifying exact config_preview format for each rule type" do
          it "formats copy_files to show source path" do
            # Mock to return a copy_files rule
            allow(rules_manager).to receive(:list_rules).and_return([
                                                                      {
                                                                        project: "test-project",
                                                                        type: :copy_files,
                                                                        index: 0,
                                                                        config: { "source" => "config/secrets.yml", "strategy" => "copy" },
                                                                        enabled: true
                                                                      }
                                                                    ])

            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            # Verify exact format: [copy_files] config/secrets.yml
            expect(text).to include("[copy_files] config/secrets.yml")
          end

          it "formats setup_commands to show joined command" do
            # Mock to return a setup_commands rule with command array
            allow(rules_manager).to receive(:list_rules).and_return([
                                                                      {
                                                                        project: "test-project",
                                                                        type: :setup_commands,
                                                                        index: 0,
                                                                        config: { "command" => ["bundle", "exec", "rake", "db:setup"] },
                                                                        enabled: true
                                                                      }
                                                                    ])

            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            # Verify exact format: [setup_commands] bundle exec rake db:setup
            expect(text).to include("[setup_commands] bundle exec rake db:setup")
          end

          it "formats template to show source -> destination" do
            # Mock to return a template rule
            allow(rules_manager).to receive(:list_rules).and_return([
                                                                      {
                                                                        project: "test-project",
                                                                        type: :template,
                                                                        index: 0,
                                                                        config: {
                                                                          "source" => ".sxn/templates/config.yml",
                                                                          "destination" => "config/app.yml"
                                                                        },
                                                                        enabled: true
                                                                      }
                                                                    ])

            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            # Verify exact format: [template] .sxn/templates/config.yml -> config/app.yml
            expect(text).to include("[template] .sxn/templates/config.yml -> config/app.yml")
          end

          it "formats unknown rule types using to_s" do
            # Mock to return a custom/unknown rule type
            allow(rules_manager).to receive(:list_rules).and_return([
                                                                      {
                                                                        project: "test-project",
                                                                        type: :custom_rule,
                                                                        index: 0,
                                                                        config: { "custom_key" => "custom_value", "number" => 42 },
                                                                        enabled: true
                                                                      }
                                                                    ])

            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]
            # Verify it uses .to_s on the config hash
            expect(text).to include("[custom_rule]")
            expect(text).to include("custom_key")
            expect(text).to include("custom_value")
          end
        end

        context "with mixed rule types in same project" do
          it "displays all rule types with correct formatting" do
            # Mock to return multiple rules of different types
            allow(rules_manager).to receive(:list_rules).and_return([
                                                                      {
                                                                        project: "test-project",
                                                                        type: :copy_files,
                                                                        index: 0,
                                                                        config: { "source" => ".env", "strategy" => "copy" },
                                                                        enabled: true
                                                                      },
                                                                      {
                                                                        project: "test-project",
                                                                        type: :setup_commands,
                                                                        index: 0,
                                                                        config: { "command" => %w[npm install] },
                                                                        enabled: true
                                                                      },
                                                                      {
                                                                        project: "test-project",
                                                                        type: :template,
                                                                        index: 0,
                                                                        config: {
                                                                          "source" => "templates/readme.md",
                                                                          "destination" => "README.md"
                                                                        },
                                                                        enabled: true
                                                                      }
                                                                    ])

            response = described_class.call(server_context: server_context)

            expect(response.error?).to be false
            text = response.content.first[:text]

            # Verify all three rule types are present with correct format
            expect(text).to include("[copy_files] .env")
            expect(text).to include("[setup_commands] npm install")
            expect(text).to include("[template] templates/readme.md -> README.md")
          end
        end
      end

      context "when not initialized" do
        let(:uninitialized_context) do
          {
            config_manager: nil,
            rules_manager: nil
          }
        end

        it "handles uninitialized context" do
          # When rules_manager is nil, it will raise NoMethodError which gets wrapped
          response = described_class.call(server_context: uninitialized_context)

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "error handling" do
        it "wraps ProjectNotFoundError" do
          response = described_class.call(
            server_context: server_context,
            project_name: "nonexistent-project"
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/not found/i)
        end

        it "wraps StandardError as unexpected error" do
          allow(rules_manager).to receive(:list_rules).and_raise(StandardError, "Something broke")

          response = described_class.call(server_context: server_context)

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
          expect(response.content.first[:text]).to include("Something broke")
        end
      end
    end
  end

  describe Sxn::MCP::Tools::Rules::ApplyRules do
    let(:project_dir) { File.join(test_dir, "test-project") }
    let(:session_name) { "test-session" }
    let(:worktree_dir) { File.join(sessions_dir, session_name, "test-project") }

    before do
      # Create project
      FileUtils.mkdir_p(project_dir)
      File.write(File.join(project_dir, ".git"), "")
      project_manager.add_project("test-project", project_dir)

      # Create session
      session_manager.create_session(session_name)

      # Create worktree directory structure
      FileUtils.mkdir_p(worktree_dir)
    end

    describe ".call" do
      context "with successful rule application" do
        before do
          # Mock apply_rules to return success
          allow(rules_manager).to receive(:apply_rules).and_return({
                                                                     success: true,
                                                                     applied_count: 1,
                                                                     errors: []
                                                                   })
        end

        it "applies rules successfully" do
          response = described_class.call(
            project_name: "test-project",
            session_name: session_name,
            server_context: server_context
          )

          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Rules applied successfully")
          expect(text).to include("test-project")
          expect(text).to include("Applied: 1 rule(s)")
        end

        it "uses current session when session_name is not provided" do
          config_manager.update_current_session(session_name)

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response.error?).to be false
          expect(response.content.first[:text]).to include("Rules applied successfully")
        end
      end

      context "with partial rule failures" do
        before do
          # Mock apply_rules to return partial failure
          allow(rules_manager).to receive(:apply_rules).and_return({
                                                                     success: false,
                                                                     applied_count: 1,
                                                                     errors: ["copy_files: File not found"]
                                                                   })
        end

        it "reports partial success with errors" do
          response = described_class.call(
            project_name: "test-project",
            session_name: session_name,
            server_context: server_context
          )

          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Some rules failed")
          expect(text).to include("test-project")
          expect(text).to include("Applied:")
          expect(text).to include("Errors:")
        end
      end

      context "error handling" do
        it "returns error when project not found" do
          response = described_class.call(
            project_name: "nonexistent-project",
            session_name: session_name,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/not found/i)
        end

        it "returns error when session not found" do
          response = described_class.call(
            project_name: "test-project",
            session_name: "nonexistent-session",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/not found/i)
        end

        it "returns error when no active session and session_name not provided" do
          # Ensure no current session is set
          config_manager.update_current_session(nil)

          response = described_class.call(
            project_name: "test-project",
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/no active session/i)
        end

        it "returns error when worktree not found" do
          allow(server_context[:worktree_manager]).to receive(:get_worktree).and_return(nil)

          response = described_class.call(
            project_name: "test-project",
            session_name: session_name,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to match(/worktree.*not found/i)
        end

        it "wraps ConfigurationError" do
          allow(rules_manager).to receive(:apply_rules)
            .and_raise(Sxn::ConfigurationError, "Config error")

          response = described_class.call(
            project_name: "test-project",
            session_name: session_name,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("sxn not initialized")
          expect(response.content.first[:text]).to include("sxn init")
        end

        it "wraps StandardError as unexpected error" do
          allow(rules_manager).to receive(:apply_rules)
            .and_raise(StandardError, "Unexpected problem")

          response = described_class.call(
            project_name: "test-project",
            session_name: session_name,
            server_context: server_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
          expect(response.content.first[:text]).to include("Unexpected problem")
        end
      end

      context "when not initialized" do
        let(:uninitialized_context) do
          {
            config_manager: nil,
            rules_manager: nil
          }
        end

        it "handles uninitialized context" do
          response = described_class.call(
            project_name: "test-project",
            server_context: uninitialized_context
          )

          expect(response.error?).to be true
          expect(response.content.first[:text]).to include("Unexpected error")
        end
      end

      context "with edge cases" do
        it "handles project with no rules" do
          allow(rules_manager).to receive(:apply_rules).and_return({
                                                                     success: true,
                                                                     applied_count: 0,
                                                                     errors: []
                                                                   })

          response = described_class.call(
            project_name: "test-project",
            session_name: session_name,
            server_context: server_context
          )

          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Rules applied successfully")
          expect(text).to include("Applied: 0 rule(s)")
        end

        it "handles multiple rules of the same type" do
          allow(rules_manager).to receive(:apply_rules).and_return({
                                                                     success: true,
                                                                     applied_count: 2,
                                                                     errors: []
                                                                   })

          response = described_class.call(
            project_name: "test-project",
            session_name: session_name,
            server_context: server_context
          )

          expect(response.error?).to be false
          text = response.content.first[:text]
          expect(text).to include("Applied: 2 rule(s)")
        end
      end
    end
  end

  # Test edge cases for both tools
  describe "shared behavior" do
    describe "input validation" do
      it "ListRules accepts optional project_name" do
        expect do
          Sxn::MCP::Tools::Rules::ListRules.call(server_context: server_context)
        end.not_to raise_error
      end

      it "ApplyRules requires project_name" do
        # This is enforced by the input_schema, but we can test the method signature
        expect do
          Sxn::MCP::Tools::Rules::ApplyRules.call(
            project_name: "test",
            server_context: server_context
          )
        end.not_to raise_error(ArgumentError)
      end
    end

    describe "response format" do
      let(:project_dir) { File.join(test_dir, "test-project") }

      before do
        FileUtils.mkdir_p(project_dir)
        File.write(File.join(project_dir, ".git"), "")
        project_manager.add_project("test-project", project_dir)
      end

      it "ListRules returns proper MCP response" do
        response = Sxn::MCP::Tools::Rules::ListRules.call(server_context: server_context)

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content).to be_an(Array)
        expect(response.content.first).to have_key(:type)
        expect(response.content.first).to have_key(:text)
      end

      it "ApplyRules returns proper MCP response" do
        session_manager.create_session("test-session")
        worktree_dir = File.join(sessions_dir, "test-session", "test-project")
        FileUtils.mkdir_p(worktree_dir)

        allow(server_context[:worktree_manager]).to receive(:get_worktree).and_return(
          {
            project: "test-project",
            session: "test-session",
            path: worktree_dir,
            branch: "main"
          }
        )

        response = Sxn::MCP::Tools::Rules::ApplyRules.call(
          project_name: "test-project",
          session_name: "test-session",
          server_context: server_context
        )

        expect(response).to be_a(MCP::Tool::Response)
        expect(response.content).to be_an(Array)
        expect(response.content.first).to have_key(:type)
        expect(response.content.first).to have_key(:text)
      end
    end
  end
end
