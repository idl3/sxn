# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Comprehensive test to cover remaining uncovered lines across multiple files
RSpec.describe "Comprehensive Coverage Tests" do
  let(:temp_dir) { Dir.mktmpdir("sxn_coverage_test") }
  let(:project_path) { File.join(temp_dir, "project") }
  let(:session_path) { File.join(temp_dir, "session") }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(session_path)
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
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
      
      expect { db.create_session(session_data) }.not_to raise_error
      expect { db.list_sessions }.not_to raise_error
      expect { db.get_session("test_session") }.not_to raise_error
      expect { db.update_session("test_session", last_accessed: Time.now) }.not_to raise_error
      expect { db.delete_session("test_session") }.not_to raise_error
      
      # Test error conditions - expect some kind of error for invalid operations
      expect { db.create_session(name: nil) }.to raise_error
      expect { db.get_session("nonexistent") }.to raise_error  
      expect { db.update_session("nonexistent", {}) }.to raise_error
      expect { db.delete_session("nonexistent") }.to raise_error
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
      dest_path = File.join(project_path, "dest.txt")
      expect { validator.validate_file_operation(valid_file, dest_path) }.not_to raise_error
      
      # Test invalid file operations
      expect { validator.validate_file_operation("nonexistent.txt", dest_path) }.to raise_error(Sxn::PathValidationError)
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
      
      # Test successful copy
      dest_file = File.join(session_path, "dest.txt")
      FileUtils.mkdir_p(File.dirname(dest_file))
      relative_dest = File.join("..", File.basename(session_path), "dest.txt")
      
      result = copier.copy_file(source_file, relative_dest)
      expect(result).to be_a(Sxn::Security::SecureFileCopier::CopyResult)
      expect(File.exist?(dest_file)).to be true
      expect(File.read(dest_file)).to eq("test content")
      
      # Test error conditions
      expect { copier.copy_file("nonexistent.txt", relative_dest) }.to raise_error
    end
  end

  describe "Rules engine edge cases" do
    it "handles rule validation and execution" do
      engine = Sxn::Rules::RulesEngine.new(project_path, session_path)
      
      # Test empty rules
      expect { engine.validate_rules_config({}) }.not_to raise_error
      
      # Test rules with missing files
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
      expect(result.success?).to be true
      expect(File.exist?(File.join(session_path, "copied.txt"))).to be true
    end

    it "handles project detection edge cases" do
      detector = Sxn::Rules::ProjectDetector.new(project_path)
      
      # Test detection with empty project
      expect(detector.detect_type(project_path)).to eq(:unknown)
      
      # Test Rails detection
      FileUtils.mkdir_p(File.join(project_path, "app", "models"))
      File.write(File.join(project_path, "Gemfile"), "gem 'rails'")
      expect(detector.detect_type(project_path)).to eq(:rails)
      
      # Test suggestion methods
      expect { detector.suggest_default_rules }.not_to raise_error
      expect { detector.suggest_templates }.not_to raise_error
      expect { detector.analyze_project }.not_to raise_error
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
      expect(processor.validate_template(template_content)).to be true
      expect(processor.validate_template("{{ invalid")).to be false
    end

    it "handles template variables collection" do
      variables = Sxn::Templates::TemplateVariables.new
      
      # Test variable collection exists and returns a hash
      expect { variables.collect }.not_to raise_error
      all_vars = variables.collect
      expect(all_vars).to be_a(Hash)
    end

    it "handles template security validation" do
      security = Sxn::Templates::TemplateSecurity.new(project_path)
      
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
      expect { engine.process_template("common/gitignore.liquid", File.join(session_path, ".gitignore")) }.not_to raise_error
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
      
      # Test table building
      table.header(["Name", "Type", "Status"])
      table.row(["Project 1", "Rails", "Active"])
      table.row(["Project 2", "Node", "Inactive"])
      
      expect { table.render }.not_to raise_error
    end

    it "handles progress bar operations" do
      progress = Sxn::UI::ProgressBar.new("Processing", 10)
      
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
      
      # Path validator should reject invalid paths
      validator = Sxn::Security::SecurePathValidator.new(temp_dir)
      expect { validator.validate_path(invalid_path) }.to raise_error(Sxn::PathValidationError)
      
      # Rule engine should handle invalid configurations
      engine = Sxn::Rules::RulesEngine.new(temp_dir, temp_dir)
      invalid_rules = {
        "invalid_rule" => {
          "type" => "nonexistent_type",
          "config" => {}
        }
      }
      expect { engine.validate_rules_config(invalid_rules) }.to raise_error(ArgumentError)
    end
  end

  describe "Performance and resource management" do
    it "handles resource cleanup properly" do
      # Test database connection management
      db_path = File.join(temp_dir, "cleanup_test.db")
      db = Sxn::Database::SessionDatabase.new(db_path)
      
      # Create and clean up sessions
      10.times do |i|
        session_data = {
          name: "session_#{i}",
          project_path: project_path,
          session_path: session_path,
          created_at: Time.now,
          last_accessed: Time.now
        }
        db.create_session(session_data)
      end
      
      # Cleanup
      db.list_sessions.each do |session|
        db.delete_session(session[:name])
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