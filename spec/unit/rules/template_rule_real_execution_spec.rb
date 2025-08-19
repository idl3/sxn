# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Rules::TemplateRule do
  let(:project_path) { Dir.mktmpdir("project") }
  let(:session_path) { Dir.mktmpdir("session") }
  let(:rule_name) { "template_test_real" }
  
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

  before do
    # Create project template for real execution
    FileUtils.mkdir_p(File.join(project_path, ".sxn/templates"))
    template_content = <<~LIQUID
      # Session: {{session.name}}
      
      Created at: {{session.created_at}}
      Project: {{project.name}}
      Custom: {{custom_var}}
    LIQUID
    File.write(File.join(project_path, ".sxn/templates/session-info.md.liquid"), template_content)
  end

  after do
    FileUtils.rm_rf(project_path)
    FileUtils.rm_rf(session_path)
  end

  describe "real execution without mocking" do
    let(:rule) { described_class.new(rule_name, basic_config, project_path, session_path) }

    describe "#initialize" do
      it "creates real template processor and variables instances" do
        expect(rule.instance_variable_get(:@template_processor)).to be_a(Sxn::Templates::TemplateProcessor)
        expect(rule.instance_variable_get(:@template_variables)).to be_a(Sxn::Templates::TemplateVariables)
      end
    end

    describe "#validate" do
      it "calls super and validates rule specific configuration" do
        expect(rule.validate).to be true
        expect(rule.state).to eq(:validated)
      end

      context "with invalid configuration" do
        let(:invalid_config) { { "templates" => [] } }
        let(:invalid_rule) { described_class.new(rule_name, invalid_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            invalid_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /'templates' cannot be empty/)
        end
      end

      context "with missing templates key" do
        let(:missing_config) { {} }
        let(:missing_rule) { described_class.new(rule_name, missing_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            missing_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /requires 'templates' configuration/)
        end
      end

      context "with non-array templates" do
        let(:non_array_config) { { "templates" => "not-an-array" } }
        let(:non_array_rule) { described_class.new(rule_name, non_array_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            non_array_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /'templates' must be an array/)
        end
      end

      context "with non-hash template config" do
        let(:non_hash_config) { { "templates" => ["not-a-hash"] } }
        let(:non_hash_rule) { described_class.new(rule_name, non_hash_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            non_hash_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /Template config 0 must be a hash/)
        end
      end

      context "with missing source" do
        let(:missing_source_config) do
          { "templates" => [{ "destination" => "test.md" }] }
        end
        let(:missing_source_rule) { described_class.new(rule_name, missing_source_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            missing_source_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /must have a 'source' string/)
        end
      end

      context "with missing destination" do
        let(:missing_dest_config) do
          { "templates" => [{ "source" => "test.liquid" }] }
        end
        let(:missing_dest_rule) { described_class.new(rule_name, missing_dest_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            missing_dest_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /must have a 'destination' string/)
        end
      end

      context "with unsupported engine" do
        let(:unsupported_engine_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/session-info.md.liquid",
                "destination" => "README.md",
                "engine" => "mustache"
              }
            ]
          }
        end
        let(:unsupported_rule) { described_class.new(rule_name, unsupported_engine_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            unsupported_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /unsupported engine 'mustache'/)
        end
      end

      context "with invalid variables type" do
        let(:invalid_vars_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/session-info.md.liquid",
                "destination" => "README.md",
                "variables" => "not-a-hash"
              }
            ]
          }
        end
        let(:invalid_vars_rule) { described_class.new(rule_name, invalid_vars_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            invalid_vars_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /'variables' must be a hash/)
        end
      end

      context "with unsafe destination path" do
        let(:unsafe_dest_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/session-info.md.liquid",
                "destination" => "../unsafe.md"
              }
            ]
          }
        end
        let(:unsafe_rule) { described_class.new(rule_name, unsafe_dest_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            unsafe_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /destination path is not safe/)
        end
      end

      context "with absolute destination path" do
        let(:absolute_dest_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/session-info.md.liquid",
                "destination" => "/absolute/path.md"
              }
            ]
          }
        end
        let(:absolute_rule) { described_class.new(rule_name, absolute_dest_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            absolute_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /destination path is not safe/)
        end
      end

      context "with missing required template file" do
        let(:missing_file_config) do
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
        let(:missing_file_rule) { described_class.new(rule_name, missing_file_config, project_path, session_path) }

        it "raises validation error" do
          expect {
            missing_file_rule.validate
          }.to raise_error(Sxn::Rules::ValidationError, /Required template file does not exist/)
        end
      end
    end

    describe "#apply" do
      before { rule.validate }

      it "executes real template processing with state changes" do
        expect(rule.apply).to be true
        expect(rule.state).to eq(:applied)
        
        output_file = File.join(session_path, "README.md")
        expect(File.exist?(output_file)).to be true
        
        content = File.read(output_file)
        expect(content).to include("# Session:")
        expect(content).to include("Created at:")
        expect(content).to include("Project:")
      end

      it "logs success message with template count" do
        expect { rule.apply }.to change { rule.state }.from(:validated).to(:applied)
      end

      it "tracks file creation change" do
        rule.apply
        
        expect(rule.changes).not_to be_empty
        change = rule.changes.first
        expect(change.type).to eq(:file_created)
        expect(change.target).to end_with("README.md")
        expect(change.metadata[:template]).to be true
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

        it "merges custom variables into template processing" do
          custom_vars_rule.apply
          
          output_file = File.join(session_path, "README.md")
          content = File.read(output_file)
          expect(content).to include("Custom: custom_value")
        end
      end

      context "with missing optional template during apply" do
        let(:optional_config) do
          {
            "templates" => [
              {
                "source" => ".sxn/templates/optional.liquid",
                "destination" => "optional.md",
                "required" => false
              }
            ]
          }
        end
        let(:optional_rule) { described_class.new(rule_name, optional_config, project_path, session_path) }

        before { optional_rule.validate }

        it "skips missing optional templates successfully" do
          expect(optional_rule.apply).to be true
          expect(optional_rule.state).to eq(:applied)
          expect(optional_rule.changes).to be_empty
        end
      end

      context "with existing destination file" do
        let(:existing_file) { File.join(session_path, "README.md") }

        before do
          File.write(existing_file, "existing content")
        end

        it "skips processing when file exists and overwrite is false" do
          rule.apply
          expect(File.read(existing_file)).to eq("existing content")
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

          it "overwrites existing files and creates backup" do
            overwrite_rule.apply
            
            # File should be overwritten
            content = File.read(existing_file)
            expect(content).not_to eq("existing content")
            expect(content).to include("# Session:")
            
            # Backup should be created
            change = overwrite_rule.changes.first
            expect(change.metadata).to have_key(:backup_path)
            expect(File.exist?(change.metadata[:backup_path])).to be true
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

        it "creates nested directories automatically" do
          nested_rule.apply
          
          nested_file = File.join(session_path, "docs/deep/nested/README.md")
          expect(File.exist?(nested_file)).to be true
          expect(File.directory?(File.dirname(nested_file))).to be true
        end
      end

      context "with multiple templates" do
        let(:multi_config) do
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
        let(:multi_rule) { described_class.new(rule_name, multi_config, project_path, session_path) }

        before { multi_rule.validate }

        it "processes multiple templates successfully" do
          multi_rule.apply
          
          expect(multi_rule.changes.size).to eq(2)
          expect(File.exist?(File.join(session_path, "README.md"))).to be true
          expect(File.exist?(File.join(session_path, "docs/SESSION.md"))).to be true
        end
      end

      context "with template processing error" do
        before do
          # Create a malformed template
          malformed_content = "{{invalid liquid syntax"
          File.write(File.join(project_path, ".sxn/templates/session-info.md.liquid"), malformed_content)
        end

        it "handles template syntax errors gracefully" do
          expect {
            rule.apply
          }.to raise_error(Sxn::Rules::ApplicationError, /Template syntax error/)
          expect(rule.state).to eq(:failed)
        end
      end
    end

    describe "private method coverage" do
      before { rule.validate }

      describe "#build_template_variables" do
        it "builds variables with template metadata" do
          template_config = {
            "source" => "test.liquid",
            "destination" => "test.md"
          }
          
          variables = rule.send(:build_template_variables, template_config)
          
          expect(variables).to have_key(:template)
          expect(variables[:template][:source]).to eq("test.liquid")
          expect(variables[:template][:destination]).to eq("test.md")
          expect(variables[:template]).to have_key(:processed_at)
        end

        it "merges custom variables correctly" do
          template_config = {
            "source" => "test.liquid",
            "destination" => "test.md",
            "variables" => { "custom" => "value" }
          }
          
          variables = rule.send(:build_template_variables, template_config)
          expect(variables["custom"]).to eq("value")
        end
      end

      describe "#deep_merge" do
        it "merges nested hashes correctly" do
          hash1 = { a: { b: 1 }, c: 2 }
          hash2 = { a: { d: 3 }, e: 4 }
          
          result = rule.send(:deep_merge, hash1, hash2)
          
          expect(result[:a][:b]).to eq(1)
          expect(result[:a][:d]).to eq(3)
          expect(result[:c]).to eq(2)
          expect(result[:e]).to eq(4)
        end

        it "overwrites non-hash values" do
          hash1 = { key: "original" }
          hash2 = { key: "new" }
          
          result = rule.send(:deep_merge, hash1, hash2)
          expect(result[:key]).to eq("new")
        end
      end

      describe "#extract_used_variables" do
        it "extracts variables from template content" do
          variables = rule.send(:extract_used_variables, "{{session.name}} and {{project.type}}")
          expect(variables).to be_an(Array)
        end

        it "handles extraction errors gracefully" do
          # Mock an error in the template processor
          allow(rule.instance_variable_get(:@template_processor)).to receive(:extract_variables).and_raise(StandardError)
          
          variables = rule.send(:extract_used_variables, "content")
          expect(variables).to eq([])
        end
      end
    end
  end
end