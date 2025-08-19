# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Sxn::Rules do
  let(:temp_dir) { Dir.mktmpdir("sxn_rules_test") }
  let(:project_path) { File.join(temp_dir, "project") }
  let(:session_path) { File.join(temp_dir, "session") }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(session_path)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "module structure" do
    it "is defined as a module" do
      expect(Sxn::Rules).to be_a(Module)
    end

    it "is nested within Sxn module" do
      expect(Sxn::Rules.name).to eq("Sxn::Rules")
    end
  end

  describe "required dependencies" do
    it "loads all rule classes" do
      expect(defined?(Sxn::Rules::BaseRule)).to eq("constant")
      expect(defined?(Sxn::Rules::CopyFilesRule)).to eq("constant")
      expect(defined?(Sxn::Rules::SetupCommandsRule)).to eq("constant")
      expect(defined?(Sxn::Rules::TemplateRule)).to eq("constant")
      expect(defined?(Sxn::Rules::RulesEngine)).to eq("constant")
      expect(defined?(Sxn::Rules::ProjectDetector)).to eq("constant")
    end

    it "loads rule errors" do
      expect(defined?(Sxn::RuleError)).to eq("constant")
      expect(defined?(Sxn::RuleValidationError)).to eq("constant")
      expect(defined?(Sxn::RuleExecutionError)).to eq("constant")
    end
  end

  describe ".available_types" do
    it "returns array of available rule types" do
      types = Sxn::Rules.available_types
      expect(types).to be_an(Array)
      expect(types).to include("copy_files", "setup_commands", "template")
    end

    it "returns rule types from RulesEngine" do
      expected_types = Sxn::Rules::RulesEngine::RULE_TYPES.keys
      expect(Sxn::Rules.available_types).to eq(expected_types)
    end
  end

  describe ".create_rule" do
    let(:rule_config) { { "files" => [{ "source" => "test.txt" }] } }

    it "creates a rule instance for valid type" do
      rule = Sxn::Rules.create_rule("test_rule", "copy_files", rule_config, project_path, session_path)

      expect(rule).to be_a(Sxn::Rules::BaseRule)
      expect(rule).to be_a(Sxn::Rules::CopyFilesRule)
    end

    it "raises error for invalid rule type" do
      expect do
        Sxn::Rules.create_rule("test_rule", "invalid_type", {}, project_path, session_path)
      end.to raise_error(ArgumentError, /Invalid rule type: invalid_type/)
    end

    it "passes dependencies to rule constructor" do
      dependencies = %w[dependency1 dependency2]
      rule = Sxn::Rules.create_rule("test_rule", "copy_files", rule_config, project_path, session_path,
                                    dependencies: dependencies)

      expect(rule.dependencies).to eq(dependencies)
    end

    it "creates setup_commands rule" do
      command_config = { "commands" => [{ "command" => %w[echo test] }] }
      rule = Sxn::Rules.create_rule("test_command", "setup_commands", command_config, project_path, session_path)

      expect(rule).to be_a(Sxn::Rules::SetupCommandsRule)
    end

    it "creates template rule" do
      template_config = { "templates" => [{ "source" => "template.liquid", "destination" => "output.txt" }] }
      rule = Sxn::Rules.create_rule("test_template", "template", template_config, project_path, session_path)

      expect(rule).to be_a(Sxn::Rules::TemplateRule)
    end
  end

  describe ".validate_configuration" do
    let(:test_file) { File.join(project_path, "test.txt") }
    let(:valid_config) do
      {
        "rule1" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "test.txt" }] }
        }
      }
    end

    before do
      File.write(test_file, "test content")
    end

    it "returns true for valid configuration" do
      expect(Sxn::Rules.validate_configuration(valid_config, project_path, session_path)).to be true
    end

    it "raises error for invalid configuration" do
      invalid_config = {
        "rule1" => {
          "type" => "invalid_type",
          "config" => {}
        }
      }

      expect do
        Sxn::Rules.validate_configuration(invalid_config, project_path, session_path)
      end.to raise_error(Sxn::Rules::ValidationError)
    end

    it "validates using RulesEngine" do
      engine_double = instance_double(Sxn::Rules::RulesEngine)
      allow(Sxn::Rules::RulesEngine).to receive(:new).with(project_path, session_path).and_return(engine_double)
      expect(engine_double).to receive(:validate_rules_config).with(valid_config)

      Sxn::Rules.validate_configuration(valid_config, project_path, session_path)
    end
  end

  describe ".rule_type_info" do
    let(:rule_info) { Sxn::Rules.rule_type_info }

    it "returns hash with rule type information" do
      expect(rule_info).to be_a(Hash)
      expect(rule_info.keys).to include("copy_files", "setup_commands", "template")
    end

    describe "copy_files rule info" do
      let(:copy_files_info) { rule_info["copy_files"] }

      it "has description and config schema" do
        expect(copy_files_info).to have_key(:description)
        expect(copy_files_info).to have_key(:config_schema)
        expect(copy_files_info[:description]).to include("copy or symlink files")
      end

      it "defines files configuration" do
        files_config = copy_files_info[:config_schema]["files"]
        expect(files_config[:type]).to eq("array")
        expect(files_config[:required]).to be true
        expect(files_config[:items]).to include("source", "destination", "strategy")
      end

      it "defines source as required" do
        source_config = copy_files_info[:config_schema]["files"][:items]["source"]
        expect(source_config[:required]).to be true
        expect(source_config[:type]).to eq("string")
      end

      it "defines strategy with enum values" do
        strategy_config = copy_files_info[:config_schema]["files"][:items]["strategy"]
        expect(strategy_config[:enum]).to eq(%w[copy symlink])
        expect(strategy_config[:default]).to eq("copy")
      end
    end

    describe "setup_commands rule info" do
      let(:commands_info) { rule_info["setup_commands"] }

      it "has description and config schema" do
        expect(commands_info).to have_key(:description)
        expect(commands_info).to have_key(:config_schema)
        expect(commands_info[:description]).to include("Execute project setup commands")
      end

      it "defines commands configuration" do
        commands_config = commands_info[:config_schema]["commands"]
        expect(commands_config[:type]).to eq("array")
        expect(commands_config[:required]).to be true
      end

      it "defines command structure" do
        command_items = commands_info[:config_schema]["commands"][:items]
        expect(command_items["command"][:required]).to be true
        expect(command_items["command"][:type]).to eq("array")
        expect(command_items["timeout"][:maximum]).to eq(1800)
      end

      it "includes continue_on_failure option" do
        continue_option = commands_info[:config_schema]["continue_on_failure"]
        expect(continue_option[:type]).to eq("boolean")
        expect(continue_option[:default]).to be false
      end
    end

    describe "template rule info" do
      let(:template_info) { rule_info["template"] }

      it "has description and config schema" do
        expect(template_info).to have_key(:description)
        expect(template_info).to have_key(:config_schema)
        expect(template_info[:description]).to include("template files")
      end

      it "defines templates configuration" do
        templates_config = template_info[:config_schema]["templates"]
        expect(templates_config[:type]).to eq("array")
        expect(templates_config[:required]).to be true
      end

      it "defines template structure" do
        template_items = template_info[:config_schema]["templates"][:items]
        expect(template_items["source"][:required]).to be true
        expect(template_items["destination"][:required]).to be true
        expect(template_items["engine"][:enum]).to eq(["liquid"])
        expect(template_items["engine"][:default]).to eq("liquid")
      end
    end
  end

  describe "module integration" do
    it "provides comprehensive rule system documentation" do
      # Test that the module documentation is reflected in functionality
      expect(Sxn::Rules).to respond_to(:available_types)
      expect(Sxn::Rules).to respond_to(:create_rule)
      expect(Sxn::Rules).to respond_to(:validate_configuration)
      expect(Sxn::Rules).to respond_to(:rule_type_info)
    end

    it "integrates with all rule classes" do
      rule_classes = [
        Sxn::Rules::BaseRule,
        Sxn::Rules::CopyFilesRule,
        Sxn::Rules::SetupCommandsRule,
        Sxn::Rules::TemplateRule
      ]

      rule_classes.each do |rule_class|
        expect(rule_class).to be_a(Class)
        expect(rule_class.name).to start_with("Sxn::Rules::")
      end
    end

    it "provides engine and detector classes" do
      expect(Sxn::Rules::RulesEngine).to be_a(Class)
      expect(Sxn::Rules::ProjectDetector).to be_a(Class)
    end
  end

  describe "error handling" do
    it "handles rule creation errors gracefully" do
      expect do
        Sxn::Rules.create_rule("test", "nonexistent", {}, project_path, session_path)
      end.to raise_error(ArgumentError)
    end

    it "provides meaningful error messages" do
      Sxn::Rules.create_rule("test", "invalid", {}, project_path, session_path)
    rescue ArgumentError => e
      expect(e.message).to include("Invalid rule type: invalid")
    end
  end
end
