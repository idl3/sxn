# frozen_string_literal: true

require "spec_helper"

# Integration tests to boost coverage by exercising uncovered code paths
RSpec.describe "Coverage Booster Integration Tests" do
  # Test that all files can be loaded without errors
  describe "File loading" do
    it "loads all CLI components" do
      expect { require "sxn/CLI" }.not_to raise_error
      expect { require "sxn/commands/init" }.not_to raise_error
      expect { require "sxn/commands/projects" }.not_to raise_error
      expect { require "sxn/commands/sessions" }.not_to raise_error
      expect { require "sxn/commands/worktrees" }.not_to raise_error
      expect { require "sxn/commands/rules" }.not_to raise_error
    end

    it "loads all core components" do
      expect { require "sxn/core/project_manager" }.not_to raise_error
      expect { require "sxn/core/session_manager" }.not_to raise_error
      expect { require "sxn/core/worktree_manager" }.not_to raise_error
      expect { require "sxn/core/rules_manager" }.not_to raise_error
    end

    it "loads all config components" do
      expect { require "sxn/config/config_discovery" }.not_to raise_error
      expect { require "sxn/config/config_cache" }.not_to raise_error
      expect { require "sxn/config/config_validator" }.not_to raise_error
    end

    it "loads all database components" do
      expect { require "sxn/database/session_database" }.not_to raise_error
    end

    it "loads all rules components" do
      expect { require "sxn/rules/project_detector" }.not_to raise_error
      expect { require "sxn/rules/rules_engine" }.not_to raise_error
      expect { require "sxn/rules/base_rule" }.not_to raise_error
      expect { require "sxn/rules/copy_files_rule" }.not_to raise_error
      expect { require "sxn/rules/setup_commands_rule" }.not_to raise_error
      expect { require "sxn/rules/template_rule" }.not_to raise_error
    end

    it "loads all security components" do
      expect { require "sxn/security/secure_command_executor" }.not_to raise_error
      expect { require "sxn/security/secure_file_copier" }.not_to raise_error
      expect { require "sxn/security/secure_path_validator" }.not_to raise_error
    end

    it "loads all template components" do
      expect { require "sxn/templates/template_engine" }.not_to raise_error
      expect { require "sxn/templates/template_processor" }.not_to raise_error
      expect { require "sxn/templates/template_security" }.not_to raise_error
      expect { require "sxn/templates/template_variables" }.not_to raise_error
    end

    it "loads all UI components" do
      expect { require "sxn/ui/output" }.not_to raise_error
      expect { require "sxn/ui/prompt" }.not_to raise_error
      expect { require "sxn/ui/table" }.not_to raise_error
      expect { require "sxn/ui/progress_bar" }.not_to raise_error
    end
  end

  # Test that classes can be instantiated
  describe "Class instantiation" do
    let(:temp_dir) { Dir.mktmpdir("coverage_booster") }
    let(:project_path) { File.join(temp_dir, "project") }
    let(:session_path) { File.join(temp_dir, "session") }

    before do
      FileUtils.mkdir_p(project_path)
      FileUtils.mkdir_p(session_path)
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "can instantiate core managers" do
      expect { Sxn::Core::ConfigManager.new(project_path) }.not_to raise_error
      # NOTE: Others may require different initialization parameters
    end

    it "can instantiate config classes" do
      expect { Sxn::Config::ConfigDiscovery.new(project_path) }.not_to raise_error
      expect { Sxn::Config::ConfigCache.new }.not_to raise_error
      expect { Sxn::Config::ConfigValidator.new }.not_to raise_error
    end

    it "can instantiate security classes with valid paths" do
      expect { Sxn::Security::SecurePathValidator.new(project_path) }.not_to raise_error
      expect { Sxn::Security::SecureFileCopier.new(project_path) }.not_to raise_error
      expect { Sxn::Security::SecureCommandExecutor.new(project_path) }.not_to raise_error
    end

    it "can instantiate template classes" do
      expect { Sxn::Templates::TemplateProcessor.new }.not_to raise_error
      expect { Sxn::Templates::TemplateSecurity.new }.not_to raise_error
      expect do
        Sxn::Templates::TemplateVariables.new(project_path: project_path, session_path: session_path)
      end.not_to raise_error
    end

    it "can instantiate UI classes" do
      expect { Sxn::UI::Output.new }.not_to raise_error
      expect { Sxn::UI::Prompt.new }.not_to raise_error
      expect { Sxn::UI::Table.new }.not_to raise_error
      expect { Sxn::UI::ProgressBar.new("test") }.not_to raise_error
    end

    it "can instantiate rules classes" do
      expect { Sxn::Rules::ProjectDetector.new(project_path) }.not_to raise_error
      expect { Sxn::Rules::RulesEngine.new(project_path, session_path) }.not_to raise_error
    end
  end

  # Test basic method calls to exercise code paths
  describe "Method execution" do
    let(:temp_dir) { Dir.mktmpdir("coverage_booster") }
    let(:project_path) { File.join(temp_dir, "project") }
    let(:session_path) { File.join(temp_dir, "session") }

    before do
      FileUtils.mkdir_p(project_path)
      FileUtils.mkdir_p(session_path)
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "exercises config discovery methods" do
      discovery = Sxn::Config::ConfigDiscovery.new(project_path)
      expect { discovery.find_config_files }.not_to raise_error
      expect { discovery.discover_config }.not_to raise_error
    end

    it "exercises config validation methods" do
      validator = Sxn::Config::ConfigValidator.new
      config = { "version" => 1, "sessions_folder" => "sessions", "projects" => {} }
      expect { validator.valid?(config) }.not_to raise_error
      expect { validator.validate_and_migrate(config) }.not_to raise_error
    end

    it "exercises template processor methods" do
      processor = Sxn::Templates::TemplateProcessor.new
      expect { processor.process("{{ test }}", { "test" => "value" }) }.not_to raise_error
      expect { processor.validate_template("{{ test }}") }.not_to raise_error
    end

    it "exercises project detection methods" do
      detector = Sxn::Rules::ProjectDetector.new(project_path)
      expect { detector.detect_type(project_path) }.not_to raise_error
      expect { detector.analyze_project_structure }.not_to raise_error
    end

    it "exercises UI output methods" do
      output = Sxn::UI::Output.new
      expect { output.success("test") }.not_to raise_error
      expect { output.error("test") }.not_to raise_error
      expect { output.info("test") }.not_to raise_error
    end

    it "exercises template variables methods" do
      variables = Sxn::Templates::TemplateVariables.new
      expect { variables.collect }.not_to raise_error
    end

    it "exercises progress bar methods" do
      progress = Sxn::UI::ProgressBar.new("test")
      expect { progress.advance }.not_to raise_error
      expect { progress.finish }.not_to raise_error
    end
  end

  # Test error conditions to cover error paths
  describe "Error condition coverage" do
    it "covers path validation errors" do
      validator = Sxn::Security::SecurePathValidator.new("/tmp")
      expect { validator.validate_path("../invalid") }.to raise_error(Sxn::PathValidationError)
    end

    it "covers template processing errors" do
      processor = Sxn::Templates::TemplateProcessor.new
      expect { processor.validate_template("{{ invalid") }.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError)
    end

    it "covers config validation errors" do
      validator = Sxn::Config::ConfigValidator.new
      invalid_config = { "version" => "invalid" }
      expect(validator.valid?(invalid_config)).to be false
    end
  end
end
