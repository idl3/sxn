# frozen_string_literal: true

require "spec_helper"
require "ostruct"

RSpec.describe Sxn::Templates::TemplateSecurity do
  let(:security) { described_class.new }
  let(:safe_variables) do
    {
      session: { name: "test-session", path: "/tmp/test" },
      git: { branch: "main", author: "John Doe" },
      user: { name: "Safe User" }
    }
  end

  describe "#validate_template" do
    context "with safe templates" do
      it "validates simple variable substitution" do
        template = "Hello {{user.name}} on {{git.branch}}"

        expect do
          security.validate_template(template, safe_variables)
        end.not_to raise_error

        expect(security.validate_template(template, safe_variables)).to be true
      end

      it "validates templates with loops and conditionals" do
        template = <<~LIQUID
          {% if session.name %}
            Session: {{session.name}}
            {% for item in session.items %}
              - {{item}}
            {% endfor %}
          {% endif %}
        LIQUID

        expect do
          security.validate_template(template, safe_variables)
        end.not_to raise_error
      end

      it "validates templates with safe filters" do
        described_class::SAFE_FILTERS.each do |filter|
          template = "{{user.name | #{filter}}}"

          expect do
            security.validate_template(template, safe_variables)
          end.not_to raise_error, "Filter #{filter} should be safe"
        end
      end
    end

    context "with dangerous patterns" do
      it "rejects templates with eval patterns" do
        dangerous_templates = [
          "{{user.name | eval}}",
          "{% eval user.code %}",
          "{{ system('rm -rf /') }}",
          "{% exec 'dangerous command' %}",
          "<script>alert('xss')</script>",
          "javascript:alert('xss')",
          "{{ File.read('/etc/passwd') }}",
          "{{ Process.spawn('ls') }}"
        ]

        dangerous_templates.each do |template|
          expect do
            security.validate_template(template, safe_variables)
          end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError),
                 "Template should be rejected: #{template}"
        end
      end

      it "rejects templates with path traversal" do
        dangerous_templates = [
          "{{ '../../../etc/passwd' }}",
          "{% include '../secret.txt' %}",
          "{{ '..\\..\\windows\\system32' }}"
        ]

        dangerous_templates.each do |template|
          expect do
            security.validate_template(template, safe_variables)
          end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError),
                 "Template should be rejected: #{template}"
        end
      end

      it "rejects templates with file system access" do
        dangerous_templates = [
          "{{ file.read('/etc/passwd') }}",
          "{% write_file 'secret.txt' %}",
          "{{ delete('/important/file') }}"
        ]

        dangerous_templates.each do |template|
          expect do
            security.validate_template(template, safe_variables)
          end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError),
                 "Template should be rejected: #{template}"
        end
      end

      it "rejects templates with excessive nesting" do
        deep_template = ""
        (described_class::MAX_TEMPLATE_DEPTH + 1).times do |i|
          deep_template += "{% if condition#{i} %}"
        end
        deep_template += "content"
        (described_class::MAX_TEMPLATE_DEPTH + 1).times do
          deep_template += "{% endif %}"
        end

        expect do
          security.validate_template(deep_template, safe_variables)
        end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError, /nesting too deep/)
      end
    end

    context "with caching" do
      it "caches validation results" do
        template = "Hello {{user.name}}"

        # Mock the validation to track all calls
        allow(security).to receive(:validate_template_content).and_call_original

        # First validation
        first_result = security.validate_template(template, safe_variables)

        # Second validation should use cache
        second_result = security.validate_template(template, safe_variables)

        expect(first_result).to eq(second_result)
        expect(security).to have_received(:validate_template_content).once
      end

      it "can clear validation cache" do
        template = "Hello {{user.name}}"

        security.validate_template(template, safe_variables)
        security.clear_cache!

        # After clearing cache, validation should run again
        allow(security).to receive(:validate_template_content).and_call_original
        security.validate_template(template, safe_variables)

        expect(security).to have_received(:validate_template_content)
      end
    end
  end

  describe "#sanitize_variables" do
    it "sanitizes variable keys" do
      dangerous_variables = {
        "key with spaces" => "value1",
        "key-with-dashes" => "value2",
        "key.with.dots" => "value3",
        "key/with/slashes" => "value4"
      }

      sanitized = security.sanitize_variables(dangerous_variables)

      expect(sanitized).to have_key("key_with_spaces")
      expect(sanitized).to have_key("key_with_dashes")
      expect(sanitized).to have_key("key_with_dots")
      expect(sanitized).to have_key("key_with_slashes")
    end

    it "filters variables by allowed namespaces" do
      mixed_variables = {
        session: { name: "test" },  # allowed
        git: { branch: "main" },    # allowed
        dangerous: { code: "evil" }, # not in ALLOWED_VARIABLE_NAMESPACES
        system: { path: "/bin" }     # not in ALLOWED_VARIABLE_NAMESPACES
      }

      sanitized = security.sanitize_variables(mixed_variables)

      expect(sanitized).to have_key("session")
      expect(sanitized).to have_key("git")
      expect(sanitized).not_to have_key("dangerous")
      expect(sanitized).not_to have_key("system")
    end

    it "sanitizes string values" do
      dangerous_variables = {
        user: {
          script: "<script>alert('xss')</script>Clean text",
          command: "echo 'test'; rm -rf /",
          html: "<div onclick='evil()'>Content</div>"
        }
      }

      sanitized = security.sanitize_variables(dangerous_variables)

      expect(sanitized["user"]["script"]).not_to include("<script>")
      expect(sanitized["user"]["script"]).to include("Clean text")
      expect(sanitized["user"]["command"]).not_to include(";")
      expect(sanitized["user"]["html"]).not_to include("<div")
      expect(sanitized["user"]["html"]).to include("Content")
    end

    it "handles nested variable structures" do
      nested_variables = {
        session: {
          worktrees: [
            { name: "core", path: "/tmp/core" },
            { name: "frontend", path: "/tmp/frontend" }
          ],
          metadata: {
            tags: %w[feature urgent],
            config: { auto_cleanup: true }
          }
        }
      }

      sanitized = security.sanitize_variables(nested_variables)

      expect(sanitized["session"]["worktrees"]).to be_an(Array)
      expect(sanitized["session"]["worktrees"].first["name"]).to eq("core")
      expect(sanitized["session"]["metadata"]["tags"]).to eq(%w[feature urgent])
      expect(sanitized["session"]["metadata"]["config"]["auto_cleanup"]).to be true
    end

    it "converts various data types safely" do
      mixed_variables = {
        user: {
          name: "string",
          age: 25,
          active: true,
          inactive: false,
          missing: nil,
          symbol: :symbol_value,
          time: Time.parse("2025-01-16 10:00:00 UTC"),
          custom: OpenStruct.new(value: "custom")
        }
      }

      sanitized = security.sanitize_variables(mixed_variables)

      expect(sanitized["user"]["name"]).to eq("string")
      expect(sanitized["user"]["age"]).to eq(25)
      expect(sanitized["user"]["active"]).to be true
      expect(sanitized["user"]["inactive"]).to be false
      expect(sanitized["user"]["missing"]).to be nil
      expect(sanitized["user"]["symbol"]).to eq("symbol_value")
      expect(sanitized["user"]["time"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
      expect(sanitized["user"]["custom"]).to be_a(String)
    end

    it "limits variable depth" do
      deep_variables = { user: {} }
      current = deep_variables[:user]

      # Create a structure deeper than MAX_TEMPLATE_DEPTH
      (described_class::MAX_TEMPLATE_DEPTH + 2).times do |i|
        current[:level] = { data: "level_#{i}" }
        current = current[:level]
      end

      sanitized = security.sanitize_variables(deep_variables)

      # Should truncate at max depth
      current = sanitized["user"]
      described_class::MAX_TEMPLATE_DEPTH.times do
        expect(current).to have_key("level")
        current = current["level"]
      end

      # Should not have more levels beyond max depth
      expect(current).to be_nil
    end

    it "limits total variable count" do
      # Create more variables than allowed
      large_variables = {}
      (described_class::MAX_VARIABLE_COUNT + 10).times do |i|
        large_variables["var_#{i}"] = "value_#{i}"
      end

      expect do
        security.sanitize_variables(large_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError, /too many variables/i)
    end

    it "truncates overly long strings" do
      long_string = "x" * 20_000
      variables = { user: { long_text: long_string } }

      sanitized = security.sanitize_variables(variables)

      expect(sanitized["user"]["long_text"].length).to be <= 10_000
    end
  end

  describe "#safe_filter?" do
    it "returns true for whitelisted filters" do
      described_class::SAFE_FILTERS.each do |filter|
        expect(security.safe_filter?(filter)).to be true
      end
    end

    it "returns false for non-whitelisted filters" do
      dangerous_filters = %w[eval exec system file_read custom_dangerous]

      dangerous_filters.each do |filter|
        expect(security.safe_filter?(filter)).to be false
      end
    end

    it "caches security errors for invalid templates" do
      dangerous_template = "{{ File.read('/etc/passwd') }}"

      # Mock the validation to track calls
      allow(security).to receive(:validate_template_content).and_call_original

      # First validation should cache the error
      expect do
        security.validate_template(dangerous_template, safe_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError)

      # Second validation should use cached result without calling validate_template_content again
      expect do
        security.validate_template(dangerous_template, safe_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError)

      # Should only call validate_template_content once due to caching
      expect(security).to have_received(:validate_template_content).once
    end

    it "handles symbol input" do
      expect(security.safe_filter?(:upcase)).to be true
      expect(security.safe_filter?(:dangerous)).to be false
    end
  end

  describe "variable validation" do
    it "validates safe variable keys" do
      safe_keys = %w[user session_name git_branch valid_123]

      safe_keys.each do |key|
        expect do
          security.send(:validate_variable_key, key)
        end.not_to raise_error, "Key #{key} should be valid"
      end
    end

    it "rejects dangerous variable keys" do
      dangerous_keys = %w[class module def end eval system]

      dangerous_keys.each do |key|
        expect do
          security.send(:validate_variable_key, key)
        end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError),
               "Key #{key} should be rejected"
      end
    end

    it "rejects keys with special characters" do
      dangerous_keys = ["key with spaces", "key-with-dashes", "key.with.dots", "key/slash"]

      dangerous_keys.each do |key|
        expect do
          security.send(:validate_variable_key, key)
        end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError),
               "Key #{key} should be rejected"
      end
    end
  end

  describe "string validation" do
    it "validates safe strings" do
      safe_strings = ["normal text", "text with numbers 123", "text-with-dashes"]

      safe_strings.each do |str|
        expect do
          security.send(:validate_string_value, str)
        end.not_to raise_error, "String #{str} should be valid"
      end
    end

    it "rejects strings with script tags" do
      dangerous_strings = [
        "<script>alert('xss')</script>",
        "<SCRIPT>alert('xss')</SCRIPT>",
        "<script src='evil.js'></script>"
      ]

      dangerous_strings.each do |str|
        expect do
          security.send(:validate_string_value, str)
        end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError),
               "String should be rejected: #{str}"
      end
    end

    it "rejects strings with command injection characters" do
      dangerous_strings = [
        "text; rm -rf /",
        "text && evil_command",
        "text | dangerous",
        "text `backtick`",
        "text $ENV_VAR"
      ]

      dangerous_strings.each do |str|
        expect do
          security.send(:validate_string_value, str)
        end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError),
               "String should be rejected: #{str}"
      end
    end
  end

  describe "performance" do
    it "handles large variable sets efficiently" do
      large_variables = {}
      1000.times do |i|
        large_variables["var_#{i}"] = {
          name: "value_#{i}",
          index: i,
          tags: %w[tag1 tag2 tag3]
        }
      end

      start_time = Time.now

      # Too many variables
      expect do
        security.sanitize_variables(large_variables)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError)

      elapsed = Time.now - start_time
      expect(elapsed).to be < 5.0 # Should fail within reasonable time
    end

    it "caches validation results for performance" do
      template = "Hello {{user.name}}"
      variables = { user: { name: "test" } }

      # First validation
      start_time = Time.now
      security.validate_template(template, variables)
      first_time = Time.now - start_time

      # Second validation (cached)
      start_time = Time.now
      security.validate_template(template, variables)
      second_time = Time.now - start_time

      # Cached call should be significantly faster
      expect(second_time).to be < first_time
    end
  end

  describe "edge cases" do
    it "handles empty templates" do
      expect do
        security.validate_template("", safe_variables)
      end.not_to raise_error
    end

    it "handles templates with only whitespace" do
      expect do
        security.validate_template("   \n\t  ", safe_variables)
      end.not_to raise_error
    end

    it "handles empty variable sets" do
      expect do
        security.validate_template("No variables here", {})
      end.not_to raise_error

      sanitized = security.sanitize_variables({})
      expect(sanitized).to eq({})
    end

    it "handles nil values in variables" do
      variables_with_nils = {
        user: {
          name: "test",
          missing: nil,
          empty: "",
          nested: { also_nil: nil }
        }
      }

      expect do
        sanitized = security.sanitize_variables(variables_with_nils)
        expect(sanitized["user"]["missing"]).to be nil
        expect(sanitized["user"]["empty"]).to eq("")
        expect(sanitized["user"]["nested"]["also_nil"]).to be nil
      end.not_to raise_error
    end
  end

  describe "#validate_template_path" do
    let(:temp_file) { File.join(Dir.tmpdir, "test_template.liquid") }

    before do
      File.write(temp_file, "Hello {{ user.name }}")
    end

    after do
      FileUtils.rm_f(temp_file)
    end

    it "validates safe template paths" do
      expect do
        security.validate_template_path(temp_file)
      end.not_to raise_error
    end

    it "rejects paths with traversal attempts" do
      dangerous_path = "../../../etc/passwd"
      expect do
        security.validate_template_path(dangerous_path)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError, /not accessible/)
    end

    it "rejects paths with tilde expansion" do
      dangerous_path = "~/secret_file"
      expect do
        security.validate_template_path(dangerous_path)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError, /not accessible/)
    end

    it "rejects non-existent paths" do
      non_existent = "/path/that/does/not/exist"
      expect do
        security.validate_template_path(non_existent)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError, /not accessible/)
    end

    it "rejects unreadable paths" do
      # Create file and make it unreadable
      unreadable_file = File.join(Dir.tmpdir, "unreadable.liquid")
      File.write(unreadable_file, "content")
      File.chmod(0o000, unreadable_file)

      expect do
        security.validate_template_path(unreadable_file)
      end.to raise_error(Sxn::Templates::Errors::TemplateSecurityError, /not accessible/)
    ensure
      File.chmod(0o644, unreadable_file) if File.exist?(unreadable_file)
      FileUtils.rm_f(unreadable_file)
    end
  end

  describe "template complexity validation" do
    it "handles elsif/else/when tags correctly" do
      complex_template = <<~LIQUID
        {% if condition1 %}
          Content 1
        {% elsif condition2 %}
          Content 2
        {% else %}
          Default content
        {% endif %}

        {% case variable %}
        {% when 'value1' %}
          Case 1
        {% when 'value2' %}
          Case 2
        {% endcase %}
      LIQUID

      expect do
        security.validate_template(complex_template, safe_variables)
      end.not_to raise_error
    end

    it "correctly tracks nesting depth with mixed tags" do
      nested_template = <<~LIQUID
        {% if outer %}
          {% for item in items %}
            {% if inner %}
              {% case item.type %}
              {% when 'special' %}
                Special content
              {% endcase %}
            {% endif %}
          {% endfor %}
        {% endif %}
      LIQUID

      expect do
        security.validate_template(nested_template, safe_variables)
      end.not_to raise_error
    end
  end

  describe "sanitization edge cases" do
    it "handles Date objects in variables" do
      require "date"
      variables_with_date = {
        user: {
          created_at: Date.today,
          updated_at: Time.now
        }
      }

      sanitized = security.sanitize_variables(variables_with_date)

      # Date.today gets converted to ISO8601 string format
      expect(sanitized["user"]["created_at"]).to match(/\d{4}-\d{2}-\d{2}/)
      expect(sanitized["user"]["updated_at"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+Z]/) # Handle both Z and timezone offset
    end

    it "handles variables with short keys" do
      short_key_variables = {
        "id" => 123,        # 2 chars - should pass namespace check
        "key" => "value",   # 3 chars - should pass namespace check
        "name" => "test"    # 4 chars - but may be filtered by namespace check
      }

      sanitized = security.sanitize_variables(short_key_variables)

      expect(sanitized).to have_key("id")
      expect(sanitized).to have_key("key")
      # 'name' has 4 chars so it might be filtered depending on namespace logic
    end

    it "processes variables with array containing hashes" do
      complex_variables = {
        session: {
          items: [
            { name: "item1", type: "file" },
            { name: "item2", type: "directory" },
            "string_item",
            123
          ]
        }
      }

      sanitized = security.sanitize_variables(complex_variables)

      items = sanitized["session"]["items"]
      expect(items[0]["name"]).to eq("item1")
      expect(items[1]["type"]).to eq("directory")
      expect(items[2]).to eq("string_item")
      expect(items[3]).to eq(123)
    end
  end
end
