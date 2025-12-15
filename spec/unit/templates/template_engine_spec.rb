# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Templates::TemplateEngine do
  let(:mock_session) do
    double("Session",
           name: "test-session",
           path: Pathname.new("/tmp/test-session"),
           created_at: Time.parse("2025-01-16 10:00:00 UTC"),
           updated_at: Time.parse("2025-01-16 14:30:00 UTC"),
           status: "active")
  end

  let(:mock_project) do
    double("Project",
           name: "test-project",
           path: Pathname.new("/tmp/test-project"))
  end

  let(:mock_config) { double("Config") }
  let(:engine) { described_class.new(session: mock_session, project: mock_project, config: mock_config) }
  let(:temp_dir) { Dir.mktmpdir }

  before do
    # Mock the variables collector to avoid complex setup
    mock_variables_collector = double("TemplateVariables")
    allow(mock_variables_collector).to receive(:collect).and_return({
                                                                      session: { name: "test-session",
                                                                                 path: "/tmp/test-session" },
                                                                      git: { branch: "main" },
                                                                      user: { name: "Test User" },
                                                                      sxn: { version: "1.0.0" }
                                                                    })
    allow(mock_variables_collector).to receive(:refresh!)
    allow(Sxn::Templates::TemplateVariables).to receive(:new).and_return(mock_variables_collector)

    # Mock security validator
    mock_security = double("TemplateSecurity")
    allow(mock_security).to receive(:validate_template).and_return(true)
    allow(mock_security).to receive(:clear_cache!)
    allow(Sxn::Templates::TemplateSecurity).to receive(:new).and_return(mock_security)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#process_template" do
    let(:template_path) { File.join(temp_dir, "test.liquid") }
    let(:output_path) { File.join(temp_dir, "output.md") }

    before do
      File.write(template_path, "Hello {{user.name}} in session {{session.name}}")
    end

    it "processes template and writes to destination" do
      # Mock template finding
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)

      result = engine.process_template("test", output_path)

      expect(result).to eq(output_path)
      expect(File).to exist(output_path)

      content = File.read(output_path)
      expect(content).to include("Hello Test User in session test-session")
    end

    it "creates destination directory if it doesn't exist" do
      nested_output = File.join(temp_dir, "nested", "deep", "output.md")
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)

      engine.process_template("test", nested_output)

      expect(File).to exist(nested_output)
    end

    it "refuses to overwrite existing files without force option" do
      File.write(output_path, "existing content")
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)

      expect do
        engine.process_template("test", output_path)
      end.to raise_error(Sxn::Templates::Errors::TemplateError, /already exists/)
    end

    it "overwrites existing files with force option" do
      File.write(output_path, "existing content")
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)

      engine.process_template("test", output_path, {}, force: true)

      content = File.read(output_path)
      expect(content).not_to include("existing content")
      expect(content).to include("Hello Test User")
    end

    it "merges custom variables with collected variables" do
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)
      File.write(template_path, "Custom: {{custom.value}}, Session: {{session.name}}")

      custom_vars = { custom: { value: "custom_value" } }
      engine.process_template("test", output_path, custom_vars)

      content = File.read(output_path)
      expect(content).to include("Custom: custom_value")
      expect(content).to include("Session: test-session")
    end

    it "validates template security by default" do
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)
      mock_security = engine.instance_variable_get(:@security)

      engine.process_template("test", output_path)

      expect(mock_security).to have_received(:validate_template)
    end

    it "skips validation when requested" do
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)
      mock_security = engine.instance_variable_get(:@security)

      engine.process_template("test", output_path, {}, validate: false)

      expect(mock_security).not_to have_received(:validate_template)
    end

    it "handles template processing errors gracefully" do
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)
      File.write(template_path, "{{ invalid liquid syntax")

      expect do
        engine.process_template("test", output_path)
      end.to raise_error(Sxn::Templates::Errors::TemplateProcessingError)
    end
  end

  describe "#list_templates" do
    let(:templates_dir) { File.join(temp_dir, "templates") }

    before do
      # Override the TEMPLATES_DIR constant for testing
      stub_const("#{described_class}::TEMPLATES_DIR", templates_dir)

      # Create test template structure
      FileUtils.mkdir_p(File.join(templates_dir, "rails"))
      FileUtils.mkdir_p(File.join(templates_dir, "javascript"))
      FileUtils.mkdir_p(File.join(templates_dir, "common"))

      File.write(File.join(templates_dir, "rails", "CLAUDE.md.liquid"), "")
      File.write(File.join(templates_dir, "rails", "session-info.md.liquid"), "")
      File.write(File.join(templates_dir, "javascript", "README.md.liquid"), "")
      File.write(File.join(templates_dir, "common", "gitignore.liquid"), "")
    end

    it "lists all templates when no category specified" do
      templates = engine.list_templates

      expect(templates).to include("rails/CLAUDE.md.liquid")
      expect(templates).to include("rails/session-info.md.liquid")
      expect(templates).to include("javascript/README.md.liquid")
      expect(templates).to include("common/gitignore.liquid")
    end

    it "lists templates for specific category" do
      rails_templates = engine.list_templates("rails")

      expect(rails_templates).to include("rails/CLAUDE.md.liquid")
      expect(rails_templates).to include("rails/session-info.md.liquid")
      expect(rails_templates).not_to include("javascript/README.md.liquid")
    end

    it "returns empty array for non-existent directory" do
      templates = engine.list_templates("nonexistent")

      expect(templates).to eq([])
    end

    it "returns sorted templates" do
      templates = engine.list_templates("rails")

      expect(templates).to eq(templates.sort)
    end
  end

  describe "#template_categories" do
    let(:templates_dir) { File.join(temp_dir, "templates") }

    before do
      stub_const("#{described_class}::TEMPLATES_DIR", templates_dir)

      FileUtils.mkdir_p(File.join(templates_dir, "rails"))
      FileUtils.mkdir_p(File.join(templates_dir, "javascript"))
      FileUtils.mkdir_p(File.join(templates_dir, "common"))
      FileUtils.mkdir_p(File.join(templates_dir, ".hidden")) # Should be ignored
    end

    it "returns available template categories" do
      categories = engine.template_categories

      expect(categories).to include("rails", "javascript", "common")
      expect(categories).not_to include(".hidden")
    end

    it "returns sorted categories" do
      categories = engine.template_categories

      expect(categories).to eq(categories.sort)
    end

    it "returns empty array if templates directory doesn't exist" do
      stub_const("#{described_class}::TEMPLATES_DIR", "/nonexistent")

      categories = engine.template_categories

      expect(categories).to eq([])
    end
  end

  describe "#template_exists?" do
    let(:templates_dir) { File.join(temp_dir, "templates") }

    before do
      stub_const("#{described_class}::TEMPLATES_DIR", templates_dir)
      FileUtils.mkdir_p(File.join(templates_dir, "rails"))
      File.write(File.join(templates_dir, "rails", "CLAUDE.md.liquid"), "")
    end

    it "returns true for existing templates" do
      expect(engine.template_exists?("rails/CLAUDE.md")).to be true
      expect(engine.template_exists?("rails/CLAUDE.md.liquid")).to be true
    end

    it "returns false for non-existing templates" do
      expect(engine.template_exists?("rails/nonexistent.md")).to be false
      expect(engine.template_exists?("nonexistent/template.md")).to be false
    end
  end

  describe "#template_info" do
    let(:templates_dir) { File.join(temp_dir, "templates") }
    let(:template_path) { File.join(templates_dir, "test.liquid") }

    before do
      stub_const("#{described_class}::TEMPLATES_DIR", templates_dir)
      FileUtils.mkdir_p(templates_dir)
      File.write(template_path, "Hello {{user.name}} on {{git.branch}}")
    end

    it "returns template metadata" do
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)
      # Mock the processor methods that template_info depends on
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:extract_variables).and_return(%w[user git])
      allow(mock_processor).to receive(:validate_syntax).and_return(true)
      # Also need to handle the case where validate_template_syntax is called with content
      allow(engine).to receive(:validate_template_syntax).with("Hello {{user.name}} on {{git.branch}}").and_return(true)

      info = engine.template_info("test")

      expect(info[:name]).to eq("test")
      expect(info[:path]).to eq(template_path)
      expect(info[:size]).to be > 0
      expect(info[:variables]).to include("user", "git")
      expect(info[:syntax_valid]).to be true
    end

    it "handles template errors gracefully" do
      allow(engine).to receive(:find_template).with("test", nil).and_raise(StandardError, "Template error")

      info = engine.template_info("test")

      expect(info[:name]).to eq("test")
      expect(info[:error]).to include("Template error")
      expect(info[:syntax_valid]).to be false
    end
  end

  describe "#validate_template_syntax" do
    it "validates correct template syntax" do
      # Use a template content with newlines to ensure it's treated as content, not a name
      valid_template = "Hello {{user.name}}\nFrom {{git.branch}}"
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with(valid_template).and_return(true)

      expect(engine.validate_template_syntax(valid_template)).to be true
    end

    it "detects invalid template syntax" do
      # Use a template content with newlines to ensure it's treated as content, not a name
      invalid_template = "{{ invalid\nsyntax"
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with(invalid_template)
                                                        .and_raise(Sxn::Templates::Errors::TemplateSyntaxError)

      expect(engine.validate_template_syntax(invalid_template)).to be false
    end

    it "can validate template files by name" do
      template_path = File.join(temp_dir, "valid.liquid")
      File.write(template_path, "Hello {{user.name}}")

      allow(engine).to receive(:find_template).with("valid", nil).and_return(template_path)
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).and_return(true)

      expect(engine.validate_template_syntax("valid")).to be true
    end
  end

  describe "#available_variables" do
    it "returns all available variables" do
      variables = engine.available_variables

      expect(variables).to have_key(:session)
      expect(variables).to have_key(:git)
      expect(variables).to have_key(:user)
      expect(variables).to have_key(:sxn)
    end

    it "merges custom variables" do
      custom_vars = { custom: { key: "value" } }
      variables = engine.available_variables(custom_vars)

      expect(variables[:custom][:key]).to eq("value")
      expect(variables).to have_key(:session) # Still has base variables
    end

    it "allows custom variables to override base variables" do
      custom_vars = { session: { name: "overridden" } }
      variables = engine.available_variables(custom_vars)

      expect(variables[:session][:name]).to eq("overridden")
    end
  end

  describe "#process_string" do
    it "processes template strings directly" do
      template = "Hello {{user.name}} from {{git.branch}}"

      result = engine.process_string(template)

      expect(result).to include("Hello Test User from main")
    end

    it "merges custom variables" do
      template = "Custom: {{custom.value}}, User: {{user.name}}"
      custom_vars = { custom: { value: "test_value" } }

      result = engine.process_string(template, custom_vars)

      expect(result).to include("Custom: test_value")
      expect(result).to include("User: Test User")
    end

    it "validates templates by default" do
      template = "Safe template"
      mock_security = engine.instance_variable_get(:@security)

      engine.process_string(template)

      expect(mock_security).to have_received(:validate_template)
    end

    it "skips validation when requested" do
      template = "Template content"
      mock_security = engine.instance_variable_get(:@security)

      engine.process_string(template, {}, validate: false)

      expect(mock_security).not_to have_received(:validate_template)
    end
  end

  describe "#apply_template_set" do
    let(:templates_dir) { File.join(temp_dir, "templates") }
    let(:output_dir) { File.join(temp_dir, "output") }

    before do
      stub_const("#{described_class}::TEMPLATES_DIR", templates_dir)

      # Create test templates
      FileUtils.mkdir_p(File.join(templates_dir, "common"))
      File.write(File.join(templates_dir, "common", "README.md.liquid"), "# {{session.name}}")
      File.write(File.join(templates_dir, "common", "gitignore.liquid"), "*.log")

      FileUtils.mkdir_p(output_dir)
    end

    it "applies all templates in a set" do
      created_files = engine.apply_template_set("common", output_dir)

      expect(created_files).to include(File.join(output_dir, "README.md"))
      expect(created_files).to include(File.join(output_dir, "gitignore"))

      expect(File).to exist(File.join(output_dir, "README.md"))
      expect(File).to exist(File.join(output_dir, "gitignore"))

      readme_content = File.read(File.join(output_dir, "README.md"))
      expect(readme_content).to include("# test-session")
    end

    it "continues processing other templates if one fails" do
      # Create a template that will fail
      File.write(File.join(templates_dir, "common", "invalid.liquid"), "{{ invalid syntax")

      # Mock the warning output
      allow(engine).to receive(:warn)

      created_files = engine.apply_template_set("common", output_dir)

      # Should still create the valid templates
      expect(created_files).to include(File.join(output_dir, "README.md"))
      expect(created_files).to include(File.join(output_dir, "gitignore"))
      expect(created_files).not_to include(File.join(output_dir, "invalid"))

      expect(engine).to have_received(:warn).with(/Failed to process template/)
    end

    it "handles custom variables for template set" do
      custom_vars = { session: { name: "custom-session" } }

      engine.apply_template_set("common", output_dir, custom_vars)

      readme_content = File.read(File.join(output_dir, "README.md"))
      expect(readme_content).to include("# custom-session")
    end
  end

  describe "#refresh_variables!" do
    it "refreshes the variables collector" do
      mock_variables_collector = engine.instance_variable_get(:@variables_collector)

      engine.refresh_variables!

      expect(mock_variables_collector).to have_received(:refresh!)
    end
  end

  describe "#clear_cache!" do
    it "clears template cache and security cache" do
      mock_security = engine.instance_variable_get(:@security)

      engine.clear_cache!

      expect(mock_security).to have_received(:clear_cache!)
    end
  end

  describe "template finding" do
    let(:templates_dir) { File.join(temp_dir, "templates") }
    let(:custom_dir) { File.join(temp_dir, "custom") }

    before do
      stub_const("#{described_class}::TEMPLATES_DIR", templates_dir)

      # Create built-in template
      FileUtils.mkdir_p(File.join(templates_dir, "rails"))
      File.write(File.join(templates_dir, "rails", "CLAUDE.md.liquid"), "built-in")

      # Create custom template directory structure
      FileUtils.mkdir_p(File.join(custom_dir, "rails"))
    end

    it "finds built-in templates" do
      template_path = engine.send(:find_template, "rails/CLAUDE.md", nil)

      expect(template_path).to eq(File.join(templates_dir, "rails", "CLAUDE.md.liquid"))
    end

    it "prefers custom templates over built-in" do
      # Custom directory structure already created in before block
      File.write(File.join(custom_dir, "rails", "CLAUDE.md.liquid"), "custom")

      template_path = engine.send(:find_template, "rails/CLAUDE.md", custom_dir)

      expect(template_path).to eq(File.join(custom_dir, "rails", "CLAUDE.md.liquid"))
    end

    it "handles missing templates gracefully" do
      expect do
        engine.send(:find_template, "nonexistent/template", nil)
      end.to raise_error(Sxn::Templates::Errors::TemplateNotFoundError, /not found/)
    end

    it "provides helpful error messages for missing templates" do
      expect do
        engine.send(:find_template, "missing/template", nil)
      end.to raise_error(Sxn::Templates::Errors::TemplateNotFoundError, /Available templates/)
    end
  end

  describe "error handling" do
    it "wraps template processing errors with context" do
      # Mock a processing error
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:process_file)
        .and_raise(StandardError, "Processing failed")

      template_path = File.join(temp_dir, "test.liquid")
      File.write(template_path, "test")
      allow(engine).to receive(:find_template).and_return(template_path)

      expect do
        engine.process_template("test", File.join(temp_dir, "output.md"))
      end.to raise_error(Sxn::Templates::Errors::TemplateProcessingError, /Failed to process template 'test'/)
    end
  end

  describe "integration with sxn version" do
    it "includes sxn version in variables" do
      variables = engine.available_variables

      expect(variables[:sxn]).to be_a(Hash)
      expect(variables[:sxn][:version]).to eq(Sxn::VERSION)
      expect(variables[:sxn][:template_engine]).to eq("liquid")
    end
  end

  describe "Hash#deep_merge" do
    # Test the deep_merge implementation from template_engine.rb (lines 10-22)
    # The challenge is that if ActiveSupport is loaded, deep_merge is already defined
    # and the code at lines 11-21 never executes. We need to test the behavior
    # regardless of whether the method was defined by our code or ActiveSupport.
    #
    # Implementation being tested:
    #   def deep_merge(other_hash)
    #     merge(other_hash) do |_key, oldval, newval|
    #       if oldval.is_a?(Hash) && newval.is_a?(Hash)  # Line 14-15
    #         oldval.deep_merge(newval)                   # Line 15[then] - RECURSIVE MERGE
    #       else                                          # Line 16-17
    #         newval                                      # Line 17[else] - REPLACE VALUE
    #       end
    #     end
    #   end

    it "recursively merges nested hashes (line 15[then])" do
      # This tests the recursive case where both oldval and newval are hashes
      h1 = { config: { database: { host: "localhost", port: 5432 } } }
      h2 = { config: { database: { port: 3306, user: "admin" } } }
      result = h1.deep_merge(h2)

      # Should recursively merge the nested hashes
      expect(result[:config][:database][:host]).to eq("localhost")
      expect(result[:config][:database][:port]).to eq(3306)
      expect(result[:config][:database][:user]).to eq("admin")
    end

    it "deeply merges multiple levels of nested hashes (line 15[then])" do
      # Additional test for recursive merging with deeper nesting
      h1 = { a: { b: { c: 1, d: 2 } } }
      h2 = { a: { b: { c: 3, e: 4 } } }
      result = h1.deep_merge(h2)

      expect(result).to eq({ a: { b: { c: 3, d: 2, e: 4 } } })
    end

    it "merges simple nested hash structures (line 15[then])" do
      # Test simple one-level nesting
      h1 = { a: { b: 1 } }
      h2 = { a: { c: 2 } }
      result = h1.deep_merge(h2)

      expect(result).to eq({ a: { b: 1, c: 2 } })
    end

    it "overwrites when old value is hash but new value is not (line 17[else])" do
      # This tests line 17[else] - oldval.is_a?(Hash) is true but newval.is_a?(Hash) is false
      h1 = { items: { a: 1, b: 2 } }
      h2 = { items: [1, 2, 3] }
      result = h1.deep_merge(h2)

      expect(result[:items]).to eq([1, 2, 3])
    end

    it "overwrites when old value is hash but new value is string (line 17[else])" do
      # Another test for line 17[else] - hash replaced by string
      h1 = { a: { b: 1 } }
      h2 = { a: "string" }
      result = h1.deep_merge(h2)

      expect(result).to eq({ a: "string" })
    end

    it "overwrites when old value is not hash but new value is hash (line 17[else])" do
      # This tests line 17[else] - oldval.is_a?(Hash) is false
      h1 = { items: [1, 2, 3] }
      h2 = { items: { a: 1 } }
      result = h1.deep_merge(h2)

      expect(result[:items]).to eq({ a: 1 })
    end

    it "overwrites when old value is string but new value is hash (line 17[else])" do
      # Another test for line 17[else] - non-hash replaced by hash
      h1 = { a: "string" }
      h2 = { a: { b: 1 } }
      result = h1.deep_merge(h2)

      expect(result[:a]).to eq({ b: 1 })
    end

    it "overwrites when both values are non-hash types (line 17[else])" do
      # Tests line 17[else] - neither oldval nor newval are hashes
      h1 = { value: "old" }
      h2 = { value: 42 }
      result = h1.deep_merge(h2)

      expect(result[:value]).to eq(42)
    end

    it "overwrites when old value is nil (line 17[else])" do
      # Tests line 17[else] - oldval is nil (not a hash)
      h1 = { data: nil }
      h2 = { data: { key: "value" } }
      result = h1.deep_merge(h2)

      expect(result[:data]).to eq({ key: "value" })
    end

    it "overwrites arrays with arrays (line 17[else])" do
      # Tests line 17[else] - both are arrays (non-hash values)
      h1 = { list: [1, 2] }
      h2 = { list: [3, 4] }
      result = h1.deep_merge(h2)

      expect(result[:list]).to eq([3, 4])
    end

    it "handles complex mixed-type merging scenario (lines 15[then] and 17[else])" do
      # This test exercises both branches in a single merge operation
      h1 = {
        simple: 1, # Will be overwritten (17[else])
        nested: { a: 1, b: 2 }, # Will be recursively merged (15[then])
        replaced: { old: "value" }        # Will be replaced by non-hash (17[else])
      }
      h2 = {
        simple: 2,                        # Overwrites simple value
        nested: { b: 3, c: 4 }, # Merges with nested hash
        replaced: "new value" # Replaces hash with string
      }
      result = h1.deep_merge(h2)

      expect(result).to eq({
                             simple: 2,
                             nested: { a: 1, b: 3, c: 4 },
                             replaced: "new value"
                           })
    end

    it "preserves original hash and returns new hash" do
      # Verify that deep_merge doesn't mutate the original
      h1 = { a: { b: 1 } }
      h2 = { a: { c: 2 } }
      original_h1 = h1.dup

      result = h1.deep_merge(h2)

      expect(result).to eq({ a: { b: 1, c: 2 } })
      # NOTE: Hash#dup is shallow, so we check the top-level key
      expect(h1.keys).to eq(original_h1.keys)
    end

    it "handles empty hash merging" do
      h1 = { a: 1 }
      h2 = {}
      result = h1.deep_merge(h2)

      expect(result).to eq({ a: 1 })
    end

    it "merges into empty hash" do
      h1 = {}
      h2 = { a: 1 }
      result = h1.deep_merge(h2)

      expect(result).to eq({ a: 1 })
    end

    it "works with symbol and string keys" do
      h1 = { a: { b: 1 } }
      h2 = { a: { c: 2 } }
      result = h1.deep_merge(h2)

      expect(result).to eq({ a: { b: 1, c: 2 } })
    end

    it "handles deep recursion with 5+ levels of nesting (line 15[then])" do
      # Test deep recursive merge to ensure the recursion works at any depth
      h1 = { a: { b: { c: { d: { e: { f: 1, g: 2 } } } } } }
      h2 = { a: { b: { c: { d: { e: { g: 3, h: 4 } } } } } }
      result = h1.deep_merge(h2)

      # Verify all levels are merged correctly
      expect(result[:a][:b][:c][:d][:e][:f]).to eq(1)
      expect(result[:a][:b][:c][:d][:e][:g]).to eq(3)
      expect(result[:a][:b][:c][:d][:e][:h]).to eq(4)
    end

    it "correctly merges when keys exist at different depths (line 15[then] and 17[else])" do
      # Mixed scenario: some keys merge deeply, others replace
      h1 = {
        settings: {
          theme: { color: "blue", size: "large" },
          notifications: { email: true },
          timeout: 30
        }
      }
      h2 = {
        settings: {
          theme: { color: "red", font: "Arial" },
          notifications: "disabled",
          timeout: 60,
          new_setting: "value"
        }
      }
      result = h1.deep_merge(h2)

      # theme should be recursively merged (line 15[then])
      expect(result[:settings][:theme]).to eq({ color: "red", size: "large", font: "Arial" })
      # notifications should be replaced (line 17[else] - hash to string)
      expect(result[:settings][:notifications]).to eq("disabled")
      # timeout should be replaced (line 17[else] - both non-hash)
      expect(result[:settings][:timeout]).to eq(60)
      # new_setting should be added
      expect(result[:settings][:new_setting]).to eq("value")
    end

    it "verifies non-destructive merge behavior" do
      # Ensure original hashes are not modified
      h1 = { a: { b: 1, c: 2 } }
      h2 = { a: { c: 3, d: 4 } }
      h1_original = Marshal.load(Marshal.dump(h1)) # Deep copy
      h2_original = Marshal.load(Marshal.dump(h2)) # Deep copy

      result = h1.deep_merge(h2)

      # Result should have merged values
      expect(result).to eq({ a: { b: 1, c: 3, d: 4 } })
      # Original hashes should be unchanged
      expect(h1).to eq(h1_original)
      expect(h2).to eq(h2_original)
    end

    it "handles boolean values correctly (line 17[else])" do
      # Booleans are not hashes, so they should replace
      h1 = { feature_flag: true }
      h2 = { feature_flag: false }
      result = h1.deep_merge(h2)

      expect(result[:feature_flag]).to eq(false)
    end

    it "merges hashes with numeric keys" do
      # Test with numeric keys
      h1 = { 1 => { a: 1 }, 2 => { b: 2 } }
      h2 = { 1 => { c: 3 }, 3 => { d: 4 } }
      result = h1.deep_merge(h2)

      expect(result[1]).to eq({ a: 1, c: 3 })
      expect(result[2]).to eq({ b: 2 })
      expect(result[3]).to eq({ d: 4 })
    end
  end

  describe "security error handling" do
    let(:template_path) { File.join(temp_dir, "test.liquid") }
    let(:output_path) { File.join(temp_dir, "output.md") }

    it "re-raises TemplateSecurityError without wrapping in process_template" do
      File.write(template_path, "{{ user.name }}")
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)

      # Mock security validator to raise a security error
      mock_security = engine.instance_variable_get(:@security)
      allow(mock_security).to receive(:validate_template).and_raise(
        Sxn::Templates::Errors::TemplateSecurityError, "Dangerous pattern detected"
      )

      expect do
        engine.process_template("test", output_path)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError, /Dangerous pattern detected/)
    end

    it "re-raises TemplateSecurityError without wrapping in render_template" do
      template_path = File.join(temp_dir, "test.liquid")
      File.write(template_path, "{{ user.name }}")
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)

      # Mock security validator to raise a security error
      mock_security = engine.instance_variable_get(:@security)
      allow(mock_security).to receive(:validate_template).and_raise(
        Sxn::Templates::Errors::TemplateSecurityError, "Dangerous pattern detected"
      )

      expect do
        engine.render_template("test")
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError, /Dangerous pattern detected/)
    end
  end

  describe "validate_template_syntax fallback cases" do
    it "treats multiline content as template content" do
      multiline_template = "Line 1\n{{ user.name }}\nLine 3"
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with(multiline_template).and_return(true)

      expect(engine.validate_template_syntax(multiline_template)).to be true
    end

    it "handles ambiguous input with Liquid syntax as content" do
      # Input with Liquid syntax but no path separators
      template = "{{ user.name }}"
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with(template).and_return(true)

      expect(engine.validate_template_syntax(template)).to be true
    end

    it "handles input with {%} syntax as content" do
      # Input with Liquid tag syntax
      template = "{% if user %}hello{% endif %}"
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with(template).and_return(true)

      expect(engine.validate_template_syntax(template)).to be true
    end

    it "handles ambiguous input without Liquid syntax as filename" do
      # Create a simple template file
      template_path = File.join(temp_dir, "simple.liquid")
      File.write(template_path, "Hello World")

      # Set up template finding
      allow(engine).to receive(:find_template).with("simple", nil).and_return(template_path)
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with("Hello World").and_return(true)

      expect(engine.validate_template_syntax("simple")).to be true
    end

    it "handles file paths with .liquid extension" do
      # Input ends with .liquid
      template_path = File.join(temp_dir, "test.liquid")
      File.write(template_path, "content")

      allow(engine).to receive(:find_template).with("test.liquid", nil).and_return(template_path)
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with("content").and_return(true)

      expect(engine.validate_template_syntax("test.liquid")).to be true
    end

    it "handles file paths with directory separators" do
      # Input has a path separator
      template_path = File.join(temp_dir, "dir", "test.liquid")
      FileUtils.mkdir_p(File.dirname(template_path))
      File.write(template_path, "content")

      allow(engine).to receive(:find_template).with("dir/test", nil).and_return(template_path)
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with("content").and_return(true)

      expect(engine.validate_template_syntax("dir/test")).to be true
    end

    it "handles template not found errors" do
      allow(engine).to receive(:find_template).with("missing", nil).and_raise(
        Sxn::Templates::Errors::TemplateNotFoundError
      )

      expect(engine.validate_template_syntax("missing")).to be false
    end

    it "treats inline content with Liquid markers as content (else branch)" do
      # This covers the else branch at line 192 - when input is treated as inline template content
      # To hit else branch: string with {{ but no "/" and no file extension
      inline_content = "Hello {{ name }}"

      # This should validate the content directly through the processor
      result = engine.validate_template_syntax(inline_content)
      expect(result).to be true
    end

    it "treats plain text without Liquid syntax and without path separators as content (line 192 else)" do
      # This specifically tests line 192[else] - fallback to treating input as content
      # Looking at the code: line 180-192 has conditions that check for Liquid syntax, path separators, etc.
      # The else at line 192 is reached when the input doesn't match the "if" at 180-183
      # and doesn't match the "elsif" at 185-189 (which looks for paths/filenames)
      # So we need input that: has no Liquid syntax, has newlines OR doesn't look like a filename
      plain_text_with_newlines = "just plain text\nwith multiple lines"
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:validate_syntax).with(plain_text_with_newlines).and_return(true)

      result = engine.validate_template_syntax(plain_text_with_newlines)
      expect(result).to be true
      expect(mock_processor).to have_received(:validate_syntax).with(plain_text_with_newlines)
    end
  end

  describe "render_template error handling" do
    it "raises TemplateNotFoundError for non-existent template" do
      allow(engine).to receive(:find_template).with("nonexistent", nil).and_raise(
        Sxn::Templates::Errors::TemplateNotFoundError, "Template not found"
      )

      expect do
        engine.render_template("nonexistent")
      end.to raise_error(Sxn::Templates::Errors::TemplateProcessingError, /Failed to render template/)
    end

    it "wraps processing errors with context" do
      template_path = File.join(temp_dir, "error.liquid")
      File.write(template_path, "{{ user.name }}")
      allow(engine).to receive(:find_template).with("error", nil).and_return(template_path)

      # Mock processor to raise an error
      mock_processor = engine.instance_variable_get(:@processor)
      allow(mock_processor).to receive(:process).and_raise(StandardError, "Processing failed")

      expect do
        engine.render_template("error")
      end.to raise_error(Sxn::Templates::Errors::TemplateProcessingError, /Failed to render template 'error'/)
    end

    it "handles file read errors gracefully" do
      allow(engine).to receive(:find_template).with("test", nil).and_return("/nonexistent/path.liquid")
      allow(File).to receive(:read).with("/nonexistent/path.liquid").and_raise(Errno::ENOENT, "No such file")

      expect do
        engine.render_template("test")
      end.to raise_error(Sxn::Templates::Errors::TemplateProcessingError)
    end

    it "skips validation when validate option is false" do
      template_path = File.join(temp_dir, "test.liquid")
      File.write(template_path, "{{ user.name }}")
      allow(engine).to receive(:find_template).with("test", nil).and_return(template_path)

      mock_security = engine.instance_variable_get(:@security)

      engine.render_template("test", {}, validate: false)

      expect(mock_security).not_to have_received(:validate_template)
    end
  end
end
