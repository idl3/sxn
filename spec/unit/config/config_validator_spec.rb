# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Config::ConfigValidator do
  let(:validator) { described_class.new }

  describe "#valid?" do
    context "with valid configuration" do
      let(:valid_config) do
        {
          "version" => 1,
          "sessions_folder" => "atlas-one-sessions",
          "current_session" => "ATL-1234-feature",
          "projects" => {
            "atlas-core" => {
              "path" => "./atlas-core",
              "type" => "rails",
              "default_branch" => "master",
              "rules" => {
                "copy_files" => [
                  {
                    "source" => "config/master.key",
                    "strategy" => "copy",
                    "permissions" => 0o600
                  }
                ],
                "setup_commands" => [
                  {
                    "command" => %w[bundle install],
                    "environment" => { "RAILS_ENV" => "development" }
                  }
                ],
                "templates" => [
                  {
                    "source" => ".sxn/templates/CLAUDE.md",
                    "destination" => "CLAUDE.md",
                    "process" => true,
                    "engine" => "liquid"
                  }
                ]
              }
            }
          },
          "settings" => {
            "auto_cleanup" => true,
            "max_sessions" => 10,
            "worktree_cleanup_days" => 30,
            "default_rules" => {
              "templates" => []
            }
          }
        }
      end

      it "returns true" do
        expect(validator.valid?(valid_config)).to be true
      end

      it "has no errors" do
        validator.valid?(valid_config)
        expect(validator.errors).to be_empty
      end
    end

    context "with minimal valid configuration" do
      let(:minimal_config) do
        {
          "version" => 1,
          "sessions_folder" => "sessions",
          "projects" => {}
        }
      end

      it "returns true" do
        expect(validator.valid?(minimal_config)).to be true
      end
    end

    context "with invalid configuration" do
      context "when not a hash" do
        it "returns false for string" do
          expect(validator.valid?("invalid")).to be false
        end

        it "returns false for array" do
          expect(validator.valid?([])).to be false
        end

        it "has appropriate error message" do
          validator.valid?("invalid")
          expect(validator.errors).to include("Configuration must be a hash, got String")
        end
      end

      context "when missing required fields" do
        let(:incomplete_config) { {} }

        it "returns false" do
          expect(validator.valid?(incomplete_config)).to be false
        end

        it "reports missing required fields" do
          validator.valid?(incomplete_config)
          expect(validator.errors).to include(
            "Required field 'version' is missing or empty",
            "Required field 'sessions_folder' is missing or empty",
            "Required field 'projects' is missing or empty"
          )
        end
      end

      context "with invalid field types" do
        let(:invalid_types_config) do
          {
            "version" => "not_a_number",
            "sessions_folder" => 123,
            "projects" => "not_a_hash"
          }
        end

        it "returns false" do
          expect(validator.valid?(invalid_types_config)).to be false
        end

        it "reports type errors" do
          validator.valid?(invalid_types_config)
          expect(validator.errors).to include(
            "Field 'version' must be of type integer, got string",
            "Field 'sessions_folder' must be of type string, got integer",
            "Field 'projects' must be of type hash, got string"
          )
        end
      end

      context "with invalid constraints" do
        let(:constraint_violations_config) do
          {
            "version" => 0,
            "sessions_folder" => "",
            "projects" => {},
            "settings" => {
              "max_sessions" => 0,
              "worktree_cleanup_days" => 400
            }
          }
        end

        it "returns false" do
          expect(validator.valid?(constraint_violations_config)).to be false
        end

        it "reports constraint violations" do
          validator.valid?(constraint_violations_config)
          expect(validator.errors).to include(
            "Field 'version' must be at least 1",
            "Required field 'sessions_folder' is missing or empty",
            "Field 'settings.max_sessions' must be at least 1",
            "Field 'settings.worktree_cleanup_days' must be at most 365"
          )
        end
      end

      context "with invalid project configuration" do
        let(:invalid_project_config) do
          {
            "version" => 1,
            "sessions_folder" => "sessions",
            "projects" => {
              "test-project" => {
                "type" => "invalid_type",
                "package_manager" => "invalid_manager",
                "rules" => {
                  "copy_files" => [
                    {
                      "strategy" => "invalid_strategy",
                      "permissions" => 999
                    }
                  ],
                  "setup_commands" => [
                    {
                      "command" => "not_an_array",
                      "condition" => "invalid_condition"
                    }
                  ]
                }
              }
            }
          }
        end

        it "returns false" do
          expect(validator.valid?(invalid_project_config)).to be false
        end

        it "reports project-specific errors" do
          validator.valid?(invalid_project_config)
          expect(validator.errors).to include(
            "Required field 'projects.test-project.path' is missing or empty",
            "Field 'projects.test-project.type' must be one of: rails, ruby, javascript, typescript, react, nextjs, vue, angular, unknown",
            "Field 'projects.test-project.package_manager' must be one of: npm, yarn, pnpm",
            "Required field 'projects.test-project.rules.copy_files[0].source' is missing or empty",
            "Field 'projects.test-project.rules.copy_files[0].strategy' must be one of: copy, symlink",
            "Field 'projects.test-project.rules.copy_files[0].permissions' must be at most 511",
            "Field 'projects.test-project.rules.setup_commands[0].command' must be of type array, got string",
            "Field 'projects.test-project.rules.setup_commands[0].condition' must be one of: always, db_not_exists, file_not_exists"
          )
        end
      end
    end
  end

  describe "#validate_and_migrate" do
    context "with valid configuration" do
      let(:valid_config) do
        {
          "version" => 1,
          "sessions_folder" => "sessions",
          "projects" => {}
        }
      end

      it "returns the configuration with defaults applied" do
        result = validator.validate_and_migrate(valid_config)

        expect(result["settings"]["auto_cleanup"]).to be true
        expect(result["settings"]["max_sessions"]).to eq 10
        expect(result["settings"]["worktree_cleanup_days"]).to eq 30
      end
      
      it "handles try/rescue for default duplication" do
        # Test the dup rescue block in apply_defaults_recursive
        schema_with_unduplicatable = {
          "test_field" => {
            type: :hash,
            default: Object.new.freeze  # This can't be duped
          }
        }
        
        config = {}
        result = validator.send(:apply_defaults_recursive, config, schema_with_unduplicatable, config)
        
        expect(result["test_field"]).not_to be_nil
      end
    end

    context "with invalid configuration" do
      let(:invalid_config) do
        {
          "version" => "invalid",
          "sessions_folder" => "",
          "projects" => "invalid"
        }
      end

      it "raises ConfigurationError" do
        expect do
          validator.validate_and_migrate(invalid_config)
        end.to raise_error(Sxn::ConfigurationError, /Configuration validation failed/)
      end

      it "includes detailed error information" do
        validator.validate_and_migrate(invalid_config)
      rescue Sxn::ConfigurationError => e
        expect(e.message).to include("Field 'version' must be of type integer")
        expect(e.message).to include("Required field 'sessions_folder' is missing or empty")
        expect(e.message).to include("Field 'projects' must be of type hash")
      end
    end
  end

  describe "#migrate_config" do
    context "with version 0 configuration" do
      let(:v0_config) do
        {
          "sessions_folder" => "old-sessions",
          "auto_cleanup" => false,
          "max_sessions" => 5,
          "projects" => {
            "test-project" => {
              "rules" => {
                "copy_files" => ["config/master.key", ".env"],
                "setup_commands" => ["bundle install", "rails db:migrate"]
              }
            }
          }
        }
      end

      it "migrates to version 1" do
        result = validator.migrate_config(v0_config)

        expect(result["version"]).to eq 1
        expect(result["settings"]["auto_cleanup"]).to be false
        expect(result["settings"]["max_sessions"]).to eq 5
        expect(result["projects"]["test-project"]["path"]).to eq "./test-project"
      end

      it "migrates copy_files rules" do
        result = validator.migrate_config(v0_config)
        copy_files = result["projects"]["test-project"]["rules"]["copy_files"]

        expect(copy_files).to eq [
          { "source" => "config/master.key", "strategy" => "copy" },
          { "source" => ".env", "strategy" => "copy" }
        ]
      end

      it "migrates setup_commands rules" do
        result = validator.migrate_config(v0_config)
        setup_commands = result["projects"]["test-project"]["rules"]["setup_commands"]

        expect(setup_commands).to eq [
          { "command" => %w[bundle install] },
          { "command" => ["rails", "db:migrate"] }
        ]
      end
    end

    context "with current version configuration" do
      let(:current_config) do
        {
          "version" => 1,
          "sessions_folder" => "sessions",
          "projects" => {}
        }
      end

      it "returns unchanged configuration" do
        result = validator.migrate_config(current_config)
        expect(result).to eq current_config
      end
    end
  end

  describe "#format_errors" do
    context "with no errors" do
      it 'returns "No errors"' do
        expect(validator.format_errors).to eq "No errors"
      end
    end

    context "with errors" do
      before do
        validator.instance_variable_set(:@errors, [
                                          "First error",
                                          "Second error",
                                          "Third error"
                                        ])
      end

      it "returns formatted error list" do
        expected = "  1. First error\n  2. Second error\n  3. Third error"
        expect(validator.format_errors).to eq expected
      end
    end
  end

  describe "performance" do
    let(:large_config) do
      {
        "version" => 1,
        "sessions_folder" => "sessions",
        "projects" => (1..100).to_h do |i|
          [
            "project-#{i}",
            {
              "path" => "./project-#{i}",
              "type" => "rails",
              "rules" => {
                "copy_files" => [
                  { "source" => "config/master.key", "strategy" => "copy" },
                  { "source" => ".env", "strategy" => "symlink" }
                ],
                "setup_commands" => [
                  { "command" => %w[bundle install] },
                  { "command" => ["rails", "db:create"] }
                ],
                "templates" => [
                  {
                    "source" => ".sxn/templates/README.md",
                    "destination" => "README.md",
                    "process" => true
                  }
                ]
              }
            }
          ]
        end
      }
    end

    it "validates large configuration in reasonable time" do
      expect do
        validator.valid?(large_config)
      end.to perform_under(100).ms
    end

    it "validates and migrates large configuration in reasonable time" do
      expect do
        validator.validate_and_migrate(large_config)
      end.to perform_under(200).ms
    end
  end
  
  describe "migrate_rules_v0_to_v1" do
    it "migrates copy_files array of strings" do
      rules = { "copy_files" => ["file1.txt", "file2.txt"] }
      validator.send(:migrate_rules_v0_to_v1, rules)
      
      expect(rules["copy_files"]).to eq([
        { "source" => "file1.txt", "strategy" => "copy" },
        { "source" => "file2.txt", "strategy" => "copy" }
      ])
    end
    
    it "migrates setup_commands array of strings" do
      rules = { "setup_commands" => ["bundle install", "rails db:migrate"] }
      validator.send(:migrate_rules_v0_to_v1, rules)
      
      expect(rules["setup_commands"]).to eq([
        { "command" => ["bundle", "install"] },
        { "command" => ["rails", "db:migrate"] }
      ])
    end
    
    it "does not migrate if rules is not a hash" do
      rules = "not_a_hash"
      expect { validator.send(:migrate_rules_v0_to_v1, rules) }.not_to raise_error
    end
    
    it "does not migrate if copy_files is not an array" do
      rules = { "copy_files" => "not_an_array" }
      expect { validator.send(:migrate_rules_v0_to_v1, rules) }.not_to raise_error
    end
    
    it "does not migrate if setup_commands is not an array" do
      rules = { "setup_commands" => "not_an_array" }
      expect { validator.send(:migrate_rules_v0_to_v1, rules) }.not_to raise_error
    end
    
    it "preserves existing hash format in copy_files" do
      rules = {
        "copy_files" => [
          { "source" => "existing.txt", "strategy" => "symlink" },
          "new_file.txt"
        ]
      }
      validator.send(:migrate_rules_v0_to_v1, rules)
      
      expect(rules["copy_files"]).to eq([
        { "source" => "existing.txt", "strategy" => "symlink" },
        { "source" => "new_file.txt", "strategy" => "copy" }
      ])
    end
  end
  
  describe "private methods" do
    describe "#needs_v0_to_v1_migration?" do
      it "returns false for non-hash config" do
        result = validator.send(:needs_v0_to_v1_migration?, "not_a_hash")
        expect(result).to be false
      end
      
      it "returns false when projects is not a hash" do
        config = { "projects" => "not_a_hash" }
        result = validator.send(:needs_v0_to_v1_migration?, config)
        expect(result).to be false
      end
      
      it "returns true when project has missing path" do
        config = {
          "projects" => {
            "test-project" => {
              "type" => "rails"
              # missing path
            }
          }
        }
        result = validator.send(:needs_v0_to_v1_migration?, config)
        expect(result).to be true
      end
      
      it "returns true when project has empty path" do
        config = {
          "projects" => {
            "test-project" => {
              "path" => "",
              "type" => "rails"
            }
          }
        }
        result = validator.send(:needs_v0_to_v1_migration?, config)
        expect(result).to be true
      end
      
      it "returns false when all projects have paths" do
        config = {
          "projects" => {
            "test-project" => {
              "path" => "./test",
              "type" => "rails"
            }
          }
        }
        result = validator.send(:needs_v0_to_v1_migration?, config)
        expect(result).to be false
      end
    end
    
    describe "#value_has_correct_type?" do
      it "validates string type" do
        expect(validator.send(:value_has_correct_type?, "test", { type: :string })).to be true
        expect(validator.send(:value_has_correct_type?, 123, { type: :string })).to be false
      end
      
      it "validates integer type" do
        expect(validator.send(:value_has_correct_type?, 123, { type: :integer })).to be true
        expect(validator.send(:value_has_correct_type?, "123", { type: :integer })).to be false
      end
      
      it "validates boolean type" do
        expect(validator.send(:value_has_correct_type?, true, { type: :boolean })).to be true
        expect(validator.send(:value_has_correct_type?, false, { type: :boolean })).to be true
        expect(validator.send(:value_has_correct_type?, "true", { type: :boolean })).to be false
      end
      
      it "validates array type" do
        expect(validator.send(:value_has_correct_type?, [], { type: :array })).to be true
        expect(validator.send(:value_has_correct_type?, {}, { type: :array })).to be false
      end
      
      it "validates hash type" do
        expect(validator.send(:value_has_correct_type?, {}, { type: :hash })).to be true
        expect(validator.send(:value_has_correct_type?, [], { type: :hash })).to be false
      end
      
      it "returns false for unknown types" do
        expect(validator.send(:value_has_correct_type?, "test", { type: :unknown })).to be false
      end
      
      it "returns true when no type specified" do
        expect(validator.send(:value_has_correct_type?, "test", {})).to be true
      end
    end
    
    describe "edge cases in validation" do
      it "handles array constraint validation" do
        config = {
          "version" => 1,
          "sessions_folder" => "test",
          "projects" => {
            "test" => {
              "path" => "./test",
              "rules" => {
                "copy_files" => []
              }
            }
          }
        }
        
        expect(validator.valid?(config)).to be true
      end
      
      it "validates max_length constraint for strings" do
        # This would need to be added to schema to test properly
        # Testing the method directly
        validator.instance_variable_set(:@errors, [])
        validator.send(:validate_field_constraints, "x" * 1000, { max_length: 10 }, "test_field")
        expect(validator.errors).to include("Field 'test_field' must be at most 10 characters long")
      end
      
      it "validates max_length constraint for arrays" do
        validator.instance_variable_set(:@errors, [])
        validator.send(:validate_field_constraints, [1, 2, 3, 4, 5], { max_length: 3 }, "test_array")
        expect(validator.errors).to include("Field 'test_array' must have at most 3 items")
      end
    end
  end
end
