# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Commands::Rules, "comprehensive coverage for missing areas" do
  let(:command) { described_class.new }
  let(:mock_ui) { instance_double(Sxn::UI::Output) }
  let(:mock_prompt) { instance_double(Sxn::UI::Prompt) }
  let(:mock_table) { instance_double(Sxn::UI::Table) }
  let(:mock_config_manager) { instance_double(Sxn::Core::ConfigManager) }
  let(:mock_project_manager) { instance_double(Sxn::Core::ProjectManager) }
  let(:mock_rules_manager) { instance_double(Sxn::Core::RulesManager) }

  before do
    allow(Sxn::UI::Output).to receive(:new).and_return(mock_ui)
    allow(Sxn::UI::Prompt).to receive(:new).and_return(mock_prompt)
    allow(Sxn::UI::Table).to receive(:new).and_return(mock_table)
    allow(Sxn::Core::ConfigManager).to receive(:new).and_return(mock_config_manager)
    allow(Sxn::Core::ProjectManager).to receive(:new).and_return(mock_project_manager)
    allow(Sxn::Core::RulesManager).to receive(:new).and_return(mock_rules_manager)
    
    # Mock common UI methods
    allow(mock_ui).to receive(:error)
    allow(mock_ui).to receive(:info)
    allow(mock_ui).to receive(:success)
    allow(mock_ui).to receive(:warning)
    allow(mock_ui).to receive(:progress_start)
    allow(mock_ui).to receive(:progress_done)
    allow(mock_ui).to receive(:progress_failed)
    allow(mock_ui).to receive(:empty_state)
    allow(mock_ui).to receive(:recovery_suggestion)
    allow(mock_ui).to receive(:section)
    allow(mock_ui).to receive(:subsection)
    allow(mock_ui).to receive(:newline)
    allow(mock_ui).to receive(:key_value)
    allow(mock_ui).to receive(:list_item)
    allow(mock_ui).to receive(:command_example)
    
    # Mock common manager methods
    allow(mock_config_manager).to receive(:initialized?).and_return(true)
    allow(mock_config_manager).to receive(:current_session).and_return("test-session")
    
    # Allow Thor to instantiate the command
    allow(command).to receive(:exit)
  end

  describe "#initialize" do
    it "initializes all required components" do
      # The initialization happens in the before block setup
      expect(command.instance_variable_get(:@ui)).to eq(mock_ui)
      expect(command.instance_variable_get(:@prompt)).to eq(mock_prompt)
      expect(command.instance_variable_get(:@table)).to eq(mock_table)
      expect(command.instance_variable_get(:@config_manager)).to eq(mock_config_manager)
      expect(command.instance_variable_get(:@project_manager)).to eq(mock_project_manager)
      expect(command.instance_variable_get(:@rules_manager)).to eq(mock_rules_manager)
    end
  end

  describe "#add" do
    before do
      allow(mock_rules_manager).to receive(:add_rule).and_return({ project: "test", type: "copy_files", config: {} })
    end

    context "with non-interactive mode and all parameters" do
      it "adds rule with provided parameters" do
        allow(command).to receive(:options).and_return({ interactive: false })
        
        expect(mock_rules_manager).to receive(:add_rule).with("project1", "copy_files", { "source" => "file.txt" })
        expect(mock_ui).to receive(:success).with("Added copy_files rule for project1")
        
        expect {
          command.add("project1", "copy_files", '{"source": "file.txt"}')
        }.not_to raise_error
      end
    end

    context "with invalid JSON config" do
      it "shows error and exits" do
        allow(command).to receive(:options).and_return({ interactive: false })
        
        expect(mock_ui).to receive(:error).with(/Invalid JSON config/)
        expect(command).to receive(:exit).with(1)
        
        command.add("project1", "copy_files", "invalid-json")
      end
    end

    context "with interactive mode" do
      before do
        allow(command).to receive(:options).and_return({ interactive: true })
        allow(command).to receive(:select_project).and_return("selected-project")
        allow(mock_prompt).to receive(:rule_type).and_return("copy_files")
        allow(command).to receive(:prompt_rule_config).and_return({ "source" => "file.txt" })
      end

      it "guides through interactive rule creation" do
        expect(command).to receive(:select_project).with("Select project for rule:")
        expect(mock_prompt).to receive(:rule_type)
        expect(command).to receive(:prompt_rule_config).with("copy_files")
        expect(mock_ui).to receive(:success)
        
        command.add
      end

      it "returns early if no project selected" do
        expect(command).to receive(:select_project).and_return(nil)
        expect(mock_prompt).not_to receive(:rule_type)
        
        command.add
      end
    end

    context "with partial parameters" do
      it "prompts for missing project" do
        allow(command).to receive(:options).and_return({})
        allow(command).to receive(:select_project).and_return("selected-project")
        allow(mock_prompt).to receive(:rule_type).and_return("copy_files")
        allow(command).to receive(:prompt_rule_config).and_return({ "source" => "file.txt" })
        
        expect(command).to receive(:select_project)
        command.add(nil, "copy_files", '{"source": "file.txt"}')
      end

      it "prompts for missing rule type" do
        allow(command).to receive(:options).and_return({})
        allow(mock_prompt).to receive(:rule_type).and_return("copy_files")
        allow(command).to receive(:prompt_rule_config).and_return({ "source" => "file.txt" })
        
        expect(mock_prompt).to receive(:rule_type)
        command.add("project1", nil, '{"source": "file.txt"}')
      end

      it "prompts for missing config" do
        allow(command).to receive(:options).and_return({})
        allow(command).to receive(:prompt_rule_config).and_return({ "source" => "file.txt" })
        
        expect(command).to receive(:prompt_rule_config).with("copy_files")
        command.add("project1", "copy_files", nil)
      end
    end

    context "when rule creation fails" do
      it "handles Sxn::Error gracefully" do
        allow(command).to receive(:options).and_return({})
        allow(mock_rules_manager).to receive(:add_rule).and_raise(Sxn::Error.new("Rule creation failed", exit_code: 2))
        
        expect(mock_ui).to receive(:progress_failed)
        expect(mock_ui).to receive(:error).with("Rule creation failed")
        expect(command).to receive(:exit).with(2)
        
        command.add("project1", "copy_files", '{"source": "file.txt"}')
      end
    end

    context "display_rule_info helper" do
      it "displays rule information" do
        rule = { project: "test-project", type: "copy_files", config: { source: "file.txt" } }
        
        expect(mock_ui).to receive(:newline)
        expect(mock_ui).to receive(:key_value).with("Project", "test-project")
        expect(mock_ui).to receive(:key_value).with("Type", "copy_files")
        expect(mock_ui).to receive(:key_value).with("Config", JSON.pretty_generate({ source: "file.txt" }))
        expect(mock_ui).to receive(:newline)
        
        command.send(:display_rule_info, rule)
      end
    end
  end

  describe "#remove" do
    before do
      allow(mock_prompt).to receive(:confirm_deletion).and_return(true)
      allow(mock_rules_manager).to receive(:remove_rule)
    end

    context "with all parameters and --all option" do
      it "removes all rules of specified type" do
        allow(command).to receive(:options).and_return({ all: true })
        
        expect(mock_rules_manager).to receive(:remove_rule).with("project1", "copy_files")
        expect(mock_ui).to receive(:success).with("Removed all copy_files rules for project1")
        
        command.remove("project1", "copy_files", "1")
      end
    end

    context "with specific rule index" do
      it "removes specific rule by index" do
        allow(command).to receive(:options).and_return({})
        
        expect(mock_rules_manager).to receive(:remove_rule).with("project1", "copy_files", 1)
        expect(mock_ui).to receive(:success).with("Removed copy_files rule #1 for project1")
        
        command.remove("project1", "copy_files", "1")
      end
    end

    context "without project parameter" do
      it "prompts for project selection" do
        allow(command).to receive(:options).and_return({})
        allow(command).to receive(:select_project).and_return("selected-project")
        
        expect(command).to receive(:select_project).with("Select project:")
        command.remove(nil, "copy_files", "1")
      end

      it "returns early if no project selected" do
        allow(command).to receive(:options).and_return({})
        allow(command).to receive(:select_project).and_return(nil)
        
        expect(mock_rules_manager).not_to receive(:remove_rule)
        command.remove
      end
    end

    context "without rule type parameter" do
      it "prompts for rule type selection when rules exist" do
        allow(command).to receive(:options).and_return({})
        allow(mock_rules_manager).to receive(:list_rules).and_return([
          { type: "copy_files" }, { type: "setup_commands" }
        ])
        allow(mock_prompt).to receive(:select).and_return("copy_files")
        
        expect(mock_prompt).to receive(:select).with("Select rule type to remove:", ["copy_files", "setup_commands"])
        command.remove("project1", nil, "1")
      end

      it "shows empty state when no rules exist" do
        allow(command).to receive(:options).and_return({})
        allow(mock_rules_manager).to receive(:list_rules).and_return([])
        
        expect(mock_ui).to receive(:empty_state).with("No rules configured for project project1")
        expect(mock_rules_manager).not_to receive(:remove_rule)
        
        command.remove("project1")
      end
    end

    context "when user cancels deletion" do
      it "cancels operation and shows info" do
        allow(command).to receive(:options).and_return({})
        allow(mock_prompt).to receive(:confirm_deletion).and_return(false)
        
        expect(mock_ui).to receive(:info).with("Cancelled")
        expect(mock_rules_manager).not_to receive(:remove_rule)
        
        command.remove("project1", "copy_files", "1")
      end
    end

    context "when removal fails" do
      it "handles Sxn::Error gracefully" do
        allow(command).to receive(:options).and_return({})
        allow(mock_rules_manager).to receive(:remove_rule).and_raise(Sxn::Error.new("Removal failed", exit_code: 3))
        
        expect(mock_ui).to receive(:progress_failed)
        expect(mock_ui).to receive(:error).with("Removal failed")
        expect(command).to receive(:exit).with(3)
        
        command.remove("project1", "copy_files", "1")
      end
    end
  end

  describe "#list" do
    context "with rules available" do
      let(:rules) { [{ project: "p1", type: "copy", config: {} }] }

      before do
        allow(mock_rules_manager).to receive(:list_rules).and_return(rules)
        allow(mock_table).to receive(:rules)
      end

      it "lists all rules without validation" do
        allow(command).to receive(:options).and_return({})
        
        expect(mock_table).to receive(:rules).with(rules, nil)
        expect(mock_ui).to receive(:info).with("Total: 1 rules")
        
        command.list
      end

      it "filters rules by type when specified" do
        allow(command).to receive(:options).and_return({ type: "copy" })
        
        expect(mock_table).to receive(:rules).with(rules, nil)
        command.list
      end

      it "lists rules with validation when requested" do
        allow(command).to receive(:options).and_return({ validate: true })
        allow(command).to receive(:list_with_validation)
        
        expect(command).to receive(:list_with_validation).with(rules, nil)
        command.list
      end
    end

    context "with no rules" do
      before do
        allow(mock_rules_manager).to receive(:list_rules).and_return([])
        allow(command).to receive(:suggest_add_rule)
      end

      it "shows empty state for all projects" do
        allow(command).to receive(:options).and_return({})
        
        expect(mock_ui).to receive(:empty_state).with("No rules configured")
        expect(command).to receive(:suggest_add_rule)
        
        command.list
      end

      it "shows empty state for specific project" do
        allow(command).to receive(:options).and_return({})
        
        expect(mock_ui).to receive(:empty_state).with("No rules configured for project test-project")
        command.list("test-project")
      end
    end

    context "when listing fails" do
      it "handles Sxn::Error gracefully" do
        allow(mock_rules_manager).to receive(:list_rules).and_raise(Sxn::Error.new("List failed", exit_code: 4))
        
        expect(mock_ui).to receive(:error).with("List failed")
        expect(command).to receive(:exit).with(4)
        
        command.list
      end
    end
  end

  describe "#apply" do
    before do
      allow(mock_rules_manager).to receive(:apply_rules).and_return({ success: true, applied_count: 2, errors: [] })
    end

    context "with dry run option" do
      it "shows preview without applying" do
        allow(command).to receive(:options).and_return({ dry_run: true })
        allow(command).to receive(:show_rules_preview)
        
        expect(mock_ui).to receive(:info).with("Dry run mode - showing rules that would be applied")
        expect(command).to receive(:show_rules_preview).with("project1")
        expect(mock_rules_manager).not_to receive(:apply_rules)
        
        command.apply("project1")
      end
    end

    context "without active session" do
      before do
        allow(mock_config_manager).to receive(:current_session).and_return(nil)
      end

      it "shows error and exits" do
        allow(command).to receive(:options).and_return({})
        
        expect(mock_ui).to receive(:error).with("No active session")
        expect(mock_ui).to receive(:recovery_suggestion).with("Use 'sxn use <session>' or specify --session")
        expect(command).to receive(:exit).with(1)
        
        command.apply("project1")
      end
    end

    context "with custom session option" do
      it "uses specified session" do
        allow(command).to receive(:options).and_return({ session: "custom-session" })
        
        expect(mock_rules_manager).to receive(:apply_rules).with("project1", "custom-session")
        command.apply("project1")
      end
    end

    context "without project parameter" do
      let(:worktree_manager) { instance_double(Sxn::Core::WorktreeManager) }
      let(:worktrees) { [{ project: "p1", branch: "main" }, { project: "p2", branch: "develop" }] }

      before do
        allow(Sxn::Core::WorktreeManager).to receive(:new).and_return(worktree_manager)
        allow(worktree_manager).to receive(:list_worktrees).and_return(worktrees)
        allow(mock_prompt).to receive(:select).and_return("p1")
        allow(command).to receive(:options).and_return({})
      end

      it "prompts for project selection from worktrees" do
        expected_choices = [
          { name: "p1 (main)", value: "p1" },
          { name: "p2 (develop)", value: "p2" }
        ]
        
        expect(mock_prompt).to receive(:select).with("Select project to apply rules:", expected_choices)
        command.apply
      end

      it "handles empty worktrees" do
        allow(worktree_manager).to receive(:list_worktrees).and_return([])
        
        expect(mock_ui).to receive(:empty_state).with("No worktrees in current session")
        expect(mock_ui).to receive(:recovery_suggestion).with("Add worktrees with 'sxn worktree add <project>'")
        expect(command).to receive(:exit).with(1)
        
        command.apply
      end
    end

    context "with successful application" do
      it "shows success message" do
        allow(command).to receive(:options).and_return({})
        
        expect(mock_ui).to receive(:success).with("Applied 2 rules successfully")
        command.apply("project1")
      end
    end

    context "with partial application failure" do
      it "shows warning and errors" do
        allow(command).to receive(:options).and_return({})
        allow(mock_rules_manager).to receive(:apply_rules).and_return({
          success: false,
          applied_count: 1,
          errors: ["Error 1", "Error 2"]
        })
        
        expect(mock_ui).to receive(:warning).with("Some rules failed to apply")
        expect(mock_ui).to receive(:error).with("  Error 1")
        expect(mock_ui).to receive(:error).with("  Error 2")
        
        command.apply("project1")
      end
    end

    context "when application fails" do
      it "handles Sxn::Error gracefully" do
        allow(command).to receive(:options).and_return({})
        allow(mock_rules_manager).to receive(:apply_rules).and_raise(Sxn::Error.new("Apply failed", exit_code: 5))
        
        expect(mock_ui).to receive(:error).with("Apply failed")
        expect(command).to receive(:exit).with(5)
        
        command.apply("project1")
      end

      it "handles Sxn::Error gracefully in dry run mode" do
        allow(command).to receive(:options).and_return({ dry_run: true })
        allow(command).to receive(:show_rules_preview).and_raise(Sxn::Error.new("Preview failed", exit_code: 5))
        
        expect(mock_ui).to receive(:progress_failed)
        expect(mock_ui).to receive(:error).with("Preview failed")
        expect(command).to receive(:exit).with(5)
        
        command.apply("project1")
      end
    end
  end

  describe "#validate" do
    let(:validation_results) do
      [
        { type: "copy_files", index: 0, valid: true, errors: [] },
        { type: "setup_commands", index: 1, valid: false, errors: ["Invalid command"] }
      ]
    end

    before do
      allow(mock_rules_manager).to receive(:validate_rules).and_return(validation_results)
    end

    context "with project parameter" do
      it "validates rules and shows results" do
        expect(mock_ui).to receive(:section).with("Rule Validation: project1")
        expect(mock_ui).to receive(:list_item).with("✅ copy_files #0")
        expect(mock_ui).to receive(:list_item).with("❌ setup_commands #1")
        expect(mock_ui).to receive(:list_item).with("  Invalid command", nil)
        expect(mock_ui).to receive(:info).with("Valid: 1, Invalid: 1")
        expect(mock_ui).to receive(:warning).with("Fix invalid rules before applying")
        
        command.validate("project1")
      end

      it "shows success when all rules are valid" do
        valid_results = [{ type: "copy_files", index: 0, valid: true, errors: [] }]
        allow(mock_rules_manager).to receive(:validate_rules).and_return(valid_results)
        
        expect(mock_ui).to receive(:info).with("Valid: 1, Invalid: 0")
        expect(mock_ui).to receive(:success).with("All rules are valid")
        
        command.validate("project1")
      end
    end

    context "without project parameter" do
      it "prompts for project selection" do
        allow(command).to receive(:select_project).and_return("selected-project")
        
        expect(command).to receive(:select_project).with("Select project to validate:")
        command.validate
      end

      it "returns early if no project selected" do
        allow(command).to receive(:select_project).and_return(nil)
        
        expect(mock_rules_manager).not_to receive(:validate_rules)
        command.validate
      end
    end

    context "when validation fails" do
      it "handles Sxn::Error gracefully" do
        allow(mock_rules_manager).to receive(:validate_rules).and_raise(Sxn::Error.new("Validation failed", exit_code: 6))
        
        expect(mock_ui).to receive(:error).with("Validation failed")
        expect(command).to receive(:exit).with(6)
        
        command.validate("project1")
      end
    end
  end

  describe "#template" do
    let(:available_types) do
      [
        { name: "copy_files", description: "Copy files", example: { source: "file.txt" } },
        { name: "setup_commands", description: "Setup commands", example: { command: ["npm", "install"] } }
      ]
    end

    before do
      allow(mock_rules_manager).to receive(:get_available_rule_types).and_return(available_types)
      allow(mock_rules_manager).to receive(:generate_rule_template).and_return([{ source: "template.txt" }])
    end

    context "with rule type parameter" do
      it "generates template for specified type" do
        expect(mock_rules_manager).to receive(:generate_rule_template).with("copy_files", "rails")
        expect(mock_ui).to receive(:section).with("Rule Template: copy_files")
        expect(mock_ui).to receive(:info).with("Copy this template and customize for your project")
        expect(mock_ui).to receive(:command_example)
        
        expect { command.template("copy_files", "rails") }.to output.to_stdout
      end
    end

    context "without rule type parameter" do
      it "prompts for rule type selection" do
        expected_choices = [
          { name: "copy_files - Copy files", value: "copy_files" },
          { name: "setup_commands - Setup commands", value: "setup_commands" }
        ]
        allow(mock_prompt).to receive(:select).and_return("copy_files")
        
        expect(mock_prompt).to receive(:select).with("Select rule type:", expected_choices)
        command.template
      end
    end

    context "when template generation fails" do
      it "handles Sxn::Error gracefully" do
        allow(mock_rules_manager).to receive(:generate_rule_template).and_raise(Sxn::Error.new("Template failed", exit_code: 7))
        
        expect(mock_ui).to receive(:error).with("Template failed")
        expect(command).to receive(:exit).with(7)
        
        command.template("copy_files")
      end
    end
  end

  describe "#types" do
    let(:available_types) do
      [
        { name: "copy_files", description: "Copy files", example: { source: "file.txt" } },
        { name: "setup_commands", description: "Setup commands", example: { command: ["npm", "install"] } }
      ]
    end

    before do
      allow(mock_rules_manager).to receive(:get_available_rule_types).and_return(available_types)
    end

    it "lists all available rule types with examples" do
      expect(mock_ui).to receive(:section).with("Available Rule Types")
      expect(mock_ui).to receive(:subsection).with("copy_files")
      expect(mock_ui).to receive(:info).with("Copy files")
      expect(mock_ui).to receive(:subsection).with("setup_commands")
      expect(mock_ui).to receive(:info).with("Setup commands")
      
      expect { command.types }.to output(/Example:/).to_stdout
    end
  end

  describe "private helper methods" do
    describe "#ensure_initialized!" do
      context "when not initialized" do
        before do
          allow(mock_config_manager).to receive(:initialized?).and_return(false)
        end

        it "shows error and exits" do
          expect(mock_ui).to receive(:error).with("Project not initialized")
          expect(mock_ui).to receive(:recovery_suggestion).with("Run 'sxn init' to initialize sxn in this project")
          expect(command).to receive(:exit).with(1)
          
          command.send(:ensure_initialized!)
        end
      end

      context "when initialized" do
        it "does nothing" do
          expect(mock_ui).not_to receive(:error)
          expect(command).not_to receive(:exit)
          
          command.send(:ensure_initialized!)
        end
      end
    end

    describe "#select_project" do
      context "with projects available" do
        let(:projects) { [{ name: "p1", type: "rails" }, { name: "p2", type: "nodejs" }] }

        before do
          allow(mock_project_manager).to receive(:list_projects).and_return(projects)
          allow(mock_prompt).to receive(:select).and_return("p1")
        end

        it "prompts for project selection" do
          expected_choices = [
            { name: "p1 (rails)", value: "p1" },
            { name: "p2 (nodejs)", value: "p2" }
          ]
          
          expect(mock_prompt).to receive(:select).with("Test message", expected_choices)
          result = command.send(:select_project, "Test message")
          expect(result).to eq("p1")
        end
      end

      context "with no projects" do
        before do
          allow(mock_project_manager).to receive(:list_projects).and_return([])
        end

        it "shows empty state and returns nil" do
          expect(mock_ui).to receive(:empty_state).with("No projects configured")
          expect(mock_ui).to receive(:recovery_suggestion).with("Add projects with 'sxn projects add <name> <path>'")
          
          result = command.send(:select_project, "Test message")
          expect(result).to be_nil
        end
      end
    end

    describe "prompt_rule_config methods" do
      describe "#prompt_copy_files_config" do
        before do
          allow(mock_prompt).to receive(:ask).with("Source file path:").and_return("source.txt")
          allow(mock_prompt).to receive(:select).with("Copy strategy:", %w[copy symlink]).and_return("copy")
          allow(mock_prompt).to receive(:ask_yes_no).with("Set custom permissions?", default: false).and_return(false)
        end

        it "prompts for copy files configuration" do
          result = command.send(:prompt_copy_files_config)
          expect(result).to eq({ "source" => "source.txt", "strategy" => "copy" })
        end

        it "includes permissions when requested" do
          allow(mock_prompt).to receive(:ask_yes_no).with("Set custom permissions?", default: false).and_return(true)
          allow(mock_prompt).to receive(:ask).with("Permissions (octal, e.g., 0600):").and_return("0644")
          
          result = command.send(:prompt_copy_files_config)
          expect(result).to eq({ "source" => "source.txt", "strategy" => "copy", "permissions" => 0o644 })
        end
      end

      describe "#prompt_setup_commands_config" do
        before do
          allow(mock_prompt).to receive(:ask).with("Command (space-separated):").and_return("npm install")
          allow(mock_prompt).to receive(:ask_yes_no).with("Set environment variables?", default: false).and_return(false)
        end

        it "prompts for setup commands configuration" do
          result = command.send(:prompt_setup_commands_config)
          expect(result).to eq({ "command" => ["npm", "install"] })
        end

        it "includes environment variables when requested" do
          allow(mock_prompt).to receive(:ask_yes_no).with("Set environment variables?", default: false).and_return(true)
          allow(mock_prompt).to receive(:ask).with("Environment variable name (blank to finish):").and_return("NODE_ENV", "PORT", "")
          allow(mock_prompt).to receive(:ask).with("Value for NODE_ENV:").and_return("production")
          allow(mock_prompt).to receive(:ask).with("Value for PORT:").and_return("3000")
          
          result = command.send(:prompt_setup_commands_config)
          expect(result).to eq({
            "command" => ["npm", "install"],
            "environment" => { "NODE_ENV" => "production", "PORT" => "3000" }
          })
        end
      end

      describe "#prompt_template_config" do
        before do
          allow(mock_prompt).to receive(:ask).with("Template source path:").and_return("template.liquid")
          allow(mock_prompt).to receive(:ask).with("Destination path:").and_return("output.md")
        end

        it "prompts for template configuration" do
          result = command.send(:prompt_template_config)
          expect(result).to eq({
            "source" => "template.liquid",
            "destination" => "output.md",
            "process" => true
          })
        end
      end

      describe "#prompt_rule_config" do
        it "delegates to appropriate method based on rule type" do
          expect(command).to receive(:prompt_copy_files_config).and_return({})
          command.send(:prompt_rule_config, "copy_files")
          
          expect(command).to receive(:prompt_setup_commands_config).and_return({})
          command.send(:prompt_rule_config, "setup_commands")
          
          expect(command).to receive(:prompt_template_config).and_return({})
          command.send(:prompt_rule_config, "template")
        end

        it "handles unknown rule type" do
          expect(mock_ui).to receive(:error).with("Unknown rule type: unknown")
          expect(command).to receive(:exit).with(1)
          
          command.send(:prompt_rule_config, "unknown")
        end
      end
    end

    describe "#list_with_validation" do
      let(:rules) { [{ project: "p1", type: "copy", config: {} }] }
      let(:validation_results) { [{ type: "copy", index: 0, valid: true, errors: [] }] }

      before do
        allow(mock_rules_manager).to receive(:validate_rules).and_return(validation_results)
        allow(mock_table).to receive(:rules)
      end

      it "shows validation results and then table" do
        expect(mock_rules_manager).to receive(:validate_rules).with("project1")
        expect(mock_ui).to receive(:subsection).with("Rule Validation")
        expect(mock_ui).to receive(:list_item).with("✅ copy #0")
        expect(mock_table).to receive(:rules).with(rules, "project1")
        
        command.send(:list_with_validation, rules, "project1")
      end

      it "skips validation when no project specified" do
        expect(mock_rules_manager).not_to receive(:validate_rules)
        expect(mock_table).to receive(:rules).with(rules, nil)
        
        command.send(:list_with_validation, rules, nil)
      end
    end

    describe "#show_rules_preview" do
      let(:rules) { [{ type: "copy", config: { source: "file.txt" } }] }

      before do
        allow(mock_rules_manager).to receive(:list_rules).and_return(rules)
      end

      it "shows rules that would be applied" do
        expect(mock_ui).to receive(:subsection).with("Rules that would be applied:")
        expect(mock_ui).to receive(:list_item).with('copy: {source: "file.txt"}')
        
        command.send(:show_rules_preview, "project1")
      end

      it "shows empty state when no rules" do
        allow(mock_rules_manager).to receive(:list_rules).and_return([])
        
        expect(mock_ui).to receive(:empty_state).with("No rules configured for project project1")
        
        command.send(:show_rules_preview, "project1")
      end
    end

    describe "#suggest_add_rule" do
      it "shows recovery suggestion" do
        expect(mock_ui).to receive(:newline)
        expect(mock_ui).to receive(:recovery_suggestion).with("Add rules with 'sxn rules add <project> <type> <config>' or use 'sxn rules template <type>' for examples")
        
        command.send(:suggest_add_rule)
      end
    end
  end
end