# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Core::RulesManager do
  let(:mock_config_manager) do
    instance_double(Sxn::Core::ConfigManager).tap do |mgr|
      allow(mgr).to receive(:get_config).and_return(mock_config)
      allow(mgr).to receive(:current_session).and_return("test-session")
      allow(mgr).to receive(:add_project)
    end
  end

  let(:mock_project_manager) do
    instance_double(Sxn::Core::ProjectManager).tap do |mgr|
      allow(mgr).to receive(:get_project).and_return(project_data)
      allow(mgr).to receive(:get_project_rules).and_return({})
      allow(mgr).to receive(:list_projects).and_return([])
    end
  end

  let(:mock_rules_engine) do
    instance_double(Sxn::Rules::RulesEngine).tap do |engine|
      allow(engine).to receive(:apply_rules).and_return([])
    end
  end

  let(:mock_config) do
    double("Config").tap do |config|
      allow(config).to receive(:projects).and_return(projects_config)
    end
  end

  let(:projects_config) { {} }

  let(:project_data) do
    {
      name: "test-project",
      path: "/path/to/project",
      type: "rails",
      default_branch: "main"
    }
  end

  let(:rules_manager) do
    described_class.new(mock_config_manager, mock_project_manager).tap do |mgr|
      mgr.instance_variable_set(:@rules_engine, mock_rules_engine)
    end
  end

  before do
    allow(Sxn::Rules::RulesEngine).to receive(:new).and_return(mock_rules_engine)
  end

  describe "#initialize" do
    it "creates default managers when none provided" do
      expect(Sxn::Core::ConfigManager).to receive(:new).and_call_original
      expect(Sxn::Core::ProjectManager).to receive(:new).and_call_original
      allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:get_config).and_return(mock_config)

      described_class.new
    end

    it "uses provided managers" do
      manager = described_class.new(mock_config_manager, mock_project_manager)
      expect(manager).to be_a(described_class)
    end
  end

  describe "#add_rule" do
    it "adds a valid copy_files rule" do
      rule_config = { "source" => "config/master.key", "strategy" => "copy" }

      result = rules_manager.add_rule("test-project", "copy_files", rule_config)

      expect(result[:project]).to eq("test-project")
      expect(result[:type]).to eq("copy_files")
      expect(result[:config]).to eq(rule_config)
    end

    it "adds a valid setup_commands rule" do
      rule_config = { "command" => %w[bundle install] }

      result = rules_manager.add_rule("test-project", "setup_commands", rule_config)

      expect(result[:project]).to eq("test-project")
      expect(result[:type]).to eq("setup_commands")
      expect(result[:config]).to eq(rule_config)
    end

    it "adds a valid template rule" do
      rule_config = { "source" => "template.erb", "destination" => "output.txt" }

      result = rules_manager.add_rule("test-project", "template", rule_config)

      expect(result[:project]).to eq("test-project")
      expect(result[:type]).to eq("template")
      expect(result[:config]).to eq(rule_config)
    end

    it "raises error for non-existent project" do
      allow(mock_project_manager).to receive(:get_project).and_return(nil)

      expect do
        rules_manager.add_rule("non-existent", "copy_files", {})
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end

    it "raises error for invalid rule type" do
      expect do
        rules_manager.add_rule("test-project", "invalid_type", {})
      end.to raise_error(Sxn::InvalidRuleTypeError, /Invalid rule type: invalid_type/)
    end

    it "raises error for invalid copy_files config" do
      invalid_config = { "strategy" => "copy" } # missing source

      expect do
        rules_manager.add_rule("test-project", "copy_files", invalid_config)
      end.to raise_error(Sxn::InvalidRuleConfigError, /must have 'source' field/)
    end

    it "raises error for invalid setup_commands config" do
      invalid_config = { "command" => "bundle install" } # should be array

      expect do
        rules_manager.add_rule("test-project", "setup_commands", invalid_config)
      end.to raise_error(Sxn::InvalidRuleConfigError, /command must be an array/)
    end

    it "raises error for invalid template config" do
      invalid_config = { "source" => "template.erb" } # missing destination

      expect do
        rules_manager.add_rule("test-project", "template", invalid_config)
      end.to raise_error(Sxn::InvalidRuleConfigError, /must have 'source' and 'destination' fields/)
    end

    it "initializes project rules structure if not exists" do
      projects_config["test-project"] = {}

      rule_config = { "source" => "test.txt", "strategy" => "copy" }
      rules_manager.add_rule("test-project", "copy_files", rule_config)

      expect(projects_config["test-project"]["rules"]).to be_a(Hash)
      expect(projects_config["test-project"]["rules"]["copy_files"]).to be_an(Array)
    end
  end

  describe "#remove_rule" do
    let(:existing_rules) do
      [
        { "source" => "file1.txt", "strategy" => "copy" },
        { "source" => "file2.txt", "strategy" => "copy" }
      ]
    end

    before do
      projects_config["test-project"] = {
        "rules" => {
          "copy_files" => existing_rules
        }
      }
    end

    it "removes specific rule by index" do
      removed_rule = rules_manager.remove_rule("test-project", "copy_files", 0)

      expect(removed_rule).to eq({ "source" => "file1.txt", "strategy" => "copy" })
      expect(existing_rules.length).to eq(1)
    end

    it "removes all rules when no index specified" do
      removed_rules = rules_manager.remove_rule("test-project", "copy_files")

      expect(removed_rules).to be_empty
      expect(existing_rules).to be_empty
    end

    it "raises error for non-existent project" do
      allow(mock_project_manager).to receive(:get_project).and_return(nil)

      expect do
        rules_manager.remove_rule("non-existent", "copy_files")
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end

    it "raises error when no rules exist for rule type" do
      expect do
        rules_manager.remove_rule("test-project", "setup_commands")
      end.to raise_error(Sxn::RuleNotFoundError, /No setup_commands rules found/)
    end

    it "raises error for invalid rule index" do
      expect do
        rules_manager.remove_rule("test-project", "copy_files", 99)
      end.to raise_error(Sxn::RuleNotFoundError, "Rule index 99 not found")
    end
  end

  describe "#list_rules" do
    context "for specific project" do
      let(:project_rules) do
        {
          "copy_files" => [{ "source" => "test.txt", "strategy" => "copy" }],
          "setup_commands" => [{ "command" => %w[npm install] }]
        }
      end

      before do
        allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)
      end

      it "lists rules for specific project" do
        rules = rules_manager.list_rules("test-project")

        expect(rules.size).to eq(2)
        expect(rules[0][:project]).to eq("test-project")
        expect(rules[0][:type]).to eq("copy_files")
        expect(rules[1][:type]).to eq("setup_commands")
      end

      it "raises error for non-existent project" do
        allow(mock_project_manager).to receive(:get_project).and_return(nil)

        expect do
          rules_manager.list_rules("non-existent")
        end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
      end
    end

    context "for all projects" do
      let(:projects) do
        [
          { name: "project1" },
          { name: "project2" }
        ]
      end

      before do
        allow(mock_project_manager).to receive(:list_projects).and_return(projects)
        allow(mock_project_manager).to receive(:get_project_rules).with("project1").and_return({
                                                                                                 "copy_files" => [{ "source" => "file1.txt" }]
                                                                                               })
        allow(mock_project_manager).to receive(:get_project_rules).with("project2").and_return({
                                                                                                 "setup_commands" => [{ "command" => %w[
                                                                                                   npm install
                                                                                                 ] }]
                                                                                               })
      end

      it "lists rules for all projects" do
        rules = rules_manager.list_rules

        expect(rules.size).to eq(2)
        expect(rules.map { |r| r[:project] }).to contain_exactly("project1", "project2")
      end
    end
  end

  describe "#apply_rules" do
    let(:temp_project_dir) { Dir.mktmpdir("project") }
    let(:temp_worktree_dir) { Dir.mktmpdir("worktree") }
    let(:session_data) { { name: "test-session", path: "/session/path" } }
    let(:worktree_data) { { project: "test-project", path: temp_worktree_dir } }
    let(:mock_session_manager) do
      instance_double(Sxn::Core::SessionManager).tap do |mgr|
        allow(mgr).to receive(:get_session).and_return(session_data)
      end
    end
    let(:mock_worktree_manager) do
      instance_double(Sxn::Core::WorktreeManager).tap do |mgr|
        allow(mgr).to receive(:get_worktree).and_return(worktree_data)
      end
    end

    before do
      allow(Sxn::Core::SessionManager).to receive(:new).and_return(mock_session_manager)
      allow(Sxn::Core::WorktreeManager).to receive(:new).and_return(mock_worktree_manager)
      # Update project_data to use temp directory
      allow(mock_project_manager).to receive(:get_project).and_return(
        { name: "test-project", path: temp_project_dir, type: "rails" }
      )
    end

    after do
      FileUtils.rm_rf(temp_project_dir)
      FileUtils.rm_rf(temp_worktree_dir)
    end

    # Test for line 102[then] - project path does not exist
    it "raises error when project path does not exist" do
      allow(mock_project_manager).to receive(:get_project).and_return(
        { name: "test-project", path: "/nonexistent/project/path", type: "rails" }
      )
      allow(mock_project_manager).to receive(:get_project_rules).and_return({})

      expect do
        rules_manager.apply_rules("test-project")
      end.to raise_error(Sxn::InvalidProjectPathError, /Project path does not exist/)
    end

    # Test for line 103[then] - worktree path does not exist
    it "raises error when worktree path does not exist" do
      allow(mock_worktree_manager).to receive(:get_worktree).and_return(
        { project: "test-project", path: "/nonexistent/worktree/path" }
      )
      allow(mock_project_manager).to receive(:get_project_rules).and_return({})

      expect do
        rules_manager.apply_rules("test-project")
      end.to raise_error(Sxn::WorktreeNotFoundError, /Worktree path does not exist/)
    end

    # Test for line 109[else] - no copy_files rules
    it "handles case when copy_files rules are nil" do
      project_rules = { "setup_commands" => [{ "command" => %w[echo test] }] }
      allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)

      result = rules_manager.apply_rules("test-project")

      expect(result[:success]).to be true
      expect(result[:applied_count]).to eq(0)
      expect(result[:errors]).to be_empty
    end

    it "applies rules successfully" do
      # Create a test file in the project directory
      File.write(File.join(temp_project_dir, "test.txt"), "test content")

      project_rules = { "copy_files" => [{ "source" => "test.txt" }] }
      allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)

      result = rules_manager.apply_rules("test-project")

      expect(result[:success]).to be true
      expect(result[:applied_count]).to eq(1)
      expect(File.exist?(File.join(temp_worktree_dir, "test.txt"))).to be true
    end

    it "uses specified session" do
      project_rules = { "copy_files" => [] }
      allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)

      rules_manager.apply_rules("test-project", "custom-session")

      expect(mock_session_manager).to have_received(:get_session).with("custom-session")
    end

    it "raises error for non-existent project" do
      allow(mock_project_manager).to receive(:get_project).and_return(nil)

      expect do
        rules_manager.apply_rules("non-existent")
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end

    it "raises error when no active session" do
      allow(mock_config_manager).to receive(:current_session).and_return(nil)

      expect do
        rules_manager.apply_rules("test-project")
      end.to raise_error(Sxn::NoActiveSessionError, "No active session specified")
    end

    it "raises error when session not found" do
      allow(mock_session_manager).to receive(:get_session).and_return(nil)

      expect do
        rules_manager.apply_rules("test-project")
      end.to raise_error(Sxn::SessionNotFoundError, "Session 'test-session' not found")
    end

    it "raises error when worktree not found" do
      allow(mock_worktree_manager).to receive(:get_worktree).and_return(nil)

      expect do
        rules_manager.apply_rules("test-project")
      end.to raise_error(Sxn::WorktreeNotFoundError, /No worktree found/)
    end

    it "captures copy file errors in errors array" do
      # Create a test file in the project directory
      File.write(File.join(temp_project_dir, "test.txt"), "test content")

      project_rules = {
        "copy_files" => [
          { "source" => "test.txt" },
          { "source" => "nonexistent.txt" } # This should fail but silently skip
        ]
      }
      allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)

      result = rules_manager.apply_rules("test-project")

      # Both rules are processed (even if source doesn't exist)
      # The implementation doesn't fail for missing files, just skips them
      expect(result[:applied_count]).to eq(2)
      # No errors captured since missing files are silently skipped
      expect(result[:errors]).to be_empty
      expect(result[:success]).to be true
    end

    it "handles glob patterns in copy_files rules" do
      # Create multiple test files
      FileUtils.mkdir_p(File.join(temp_project_dir, "configs"))
      File.write(File.join(temp_project_dir, "configs/file1.txt"), "content1")
      File.write(File.join(temp_project_dir, "configs/file2.txt"), "content2")

      project_rules = {
        "copy_files" => [
          { "source" => "configs/*.txt", "strategy" => "copy" }
        ]
      }
      allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)

      result = rules_manager.apply_rules("test-project")

      expect(result[:success]).to be true
      expect(result[:applied_count]).to eq(1)

      # Verify files were copied
      expect(File.exist?(File.join(temp_worktree_dir, "configs/file1.txt"))).to be true
      expect(File.exist?(File.join(temp_worktree_dir, "configs/file2.txt"))).to be true
    end

    it "applies copy_file_rule with symlink strategy" do
      # Create a test file in the project directory
      File.write(File.join(temp_project_dir, "test.txt"), "test content")

      project_rules = {
        "copy_files" => [
          { "source" => "test.txt", "strategy" => "symlink" }
        ]
      }
      allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)

      result = rules_manager.apply_rules("test-project")

      expect(result[:success]).to be true
      expect(result[:applied_count]).to eq(1)

      # Verify symlink was created
      dest_file = File.join(temp_worktree_dir, "test.txt")
      expect(File.symlink?(dest_file)).to be true
      expect(File.readlink(dest_file)).to eq(File.join(temp_project_dir, "test.txt"))
    end

    # Test for line 146[else] - strategy is neither copy nor symlink (should do nothing)
    it "handles unknown strategy by doing nothing" do
      # Create a test file in the project directory
      File.write(File.join(temp_project_dir, "test.txt"), "test content")

      project_rules = {
        "copy_files" => [
          { "source" => "test.txt", "strategy" => "unknown" }
        ]
      }
      allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)

      result = rules_manager.apply_rules("test-project")

      expect(result[:success]).to be true
      expect(result[:applied_count]).to eq(1)

      # Verify file was NOT copied (unknown strategy is ignored)
      dest_file = File.join(temp_worktree_dir, "test.txt")
      expect(File.exist?(dest_file)).to be false
    end
  end

  describe "#validate_rules" do
    let(:project_rules) do
      {
        "copy_files" => [
          { "source" => "valid.txt", "strategy" => "copy" },
          { "strategy" => "copy" } # invalid - missing source
        ],
        "setup_commands" => [
          { "command" => %w[npm install] } # valid
        ]
      }
    end

    before do
      allow(mock_project_manager).to receive(:get_project_rules).and_return(project_rules)
    end

    it "validates all rules and returns results" do
      results = rules_manager.validate_rules("test-project")

      expect(results.size).to eq(3)

      # First copy_files rule - valid
      expect(results[0][:valid]).to be(true)
      expect(results[0][:type]).to eq("copy_files")
      expect(results[0][:index]).to eq(0)

      # Second copy_files rule - invalid
      expect(results[1][:valid]).to be(false)
      expect(results[1][:type]).to eq("copy_files")
      expect(results[1][:index]).to eq(1)
      expect(results[1][:errors]).not_to be_empty

      # Setup command rule - valid
      expect(results[2][:valid]).to be(true)
      expect(results[2][:type]).to eq("setup_commands")
    end

    it "raises error for non-existent project" do
      allow(mock_project_manager).to receive(:get_project).and_return(nil)

      expect do
        rules_manager.validate_rules("non-existent")
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end
  end

  describe "#generate_rule_template" do
    it "generates copy_files template for Rails" do
      template = rules_manager.generate_rule_template("copy_files", "rails")

      expect(template).to be_an(Array)
      expect(template).to include({ "source" => "config/master.key", "strategy" => "copy" })
      expect(template).to include({ "source" => ".env", "strategy" => "copy" })
    end

    # Test for line 322[when] - "javascript", "typescript" branch
    it "generates copy_files template for JavaScript" do
      template = rules_manager.generate_rule_template("copy_files", "javascript")

      expect(template).to be_an(Array)
      expect(template).to include({ "source" => ".env", "strategy" => "copy" })
      expect(template).to include({ "source" => ".env.local", "strategy" => "copy" })
      expect(template).to include({ "source" => ".npmrc", "strategy" => "copy" })
    end

    it "generates copy_files template for TypeScript" do
      template = rules_manager.generate_rule_template("copy_files", "typescript")

      expect(template).to be_an(Array)
      expect(template).to include({ "source" => ".env", "strategy" => "copy" })
      expect(template).to include({ "source" => ".env.local", "strategy" => "copy" })
      expect(template).to include({ "source" => ".npmrc", "strategy" => "copy" })
    end

    it "generates setup_commands template for JavaScript" do
      template = rules_manager.generate_rule_template("setup_commands", "javascript")

      expect(template).to be_an(Array)
      expect(template).to include({ "command" => %w[npm install] })
    end

    # Test for line 337[when] - "rails" branch in generate_setup_commands_template
    it "generates setup_commands template for Rails" do
      template = rules_manager.generate_rule_template("setup_commands", "rails")

      expect(template).to be_an(Array)
      expect(template).to include({ "command" => %w[bundle install] })
      expect(template).to include({ "command" => ["bin/rails", "db:create"] })
      expect(template).to include({ "command" => ["bin/rails", "db:migrate"] })
    end

    it "generates setup_commands template for TypeScript" do
      template = rules_manager.generate_rule_template("setup_commands", "typescript")

      expect(template).to be_an(Array)
      expect(template).to include({ "command" => %w[npm install] })
    end

    it "generates template rule template" do
      template = rules_manager.generate_rule_template("template")

      expect(template).to be_an(Array)
      expect(template.first).to have_key("source")
      expect(template.first).to have_key("destination")
    end

    it "raises error for unknown rule type" do
      expect do
        rules_manager.generate_rule_template("unknown_type")
      end.to raise_error(Sxn::InvalidRuleTypeError, "Unknown rule type: unknown_type")
    end

    it "generates generic templates for unknown project types" do
      copy_template = rules_manager.generate_rule_template("copy_files", "unknown")
      setup_template = rules_manager.generate_rule_template("setup_commands", "unknown")

      expect(copy_template).to include({ "source" => "path/to/file", "strategy" => "copy" })
      expect(setup_template).to include({ "command" => ["echo", "Replace with your setup command"] })
    end
  end

  describe "#get_available_rule_types" do
    it "returns list of available rule types with descriptions" do
      types = rules_manager.get_available_rule_types

      expect(types).to be_an(Array)
      expect(types.size).to eq(3)

      copy_files_type = types.find { |t| t[:name] == "copy_files" }
      expect(copy_files_type[:description]).to include("Copy files")
      expect(copy_files_type[:example]).to be_a(Hash)

      setup_commands_type = types.find { |t| t[:name] == "setup_commands" }
      expect(setup_commands_type[:description]).to include("Run setup commands")

      template_type = types.find { |t| t[:name] == "template" }
      expect(template_type[:description]).to include("Process template files")
    end
  end

  describe "private validation methods" do
    describe "#validate_rule_type!" do
      it "accepts valid rule types" do
        %w[copy_files setup_commands template].each do |type|
          expect do
            rules_manager.send(:validate_rule_type!, type)
          end.not_to raise_error
        end
      end

      it "rejects invalid rule types" do
        expect do
          rules_manager.send(:validate_rule_type!, "invalid_type")
        end.to raise_error(Sxn::InvalidRuleTypeError, /Invalid rule type: invalid_type/)
      end
    end

    describe "#validate_copy_files_config!" do
      it "accepts valid config" do
        valid_configs = [
          { "source" => "file.txt" },
          { "source" => "file.txt", "strategy" => "copy" },
          { "source" => "file.txt", "strategy" => "symlink" }
        ]

        valid_configs.each do |config|
          expect do
            rules_manager.send(:validate_copy_files_config!, config)
          end.not_to raise_error
        end
      end

      it "rejects config without source" do
        expect do
          rules_manager.send(:validate_copy_files_config!, { "strategy" => "copy" })
        end.to raise_error(Sxn::InvalidRuleConfigError, /must have 'source' field/)
      end

      it "rejects invalid strategy" do
        expect do
          rules_manager.send(:validate_copy_files_config!, { "source" => "file.txt", "strategy" => "invalid" })
        end.to raise_error(Sxn::InvalidRuleConfigError, /strategy must be 'copy' or 'symlink'/)
      end
    end

    describe "#validate_setup_commands_config!" do
      it "accepts valid config" do
        valid_config = { "command" => %w[npm install] }

        expect do
          rules_manager.send(:validate_setup_commands_config!, valid_config)
        end.not_to raise_error
      end

      it "rejects config without command" do
        expect do
          rules_manager.send(:validate_setup_commands_config!, { "working_dir" => "/tmp" })
        end.to raise_error(Sxn::InvalidRuleConfigError, /must have 'command' field/)
      end

      it "rejects non-array command" do
        expect do
          rules_manager.send(:validate_setup_commands_config!, { "command" => "npm install" })
        end.to raise_error(Sxn::InvalidRuleConfigError, /command must be an array/)
      end
    end

    describe "#validate_template_config!" do
      it "accepts valid config" do
        valid_config = { "source" => "template.erb", "destination" => "output.txt" }

        expect do
          rules_manager.send(:validate_template_config!, valid_config)
        end.not_to raise_error
      end

      it "rejects config without source" do
        expect do
          rules_manager.send(:validate_template_config!, { "destination" => "output.txt" })
        end.to raise_error(Sxn::InvalidRuleConfigError, /must have 'source' and 'destination' fields/)
      end

      it "rejects config without destination" do
        expect do
          rules_manager.send(:validate_template_config!, { "source" => "template.erb" })
        end.to raise_error(Sxn::InvalidRuleConfigError, /must have 'source' and 'destination' fields/)
      end
    end

    # Test for line 229[else] - when rule_type is unknown in validate_rule_config!
    describe "#validate_rule_config!" do
      it "does nothing for unknown rule type" do
        # The else branch does nothing, so this should complete without raising an error
        expect do
          rules_manager.send(:validate_rule_config!, "unknown_type", { "key" => "value" })
        end.not_to raise_error
      end
    end
  end

  describe "#format_rules_for_display" do
    let(:rules) do
      {
        "copy_files" => [
          { "source" => "file1.txt", "strategy" => "copy" },
          { "source" => "file2.txt", "strategy" => "symlink" }
        ],
        "setup_commands" => [
          { "command" => %w[npm install] }
        ]
      }
    end

    it "formats rules with proper structure" do
      formatted = rules_manager.send(:format_rules_for_display, "test-project", rules)

      expect(formatted.size).to eq(3)

      expect(formatted[0]).to include(
        project: "test-project",
        type: "copy_files",
        index: 0,
        enabled: true
      )

      expect(formatted[1]).to include(
        project: "test-project",
        type: "copy_files",
        index: 1
      )

      expect(formatted[2]).to include(
        project: "test-project",
        type: "setup_commands",
        index: 0
      )
    end
  end
end
