# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Templates::TemplateProcessor do
  let(:processor) { described_class.new }
  let(:simple_variables) do
    {
      session: { name: "test-session", path: "/tmp/test" },
      git: { branch: "main", author: "John Doe" },
      user: { name: "Test User" }
    }
  end

  describe "#process" do
    context "with simple variable substitution" do
      it "substitutes basic variables" do
        template = "Hello {{user.name}} on {{git.branch}}"
        result = processor.process(template, simple_variables)
        
        expect(result).to eq("Hello Test User on main")
      end

      it "handles nested variable access" do
        template = "Session: {{session.name}} at {{session.path}}"
        result = processor.process(template, simple_variables)
        
        expect(result).to eq("Session: test-session at /tmp/test")
      end

      it "handles missing variables gracefully" do
        template = "Missing: {{missing.variable}}"
        result = processor.process(template, simple_variables, strict: false)
        
        expect(result).to eq("Missing: ")
      end
    end

    context "with Liquid filters" do
      it "applies upcase filter" do
        template = "Branch: {{git.branch | upcase}}"
        result = processor.process(template, simple_variables)
        
        expect(result).to eq("Branch: MAIN")
      end

      it "applies truncate filter" do
        template = "Name: {{user.name | truncate: 4}}"
        result = processor.process(template, simple_variables)
        
        expect(result).to eq("Name: T...")
      end

      it "applies default filter" do
        template = "Value: {{missing.value | default: 'fallback'}}"
        result = processor.process(template, simple_variables)
        
        expect(result).to eq("Value: fallback")
      end
    end

    context "with arrays and loops" do
      let(:array_variables) do
        {
          projects: ["atlas-core", "atlas-pay"],
          session: { tags: ["feature", "urgent"] }
        }
      end

      it "processes arrays with for loops" do
        template = "{% for project in projects %}{{ project }} {% endfor %}"
        result = processor.process(template, array_variables)
        
        expect(result.strip).to eq("atlas-core atlas-pay")
      end

      it "processes nested arrays" do
        template = 'Tags: {% for tag in session.tags %}#{{ tag }} {% endfor %}'
        result = processor.process(template, array_variables)
        
        expect(result.strip).to eq("Tags: #feature #urgent")
      end
    end

    context "with conditionals" do
      it "processes if statements" do
        template = "{% if git.branch %}Branch: {{ git.branch }}{% endif %}"
        result = processor.process(template, simple_variables)
        
        expect(result).to eq("Branch: main")
      end

      it "processes unless statements" do
        template = "{% unless missing.value %}No value{% endunless %}"
        result = processor.process(template, simple_variables)
        
        expect(result).to eq("No value")
      end

      it "processes else statements" do
        template = "{% if missing.value %}Has value{% else %}No value{% endif %}"
        result = processor.process(template, simple_variables)
        
        expect(result).to eq("No value")
      end
    end

    context "with complex nested structures" do
      let(:complex_variables) do
        {
          session: {
            name: "complex-test",
            worktrees: [
              { name: "core", branch: "feature/test", path: "/tmp/core" },
              { name: "frontend", branch: "feature/ui", path: "/tmp/frontend" }
            ]
          }
        }
      end

      it "processes nested object arrays" do
        template = <<~LIQUID
          Worktrees:
          {% for worktree in session.worktrees %}
          - {{ worktree.name }}: {{ worktree.branch }}
          {% endfor %}
        LIQUID

        result = processor.process(template, complex_variables)
        
        expect(result).to include("- core: feature/test")
        expect(result).to include("- frontend: feature/ui")
      end
    end

    context "with template size limits" do
      it "raises error for templates that are too large" do
        large_template = "x" * (described_class::MAX_TEMPLATE_SIZE + 1)
        
        expect {
          processor.process(large_template, simple_variables)
        }.to raise_error(Sxn::Templates::Errors::TemplateTooLargeError)
      end

      it "processes templates within size limit" do
        normal_template = "x" * 1000
        
        expect {
          processor.process(normal_template, simple_variables)
        }.not_to raise_error
      end
    end

    context "with syntax errors" do
      it "raises error for invalid Liquid syntax" do
        invalid_template = "{{ unclosed variable"
        
        expect {
          processor.process(invalid_template, simple_variables)
        }.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError)
      end

      it "raises error for invalid tags" do
        invalid_template = "{% invalid_tag %}"
        
        expect {
          processor.process(invalid_template, simple_variables)
        }.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError)
      end
    end

    context "with security considerations" do
      it "sanitizes variable keys" do
        dangerous_variables = { "key with spaces" => "value", "key-with-dash" => "value2" }
        template = "{{key_with_spaces}} {{key_with_dash}}"
        
        result = processor.process(template, dangerous_variables)
        expect(result).to eq("value value2")
      end

      it "sanitizes string values" do
        dangerous_variables = { user: { script: "<script>alert('xss')</script>normal" } }
        template = "{{user.script}}"
        
        result = processor.process(template, dangerous_variables)
        expect(result).not_to include("<script>")
        expect(result).to include("normal")
      end

      it "converts unknown types to strings" do
        variables = { custom: Class.new { def to_s; "custom_object"; end }.new }
        template = "{{custom}}"
        
        result = processor.process(template, variables)
        expect(result).to eq("custom_object")
      end
    end

    context "with timeout protection" do
      # Note: This test might be flaky in CI environments
      it "handles long-running templates", :slow do
        # Create a template that could potentially run for a long time
        template = "{% for i in (1..1000) %}{{ i }}{% endfor %}"
        variables = {}
        
        start_time = Time.now
        
        expect {
          processor.process(template, variables)
        }.not_to raise_error
        
        elapsed = Time.now - start_time
        expect(elapsed).to be < described_class::MAX_RENDER_TIME
      end
    end
  end

  describe "#process_file" do
    let(:temp_dir) { Dir.mktmpdir }
    let(:template_path) { File.join(temp_dir, "test.liquid") }

    before do
      File.write(template_path, "Hello {{user.name}}")
    end

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "processes template files" do
      result = processor.process_file(template_path, simple_variables)
      expect(result).to eq("Hello Test User")
    end

    it "raises error for missing files" do
      missing_path = File.join(temp_dir, "missing.liquid")
      
      expect {
        processor.process_file(missing_path, simple_variables)
      }.to raise_error(Sxn::Templates::Errors::TemplateNotFoundError)
    end
  end

  describe "#validate_syntax" do
    it "validates correct syntax" do
      valid_template = "Hello {{user.name}}"
      
      expect {
        processor.validate_syntax(valid_template)
      }.not_to raise_error
      
      expect(processor.validate_syntax(valid_template)).to be true
    end

    it "raises error for invalid syntax" do
      invalid_template = "{{ unclosed"
      
      expect {
        processor.validate_syntax(invalid_template)
      }.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError)
    end
  end

  describe "#extract_variables" do
    it "extracts simple variables" do
      template = "Hello {{user.name}} on {{git.branch}}"
      variables = processor.extract_variables(template)
      
      expect(variables).to include("user", "git")
    end

    it "extracts variables from loops" do
      template = "{% for item in items %}{{ item.name }}{% endfor %}"
      variables = processor.extract_variables(template)
      
      expect(variables).to include("items")
    end

    it "extracts variables from conditionals" do
      template = "{% if session.active %}{{ session.name }}{% endif %}"
      variables = processor.extract_variables(template)
      
      expect(variables).to include("session")
    end

    it "returns sorted unique variables" do
      template = "{{ user.name }} {{ user.email }} {{ git.branch }} {{ user.name }}"
      variables = processor.extract_variables(template)
      
      expect(variables).to eq(["git", "user"])
    end
  end

  describe "filter whitelisting" do
    it "allows safe filters" do
      # Test a few key filters with proper arguments
      test_cases = {
        'upcase' => "{{ 'test' | upcase }}",
        'downcase' => "{{ 'TEST' | downcase }}",
        'capitalize' => "{{ 'test' | capitalize }}",
        'size' => "{{ 'test' | size }}",
        'split' => "{{ 'a,b,c' | split: ',' }}",
        'join' => "{{ items | join: ', ' }}",
        'default' => "{{ missing | default: 'fallback' }}",
        'truncate' => "{{ 'long text' | truncate: 5 }}"
      }
      
      test_cases.each do |filter, template|
        expect {
          processor.process(template, { 'items' => ['a', 'b'] })
        }.not_to raise_error, "Filter #{filter} should be allowed"
      end
    end

    # Note: Testing that dangerous filters are blocked would require
    # modifying Liquid's filter registry, which might affect other tests
  end

  describe "error handling" do
    it "provides meaningful error messages" do
      invalid_template = "{% invalid %}"
      
      expect {
        processor.process(invalid_template, simple_variables)
      }.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError, /syntax error/i)
    end

    it "handles processing errors gracefully" do
      # This might be hard to trigger with Liquid's robustness
      # but we test the error handling structure
      allow(Liquid::Template).to receive(:parse).and_raise(StandardError, "Test error")
      
      expect {
        processor.process("test", simple_variables)
      }.to raise_error(Sxn::Templates::Errors::TemplateProcessingError, /Test error/)
    end
  end
end