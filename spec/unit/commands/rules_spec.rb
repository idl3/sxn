# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Commands::Rules do
  let(:mock_ui) { instance_double(Sxn::UI::Output) }
  let(:mock_prompt) { instance_double(Sxn::UI::Prompt) }
  let(:mock_table) { instance_double(Sxn::UI::Table) }
  let(:mock_config_manager) { instance_double(Sxn::Core::ConfigManager) }
  let(:mock_project_manager) { instance_double(Sxn::Core::ProjectManager) }
  let(:mock_rules_manager) { instance_double(Sxn::Core::RulesManager) }

  let(:rules_command) { described_class.new }

  before do
    allow(Sxn::UI::Output).to receive(:new).and_return(mock_ui)
    allow(Sxn::UI::Prompt).to receive(:new).and_return(mock_prompt)
    allow(Sxn::UI::Table).to receive(:new).and_return(mock_table)
    allow(Sxn::Core::ConfigManager).to receive(:new).and_return(mock_config_manager)
    allow(Sxn::Core::ProjectManager).to receive(:new).and_return(mock_project_manager)
    allow(Sxn::Core::RulesManager).to receive(:new).and_return(mock_rules_manager)

    # Default mock responses
    allow(mock_config_manager).to receive(:initialized?).and_return(true)
    allow(mock_ui).to receive(:success)
    allow(mock_ui).to receive(:error)
    allow(mock_ui).to receive(:info)
    allow(mock_ui).to receive(:warning)
    allow(mock_ui).to receive(:section)
    allow(mock_ui).to receive(:subsection)
    allow(mock_ui).to receive(:empty_state)
    allow(mock_ui).to receive(:recovery_suggestion)
    allow(mock_ui).to receive(:progress_start)
    allow(mock_ui).to receive(:progress_done)
    allow(mock_ui).to receive(:progress_failed)
    allow(mock_ui).to receive(:newline)
    allow(mock_ui).to receive(:key_value)
    allow(mock_ui).to receive(:list_item)
    allow(mock_table).to receive(:rules)
    allow(mock_prompt).to receive(:confirm_deletion).and_return(true)
    allow(mock_prompt).to receive(:rule_type).and_return("copy_files")
    allow(mock_prompt).to receive(:select).and_return("copy_files")
    allow(mock_prompt).to receive(:ask).and_return("test-input")
    allow(mock_prompt).to receive(:ask_yes_no).and_return(true)
    allow(rules_command).to receive(:options).and_return({})

    # Add default stubs for manager methods
    allow(mock_rules_manager).to receive(:add_rule)
    allow(mock_rules_manager).to receive(:remove_rule)
    allow(mock_rules_manager).to receive(:apply_rules)
    allow(mock_rules_manager).to receive(:validate_rules)
    allow(mock_rules_manager).to receive(:list_rules).and_return([])
  end

  describe "#add" do
    let(:rule_config) { { "source" => "config/master.key", "strategy" => "copy" } }
    let(:added_rule) { { project: "test-project", type: "copy_files", config: rule_config } }

    it "adds rule successfully" do
      allow(mock_rules_manager).to receive(:add_rule).and_return(added_rule)

      rules_command.add("test-project", "copy_files", rule_config.to_json)

      expect(mock_rules_manager).to have_received(:add_rule).with(
        "test-project",
        "copy_files",
        rule_config
      )
      expect(mock_ui).to have_received(:success).with("Added copy_files rule for test-project")
    end

    context "when JSON parsing fails" do
      it "handles invalid JSON gracefully" do
        expect { rules_command.add("project", "copy_files", "invalid json") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with(/Invalid JSON config/)
      end
    end

    context "when not initialized" do
      it "shows error and exits" do
        allow(mock_config_manager).to receive(:initialized?).and_return(false)

        expect { rules_command.add("project", "copy_files", "{}") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Project not initialized")
      end
    end

    context "when rule addition fails" do
      it "handles errors gracefully" do
        error = Sxn::InvalidRuleTypeError.new("Invalid rule type")
        allow(error).to receive(:exit_code).and_return(30)
        allow(mock_rules_manager).to receive(:add_rule).and_raise(error)

        expect { rules_command.add("project", "invalid", "{}") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Invalid rule type")
      end
    end

    context "interactive mode" do
      before do
        allow(rules_command).to receive(:options).and_return({ interactive: true })
        allow(rules_command).to receive(:select_project).and_return("selected-project")
        allow(rules_command).to receive(:prompt_rule_config).and_return(rule_config)
      end

      it "prompts for project when project_name is nil" do
        allow(mock_rules_manager).to receive(:add_rule).and_return(added_rule)

        rules_command.add(nil)

        expect(rules_command).to have_received(:select_project).with("Select project for rule:")
      end

      it "returns early when project selection is cancelled" do
        allow(rules_command).to receive(:select_project).and_return(nil)

        result = rules_command.add(nil)

        expect(result).to be_nil
        expect(mock_rules_manager).not_to have_received(:add_rule)
      end

      it "prompts for rule type when interactive" do
        allow(mock_rules_manager).to receive(:add_rule).and_return(added_rule)

        rules_command.add("project", nil)

        expect(mock_prompt).to have_received(:rule_type)
      end

      it "prompts for rule config when interactive" do
        allow(mock_rules_manager).to receive(:add_rule).and_return(added_rule)

        rules_command.add("project", "copy_files", nil)

        expect(rules_command).to have_received(:prompt_rule_config).with("copy_files")
      end
    end

    context "when project_name is nil but not interactive" do
      it "prompts for project selection" do
        allow(rules_command).to receive(:select_project).and_return("selected-project")
        allow(mock_rules_manager).to receive(:add_rule).and_return(added_rule)

        rules_command.add(nil, "copy_files", rule_config.to_json)

        expect(rules_command).to have_received(:select_project).with("Select project for rule:")
      end
    end

    context "when rule_type is nil but not interactive" do
      it "prompts for rule type" do
        allow(mock_rules_manager).to receive(:add_rule).and_return(added_rule)

        rules_command.add("project", nil, rule_config.to_json)

        expect(mock_prompt).to have_received(:rule_type)
      end
    end

    context "when rule_config is nil but not interactive" do
      before do
        allow(rules_command).to receive(:prompt_rule_config).and_return(rule_config)
      end

      it "prompts for rule config" do
        allow(mock_rules_manager).to receive(:add_rule).and_return(added_rule)

        rules_command.add("project", "copy_files", nil)

        expect(rules_command).to have_received(:prompt_rule_config).with("copy_files")
      end
    end
  end

  describe "#remove" do
    it "removes specific rule by index" do
      removed_rule = { "source" => "file.txt" }
      allow(mock_rules_manager).to receive(:remove_rule).and_return(removed_rule)

      rules_command.remove("test-project", "copy_files", "0")

      expect(mock_rules_manager).to have_received(:remove_rule).with(
        "test-project",
        "copy_files",
        0
      )
      expect(mock_ui).to have_received(:success).with("Removed copy_files rule #0 for test-project")
    end

    it "removes all rules with --all option" do
      allow(mock_rules_manager).to receive(:remove_rule)
      allow(rules_command).to receive(:options).and_return({ all: true })

      rules_command.remove("test-project", "copy_files")

      expect(mock_rules_manager).to have_received(:remove_rule).with(
        "test-project",
        "copy_files"
      )
      expect(mock_ui).to have_received(:success).with("Removed all copy_files rules for test-project")
    end

    context "when project_name is nil" do
      before do
        allow(rules_command).to receive(:select_project).and_return("selected-project")
      end

      it "prompts for project selection" do
        allow(mock_rules_manager).to receive(:remove_rule)

        rules_command.remove(nil, "copy_files")

        expect(rules_command).to have_received(:select_project).with("Select project:")
      end

      it "returns early when project selection is cancelled" do
        allow(rules_command).to receive(:select_project).and_return(nil)

        result = rules_command.remove(nil, "copy_files")

        expect(result).to be_nil
        expect(mock_rules_manager).not_to have_received(:remove_rule)
      end
    end

    context "when rule_type is nil" do
      let(:existing_rules) do
        [
          { type: "copy_files", config: {} },
          { type: "setup_commands", config: {} }
        ]
      end

      it "prompts for rule type selection when rules exist" do
        allow(mock_rules_manager).to receive(:list_rules).with("test-project").and_return(existing_rules)
        allow(mock_prompt).to receive(:select).and_return("copy_files")
        allow(mock_rules_manager).to receive(:remove_rule)

        rules_command.remove("test-project", nil)

        expect(mock_prompt).to have_received(:select).with(
          "Select rule type to remove:",
          %w[copy_files setup_commands]
        )
      end

      it "shows empty state and returns when no rules exist" do
        allow(mock_rules_manager).to receive(:list_rules).with("test-project").and_return([])

        result = rules_command.remove("test-project", nil)

        expect(mock_ui).to have_received(:empty_state).with("No rules configured for project test-project")
        expect(result).to be_nil
      end
    end

    context "when user cancels deletion confirmation" do
      it "shows cancelled message and returns" do
        allow(mock_prompt).to receive(:confirm_deletion).and_return(false)

        result = rules_command.remove("test-project", "copy_files")

        expect(mock_ui).to have_received(:info).with("Cancelled")
        expect(result).to be_nil
        expect(mock_rules_manager).not_to have_received(:remove_rule)
      end
    end

    context "when rule removal fails" do
      it "handles errors gracefully" do
        error = Sxn::RuleNotFoundError.new("Rule not found")
        allow(error).to receive(:exit_code).and_return(31)
        allow(mock_rules_manager).to receive(:remove_rule).and_raise(error)

        expect { rules_command.remove("project", "copy_files") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Rule not found")
      end
    end
  end

  describe "#list" do
    context "for specific project" do
      let(:project_rules) do
        [
          { project: "test-project", type: "copy_files", config: { source: "file.txt" } },
          { project: "test-project", type: "setup_commands", config: { command: %w[npm install] } }
        ]
      end

      it "lists rules for specific project" do
        allow(mock_rules_manager).to receive(:list_rules).with("test-project").and_return(project_rules)

        rules_command.list("test-project")

        expect(mock_table).to have_received(:rules).with(project_rules, "test-project")
        expect(mock_ui).to have_received(:info).with("Total: 2 rules")
      end

      it "shows empty state when no rules" do
        allow(mock_rules_manager).to receive(:list_rules).with("test-project").and_return([])

        rules_command.list("test-project")

        expect(mock_ui).to have_received(:empty_state).with("No rules configured for project test-project")
      end
    end

    context "for all projects" do
      let(:all_rules) do
        [
          { project: "project1", type: "copy_files", config: {} },
          { project: "project2", type: "setup_commands", config: {} }
        ]
      end

      it "lists rules for all projects" do
        allow(mock_rules_manager).to receive(:list_rules).with(nil).and_return(all_rules)

        rules_command.list

        expect(mock_table).to have_received(:rules).with(all_rules, nil)
        expect(mock_ui).to have_received(:info).with("Total: 2 rules")
      end

      it "shows empty state when no rules for all projects" do
        allow(mock_rules_manager).to receive(:list_rules).with(nil).and_return([])

        rules_command.list

        expect(mock_ui).to have_received(:empty_state).with("No rules configured")
      end
    end

    context "with type filter" do
      let(:all_rules) do
        [
          { project: "project1", type: "copy_files", config: {} },
          { project: "project2", type: "setup_commands", config: {} }
        ]
      end

      it "filters rules by type when type option is provided" do
        allow(rules_command).to receive(:options).and_return({ type: "copy_files" })
        allow(mock_rules_manager).to receive(:list_rules).with(nil).and_return(all_rules)

        rules_command.list

        filtered_rules = [{ project: "project1", type: "copy_files", config: {} }]
        expect(mock_table).to have_received(:rules).with(filtered_rules, nil)
        expect(mock_ui).to have_received(:info).with("Total: 1 rules")
      end
    end

    context "with validation option" do
      let(:project_rules) do
        [
          { project: "test-project", type: "copy_files", config: {} },
          { project: "test-project", type: "setup_commands", config: {} }
        ]
      end

      before do
        allow(rules_command).to receive(:options).and_return({ validate: true })
        allow(rules_command).to receive(:list_with_validation)
      end

      it "calls list_with_validation when validate option is set" do
        allow(mock_rules_manager).to receive(:list_rules).with("test-project").and_return(project_rules)

        rules_command.list("test-project")

        expect(rules_command).to have_received(:list_with_validation).with(project_rules, "test-project")
      end
    end

    context "when list operation fails" do
      it "handles errors gracefully" do
        error = Sxn::Error.new("List operation failed")
        allow(error).to receive(:exit_code).and_return(35)
        allow(mock_rules_manager).to receive(:list_rules).and_raise(error)

        expect { rules_command.list("project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("List operation failed")
      end
    end
  end

  describe "#apply" do
    let(:mock_worktree_manager) { instance_double(Sxn::Core::WorktreeManager) }

    before do
      allow(mock_config_manager).to receive(:current_session).and_return("test-session")
      allow(Sxn::Core::WorktreeManager).to receive(:new).and_return(mock_worktree_manager)
    end

    it "applies rules successfully" do
      results = { success: true, applied_count: 3, errors: [] }
      allow(mock_rules_manager).to receive(:apply_rules).and_return(results)

      rules_command.apply("test-project")

      expect(mock_rules_manager).to have_received(:apply_rules).with("test-project", "test-session")
      expect(mock_ui).to have_received(:success).with("Applied 3 rules successfully")
    end

    it "applies rules to specific session" do
      results = { success: true, applied_count: 1, errors: [] }
      allow(mock_rules_manager).to receive(:apply_rules).and_return(results)
      allow(rules_command).to receive(:options).and_return({ session: "custom-session" })

      rules_command.apply("test-project")

      expect(mock_rules_manager).to have_received(:apply_rules).with("test-project", "custom-session")
    end

    it "shows warning when some rules fail" do
      results = { success: false, applied_count: 1, errors: ["Rule failed"] }
      allow(mock_rules_manager).to receive(:apply_rules).and_return(results)

      rules_command.apply("test-project")

      expect(mock_ui).to have_received(:warning).with("Some rules failed to apply")
      expect(mock_ui).to have_received(:error).with("  Rule failed")
    end

    context "when no active session" do
      it "shows error and exits" do
        allow(mock_config_manager).to receive(:current_session).and_return(nil)

        expect { rules_command.apply("project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("No active session")
      end
    end

    context "when project_name is nil" do
      let(:worktrees) do
        [
          { project: "project1", branch: "main" },
          { project: "project2", branch: "develop" }
        ]
      end

      it "prompts for project selection when worktrees exist" do
        allow(mock_worktree_manager).to receive(:list_worktrees).with(session_name: "test-session").and_return(worktrees)
        allow(mock_prompt).to receive(:select).and_return("project1")
        allow(mock_rules_manager).to receive(:apply_rules).and_return({ success: true, applied_count: 1, errors: [] })

        rules_command.apply(nil)

        expect(mock_prompt).to have_received(:select).with(
          "Select project to apply rules:",
          [
            { name: "project1 (main)", value: "project1" },
            { name: "project2 (develop)", value: "project2" }
          ]
        )
      end

      it "shows error when no worktrees exist" do
        allow(mock_worktree_manager).to receive(:list_worktrees).with(session_name: "test-session").and_return([])

        expect { rules_command.apply(nil) }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:empty_state).with("No worktrees in current session")
        expect(mock_ui).to have_received(:recovery_suggestion).with("Add worktrees with 'sxn worktree add <project>'")
      end
    end

    context "with dry_run option" do
      before do
        allow(rules_command).to receive(:options).and_return({ dry_run: true })
        allow(rules_command).to receive(:show_rules_preview)
      end

      it "shows preview instead of applying rules" do
        rules_command.apply("test-project")

        expect(mock_ui).to have_received(:info).with("Dry run mode - showing rules that would be applied")
        expect(rules_command).to have_received(:show_rules_preview).with("test-project")
        expect(mock_rules_manager).not_to have_received(:apply_rules)
      end
    end

    context "when rule application fails" do
      it "handles errors gracefully" do
        error = Sxn::Error.new("Rule application failed")
        allow(error).to receive(:exit_code).and_return(32)
        allow(mock_rules_manager).to receive(:apply_rules).and_raise(error)

        expect { rules_command.apply("project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Rule application failed")
      end

      it "handles errors in dry run mode" do
        error = Sxn::Error.new("Preview failed")
        allow(error).to receive(:exit_code).and_return(32)
        allow(rules_command).to receive(:options).and_return({ dry_run: true })
        allow(rules_command).to receive(:show_rules_preview).and_raise(error)

        expect { rules_command.apply("project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:progress_failed)
        expect(mock_ui).to have_received(:error).with("Preview failed")
      end
    end
  end

  describe "#validate" do
    let(:validation_results) do
      [
        { type: "copy_files", index: 0, valid: true, errors: [] },
        { type: "copy_files", index: 1, valid: false, errors: ["Missing source"] }
      ]
    end

    it "validates rules and shows results" do
      allow(mock_rules_manager).to receive(:validate_rules).and_return(validation_results)

      rules_command.validate("test-project")

      expect(mock_rules_manager).to have_received(:validate_rules).with("test-project")
      expect(mock_ui).to have_received(:list_item).with("✅ copy_files #0")
      expect(mock_ui).to have_received(:list_item).with("❌ copy_files #1")
    end

    it "shows summary of validation results" do
      allow(mock_rules_manager).to receive(:validate_rules).and_return(validation_results)

      rules_command.validate("test-project")

      expect(mock_ui).to have_received(:info).with("Valid: 1, Invalid: 1")
    end

    context "when all rules are valid" do
      let(:all_valid_results) do
        [{ type: "copy_files", index: 0, valid: true, errors: [] }]
      end

      it "shows success message" do
        allow(mock_rules_manager).to receive(:validate_rules).and_return(all_valid_results)

        rules_command.validate("test-project")

        expect(mock_ui).to have_received(:success).with("All rules are valid")
      end
    end

    context "when project_name is nil" do
      before do
        allow(rules_command).to receive(:select_project).and_return("selected-project")
      end

      it "prompts for project selection" do
        allow(mock_rules_manager).to receive(:validate_rules).and_return(validation_results)

        rules_command.validate(nil)

        expect(rules_command).to have_received(:select_project).with("Select project to validate:")
      end

      it "returns early when project selection is cancelled" do
        allow(rules_command).to receive(:select_project).and_return(nil)

        result = rules_command.validate(nil)

        expect(result).to be_nil
        expect(mock_rules_manager).not_to have_received(:validate_rules)
      end
    end

    context "when validation results are nil" do
      it "shows error message and returns" do
        allow(mock_rules_manager).to receive(:validate_rules).and_return(nil)

        result = rules_command.validate("test-project")

        expect(mock_ui).to have_received(:error).with("No validation results returned")
        expect(result).to be_nil
      end
    end

    context "when validation fails with error" do
      it "handles Sxn::Error gracefully" do
        error = Sxn::Error.new("Validation failed")
        allow(error).to receive(:exit_code).and_return(36)
        allow(mock_rules_manager).to receive(:validate_rules).and_raise(error)

        expect { rules_command.validate("project") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Validation failed")
      end

      it "handles NoMethodError with warning" do
        error = NoMethodError.new("validate_rules not implemented")
        allow(mock_rules_manager).to receive(:validate_rules).and_raise(error)

        rules_command.validate("project")

        expect(mock_ui).to have_received(:warning).with("Validation not yet fully implemented: validate_rules not implemented")
      end
    end
  end

  describe "#template" do
    let(:rule_types) do
      [
        { name: "copy_files", description: "Copy files", example: {} },
        { name: "setup_commands", description: "Setup commands", example: {} }
      ]
    end

    before do
      allow(mock_ui).to receive(:command_example)
      allow(mock_prompt).to receive(:select).and_return("copy_files")
    end

    it "prompts for rule type when none specified" do
      allow(mock_rules_manager).to receive(:get_available_rule_types).and_return(rule_types)
      template = [{ "source" => "file.txt", "strategy" => "copy" }]
      allow(mock_rules_manager).to receive(:generate_rule_template).and_return(template)

      rules_command.template

      expect(mock_prompt).to have_received(:select).with(
        "Select rule type:",
        [
          { name: "copy_files - Copy files", value: "copy_files" },
          { name: "setup_commands - Setup commands", value: "setup_commands" }
        ]
      )
    end

    it "generates template for specific rule type" do
      template = [{ "source" => "file.txt", "strategy" => "copy" }]
      allow(mock_rules_manager).to receive(:generate_rule_template).and_return(template)

      rules_command.template("copy_files")

      expect(mock_rules_manager).to have_received(:generate_rule_template).with(
        "copy_files",
        nil
      )
      expect(mock_ui).to have_received(:section).with("Rule Template: copy_files")
    end

    it "generates template for specific rule type and project type" do
      template = [{ "source" => "config/master.key", "strategy" => "copy" }]
      allow(mock_rules_manager).to receive(:generate_rule_template).and_return(template)

      rules_command.template("copy_files", "rails")

      expect(mock_rules_manager).to have_received(:generate_rule_template).with(
        "copy_files",
        "rails"
      )
    end

    context "when template generation fails" do
      it "handles errors gracefully" do
        error = Sxn::Error.new("Unknown rule type")
        allow(error).to receive(:exit_code).and_return(33)
        allow(mock_rules_manager).to receive(:generate_rule_template).and_raise(error)

        expect { rules_command.template("invalid") }.to raise_error(SystemExit)
        expect(mock_ui).to have_received(:error).with("Unknown rule type")
      end
    end
  end

  describe "#types" do
    let(:rule_types) do
      [
        { name: "copy_files", description: "Copy files", example: { "source" => "file.txt" } },
        { name: "setup_commands", description: "Run commands", example: { "command" => %w[npm install] } }
      ]
    end

    it "displays available rule types" do
      allow(mock_rules_manager).to receive(:get_available_rule_types).and_return(rule_types)

      rules_command.types

      expect(mock_ui).to have_received(:section).with("Available Rule Types")
      expect(mock_ui).to have_received(:subsection).with("copy_files")
      expect(mock_ui).to have_received(:info).with("Copy files")
      expect(mock_ui).to have_received(:subsection).with("setup_commands")
      expect(mock_ui).to have_received(:info).with("Run commands")
    end
  end

  describe "private helper methods" do
    describe "#ensure_initialized!" do
      it "passes when initialized" do
        allow(mock_config_manager).to receive(:initialized?).and_return(true)

        expect do
          rules_command.send(:ensure_initialized!)
        end.not_to raise_error
      end

      it "exits when not initialized" do
        allow(mock_config_manager).to receive(:initialized?).and_return(false)

        expect do
          rules_command.send(:ensure_initialized!)
        end.to raise_error(SystemExit)

        expect(mock_ui).to have_received(:error).with("Project not initialized")
        expect(mock_ui).to have_received(:recovery_suggestion)
      end
    end

    describe "#select_project" do
      it "returns project name when projects exist" do
        projects = [{ name: "test-project", type: "rails" }]
        allow(mock_project_manager).to receive(:list_projects).and_return(projects)
        allow(mock_prompt).to receive(:select).and_return("test-project")

        result = rules_command.send(:select_project, "Select project:")

        expect(mock_prompt).to have_received(:select).with(
          "Select project:",
          [{ name: "test-project (rails)", value: "test-project" }]
        )
        expect(result).to eq("test-project")
      end

      it "returns nil when no projects exist" do
        allow(mock_project_manager).to receive(:list_projects).and_return([])

        result = rules_command.send(:select_project, "Select project:")

        expect(mock_ui).to have_received(:empty_state).with("No projects configured")
        expect(result).to be_nil
      end
    end

    describe "#prompt_rule_config" do
      context "for copy_files rule type" do
        it "prompts for copy files configuration" do
          allow(mock_prompt).to receive(:ask).with("Source file path:").and_return("config/file.txt")
          allow(mock_prompt).to receive(:select).with("Copy strategy:", %w[copy symlink]).and_return("copy")
          allow(mock_prompt).to receive(:ask_yes_no).with("Set custom permissions?", default: false).and_return(false)

          result = rules_command.send(:prompt_rule_config, "copy_files")

          expect(result).to eq({ "source" => "config/file.txt", "strategy" => "copy" })
        end

        it "prompts for permissions when requested" do
          allow(mock_prompt).to receive(:ask).with("Source file path:").and_return("config/file.txt")
          allow(mock_prompt).to receive(:select).with("Copy strategy:", %w[copy symlink]).and_return("copy")
          allow(mock_prompt).to receive(:ask_yes_no).with("Set custom permissions?", default: false).and_return(true)
          allow(mock_prompt).to receive(:ask).with("Permissions (octal, e.g., 0600):").and_return("0600")

          result = rules_command.send(:prompt_rule_config, "copy_files")

          expect(result).to eq({
                                 "source" => "config/file.txt",
                                 "strategy" => "copy",
                                 "permissions" => 384 # 0600 in decimal
                               })
        end
      end

      context "for setup_commands rule type" do
        it "prompts for setup commands configuration" do
          allow(mock_prompt).to receive(:ask).with("Command (space-separated):").and_return("npm install")
          allow(mock_prompt).to receive(:ask_yes_no).with("Set environment variables?", default: false).and_return(false)

          result = rules_command.send(:prompt_rule_config, "setup_commands")

          expect(result).to eq({ "command" => %w[npm install] })
        end

        it "prompts for environment variables when requested" do
          allow(mock_prompt).to receive(:ask).with("Command (space-separated):").and_return("npm install")
          allow(mock_prompt).to receive(:ask_yes_no).with("Set environment variables?", default: false).and_return(true)
          allow(mock_prompt).to receive(:ask).with("Environment variable name (blank to finish):").and_return("NODE_ENV", "PORT", "")
          allow(mock_prompt).to receive(:ask).with("Value for NODE_ENV:").and_return("development")
          allow(mock_prompt).to receive(:ask).with("Value for PORT:").and_return("3000")

          result = rules_command.send(:prompt_rule_config, "setup_commands")

          expect(result).to eq({
                                 "command" => %w[npm install],
                                 "environment" => { "NODE_ENV" => "development", "PORT" => "3000" }
                               })
        end

        it "skips environment variables when none are provided" do
          allow(mock_prompt).to receive(:ask).with("Command (space-separated):").and_return("npm install")
          allow(mock_prompt).to receive(:ask_yes_no).with("Set environment variables?", default: false).and_return(true)
          allow(mock_prompt).to receive(:ask).with("Environment variable name (blank to finish):").and_return("")

          result = rules_command.send(:prompt_rule_config, "setup_commands")

          expect(result).to eq({ "command" => %w[npm install] })
        end
      end

      context "for template rule type" do
        it "prompts for template configuration" do
          allow(mock_prompt).to receive(:ask).with("Template source path:").and_return("templates/config.erb")
          allow(mock_prompt).to receive(:ask).with("Destination path:").and_return("config/app.conf")

          result = rules_command.send(:prompt_rule_config, "template")

          expect(result).to eq({
                                 "source" => "templates/config.erb",
                                 "destination" => "config/app.conf",
                                 "process" => true
                               })
        end
      end

      context "for unknown rule type" do
        it "shows error and exits" do
          expect { rules_command.send(:prompt_rule_config, "unknown") }.to raise_error(SystemExit)
          expect(mock_ui).to have_received(:error).with("Unknown rule type: unknown")
        end
      end
    end

    describe "#display_rule_info" do
      it "displays rule information when rule is provided" do
        rule = {
          project: "test-project",
          type: "copy_files",
          config: { source: "file.txt", strategy: "copy" }
        }

        rules_command.send(:display_rule_info, rule)

        expect(mock_ui).to have_received(:key_value).with("Project", "test-project")
        expect(mock_ui).to have_received(:key_value).with("Type", "copy_files")
        expect(mock_ui).to have_received(:key_value).with("Config", JSON.pretty_generate(rule[:config]))
      end

      it "returns early when rule is nil" do
        result = rules_command.send(:display_rule_info, nil)

        expect(result).to be_nil
        expect(mock_ui).not_to have_received(:key_value)
      end

      it "handles rule with missing keys gracefully" do
        rule = {}

        rules_command.send(:display_rule_info, rule)

        expect(mock_ui).to have_received(:key_value).with("Project", "Unknown")
        expect(mock_ui).to have_received(:key_value).with("Type", "Unknown")
        expect(mock_ui).to have_received(:key_value).with("Config", "{}")
      end
    end

    describe "#list_with_validation" do
      let(:rules) do
        [
          { project: "test-project", type: "copy_files", config: {} }
        ]
      end

      context "when project_name is provided" do
        let(:validation_results) do
          [
            { type: "copy_files", index: 0, valid: true, errors: [] },
            { type: "setup_commands", index: 1, valid: false, errors: ["Command missing"] }
          ]
        end

        it "shows validation results and calls table" do
          allow(mock_rules_manager).to receive(:validate_rules).with("test-project").and_return(validation_results)

          rules_command.send(:list_with_validation, rules, "test-project")

          expect(mock_ui).to have_received(:subsection).with("Rule Validation")
          expect(mock_ui).to have_received(:list_item).with("✅ copy_files #0")
          expect(mock_ui).to have_received(:list_item).with("❌ setup_commands #1")
          expect(mock_ui).to have_received(:list_item).with("  Command missing")
          expect(mock_table).to have_received(:rules).with(rules, "test-project")
        end
      end

      context "when project_name is nil" do
        it "skips validation and calls table directly" do
          rules_command.send(:list_with_validation, rules, nil)

          expect(mock_ui).not_to have_received(:subsection).with("Rule Validation")
          expect(mock_table).to have_received(:rules).with(rules, nil)
        end
      end
    end

    describe "#show_rules_preview" do
      let(:rules) do
        [
          { type: "copy_files", config: { source: "file.txt" } },
          { type: "setup_commands", config: { command: %w[npm install] } }
        ]
      end

      it "shows preview of rules to be applied" do
        allow(mock_rules_manager).to receive(:list_rules).with("test-project").and_return(rules)

        rules_command.send(:show_rules_preview, "test-project")

        expect(mock_ui).to have_received(:subsection).with("Rules that would be applied:")
        # Use regex to match both Ruby 3.2 hashrocket (=>) and Ruby 3.3+ colon syntax
        expect(mock_ui).to have_received(:list_item).with(/copy_files: \{.*source.*"file\.txt".*\}/)
        expect(mock_ui).to have_received(:list_item).with(/setup_commands: \{.*command.*\["npm", "install"\].*\}/)
      end

      it "shows empty state when no rules exist" do
        allow(mock_rules_manager).to receive(:list_rules).with("test-project").and_return([])

        result = rules_command.send(:show_rules_preview, "test-project")

        expect(mock_ui).to have_received(:empty_state).with("No rules configured for project test-project")
        expect(result).to be_nil
      end
    end

    describe "#suggest_add_rule" do
      it "shows recovery suggestion for adding rules" do
        rules_command.send(:suggest_add_rule)

        expect(mock_ui).to have_received(:recovery_suggestion).with(
          "Add rules with 'sxn rules add <project> <type> <config>' or use 'sxn rules template <type>' for examples"
        )
      end
    end
  end
end
