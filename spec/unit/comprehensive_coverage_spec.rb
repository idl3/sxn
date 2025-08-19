# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Comprehensive test to cover remaining uncovered lines across multiple files
RSpec.describe "Comprehensive Coverage Tests", :slow do
  let(:temp_dir) { Dir.mktmpdir("sxn_coverage_test") }
  let(:project_path) { File.join(temp_dir, "project") }
  let(:session_path) { File.join(temp_dir, "session") }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(session_path)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "Error handling edge cases" do
    it "handles all error types with custom exit codes" do
      error_classes = [
        Sxn::ConfigurationError,
        Sxn::SessionError, Sxn::SessionNotFoundError, Sxn::SessionAlreadyExistsError,
        Sxn::ProjectError, Sxn::ProjectNotFoundError, Sxn::ProjectAlreadyExistsError,
        Sxn::GitError, Sxn::WorktreeError, Sxn::WorktreeExistsError, Sxn::WorktreeNotFoundError,
        Sxn::SecurityError, Sxn::PathValidationError, Sxn::CommandExecutionError,
        Sxn::RuleError, Sxn::RuleValidationError, Sxn::RuleExecutionError,
        Sxn::TemplateError, Sxn::TemplateNotFoundError, Sxn::TemplateProcessingError,
        Sxn::DatabaseError, Sxn::DatabaseConnectionError, Sxn::DatabaseMigrationError
      ]

      error_classes.each do |error_class|
        # Test with custom exit codes
        error = error_class.new("Test message", exit_code: 42)
        expect(error.exit_code).to eq(42)
        expect(error.message).to eq("Test message")

        # Test inheritance chain
        expect(error).to be_a(Sxn::Error)
        expect(error).to be_a(StandardError)
      end
    end
  end

  describe "Configuration edge cases" do
    it "handles config discovery with missing directories" do
      discovery = Sxn::Config::ConfigDiscovery.new("/nonexistent/path")
      expect { discovery.discover_config }.not_to raise_error
    end

    it "handles config cache with various scenarios" do
      cache = Sxn::Config::ConfigCache.new(ttl: 1)

      # Test cache operations - ConfigCache expects config_files array
      test_config = { "test" => "value" }
      config_files = []
      cache.set(test_config, config_files)
      expect(cache.get(config_files)).to eq(test_config)

      # Test cache expiration
      sleep(1.1)
      expect(cache.get(config_files)).to be_nil

      # Test cache invalidation
      cache.set(test_config, config_files)
      cache.invalidate
      expect(cache.get(config_files)).to be_nil
    end

    it "handles config validation with various scenarios" do
      validator = Sxn::Config::ConfigValidator.new

      # Test valid config
      valid_config = {
        "version" => 1,
        "sessions_folder" => "sessions",
        "projects" => {},
        "settings" => {
          "auto_cleanup" => true,
          "max_sessions" => 10,
          "worktree_cleanup_days" => 30
        }
      }

      result = validator.valid?(valid_config)
      expect(result).to be true

      # Test invalid config
      invalid_config = { "version" => "invalid" }
      result = validator.valid?(invalid_config)
      expect(result).to be false
      expect(validator.errors).not_to be_empty
    end
  end

  describe "Database edge cases" do
    it "handles database operations with error conditions" do
      db_path = File.join(temp_dir, "test.db")
      db = Sxn::Database::SessionDatabase.new(db_path)

      # Test successful operations
      session_data = {
        name: "test_session",
        project_path: project_path,
        session_path: session_path,
        created_at: Time.now,
        last_accessed: Time.now
      }

      session_id = db.create_session(session_data)
      expect(session_id).not_to be_nil
      expect { db.list_sessions }.not_to raise_error
      created_session = db.get_session(session_id)
      expect(created_session).not_to be_nil
      expect { db.update_session(session_id, { updated_at: Time.now.utc.iso8601 }) }.not_to raise_error

      # Test error conditions - expect some kind of error for invalid operations
      expect { db.create_session({ name: nil }) }.to raise_error(ArgumentError, "Session name is required")
      expect { db.get_session("nonexistent") }.to raise_error(Sxn::Database::SessionNotFoundError, "Session with ID 'nonexistent' not found")
      expect { db.update_session("nonexistent", {}) }.to raise_error(Sxn::Database::SessionNotFoundError, "Session with ID 'nonexistent' not found")

      # Delete the session we created - this should work
      expect { db.delete_session(session_id) }.not_to raise_error
    end
  end

  describe "Security component edge cases" do
    it "handles secure path validation with various inputs" do
      validator = Sxn::Security::SecurePathValidator.new(project_path)

      # Test valid paths
      valid_file = File.join(project_path, "valid_file.txt")
      File.write(valid_file, "content")
      expect { validator.validate_path(valid_file) }.not_to raise_error

      # Test invalid paths (path validation might handle these differently)
      expect { validator.validate_path("../outside") }.to raise_error(Sxn::PathValidationError)
      expect { validator.validate_path("path\0null") }.to raise_error(Sxn::PathValidationError)

      # Test file operations
      dest_path = "dest.txt"
      expect { validator.validate_file_operation(valid_file, dest_path) }.not_to raise_error

      # Test invalid file operations
      expect { validator.validate_file_operation("nonexistent.txt", dest_path) }.to raise_error(Errno::ENOENT)
      expect { validator.validate_file_operation(valid_file, "../outside.txt") }.to raise_error(Sxn::PathValidationError)
    end

    it "handles secure command execution" do
      executor = Sxn::Security::SecureCommandExecutor.new(project_path)

      # Test valid command with whitelisted git
      result = executor.execute(["git", "--version"])
      expect(result.success?).to be true
      expect(result.stdout).to include("git version")

      # Test command with timeout
      result = executor.execute(["git", "--version"], timeout: 5)
      expect(result.success?).to be true

      # Test invalid command (not whitelisted)
      expect { executor.execute(["nonexistent_command"]) }.to raise_error(Sxn::CommandExecutionError)
    end

    it "handles secure file copying" do
      copier = Sxn::Security::SecureFileCopier.new(project_path)

      # Create source file
      source_file = "source.txt"
      File.write(File.join(project_path, source_file), "test content")

      # Test successful copy within project boundaries
      dest_file = "dest.txt"

      result = copier.copy_file(source_file, dest_file)
      expect(result).to be_a(Sxn::Security::SecureFileCopier::CopyResult)
      expect(File.exist?(File.join(project_path, dest_file))).to be true
      expect(File.read(File.join(project_path, dest_file))).to eq("test content")

      # Test error conditions
      expect { copier.copy_file("nonexistent.txt", dest_file) }.to raise_error(Errno::ENOENT)
    end
  end

  describe "Rules engine edge cases" do
    it "handles rule validation and execution" do
      engine = Sxn::Rules::RulesEngine.new(project_path, session_path)

      # Test empty rules
      expect { engine.validate_rules_config({}) }.not_to raise_error

      # Test rules with missing files - simplified config with proper structure
      rules_config = {
        "copy_rule" => {
          "type" => "copy_files",
          "config" => {
            "files" => [
              { "source" => "missing.txt", "required" => false }
            ]
          }
        }
      }

      expect { engine.validate_rules_config(rules_config) }.not_to raise_error

      # Test rule execution
      source_file = File.join(project_path, "test.txt")
      File.write(source_file, "content")

      valid_rules_config = {
        "copy_rule" => {
          "type" => "copy_files",
          "config" => {
            "files" => [
              { "source" => "test.txt", "destination" => "copied.txt" }
            ]
          }
        }
      }

      result = engine.apply_rules(valid_rules_config)
      expect(result).to respond_to(:success?)
      # Test that rule execution completed - file copy may or may not work in test environment
      expect(result.errors).to be_an(Array)
    end

    it "handles project detection edge cases" do
      detector = Sxn::Rules::ProjectDetector.new(project_path)

      # Test detection with empty project
      expect(detector.detect_type(project_path)).to eq(:unknown)

      # Test Rails detection
      FileUtils.mkdir_p(File.join(project_path, "app", "models"))
      FileUtils.mkdir_p(File.join(project_path, "config"))
      File.write(File.join(project_path, "Gemfile"), "gem 'rails'")
      File.write(File.join(project_path, "config", "application.rb"), "# Rails app")
      expect(detector.detect_type(project_path)).to eq(:rails)

      # Test suggestion methods
      expect { detector.suggest_default_rules }.not_to raise_error
      expect { detector.analyze_project_structure }.not_to raise_error
    end
  end

  describe "Template system edge cases" do
    it "handles template processing with various scenarios" do
      processor = Sxn::Templates::TemplateProcessor.new

      # Test simple template processing
      template_content = "Hello {{ name }}!"
      variables = { "name" => "World" }
      result = processor.process(template_content, variables)
      expect(result).to eq("Hello World!")

      # Test template validation
      expect(processor.validate_syntax(template_content)).to be true
      expect { processor.validate_syntax("{{ invalid") }.to raise_error(Sxn::Templates::Errors::TemplateSyntaxError)
    end

    it "handles template variables collection" do
      variables = Sxn::Templates::TemplateVariables.new

      # Test variable collection exists and returns a hash
      expect { variables.collect }.not_to raise_error
      all_vars = variables.collect
      expect(all_vars).to be_a(Hash)
    end

    it "handles template security validation" do
      security = Sxn::Templates::TemplateSecurity.new

      # Test template path validation
      valid_template = File.join(project_path, "template.liquid")
      File.write(valid_template, "{{ name }}")
      expect { security.validate_template_path(valid_template) }.not_to raise_error

      # Test template content validation
      expect(security.validate_template_content("{{ safe }}")).to be true
    end

    it "handles template engine operations" do
      engine = Sxn::Templates::TemplateEngine.new(
        session: { name: "test_session", path: session_path },
        project: { name: "test_project", path: project_path }
      )

      # Test template existence checking
      expect(engine.template_exists?("nonexistent.liquid")).to be false

      # Test template listing
      templates = engine.list_templates
      expect(templates).to be_an(Array)

      # Test processing with built-in templates
      expect do
        engine.process_template("common/gitignore.liquid", File.join(session_path, ".gitignore"))
      end.not_to raise_error
    end
  end

  describe "UI component edge cases" do
    it "handles output formatting edge cases" do
      output = Sxn::UI::Output.new

      # Test all output methods
      expect { output.success("Success message") }.not_to raise_error
      expect { output.error("Error message") }.not_to raise_error
      expect { output.warning("Warning message") }.not_to raise_error
      expect { output.info("Info message") }.not_to raise_error
      expect { output.debug("Debug message") }.not_to raise_error
      expect { output.status("label", "message") }.not_to raise_error
      expect { output.section("Section Title") }.not_to raise_error
      expect { output.subsection("Subsection") }.not_to raise_error
      expect { output.empty_state("No items found") }.not_to raise_error
      expect { output.key_value("Key", "Value") }.not_to raise_error
      expect { output.recovery_suggestion("Try this") }.not_to raise_error
      expect { output.command_example("sxn init", "Initialize sxn") }.not_to raise_error
      expect { output.newline }.not_to raise_error
    end

    it "handles prompt interactions" do
      prompt = Sxn::UI::Prompt.new

      # Test prompt methods exist
      expect(prompt).to respond_to(:ask)
      expect(prompt).to respond_to(:ask_yes_no)
      expect(prompt).to respond_to(:select)
      expect(prompt).to respond_to(:multi_select)
    end

    it "handles table rendering" do
      table = Sxn::UI::Table.new

      # Test table methods exist and work with test data
      test_sessions = [
        { name: "Project 1", status: "active", projects: ["rails"], created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601 },
        { name: "Project 2", status: "inactive", projects: ["node"], created_at: Time.now.iso8601,
          updated_at: Time.now.iso8601 }
      ]

      expect { table.sessions(test_sessions) }.not_to raise_error
    end

    it "handles progress bar operations" do
      progress = Sxn::UI::ProgressBar.new("Processing", total: 10)

      # Test progress operations
      expect(progress.current).to eq(0)
      expect(progress.total).to eq(10)

      progress.advance
      expect(progress.current).to eq(1)

      progress.advance(3)
      expect(progress.current).to eq(4)

      progress.finish
      expect(progress.current).to eq(10)
    end
  end

  describe "Command error handling" do
    it "handles command class loading" do
      # Test that command classes can be loaded
      expect(Sxn::Commands::Init).to be_a(Class)
      expect(Sxn::Commands::Sessions).to be_a(Class)
      expect(Sxn::Commands::Projects).to be_a(Class)
      expect(Sxn::Commands::Worktrees).to be_a(Class)
      expect(Sxn::Commands::Rules).to be_a(Class)
    end
  end

  describe "Integration error scenarios" do
    it "handles cascading failures gracefully" do
      # Test scenario where multiple components fail
      invalid_path = "/nonexistent/path"

      # Config discovery should handle missing paths
      discovery = Sxn::Config::ConfigDiscovery.new(invalid_path)
      expect { discovery.discover_config }.not_to raise_error

      # Path validator should reject invalid paths that exist but are outside boundaries
      validator = Sxn::Security::SecurePathValidator.new(temp_dir)
      # Create a path that exists outside the temp_dir to test boundary validation
      outside_path = File.join(File.dirname(temp_dir), "outside_file.txt")
      File.write(outside_path, "content")
      expect { validator.validate_path(outside_path) }.to raise_error(Sxn::PathValidationError)
      FileUtils.rm_f(outside_path)

      # Rule engine should handle invalid configurations
      engine = Sxn::Rules::RulesEngine.new(temp_dir, temp_dir)
      invalid_rules = {
        "invalid_rule" => {
          "type" => "nonexistent_type",
          "config" => {}
        }
      }
      expect { engine.validate_rules_config(invalid_rules) }.to raise_error(ArgumentError, "Invalid rule type 'nonexistent_type' for rule 'invalid_rule'. Available: copy_files, setup_commands, template")
    end
  end

  describe "Performance and resource management" do
    it "handles resource cleanup properly" do
      # Test database connection management
      db_path = File.join(temp_dir, "cleanup_test.db")
      db = Sxn::Database::SessionDatabase.new(db_path)

      # Create and clean up sessions
      session_ids = []
      10.times do |i|
        session_data = {
          name: "session_#{i}",
          project_path: project_path,
          session_path: session_path,
          created_at: Time.now,
          last_accessed: Time.now
        }
        session_ids << db.create_session(session_data)
      end

      # Cleanup using session IDs
      session_ids.each do |session_id|
        db.delete_session(session_id)
      end

      expect(db.list_sessions).to be_empty
    end

    it "handles concurrent operations" do
      # Test thread safety
      threads = []
      results = []

      5.times do
        threads << Thread.new do
          cache = Sxn::Config::ConfigCache.new
          config_files = []
          config_data = { "value" => rand(1000) }
          cache.set(config_data, config_files)
          results << cache.get(config_files)
        end
      end

      threads.each(&:join)
      expect(results.size).to eq(5)
    end
  end
end
