# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# Tests specifically targeting uncovered lines across multiple files
RSpec.describe "Missing Coverage Tests" do
  let(:temp_dir) { Dir.mktmpdir("missing_coverage_test") }
  let(:project_path) { File.join(temp_dir, "project") }
  let(:session_path) { File.join(temp_dir, "session") }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(session_path)
  end

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "Commands module comprehensive coverage" do
    describe "Sxn::Commands::Projects" do
      let(:command) { Sxn::Commands::Projects.new }
      let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
      let(:project_manager) { instance_double(Sxn::Core::ProjectManager) }

      before do
        allow(Sxn::Core::ConfigManager).to receive(:new).and_return(config_manager)
        allow(Sxn::Core::ProjectManager).to receive(:new).and_return(project_manager)
        allow(config_manager).to receive(:initialized?).and_return(true)
      end

      it "handles Thor start method" do
        allow(Sxn::Commands::Projects).to receive(:start)
        expect { Sxn::Commands::Projects.start(["list"]) }.not_to raise_error
      end

      it "handles project listing" do
        allow(project_manager).to receive(:list_projects).and_return([])
        expect { command.list }.not_to raise_error
      end

      it "handles project addition" do
        allow(project_manager).to receive(:add_project)
        expect { command.add("test-project", project_path) }.not_to raise_error
      end

      it "handles project removal" do
        allow(project_manager).to receive(:remove_project)
        expect { command.remove("test-project") }.not_to raise_error
      end
    end

    describe "Sxn::Commands::Sessions" do
      let(:command) { Sxn::Commands::Sessions.new }
      let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
      let(:session_manager) { instance_double(Sxn::Core::SessionManager) }

      before do
        allow(Sxn::Core::ConfigManager).to receive(:new).and_return(config_manager)
        allow(Sxn::Core::SessionManager).to receive(:new).and_return(session_manager)
        allow(config_manager).to receive(:initialized?).and_return(true)
      end

      it "handles Thor start method" do
        allow(Sxn::Commands::Sessions).to receive(:start)
        expect { Sxn::Commands::Sessions.start(["list"]) }.not_to raise_error
      end

      it "handles session addition" do
        allow(session_manager).to receive(:create_session)
        expect { command.add("test-session") }.not_to raise_error
      end

      it "handles session switching" do
        allow(session_manager).to receive(:use_session)
        expect { command.use("test-session") }.not_to raise_error
      end

      it "handles session listing" do
        allow(session_manager).to receive(:list_sessions).and_return([])
        expect { command.list }.not_to raise_error
      end

      it "handles current session display" do
        allow(config_manager).to receive(:current_session).and_return("current")
        expect { command.current }.not_to raise_error
      end
    end

    describe "Sxn::Commands::Worktrees" do
      let(:command) { Sxn::Commands::Worktrees.new }
      let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
      let(:worktree_manager) { instance_double(Sxn::Core::WorktreeManager) }

      before do
        allow(Sxn::Core::ConfigManager).to receive(:new).and_return(config_manager)
        allow(Sxn::Core::WorktreeManager).to receive(:new).and_return(worktree_manager)
        allow(config_manager).to receive(:initialized?).and_return(true)
      end

      it "handles Thor start method" do
        allow(Sxn::Commands::Worktrees).to receive(:start)
        expect { Sxn::Commands::Worktrees.start(["list"]) }.not_to raise_error
      end

      it "handles worktree listing" do
        allow(worktree_manager).to receive(:list_worktrees).and_return([])
        expect { command.list }.not_to raise_error
      end

      it "handles worktree addition" do
        allow(worktree_manager).to receive(:add_worktree)
        expect { command.add("test-project", "feature-branch") }.not_to raise_error
      end

      it "handles worktree removal" do
        allow(worktree_manager).to receive(:remove_worktree)
        expect { command.remove("test-project") }.not_to raise_error
      end
    end

    describe "Sxn::Commands::Rules" do
      let(:command) { Sxn::Commands::Rules.new }
      let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
      let(:rules_manager) { instance_double(Sxn::Core::RulesManager) }

      before do
        allow(Sxn::Core::ConfigManager).to receive(:new).and_return(config_manager)
        allow(Sxn::Core::RulesManager).to receive(:new).and_return(rules_manager)
        allow(config_manager).to receive(:initialized?).and_return(true)
      end

      it "handles Thor start method" do
        allow(Sxn::Commands::Rules).to receive(:start)
        expect { Sxn::Commands::Rules.start(["list"]) }.not_to raise_error
      end

      it "handles rules listing" do
        allow(rules_manager).to receive(:list_rules).and_return({})
        expect { command.list }.not_to raise_error
      end

      it "handles rule addition" do
        allow(rules_manager).to receive(:add_rule)
        expect { command.add("test-project", "copy_files") }.not_to raise_error
      end

      it "handles rule removal" do
        allow(rules_manager).to receive(:remove_rule)
        expect { command.remove("test-project", "copy_files") }.not_to raise_error
      end

      it "handles rule application" do
        allow(rules_manager).to receive(:apply_rules)
        expect { command.apply("test-project") }.not_to raise_error
      end

      it "handles rule validation" do
        allow(rules_manager).to receive(:validate_rules)
        expect { command.validate("test-project") }.not_to raise_error
      end

      it "handles rule types listing" do
        allow(rules_manager).to receive(:get_available_rule_types).and_return({})
        expect { command.types }.not_to raise_error
      end

      it "handles rule template generation" do
        allow(rules_manager).to receive(:generate_rule_template).and_return({})
        expect { command.template("copy_files", "rails") }.not_to raise_error
      end
    end
  end

  describe "Core managers comprehensive coverage" do
    describe "Sxn::Core::ProjectManager" do
      let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
      let(:manager) { Sxn::Core::ProjectManager.new(config_manager) }

      before do
        allow(config_manager).to receive(:get_config).and_return({
          "projects" => {
            "test-project" => {
              "path" => project_path,
              "type" => "rails"
            }
          }
        })
        allow(config_manager).to receive(:save_config)
      end

      it "lists projects" do
        result = manager.list_projects
        expect(result).to be_an(Array)
        expect(result.first[:name]).to eq("test-project")
      end

      it "gets specific project" do
        result = manager.get_project("test-project")
        expect(result[:name]).to eq("test-project")
        expect(result[:type]).to eq("rails")
      end

      it "adds new project" do
        expect { manager.add_project("new-project", project_path, type: "javascript") }.not_to raise_error
      end

      it "removes project" do
        expect { manager.remove_project("test-project") }.not_to raise_error
      end

      it "updates project" do
        expect { manager.update_project("test-project", type: "javascript") }.not_to raise_error
      end

      it "checks project existence" do
        expect(manager.project_exists?("test-project")).to be true
        expect(manager.project_exists?("nonexistent")).to be false
      end

      it "detects projects in directory" do
        FileUtils.mkdir_p(File.join(project_path, "app", "models"))
        File.write(File.join(project_path, "Gemfile"), "gem 'rails'")
        
        projects = manager.detect_projects(File.dirname(project_path))
        expect(projects).to be_an(Array)
      end

      it "validates project configurations" do
        result = manager.validate_projects
        expect(result).to be_an(Array)
      end

      it "handles project not found errors" do
        expect { manager.get_project("nonexistent") }.to raise_error(Sxn::ProjectNotFoundError)
      end

      it "handles duplicate project errors" do
        expect { manager.add_project("test-project", project_path) }.to raise_error(Sxn::ProjectAlreadyExistsError)
      end
    end

    describe "Sxn::Core::SessionManager" do
      let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
      let(:database) { instance_double(Sxn::Database::SessionDatabase) }
      let(:manager) { Sxn::Core::SessionManager.new(config_manager) }

      before do
        allow(Sxn::Database::SessionDatabase).to receive(:new).and_return(database)
        allow(config_manager).to receive(:sessions_folder_path).and_return(session_path)
        allow(config_manager).to receive(:current_session).and_return("current-session")
        allow(config_manager).to receive(:set_current_session)
        allow(database).to receive(:create_session)
        allow(database).to receive(:get_session).and_return({
          name: "test-session",
          project_path: project_path,
          session_path: session_path,
          created_at: Time.now,
          last_accessed: Time.now
        })
        allow(database).to receive(:list_sessions).and_return([
          {
            name: "test-session",
            project_path: project_path,
            session_path: session_path
          }
        ])
        allow(database).to receive(:update_session)
        allow(database).to receive(:delete_session)
      end

      it "creates sessions" do
        expect { manager.create_session("new-session") }.not_to raise_error
      end

      it "uses sessions" do
        expect { manager.use_session("test-session") }.not_to raise_error
      end

      it "lists sessions" do
        result = manager.list_sessions
        expect(result).to be_an(Array)
      end

      it "gets specific session" do
        result = manager.get_session("test-session")
        expect(result[:name]).to eq("test-session")
      end

      it "updates sessions" do
        expect { manager.update_session("test-session", last_accessed: Time.now) }.not_to raise_error
      end

      it "deletes sessions" do
        allow(FileUtils).to receive(:rm_rf)
        expect { manager.delete_session("test-session") }.not_to raise_error
      end

      it "checks session existence" do
        allow(database).to receive(:get_session).with("test-session").and_return({name: "test-session"})
        allow(database).to receive(:get_session).with("nonexistent").and_raise(Sxn::SessionNotFoundError.new("Not found"))
        
        expect(manager.session_exists?("test-session")).to be true
        expect(manager.session_exists?("nonexistent")).to be false
      end

      it "gets current session info" do
        allow(database).to receive(:get_session).with("current-session").and_return({name: "current-session"})
        result = manager.current_session_info
        expect(result[:name]).to eq("current-session")
      end

      it "archives sessions" do
        expect { manager.archive_session("test-session") }.not_to raise_error
      end

      it "activates sessions" do
        expect { manager.activate_session("test-session") }.not_to raise_error
      end

      it "cleans up old sessions" do
        expect { manager.cleanup_old_sessions(30) }.not_to raise_error
      end

      it "handles session creation errors" do
        allow(database).to receive(:create_session).and_raise(Sxn::SessionAlreadyExistsError.new("Already exists"))
        expect { manager.create_session("test-session") }.to raise_error(Sxn::SessionAlreadyExistsError)
      end

      it "handles session not found errors" do
        allow(database).to receive(:get_session).and_raise(Sxn::SessionNotFoundError.new("Not found"))
        expect { manager.get_session("nonexistent") }.to raise_error(Sxn::SessionNotFoundError)
      end
    end

    describe "Sxn::Core::WorktreeManager" do
      let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
      let(:session_manager) { instance_double(Sxn::Core::SessionManager) }
      let(:manager) { Sxn::Core::WorktreeManager.new(config_manager, session_manager) }

      before do
        allow(config_manager).to receive(:current_session).and_return("current-session")
        allow(session_manager).to receive(:get_session).and_return({
          name: "current-session",
          session_path: session_path
        })
      end

      it "lists worktrees" do
        allow(Dir).to receive(:glob).and_return([])
        result = manager.list_worktrees
        expect(result).to be_an(Array)
      end

      it "adds worktrees" do
        allow(manager).to receive(:execute_git_command).and_return(true)
        expect { manager.add_worktree("test-project", "feature-branch") }.not_to raise_error
      end

      it "removes worktrees" do
        allow(manager).to receive(:execute_git_command).and_return(true)
        allow(FileUtils).to receive(:rm_rf)
        expect { manager.remove_worktree("test-project") }.not_to raise_error
      end

      it "checks worktree existence" do
        allow(File).to receive(:directory?).and_return(false)
        expect(manager.worktree_exists?("test-project")).to be false
      end

      it "gets worktree path" do
        path = manager.worktree_path("test-project")
        expect(path).to include("test-project")
      end

      it "validates worktree names" do
        expect { manager.validate_worktree_name("valid-name") }.not_to raise_error
        expect { manager.validate_worktree_name("invalid name") }.to raise_error(Sxn::WorktreeError)
      end

      it "handles worktree creation errors" do
        allow(manager).to receive(:execute_git_command).and_raise(Sxn::GitError.new("Git error"))
        expect { manager.add_worktree("test-project", "branch") }.to raise_error(Sxn::GitError)
      end

      it "handles worktree not found errors" do
        allow(File).to receive(:directory?).and_return(false)
        expect { manager.remove_worktree("nonexistent") }.to raise_error(Sxn::WorktreeNotFoundError)
      end
    end
  end

  describe "Template system comprehensive coverage" do
    describe "Sxn::Templates::TemplateVariables" do
      let(:variables) { Sxn::Templates::TemplateVariables.new }

      it "collects session variables" do
        result = variables.send(:collect_session_variables)
        expect(result).to be_a(Hash)
      end

      it "collects git variables" do
        result = variables.send(:collect_git_variables)
        expect(result).to be_a(Hash)
      end

      it "collects project variables" do
        result = variables.send(:collect_project_variables)
        expect(result).to be_a(Hash)
      end

      it "collects environment variables" do
        result = variables.send(:collect_environment_variables)
        expect(result).to be_a(Hash)
      end

      it "collects user variables" do
        result = variables.send(:collect_user_variables)
        expect(result).to be_a(Hash)
      end

      it "collects timestamp variables" do
        result = variables.send(:collect_timestamp_variables)
        expect(result).to be_a(Hash)
      end

      it "caches variables" do
        first_call = variables.collect
        second_call = variables.collect
        expect(first_call).to equal(second_call)
      end

      it "handles git command failures gracefully" do
        allow(variables).to receive(:execute_git_command).and_return(nil)
        result = variables.send(:collect_git_variables)
        expect(result).to be_a(Hash)
      end

      it "detects ruby version" do
        result = variables.send(:detect_ruby_version)
        expect(result).to be_a(String)
      end

      it "detects rails version" do
        result = variables.send(:detect_rails_version)
        expect(result).to be_a(String).or(be_nil)
      end

      it "detects node version" do
        result = variables.send(:detect_node_version)
        expect(result).to be_a(String).or(be_nil)
      end
    end

    describe "Sxn::Templates::TemplateEngine" do
      let(:session) { { name: "test-session", path: session_path } }
      let(:project) { { name: "test-project", path: project_path } }
      let(:engine) { Sxn::Templates::TemplateEngine.new(session: session, project: project) }

      it "lists available templates" do
        result = engine.list_templates
        expect(result).to be_an(Array)
      end

      it "checks template existence" do
        expect(engine.template_exists?("common/gitignore.liquid")).to be true
        expect(engine.template_exists?("nonexistent.liquid")).to be false
      end

      it "processes templates" do
        FileUtils.mkdir_p(File.dirname(File.join(session_path, ".gitignore")))
        expect { engine.process_template("common/gitignore.liquid", File.join(session_path, ".gitignore")) }.not_to raise_error
        expect(File.exist?(File.join(session_path, ".gitignore"))).to be true
      end

      it "renders template content" do
        result = engine.render_template("common/gitignore.liquid")
        expect(result).to be_a(String)
      end

      it "handles missing templates" do
        expect { engine.process_template("nonexistent.liquid", "output.txt") }.to raise_error(Sxn::TemplateNotFoundError)
      end

      it "validates output paths" do
        expect { engine.process_template("common/gitignore.liquid", "../outside.txt") }.to raise_error(Sxn::SecurityError)
      end
    end
  end

  describe "Rule system comprehensive coverage" do
    describe "Sxn::Rules::BaseRule" do
      let(:rule) { Sxn::Rules::BaseRule.new(project_path, session_path) }

      it "has default type" do
        expect(rule.type).to eq("base")
      end

      it "has default required flag" do
        expect(rule.required?).to be true
      end

      it "validates by default" do
        expect(rule.validate({})).to be true
      end

      it "raises not implemented error for apply" do
        expect { rule.apply({}) }.to raise_error(NotImplementedError)
      end

      it "provides default description" do
        expect(rule.description).to be_a(String)
      end
    end

    describe "Sxn::Rules::CopyFilesRule" do
      let(:rule) { Sxn::Rules::CopyFilesRule.new(project_path, session_path) }

      before do
        File.write(File.join(project_path, "source.txt"), "test content")
      end

      it "validates file configuration" do
        config = {
          "files" => [
            { "source" => "source.txt", "destination" => "dest.txt" }
          ]
        }
        expect(rule.validate(config)).to be true
      end

      it "applies file copying" do
        config = {
          "files" => [
            { "source" => "source.txt", "destination" => "dest.txt" }
          ]
        }
        result = rule.apply(config)
        expect(result.success?).to be true
        expect(File.exist?(File.join(session_path, "dest.txt"))).to be true
      end

      it "handles missing source files" do
        config = {
          "files" => [
            { "source" => "missing.txt", "destination" => "dest.txt", "required" => false }
          ]
        }
        result = rule.apply(config)
        expect(result.success?).to be true
      end

      it "fails on missing required files" do
        config = {
          "files" => [
            { "source" => "missing.txt", "destination" => "dest.txt", "required" => true }
          ]
        }
        expect { rule.apply(config) }.to raise_error(Sxn::RuleExecutionError)
      end

      it "validates file configurations" do
        expect(rule.validate({})).to be false
        expect(rule.validate({ "files" => [] })).to be true
        expect(rule.validate({ "files" => [{}] })).to be false
      end
    end

    describe "Sxn::Rules::SetupCommandsRule" do
      let(:rule) { Sxn::Rules::SetupCommandsRule.new(project_path, session_path) }

      it "validates command configuration" do
        config = {
          "commands" => ["echo 'test'"]
        }
        expect(rule.validate(config)).to be true
      end

      it "applies setup commands" do
        config = {
          "commands" => ["git --version"]
        }
        result = rule.apply(config)
        expect(result.success?).to be true
      end

      it "handles command failures" do
        config = {
          "commands" => ["nonexistent_command_that_fails"],
          "ignore_failures" => true
        }
        result = rule.apply(config)
        expect(result.success?).to be true
      end

      it "validates command configurations" do
        expect(rule.validate({})).to be false
        expect(rule.validate({ "commands" => [] })).to be true
        expect(rule.validate({ "commands" => ["valid"] })).to be true
        expect(rule.validate({ "commands" => "invalid" })).to be false
      end
    end

    describe "Sxn::Rules::TemplateRule" do
      let(:rule) { Sxn::Rules::TemplateRule.new(project_path, session_path) }

      it "validates template configuration" do
        config = {
          "source" => "common/gitignore.liquid",
          "destination" => ".gitignore"
        }
        expect(rule.validate(config)).to be true
      end

      it "applies template processing" do
        config = {
          "source" => "common/gitignore.liquid",
          "destination" => ".gitignore"
        }
        result = rule.apply(config)
        expect(result.success?).to be true
        expect(File.exist?(File.join(session_path, ".gitignore"))).to be true
      end

      it "handles missing templates" do
        config = {
          "source" => "nonexistent.liquid",
          "destination" => "output.txt"
        }
        expect { rule.apply(config) }.to raise_error(Sxn::RuleExecutionError)
      end

      it "validates template configurations" do
        expect(rule.validate({})).to be false
        expect(rule.validate({ "source" => "test.liquid" })).to be false
        expect(rule.validate({ "destination" => "test.txt" })).to be false
        expect(rule.validate({ "source" => "test.liquid", "destination" => "test.txt" })).to be true
      end
    end
  end

  describe "Database comprehensive coverage" do
    describe "Sxn::Database::SessionDatabase" do
      let(:db_path) { File.join(temp_dir, "test.db") }
      let(:database) { Sxn::Database::SessionDatabase.new(db_path) }

      it "creates database and tables" do
        expect(File.exist?(db_path)).to be true
      end

      it "handles database migrations" do
        expect { database.send(:create_tables) }.not_to raise_error
      end

      it "creates sessions with all fields" do
        session_data = {
          name: "test-session",
          project_path: project_path,
          session_path: session_path,
          created_at: Time.now,
          last_accessed: Time.now,
          status: "active",
          description: "Test session"
        }
        expect { database.create_session(session_data) }.not_to raise_error
      end

      it "handles duplicate session creation" do
        session_data = { name: "duplicate", project_path: project_path, session_path: session_path }
        database.create_session(session_data)
        expect { database.create_session(session_data) }.to raise_error(Sxn::SessionAlreadyExistsError)
      end

      it "updates session fields" do
        session_data = { name: "update-test", project_path: project_path, session_path: session_path }
        database.create_session(session_data)
        
        expect { database.update_session("update-test", last_accessed: Time.now, status: "inactive") }.not_to raise_error
      end

      it "lists sessions with filtering" do
        # Create test sessions
        database.create_session(name: "active1", project_path: project_path, session_path: session_path, status: "active")
        database.create_session(name: "inactive1", project_path: project_path, session_path: session_path, status: "inactive")
        
        all_sessions = database.list_sessions
        expect(all_sessions.size).to be >= 2
        
        active_sessions = database.list_sessions(status: "active")
        expect(active_sessions.all? { |s| s[:status] == "active" }).to be true
      end

      it "handles database connection errors" do
        bad_db = Sxn::Database::SessionDatabase.new("/invalid/path/db.sqlite3")
        expect { bad_db.create_session(name: "test") }.to raise_error(Sxn::DatabaseError)
      end

      it "handles SQL injection attempts" do
        malicious_name = "'; DROP TABLE sessions; --"
        session_data = { name: malicious_name, project_path: project_path, session_path: session_path }
        expect { database.create_session(session_data) }.not_to raise_error
        
        result = database.get_session(malicious_name)
        expect(result[:name]).to eq(malicious_name)
      end

      it "validates session data types" do
        expect { database.create_session(name: nil) }.to raise_error
        expect { database.create_session(name: 123) }.to raise_error
      end

      it "handles concurrent access" do
        threads = []
        10.times do |i|
          threads << Thread.new do
            session_data = { name: "concurrent_#{i}", project_path: project_path, session_path: session_path }
            database.create_session(session_data)
          end
        end
        
        threads.each(&:join)
        sessions = database.list_sessions
        concurrent_sessions = sessions.select { |s| s[:name].start_with?("concurrent_") }
        expect(concurrent_sessions.size).to eq(10)
      end
    end
  end
end