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
          projects: %w[atlas-core atlas-pay],
          session: { tags: %w[feature urgent] }
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

        expect do
          processor.process(large_template, simple_variables)
        end.to raise_error(Sxn::Templates::Errors::TemplateTooLargeError)
      end

      it "processes templates within size limit" do
        normal_template = "x" * 1000

        expect do
          processor.process(normal_template, simple_variables)
        end.not_to raise_error
      end
    end

    context "with syntax errors" do
      it "raises error for invalid Liquid syntax" do
        invalid_template = "{{ unclosed variable"

        expect do
          processor.process(invalid_template, simple_variables)
        end.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError)
      end

      it "raises error for invalid tags" do
        invalid_template = "{% invalid_tag %}"

        expect do
          processor.process(invalid_template, simple_variables)
        end.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError)
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
        variables = { custom: Class.new { def to_s = "custom_object" }.new }
        template = "{{custom}}"

        result = processor.process(template, variables)
        expect(result).to eq("custom_object")
      end
    end

    context "with timeout protection" do
      # NOTE: This test might be flaky in CI environments
      it "handles long-running templates", :slow do
        # Create a template that could potentially run for a long time
        template = "{% for i in (1..1000) %}{{ i }}{% endfor %}"
        variables = {}

        start_time = Time.now

        expect do
          processor.process(template, variables)
        end.not_to raise_error

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

      expect do
        processor.process_file(missing_path, simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateNotFoundError)
    end
  end

  describe "#validate_syntax" do
    it "validates correct syntax" do
      valid_template = "Hello {{user.name}}"

      expect do
        processor.validate_syntax(valid_template)
      end.not_to raise_error

      expect(processor.validate_syntax(valid_template)).to be true
    end

    it "raises error for invalid syntax" do
      invalid_template = "{{ unclosed"

      expect do
        processor.validate_syntax(invalid_template)
      end.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError)
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

      expect(variables).to eq(%w[git user])
    end
  end

  describe "filter whitelisting" do
    it "allows safe filters" do
      # Test a few key filters with proper arguments
      test_cases = {
        "upcase" => "{{ 'test' | upcase }}",
        "downcase" => "{{ 'TEST' | downcase }}",
        "capitalize" => "{{ 'test' | capitalize }}",
        "size" => "{{ 'test' | size }}",
        "split" => "{{ 'a,b,c' | split: ',' }}",
        "join" => "{{ items | join: ', ' }}",
        "default" => "{{ missing | default: 'fallback' }}",
        "truncate" => "{{ 'long text' | truncate: 5 }}"
      }

      test_cases.each do |filter, template|
        expect do
          processor.process(template, { "items" => %w[a b] })
        end.not_to raise_error, "Filter #{filter} should be allowed"
      end
    end

    # NOTE: Testing that dangerous filters are blocked would require
    # modifying Liquid's filter registry, which might affect other tests
  end

  describe "variable sanitization" do
    it "handles numeric values" do
      variables = { number: 42, float: 3.14, negative: -10 }
      template = "{{number}} {{float}} {{negative}}"
      result = processor.process(template, variables)
      expect(result).to eq("42 3.14 -10")
    end

    it "handles boolean values" do
      variables = { true_val: true, false_val: false, nil_val: nil }
      template = "{{true_val}} {{false_val}} {{nil_val}}"
      result = processor.process(template, variables)
      expect(result).to eq("true false ")
    end

    it "handles Time and Date objects" do
      time = Time.parse("2025-01-16 10:00:00 UTC")
      date = Date.parse("2025-01-16")
      variables = { time: time, date: date }
      template = "{{time}} {{date}}"
      result = processor.process(template, variables)
      expect(result).to include("2025-01-16T10:00:00Z")
      expect(result).to include("2025-01-16")
    end

    it "converts unknown types to string" do
      custom_object = Class.new do
        def to_s
          "custom_object"
        end
      end.new

      variables = { custom: custom_object }
      template = "{{custom}}"
      result = processor.process(template, variables)
      expect(result).to eq("custom_object")
    end

    it "handles symbols" do
      variables = { symbol: :test_symbol }
      template = "{{symbol}}"
      result = processor.process(template, variables)
      expect(result).to eq("test_symbol")
    end
  end

  describe "performance and debugging" do
    it "logs performance metrics in debug mode" do
      original_env = ENV.fetch("SXN_DEBUG", nil)
      ENV["SXN_DEBUG"] = "true"

      # Capture stdout to check debug output
      original_stdout = $stdout
      $stdout = StringIO.new

      begin
        template = "Hello {{user.name}}"
        processor.process(template, simple_variables)

        output = $stdout.string
        expect(output).to match(/Template rendered in \d+\.\d+s/)
      ensure
        $stdout = original_stdout
        ENV["SXN_DEBUG"] = original_env
      end
    end

    it "handles timeout scenarios gracefully", :slow do
      # Mock a scenario where rendering would timeout
      allow(processor).to receive(:render_with_timeout) do |_template, _context, _options|
        sleep(0.1) # Small delay to simulate processing
        raise Sxn::Templates::Errors::TemplateTimeoutError,
              "Template rendering exceeded #{described_class::MAX_RENDER_TIME} seconds"
      end

      template = "{{user.name}}"

      expect do
        processor.process(template, simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateTimeoutError)
    end
  end

  describe "error handling" do
    it "provides meaningful error messages" do
      invalid_template = "{% invalid %}"

      expect do
        processor.process(invalid_template, simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError, /syntax error/i)
    end

    it "handles processing errors gracefully" do
      # This might be hard to trigger with Liquid's robustness
      # but we test the error handling structure
      allow(Liquid::Template).to receive(:parse).and_raise(StandardError, "Test error")

      expect do
        processor.process("test", simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateProcessingError, /Test error/)
    end

    it "collects Liquid rendering errors" do
      # Create a template with a Liquid error (e.g., undefined variable in strict mode)
      template = "{{ undefined_variable }}"

      # Mock the template to have errors
      mock_template = double("Liquid::Template")
      allow(mock_template).to receive(:render).and_return("")
      allow(mock_template).to receive(:errors).and_return(["Liquid error: undefined variable 'undefined_variable'"])
      allow(Liquid::Template).to receive(:parse).and_return(mock_template)

      expect do
        processor.process(template, simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateRenderError, /Template rendering errors/)
    end
  end

  describe "actual timeout mechanism" do
    it "raises TemplateTimeoutError when template exceeds max render time" do
      # Create a template that sleeps longer than MAX_RENDER_TIME
      # We'll mock the sleep to happen in the timeout thread
      template = "{{ user.name }}"

      # Mock render to take too long
      allow_any_instance_of(Liquid::Template).to receive(:render) do
        sleep(described_class::MAX_RENDER_TIME + 1)
        "result"
      end

      expect do
        processor.process(template, simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateTimeoutError, /exceeded/)
    end

    it "ensures timeout thread is cleaned up after render" do
      template = "{{ user.name }}"

      # Simply verify that processing completes without leaving hanging threads
      initial_thread_count = Thread.list.size

      processor.process(template, simple_variables)

      # Give threads time to clean up
      sleep 0.2

      # The timeout thread should have been killed
      final_thread_count = Thread.list.size
      expect(final_thread_count).to be <= initial_thread_count
    end
  end

  describe "re-raising specific template errors" do
    it "re-raises TemplateTooLargeError without wrapping" do
      large_template = "x" * (described_class::MAX_TEMPLATE_SIZE + 1)

      expect do
        processor.process(large_template, simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateTooLargeError)
    end

    it "re-raises TemplateTimeoutError without wrapping" do
      # Mock render_with_timeout to raise timeout error
      allow(processor).to receive(:render_with_timeout).and_raise(
        Sxn::Templates::Errors::TemplateTimeoutError, "Timeout"
      )

      expect do
        processor.process("{{ user.name }}", simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateTimeoutError, /Timeout/)
    end

    it "re-raises TemplateRenderError without wrapping" do
      # Mock render_with_timeout to raise render error
      allow(processor).to receive(:render_with_timeout).and_raise(
        Sxn::Templates::Errors::TemplateRenderError, "Render error"
      )

      expect do
        processor.process("{{ user.name }}", simple_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateRenderError, /Render error/)
    end
  end
end
