# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Templates do
  describe "module structure" do
    it "is defined as a module" do
      expect(Sxn::Templates).to be_a(Module)
    end

    it "is nested within Sxn module" do
      expect(Sxn::Templates.name).to eq("Sxn::Templates")
    end
  end

  describe "autoloaded constants" do
    it "defines all expected template autoloads" do
      expected_constants = [:TemplateEngine, :TemplateProcessor, :TemplateVariables, :TemplateSecurity, :Errors]
      
      expected_constants.each do |const|
        expect(Sxn::Templates.const_defined?(const)).to be true
      end
    end
  end

  describe "autoload functionality" do
    it "can load TemplateEngine class" do
      expect { Sxn::Templates::TemplateEngine }.not_to raise_error
      expect(Sxn::Templates::TemplateEngine).to be_a(Class)
    end

    it "can load TemplateProcessor class" do
      expect { Sxn::Templates::TemplateProcessor }.not_to raise_error
      expect(Sxn::Templates::TemplateProcessor).to be_a(Class)
    end

    it "can load TemplateVariables class" do
      expect { Sxn::Templates::TemplateVariables }.not_to raise_error
      expect(Sxn::Templates::TemplateVariables).to be_a(Class)
    end

    it "can load TemplateSecurity class" do
      expect { Sxn::Templates::TemplateSecurity }.not_to raise_error
      expect(Sxn::Templates::TemplateSecurity).to be_a(Class)
    end

    it "can load Errors module" do
      expect { Sxn::Templates::Errors }.not_to raise_error
      expect(Sxn::Templates::Errors).to be_a(Module)
    end
  end

  describe "template class availability" do
    before do
      # Force autoload to trigger
      Sxn::Templates::TemplateEngine
      Sxn::Templates::TemplateProcessor
      Sxn::Templates::TemplateVariables
      Sxn::Templates::TemplateSecurity
      Sxn::Templates::Errors
    end

    it "provides access to all template classes" do
      template_classes = [
        Sxn::Templates::TemplateEngine,
        Sxn::Templates::TemplateProcessor,
        Sxn::Templates::TemplateVariables,
        Sxn::Templates::TemplateSecurity
      ]

      template_classes.each do |template_class|
        expect(template_class).to be_a(Class)
        expect(template_class.name).to start_with("Sxn::Templates::")
      end
    end

    it "Errors module is properly namespaced" do
      expect(Sxn::Templates::Errors).to be_a(Module)
      expect(Sxn::Templates::Errors.name).to eq("Sxn::Templates::Errors")
    end

    it "all template classes are properly namespaced" do
      constants = Sxn::Templates.constants
      expected_constants = [:TemplateEngine, :TemplateProcessor, :TemplateVariables, :TemplateSecurity, :Errors]
      
      expected_constants.each do |const|
        expect(constants).to include(const)
      end
    end
  end

  describe "module features documentation" do
    it "provides comprehensive template processing features" do
      # Test that the module documentation is reflected in available classes
      features = [
        "Liquid-based template processing",
        "Whitelisted variables and filters",
        "Built-in templates for Rails, JavaScript, and common projects",
        "Template security validation",
        "Variable collection from session, git, project, and environment",
        "Performance optimizations with caching"
      ]

      # While we can't test the features directly from the module,
      # we can verify the module provides the necessary components
      expect(Sxn::Templates::TemplateEngine).to be_a(Class)
      expect(Sxn::Templates::TemplateProcessor).to be_a(Class)
      expect(Sxn::Templates::TemplateVariables).to be_a(Class)
      expect(Sxn::Templates::TemplateSecurity).to be_a(Class)
    end
  end

  describe "error handling integration" do
    it "loads template errors" do
      # Check that template-specific errors are available through the errors module
      expect(defined?(Sxn::TemplateError)).to eq("constant")
      expect(defined?(Sxn::TemplateNotFoundError)).to eq("constant")
      expect(defined?(Sxn::TemplateProcessingError)).to eq("constant")
    end

    it "template errors inherit properly" do
      expect(Sxn::TemplateError).to be < Sxn::Error
      expect(Sxn::TemplateNotFoundError).to be < Sxn::TemplateError
      expect(Sxn::TemplateProcessingError).to be < Sxn::TemplateError
    end
  end

  describe "template engine integration" do
    it "can create template engine instances" do
      # Basic test that the template engine can be instantiated
      # without providing session/project details
      expect { Sxn::Templates::TemplateEngine.new }.not_to raise_error
    end

    it "template engine provides core functionality" do
      engine = Sxn::Templates::TemplateEngine.new
      
      # Check that the engine has the expected interface
      expect(engine).to respond_to(:process_template)
      expect(engine).to respond_to(:list_templates)
      expect(engine).to respond_to(:template_exists?)
    end
  end

  describe "security features" do
    it "provides template security validation" do
      security = Sxn::Templates::TemplateSecurity.new
      
      # Check that security validation methods are available
      expect(security).to respond_to(:validate_template_path)
      expect(security).to respond_to(:validate_template_content)
    end
  end

  describe "variable collection" do
    it "provides template variable collection" do
      variables = Sxn::Templates::TemplateVariables.new
      
      # Check that variable collection methods are available
      expect(variables).to respond_to(:collect_all_variables)
      expect(variables).to respond_to(:collect_session_variables)
      expect(variables).to respond_to(:collect_project_variables)
      expect(variables).to respond_to(:collect_git_variables)
      expect(variables).to respond_to(:collect_environment_variables)
    end
  end

  describe "template processing" do
    it "provides template processing functionality" do
      processor = Sxn::Templates::TemplateProcessor.new
      
      # Check that processing methods are available
      expect(processor).to respond_to(:process)
      expect(processor).to respond_to(:validate_template)
    end
  end
end