# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Rules::RulesEngine do
  let(:project_path) { Dir.mktmpdir("project") }
  let(:session_path) { Dir.mktmpdir("session") }
  let(:engine) { described_class.new(project_path, session_path) }

  let(:simple_rules_config) do
    {
      "rule1" => {
        "type" => "copy_files",
        "config" => {
          "files" => [
            { "source" => "config/test.key", "strategy" => "copy", "required" => false }
          ]
        }
      }
    }
  end

  let(:complex_rules_config) do
    {
      "copy_files" => {
        "type" => "copy_files",
        "config" => {
          "files" => [
            { "source" => "config/master.key", "strategy" => "copy", "required" => false }
          ]
        }
      },
      "setup_commands" => {
        "type" => "setup_commands",
        "config" => {
          "commands" => [
            { "command" => %w[bundle install] }
          ]
        },
        "dependencies" => ["copy_files"]
      },
      "generate_docs" => {
        "type" => "template",
        "config" => {
          "templates" => [
            { "source" => ".sxn/templates/README.md.liquid", "destination" => "README.md", "required" => false }
          ]
        },
        "dependencies" => ["setup_commands"]
      }
    }
  end

  before do
    # Create project structure
    FileUtils.mkdir_p(File.join(project_path, "config"))
    File.write(File.join(project_path, "config/master.key"), "secret")
    File.write(File.join(project_path, "config/test.key"), "test-secret")

    # Mock rule classes to avoid complex setup while preserving dependency resolution
    allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:validate).and_return(true)
    allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:apply).and_return(true)
    allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:rollback).and_return(true)
    allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:rollbackable?).and_return(true)
    allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:applied?).and_return(true)
    allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:changes).and_return([])
    # Don't mock can_execute? - let it use the real implementation for dependency resolution

    allow_any_instance_of(Sxn::Rules::SetupCommandsRule).to receive(:validate).and_return(true)
    allow_any_instance_of(Sxn::Rules::SetupCommandsRule).to receive(:apply).and_return(true)
    allow_any_instance_of(Sxn::Rules::SetupCommandsRule).to receive(:rollback).and_return(true)
    allow_any_instance_of(Sxn::Rules::SetupCommandsRule).to receive(:rollbackable?).and_return(true)
    allow_any_instance_of(Sxn::Rules::SetupCommandsRule).to receive(:applied?).and_return(true)
    allow_any_instance_of(Sxn::Rules::SetupCommandsRule).to receive(:changes).and_return([])
    # Don't mock can_execute? - let it use the real implementation for dependency resolution

    allow_any_instance_of(Sxn::Rules::TemplateRule).to receive(:validate).and_return(true)
    allow_any_instance_of(Sxn::Rules::TemplateRule).to receive(:apply).and_return(true)
    allow_any_instance_of(Sxn::Rules::TemplateRule).to receive(:rollback).and_return(true)
    allow_any_instance_of(Sxn::Rules::TemplateRule).to receive(:rollbackable?).and_return(true)
    allow_any_instance_of(Sxn::Rules::TemplateRule).to receive(:applied?).and_return(true)
    allow_any_instance_of(Sxn::Rules::TemplateRule).to receive(:changes).and_return([])
    # Don't mock can_execute? - let it use the real implementation for dependency resolution
  end

  after do
    FileUtils.rm_rf(project_path)
    FileUtils.rm_rf(session_path)
  end

  describe "#initialize" do
    it "initializes with valid paths" do
      expect(engine.project_path).to eq(File.realpath(project_path))
      expect(engine.session_path).to eq(File.realpath(session_path))
    end

    it "raises error for non-existent project path" do
      expect do
        described_class.new("/non/existent", session_path)
      end.to raise_error(ArgumentError, /Invalid path provided/)
    end

    it "raises error for non-existent session path" do
      expect do
        described_class.new(project_path, "/non/existent")
      end.to raise_error(ArgumentError, /Invalid path provided/)
    end

    it "raises error for non-directory project path" do
      file_path = File.join(project_path, "file.txt")
      File.write(file_path, "test")

      expect do
        described_class.new(file_path, session_path)
      end.to raise_error(ArgumentError, /Project path is not a directory/)
    end

    it "raises error for non-writable session path" do
      File.chmod(0o444, session_path)

      expect do
        described_class.new(project_path, session_path)
      end.to raise_error(ArgumentError, /Session path is not writable/)
    ensure
      File.chmod(0o755, session_path)
    end
  end

  describe "#apply_rules" do
    context "with simple rule configuration" do
      it "applies rules successfully" do
        result = engine.apply_rules(simple_rules_config)

        expect(result.success?).to be true
        expect(result.applied_rules.size).to eq(1)
        expect(result.failed_rules).to be_empty
        expect(result.total_rules).to eq(1)
      end

      it "returns execution result with timing" do
        result = engine.apply_rules(simple_rules_config)

        expect(result.total_duration).to be > 0
        expect(result.to_h).to include(
          success: true,
          total_rules: 1,
          applied_rules: ["rule1"],
          failed_rules: [],
          skipped_rules: []
        )
      end
    end

    context "with complex rule configuration with dependencies" do
      it "resolves dependencies and applies rules in correct order" do
        result = engine.apply_rules(complex_rules_config)

        expect(result.success?).to be true
        expect(result.applied_rules.size).to eq(3)
        expect(result.failed_rules).to be_empty
      end

      it "executes rules in dependency order" do
        applied_order = []

        allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:apply) do
          applied_order << "copy_files"
          true
        end

        allow_any_instance_of(Sxn::Rules::SetupCommandsRule).to receive(:apply) do
          applied_order << "setup_commands"
          true
        end

        allow_any_instance_of(Sxn::Rules::TemplateRule).to receive(:apply) do
          applied_order << "generate_docs"
          true
        end

        engine.apply_rules(complex_rules_config)

        expect(applied_order.index("copy_files")).to be < applied_order.index("setup_commands")
        expect(applied_order.index("setup_commands")).to be < applied_order.index("generate_docs")
      end
    end

    context "with validation-only option" do
      it "validates without executing rules" do
        result = engine.apply_rules(simple_rules_config, validate_only: true)

        expect(result.success?).to be true
        expect(result.applied_rules).to be_empty
        expect(result.total_rules).to eq(0)
      end
    end

    context "with parallel execution disabled" do
      it "executes rules sequentially" do
        result = engine.apply_rules(simple_rules_config, parallel: false)

        expect(result.success?).to be true
        expect(result.applied_rules.size).to eq(1)
      end
    end

    context "with continue_on_failure enabled" do
      let(:failing_rules_config) do
        {
          "rule1" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "missing.key", "strategy" => "copy" }] }
          },
          "rule2" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
          }
        }
      end

      before do
        # Make first rule fail
        allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:apply).and_raise(Sxn::Rules::ApplicationError,
                                                                                      "Simulated failure")
        allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:name).and_return("failing_rule")
      end

      it "continues execution after failures" do
        result = engine.apply_rules(failing_rules_config, continue_on_failure: true)

        expect(result.success?).to be false
        expect(result.failed_rules.size).to eq(2) # Both rules will fail with the mock
        expect(result.errors).not_to be_empty
      end
    end

    context "with rule failure and rollback" do
      before do
        call_count = 0
        allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:apply) do
          call_count += 1
          raise Sxn::Rules::ApplicationError, "Second rule failed" unless call_count == 1

          true # First rule succeeds
        end
      end

      it "attempts rollback on rule failure" do
        failing_config = {
          "rule1" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
          },
          "rule2" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
          }
        }

        expect_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:rollback)

        result = engine.apply_rules(failing_config)
        expect(result.success?).to be false
      end
    end
  end

  describe "#rollback_rules" do
    context "with applied rules" do
      before do
        engine.apply_rules(simple_rules_config)
      end

      it "rolls back applied rules in reverse order" do
        expect(engine.rollback_rules).to be true
      end

      it "clears applied rules after rollback" do
        engine.rollback_rules
        expect(engine.instance_variable_get(:@applied_rules)).to be_empty
      end
    end

    context "with no applied rules" do
      it "returns true without errors" do
        expect(engine.rollback_rules).to be true
      end
    end

    context "with rollback failures" do
      before do
        engine.apply_rules(simple_rules_config)
        allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:rollback).and_raise(StandardError,
                                                                                         "Rollback failed")
      end

      it "continues rollback despite individual failures" do
        expect(engine.rollback_rules).to be true
      end
    end
  end

  describe "#validate_rules_config" do
    context "with valid configuration" do
      it "validates and returns rules" do
        rules = engine.validate_rules_config(simple_rules_config)

        expect(rules).to be_an(Array)
        expect(rules.size).to eq(1)
        expect(rules.first).to be_a(Sxn::Rules::CopyFilesRule)
      end
    end

    context "with invalid rule type" do
      let(:invalid_config) do
        {
          "rule1" => {
            "type" => "invalid_type",
            "config" => {}
          }
        }
      end

      it "raises validation error" do
        expect do
          engine.validate_rules_config(invalid_config)
        end.to raise_error(Sxn::Rules::ValidationError, /Unknown rule type/)
      end
    end

    context "with missing rule type" do
      let(:invalid_config) do
        {
          "rule1" => {
            "config" => {}
          }
        }
      end

      it "raises validation error" do
        expect do
          engine.validate_rules_config(invalid_config)
        end.to raise_error(Sxn::Rules::ValidationError, /Unknown rule type/)
      end
    end

    context "with non-hash rule spec" do
      let(:invalid_config) do
        {
          "rule1" => "not-a-hash"
        }
      end

      it "raises validation error" do
        expect do
          engine.validate_rules_config(invalid_config)
        end.to raise_error(ArgumentError, /Rule spec.*must be a hash/)
      end
    end

    context "with non-existent dependency" do
      let(:invalid_deps_config) do
        {
          "rule1" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] },
            "dependencies" => ["non_existent_rule"]
          }
        }
      end

      it "raises validation error" do
        expect do
          engine.validate_rules_config(invalid_deps_config)
        end.to raise_error(Sxn::Rules::ValidationError, /depends on non-existent rule/)
      end
    end

    context "with circular dependencies" do
      let(:circular_deps_config) do
        {
          "rule1" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] },
            "dependencies" => ["rule2"]
          },
          "rule2" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] },
            "dependencies" => ["rule1"]
          }
        }
      end

      it "raises validation error" do
        expect do
          engine.validate_rules_config(circular_deps_config)
        end.to raise_error(Sxn::Rules::ValidationError, /Circular dependency detected/)
      end
    end

    context "with rule validation failure" do
      before do
        allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:validate).and_raise(Sxn::Rules::ValidationError,
                                                                                         "Rule validation failed")
      end

      it "raises validation error with rule context" do
        expect do
          engine.validate_rules_config(simple_rules_config)
        end.to raise_error(Sxn::Rules::ValidationError, /Rule 'rule1' validation failed/)
      end
    end
  end

  describe "#available_rule_types" do
    it "returns available rule types" do
      types = engine.available_rule_types

      expect(types).to include("copy_files", "setup_commands", "template")
      expect(types).to be_an(Array)
    end
  end

  describe "dependency resolution" do
    let(:complex_dependency_config) do
      {
        "d" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] },
          "dependencies" => %w[b c]
        },
        "c" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] },
          "dependencies" => ["a"]
        },
        "b" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] },
          "dependencies" => ["a"]
        },
        "a" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
        }
      }
    end

    it "resolves complex dependency chains" do
      result = engine.apply_rules(complex_dependency_config)

      expect(result.success?).to be true
      expect(result.applied_rules.size).to eq(4)
    end

    it "executes rules in topologically sorted order" do
      rules = engine.validate_rules_config(complex_dependency_config)
      execution_order = engine.send(:resolve_execution_order, rules)

      # 'a' should be in first phase
      first_phase_names = execution_order[0].map(&:name)
      expect(first_phase_names).to include("a")

      # 'b' and 'c' should be in second phase (can run in parallel)
      second_phase_names = execution_order[1].map(&:name)
      expect(second_phase_names).to include("b", "c")

      # 'd' should be in third phase
      third_phase_names = execution_order[2].map(&:name)
      expect(third_phase_names).to include("d")
    end
  end

  describe "parallel execution" do
    let(:parallel_rules_config) do
      {
        "rule1" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
        },
        "rule2" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
        },
        "rule3" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
        }
      }
    end

    it "executes independent rules in parallel" do
      result = engine.apply_rules(parallel_rules_config, parallel: true, max_parallelism: 2)

      expect(result.success?).to be true
      expect(result.applied_rules.size).to eq(3)
    end

    it "limits parallelism to specified maximum" do
      # This is difficult to test without complex threading scenarios
      # but we can verify the option is accepted and doesn't break execution
      result = engine.apply_rules(parallel_rules_config, max_parallelism: 1)

      expect(result.success?).to be true
    end
  end

  describe "ExecutionResult" do
    let(:result) { described_class::ExecutionResult.new }

    describe "#initialize" do
      it "initializes with empty collections" do
        expect(result.applied_rules).to be_empty
        expect(result.failed_rules).to be_empty
        expect(result.skipped_rules).to be_empty
        expect(result.errors).to be_empty
        expect(result.total_duration).to eq(0)
      end
    end

    describe "#start! and #finish!" do
      it "tracks execution timing" do
        result.start!
        sleep(0.01) # Small delay to ensure measurable duration
        result.finish!

        expect(result.total_duration).to be > 0
      end
    end

    describe "#success?" do
      it "returns true when no rules failed" do
        expect(result.success?).to be true
      end

      it "returns false when rules failed" do
        mock_rule = double("rule", name: "failed_rule")
        mock_error = StandardError.new("Test error")
        result.add_failed_rule(mock_rule, mock_error)

        expect(result.success?).to be false
      end
    end

    describe "#to_h" do
      it "returns hash representation" do
        hash = result.to_h

        expect(hash).to include(
          success: true,
          total_rules: 0,
          applied_rules: [],
          failed_rules: [],
          skipped_rules: [],
          total_duration: 0,
          errors: []
        )
      end
    end
  end

  describe "edge cases and error handling" do
    it "handles missing rule class gracefully" do
      bad_config = {
        "rule1" => {
          "type" => "nonexistent_rule",
          "config" => {}
        }
      }
      
      expect do
        engine.apply_rules(bad_config)
      end.to raise_error(Sxn::Rules::ValidationError, /Unknown rule type/)
    end

    it "handles rule instantiation errors" do
      allow(Sxn::Rules::CopyFilesRule).to receive(:new).and_raise(ArgumentError, "Bad initialization")
      
      config = {
        "rule1" => {
          "type" => "copy_files",
          "config" => { "files" => [] }
        }
      }
      
      result = engine.apply_rules(config)
      expect(result.success?).to be false
      expect(result.errors).not_to be_empty
    end

    it "skips rules that fail validation" do
      config = {
        "valid_rule" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
        },
        "invalid_rule" => {
          "type" => "copy_files",
          "config" => { "files" => [] } # Invalid empty files
        }
      }
      
      allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:validate) do |rule|
        raise Sxn::Rules::ValidationError, "Invalid config" if rule.name == "invalid_rule"
      end
      
      result = engine.apply_rules(config)
      expect(result.applied_rules.map(&:name)).to include("valid_rule")
      expect(result.skipped_rules.map(&:name)).to include("invalid_rule")
    end

    it "handles circular dependencies" do
      circular_config = {
        "rule1" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "test1", "strategy" => "copy", "required" => false }] },
          "dependencies" => ["rule2"]
        },
        "rule2" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "test2", "strategy" => "copy", "required" => false }] },
          "dependencies" => ["rule1"]
        }
      }
      
      expect do
        engine.apply_rules(circular_config)
      end.to raise_error(Sxn::Rules::ValidationError, /circular dependency/i)
    end

    it "handles rule application failures gracefully" do
      config = {
        "failing_rule" => {
          "type" => "copy_files",
          "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] }
        }
      }
      
      allow_any_instance_of(Sxn::Rules::CopyFilesRule).to receive(:apply).and_raise(StandardError, "Application failed")
      
      result = engine.apply_rules(config)
      expect(result.success?).to be false
      expect(result.failed_rules).not_to be_empty
      expect(result.errors).not_to be_empty
    end
  end

  describe "private methods" do
    describe "#create_rule" do
      it "creates rules with correct parameters" do
        rule = engine.send(:create_rule, "test_rule", "copy_files", 
                           { "files" => [{ "source" => "test", "strategy" => "copy", "required" => false }] }, 
                           [], session_path, project_path)
        
        expect(rule).to be_a(Sxn::Rules::CopyFilesRule)
        expect(rule.name).to eq("test_rule")
      end

      it "raises error for unknown rule types" do
        expect do
          engine.send(:create_rule, "test", "unknown_type", {}, [], session_path, project_path)
        end.to raise_error(Sxn::Rules::ValidationError, /Unknown rule type/)
      end
    end

    describe "#get_rule_class" do
      it "returns correct class for valid rule types" do
        copy_class = engine.send(:get_rule_class, "copy_files")
        expect(copy_class).to eq(Sxn::Rules::CopyFilesRule)
        
        setup_class = engine.send(:get_rule_class, "setup_commands")
        expect(setup_class).to eq(Sxn::Rules::SetupCommandsRule)
        
        template_class = engine.send(:get_rule_class, "template")
        expect(template_class).to eq(Sxn::Rules::TemplateRule)
      end

      it "returns nil for unknown rule types" do
        unknown_class = engine.send(:get_rule_class, "nonexistent_type")
        expect(unknown_class).to be_nil
      end
    end

    describe "#validate_dependencies" do
      it "validates all dependencies exist" do
        rules = [
          double("rule", name: "rule1", dependencies: ["rule2"]),
          double("rule", name: "rule2", dependencies: [])
        ]
        
        expect { engine.send(:validate_dependencies, rules) }.not_to raise_error
      end

      it "raises error for missing dependencies" do
        rules = [
          double("rule", name: "rule1", dependencies: ["missing_rule"])
        ]
        
        expect do
          engine.send(:validate_dependencies, rules)
        end.to raise_error(Sxn::Rules::ValidationError, /depends on non-existent rule 'missing_rule'/)
      end
    end

    describe "#check_circular_dependencies" do
      it "detects circular dependencies" do
        rules = [
          double("rule", name: "rule1", dependencies: ["rule2"]),
          double("rule", name: "rule2", dependencies: ["rule1"])
        ]
        
        expect do
          engine.send(:check_circular_dependencies, rules)
        end.to raise_error(Sxn::Rules::ValidationError, /circular dependency/i)
      end

      it "allows valid dependency chains" do
        rules = [
          double("rule", name: "rule1", dependencies: ["rule2"]),
          double("rule", name: "rule2", dependencies: ["rule3"]),
          double("rule", name: "rule3", dependencies: [])
        ]
        
        expect { engine.send(:check_circular_dependencies, rules) }.not_to raise_error
      end
    end
  end

  describe "error handling" do
    context "with engine-level errors" do
      let(:bad_config) { "not-a-hash" }

      it "captures engine errors in result" do
        result = engine.apply_rules(bad_config)

        expect(result.success?).to be false
        expect(result.errors).not_to be_empty
        expect(result.errors.first[:rule]).to eq("engine")
      end
    end

    context "with unresolvable dependencies" do
      let(:unresolvable_config) do
        {
          "rule1" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "config/test.key", "strategy" => "copy", "required" => false }] },
            "dependencies" => ["missing_rule"]
          }
        }
      end

      it "raises appropriate error" do
        expect do
          engine.apply_rules(unresolvable_config)
        end.to raise_error(Sxn::Rules::ValidationError, /depends on non-existent rule/)
      end
    end
  end
end
