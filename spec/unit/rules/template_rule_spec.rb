# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Rules::TemplateRule do
  let(:project_path) { Dir.mktmpdir("project") }
  let(:session_path) { Dir.mktmpdir("session") }
  let(:rule_name) { "template_test" }
  
  let(:basic_config) do
    {
      "templates" => [
        {
          "source" => ".sxn/templates/session-info.md.liquid",
          "destination" => "README.md"
        }
      ]
    }
  end

  let(:rule) { described_class.new(rule_name, basic_config, project_path, session_path) }
  let(:mock_processor) { instance_double("Sxn::Templates::TemplateProcessor") }
  let(:mock_variables) { instance_double("Sxn::Templates::TemplateVariables") }

  before do
    # Create project template
    FileUtils.mkdir_p(File.join(project_path, ".sxn/templates"))
    template_content = <<~LIQUID
      # Session: {{session.name}}
      
      Created at: {{session.created_at}}
      Project: {{project.name}}
    LIQUID
    File.write(File.join(project_path, ".sxn/templates/session-info.md.liquid"), template_content)

    # Mock template processor and variables
    allow(Sxn::Templates::TemplateProcessor).to receive(:new).and_return(mock_processor)
    allow(Sxn::Templates::TemplateVariables).to receive(:new).and_return(mock_variables)
    
    # Mock successful processing
    allow(mock_processor).to receive(:validate_syntax).and_return(true)
    allow(mock_processor).to receive(:process).and_return("# Session: test-session\n\nCreated at: 2025-01-16T10:00:00Z\nProject: test-project")
    allow(mock_processor).to receive(:extract_variables).and_return(["session.name", "session.created_at", "project.name"])
    
    # Mock variables
    allow(mock_variables).to receive(:build_variables).and_return({
      session: { name: "test-session", created_at: "2025-01-16T10:00:00Z" },
      project: { name: "test-project" }
    })
  end

  after do
    FileUtils.rm_rf(project_path)
    FileUtils.rm_rf(session_path)
  end

  describe "#initialize" do
    it "initializes with template processor and variables" do
      expect(rule.instance_variable_get(:@template_processor)).to eq(mock_processor)
      expect(rule.instance_variable_get(:@template_variables)).to eq(mock_variables)
    end
  end

  describe "#validate" do
    context "with valid configuration" do
      it "validates successfully" do
        expect(rule.validate).to be true
        expect(rule.state).to eq(:validated)
      end
    end

    context "with missing templates configuration" do
      let(:invalid_config) { {} }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /requires 'templates' configuration/)
      end
    end

    context "with non-array templates configuration" do
      let(:invalid_config) { { "templates" => "not-an-array" } }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'templates' must be an array/)
      end
    end

    context "with empty templates array" do
      let(:invalid_config) { { "templates" => [] } }
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'templates' cannot be empty/)
      end
    end

    context "with invalid template configuration" do
      let(:invalid_config) do
        {
          "templates" => [
            { "destination" => "README.md" } # missing source
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /must have a 'source' string/)
      end
    end

    context "with missing destination" do
      let(:invalid_config) do
        {
          "templates" => [
            { "source" => ".sxn/templates/test.liquid" } # missing destination
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /must have a 'destination' string/)
      end
    end

    context "with unsupported engine" do
      let(:invalid_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/test.erb",
              "destination" => "README.md",
              "engine" => "erb"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /unsupported engine 'erb'/)
      end
    end

    context "with invalid variables type" do
      let(:invalid_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/test.liquid",
              "destination" => "README.md",
              "variables" => "not-a-hash"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /'variables' must be a hash/)
      end
    end

    context "with missing required template file" do
      let(:invalid_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/missing.liquid",
              "destination" => "README.md",
              "required" => true
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /Required template file does not exist/)
      end
    end

    context "with missing optional template file" do
      let(:valid_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/optional.liquid",
              "destination" => "README.md",
              "required" => false
            }
          ]
        }
      end
      let(:valid_rule) { described_class.new(rule_name, valid_config, project_path, session_path) }

      it "validates successfully" do
        expect(valid_rule.validate).to be true
      end
    end

    context "with unsafe destination path" do
      let(:invalid_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/session-info.md.liquid",
              "destination" => "../unsafe.md"
            }
          ]
        }
      end
      let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

      it "fails validation" do
        expect {
          invalid_rule.validate
        }.to raise_error(Sxn::Rules::ValidationError, /destination path is not safe/)
      end
    end
  end

  describe "#apply" do
    before { rule.validate }

    context "with successful template processing" do
      it "processes templates successfully" do
        expect(rule.apply).to be true
        expect(rule.state).to eq(:applied)
        
        output_file = File.join(session_path, "README.md")
        expect(File.exist?(output_file)).to be true
      end

      it "calls template processor with correct parameters" do
        template_content = File.read(File.join(project_path, ".sxn/templates/session-info.md.liquid"))
        expected_variables = hash_including(
          session: { name: "test-session", created_at: "2025-01-16T10:00:00Z" },
          project: { name: "test-project" }
        )
        
        expect(mock_processor).to receive(:validate_syntax).with(template_content)
        expect(mock_processor).to receive(:process).with(template_content, expected_variables)
        
        rule.apply
      end

      it "tracks template processing change" do
        rule.apply
        
        expect(rule.changes.size).to eq(1)
        change = rule.changes.first
        expect(change.type).to eq(:file_created)
        expect(change.target).to end_with("README.md")
        expect(change.metadata[:template]).to be true
      end

      it "sets appropriate file permissions" do
        rule.apply
        
        output_file = File.join(session_path, "README.md")
        stat = File.stat(output_file)
        expect(stat.mode & 0o777).to eq(0o644)
      end
    end

    context "with custom variables" do
      let(:custom_vars_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/session-info.md.liquid",
              "destination" => "README.md",
              "variables" => { "custom_var" => "custom_value" }
            }
          ]
        }
      end
      let(:custom_vars_rule) { described_class.new(rule_name, custom_vars_config, project_path, session_path) }

      before { custom_vars_rule.validate }

      it "merges custom variables with system variables" do
        expected_variables = hash_including(
          session: { name: "test-session", created_at: "2025-01-16T10:00:00Z" },
          project: { name: "test-project" },
          "custom_var" => "custom_value"
        )
        
        expect(mock_processor).to receive(:process).with(anything, expected_variables)
        custom_vars_rule.apply
      end
    end

    context "with multiple templates" do
      let(:multi_template_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/session-info.md.liquid",
              "destination" => "README.md"
            },
            {
              "source" => ".sxn/templates/session-info.md.liquid",
              "destination" => "docs/SESSION.md"
            }
          ]
        }
      end
      let(:multi_template_rule) { described_class.new(rule_name, multi_template_config, project_path, session_path) }

      before { multi_template_rule.validate }

      it "processes multiple templates" do
        expect(mock_processor).to receive(:validate_syntax).twice
        expect(mock_processor).to receive(:process).twice
        
        multi_template_rule.apply
        
        expect(multi_template_rule.changes.size).to eq(2)
        
        # Check both files were created
        expect(File.exist?(File.join(session_path, "README.md"))).to be true
        expect(File.exist?(File.join(session_path, "docs/SESSION.md"))).to be true
      end
    end

    context "with missing optional template" do
      let(:optional_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/optional.liquid",
              "destination" => "OPTIONAL.md",
              "required" => false
            }
          ]
        }
      end
      let(:optional_rule) { described_class.new(rule_name, optional_config, project_path, session_path) }

      before { optional_rule.validate }

      it "skips missing optional templates" do
        expect(mock_processor).not_to receive(:process)
        
        expect(optional_rule.apply).to be true
        expect(optional_rule.changes).to be_empty
      end
    end

    context "with existing destination file" do
      let(:existing_file) { File.join(session_path, "README.md") }

      before do
        File.write(existing_file, "existing content")
      end

      context "without overwrite" do
        it "skips existing files by default" do
          expect(mock_processor).not_to receive(:process)
          
          rule.apply
          expect(File.read(existing_file)).to eq("existing content")
        end
      end

      context "with overwrite enabled" do
        let(:overwrite_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/session-info.md.liquid",
                "destination" => "README.md",
                "overwrite" => true
              }
            ]
          }
        end
        let(:overwrite_rule) { described_class.new(rule_name, overwrite_config, project_path, session_path) }

        before { overwrite_rule.validate }

        it "overwrites existing files when enabled" do
          expect(mock_processor).to receive(:process)
          
          overwrite_rule.apply
          
          # Should have created backup
          change = overwrite_rule.changes.first
          expect(change.metadata).to have_key(:backup_path)
        end
      end
    end

    context "with nested destination directory" do
      let(:nested_config) do
        {
          "templates" => [
            {
              "source" => ".sxn/templates/session-info.md.liquid",
              "destination" => "docs/deep/nested/README.md"
            }
          ]
        }
      end
      let(:nested_rule) { described_class.new(rule_name, nested_config, project_path, session_path) }

      before { nested_rule.validate }

      it "creates nested directories" do
        nested_rule.apply
        
        nested_file = File.join(session_path, "docs/deep/nested/README.md")
        expect(File.exist?(nested_file)).to be true
        expect(File.directory?(File.dirname(nested_file))).to be true
      end
    end

    context "with template syntax error" do
      before do
        allow(mock_processor).to receive(:validate_syntax).and_raise(
          Sxn::Templates::Errors::TemplateSyntaxError, "Invalid syntax"
        )
      end

      it "fails with template syntax error" do
        expect {
          rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError, /Template syntax error/)
        
        expect(rule.state).to eq(:failed)
      end
    end

    context "with template processing error" do
      before do
        allow(mock_processor).to receive(:process).and_raise(
          Sxn::Templates::Errors::TemplateProcessingError, "Processing failed"
        )
      end

      it "fails with template processing error" do
        expect {
          rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError, /Template processing error/)
        
        expect(rule.state).to eq(:failed)
      end
    end

    context "with file system error" do
      before do
        # Make session path read-only to cause write failure
        File.chmod(0o444, session_path)
      end

      after do
        File.chmod(0o755, session_path)
      end

      it "handles file system errors gracefully" do
        expect {
          rule.apply
        }.to raise_error(Sxn::Rules::ApplicationError, /Failed to process template/)
      end
    end
  end

  describe "#rollback" do
    before do
      rule.validate
      rule.apply
    end

    it "removes created files" do
      output_file = File.join(session_path, "README.md")
      expect(File.exist?(output_file)).to be true
      
      rule.rollback
      expect(File.exist?(output_file)).to be false
    end
  end

  describe "variable building" do
    let(:rule_instance) { rule }

    before { rule.validate }

    it "builds template variables correctly" do
      template_config = {
        "source" => ".sxn/templates/test.liquid",
        "destination" => "test.md",
        "variables" => { "custom" => "value" }
      }
      
      variables = rule_instance.send(:build_template_variables, template_config)
      
      expect(variables).to include(
        session: { name: "test-session", created_at: "2025-01-16T10:00:00Z" },
        project: { name: "test-project" },
        "custom" => "value"
      )
      expect(variables[:template]).to include(
        source: ".sxn/templates/test.liquid",
        destination: "test.md"
      )
    end

    it "handles deep merging of variables" do
      base_hash = { session: { name: "base" }, other: "value" }
      override_hash = { session: { created_at: "2025-01-16" }, new: "added" }
      
      result = rule_instance.send(:deep_merge, base_hash, override_hash)
      
      expect(result).to eq({
        session: { name: "base", created_at: "2025-01-16" },
        other: "value",
        new: "added"
      })
    end
  end

  describe "variable extraction" do
    let(:rule_instance) { rule }

    before { rule.validate }

    it "extracts variables from templates" do
      allow(mock_processor).to receive(:extract_variables).and_return(["session.name", "project.type"])
      
      variables = rule_instance.send(:extract_used_variables, "template content")
      expect(variables).to eq(["session.name", "project.type"])
    end

    it "handles extraction errors gracefully" do
      allow(mock_processor).to receive(:extract_variables).and_raise(StandardError, "Extraction failed")
      
      variables = rule_instance.send(:extract_used_variables, "template content")
      expect(variables).to eq([])
    end
  end

  describe "real execution coverage" do
    let(:real_rule) { described_class.new(rule_name, basic_config, project_path, session_path) }

    before do
      # Don't mock for these tests - use real instances
      allow(Sxn::Templates::TemplateProcessor).to receive(:new).and_call_original
      allow(Sxn::Templates::TemplateVariables).to receive(:new).and_call_original
    end

    describe "initialization without mocking" do
      it "creates real template processor and variables instances" do
        expect(real_rule.instance_variable_get(:@template_processor)).to be_a(Sxn::Templates::TemplateProcessor)
        expect(real_rule.instance_variable_get(:@template_variables)).to be_a(Sxn::Templates::TemplateVariables)
      end
    end

    describe "validation without mocking" do
      it "validates basic configuration successfully" do
        expect(real_rule.validate).to be true
        expect(real_rule.state).to eq(:validated)
      end

      context "with non-hash template config" do
        let(:invalid_config) do
          {
            "templates" => [
              "not-a-hash"
            ]
          }
        end
        let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

        it "fails validation with specific error" do
          expect {
            invalid_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /Template config 0 must be a hash/)
        end
      end

      context "with absolute destination path" do
        let(:invalid_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/session-info.md.liquid",
                "destination" => "/absolute/path.md"
              }
            ]
          }
        end
        let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

        it "fails validation for absolute paths" do
          expect {
            invalid_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /destination path is not safe/)
        end
      end
    end

    describe "applying templates without extensive mocking" do
      context "with missing required template" do
        let(:missing_template_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/missing.liquid",
                "destination" => "output.md",
                "required" => true
              }
            ]
          }
        end
        let(:missing_rule) { described_class.new(rule_name, missing_template_config, project_path, session_path) }

        it "raises validation error for missing required template during validation" do
          expect {
            missing_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /Required template file does not exist/)
        end
      end

      context "with missing required template during apply" do
        let(:apply_missing_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/missing-during-apply.liquid",
                "destination" => "output.md",
                "required" => true
              }
            ]
          }
        end
        let(:apply_missing_rule) { described_class.new(rule_name, apply_missing_config, project_path, session_path) }

        before do
          # Create the template file for validation, then remove it before apply
          FileUtils.mkdir_p(File.join(project_path, ".sxn/templates"))
          File.write(File.join(project_path, ".sxn/templates/missing-during-apply.liquid"), "temp content")
          apply_missing_rule.validate
          File.delete(File.join(project_path, ".sxn/templates/missing-during-apply.liquid"))
        end

        it "raises application error for missing required template during apply" do
          expect {
            apply_missing_rule.apply
          }.to raise_error(Sxn::Rules::ApplicationError, /Required template file does not exist/)
          expect(apply_missing_rule.state).to eq(:failed)
        end
      end

      context "with missing optional template" do
        let(:optional_missing_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/optional-missing.liquid",
                "destination" => "output.md",
                "required" => false
              }
            ]
          }
        end
        let(:optional_rule) { described_class.new(rule_name, optional_missing_config, project_path, session_path) }

        before { optional_rule.validate }

        it "succeeds and skips missing optional templates" do
          expect(optional_rule.apply).to be true
          expect(optional_rule.state).to eq(:applied)
          expect(optional_rule.changes).to be_empty
        end
      end

      context "with engine specification" do
        let(:engine_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/session-info.md.liquid",
                "destination" => "README.md",
                "engine" => "liquid"
              }
            ]
          }
        end
        let(:engine_rule) { described_class.new(rule_name, engine_config, project_path, session_path) }

        before { engine_rule.validate }

        it "validates successfully with supported engine" do
          expect(engine_rule.validate).to be true
        end
      end
    end

    describe "template variable building edge cases" do
      before { real_rule.validate }

      it "handles template config without custom variables" do
        template_config = {
          "source" => ".sxn/templates/test.liquid",
          "destination" => "test.md"
        }
        
        variables = real_rule.send(:build_template_variables, template_config)
        
        expect(variables).to have_key(:template)
        expect(variables[:template][:source]).to eq(".sxn/templates/test.liquid")
        expect(variables[:template][:destination]).to eq("test.md")
        expect(variables[:template]).to have_key(:processed_at)
      end

      it "merges custom variables with system variables" do
        template_config = {
          "source" => ".sxn/templates/test.liquid",
          "destination" => "test.md",
          "variables" => {
            "custom_key" => "custom_value",
            "session" => { "custom_session_key" => "custom_session_value" }
          }
        }
        
        variables = real_rule.send(:build_template_variables, template_config)
        
        expect(variables["custom_key"]).to eq("custom_value")
        # Variables merging works, but symbol and string keys may be handled differently
        expect(variables).to have_key("session")
        expect(variables["session"]).to include("custom_session_key" => "custom_session_value")
      end
    end

    describe "deep merge functionality" do
      before { real_rule.validate }

      it "merges nested hashes correctly" do
        hash1 = {
          level1: {
            level2: { existing: "value1" },
            other: "keep"
          },
          simple: "original"
        }
        
        hash2 = {
          level1: {
            level2: { new: "value2" },
            added: "new"
          },
          simple: "overridden"
        }
        
        result = real_rule.send(:deep_merge, hash1, hash2)
        
        expect(result[:level1][:level2][:existing]).to eq("value1")
        expect(result[:level1][:level2][:new]).to eq("value2")
        expect(result[:level1][:other]).to eq("keep")
        expect(result[:level1][:added]).to eq("new")
        expect(result[:simple]).to eq("overridden")
      end

      it "handles non-hash values correctly" do
        hash1 = { key: "original" }
        hash2 = { key: "replacement" }
        
        result = real_rule.send(:deep_merge, hash1, hash2)
        expect(result[:key]).to eq("replacement")
      end
    end
  end
end