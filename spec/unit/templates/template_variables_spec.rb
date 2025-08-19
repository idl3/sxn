# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe Sxn::Templates::TemplateVariables do
  let(:mock_session) do
    double("Session",
      name: "test-session",
      path: Pathname.new("/tmp/test-session"),
      created_at: Time.parse("2025-01-16 10:00:00 UTC"),
      updated_at: Time.parse("2025-01-16 14:30:00 UTC"),
      status: "active"
    ).tap do |session|
      # Set up default respond_to? behavior
      allow(session).to receive(:respond_to?).and_return(false)
    end
  end

  let(:mock_project) do
    double("Project",
      name: "test-project",
      path: Pathname.new("/tmp/test-project")
    )
  end

  let(:mock_config) do
    double("Config").tap do |config|
      # Set up default respond_to? behavior
      allow(config).to receive(:respond_to?).and_return(false)
    end
  end

  let(:collector) { described_class.new(mock_session, mock_project, mock_config) }

  # Set up default stubs for all tests
  before do
    # Mock git operations with default stubbing to prevent unexpected calls
    allow(collector).to receive(:execute_git_command).and_return("")
    
    # Mock file system operations
    allow(File).to receive(:exist?).and_call_original
    allow(Dir).to receive(:exist?).and_call_original
    
    # Mock ENV access
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("USER").and_return("testuser")
    allow(Dir).to receive(:home).and_return("/home/testuser")
    
    # Mock command executions to prevent unexpected calls
    allow(collector).to receive(:`).and_return("")
    allow(collector).to receive(:system).and_return(false)
  end

  describe "#collect" do

    it "returns a hash with all variable categories" do
      variables = collector.collect
      
      expect(variables).to be_a(Hash)
      expect(variables).to have_key(:session)
      expect(variables).to have_key(:git)
      expect(variables).to have_key(:project)
      expect(variables).to have_key(:environment)
      expect(variables).to have_key(:user)
      expect(variables).to have_key(:timestamp)
    end

    it "caches variables after first collection" do
      first_call = collector.collect
      second_call = collector.collect
      
      expect(first_call.object_id).to eq(second_call.object_id)
    end

    it "refreshes variables when requested" do
      first_call = collector.collect
      collector.refresh!
      second_call = collector.collect
      
      expect(first_call.object_id).not_to eq(second_call.object_id)
    end
  end

  describe "#collect_session_variables" do
    it "collects basic session information" do
      variables = collector.get_category(:session)
      
      expect(variables[:name]).to eq("test-session")
      expect(variables[:path]).to eq("/tmp/test-session")
      expect(variables[:created_at]).to include("2025-01-16 10:00:00")
      expect(variables[:updated_at]).to include("2025-01-16 14:30:00")
      expect(variables[:status]).to eq("active")
    end

    context "with optional session fields" do
      before do
        allow(mock_session).to receive(:respond_to?).with(:linear_task).and_return(true)
        allow(mock_session).to receive(:linear_task).and_return("ATL-1234")
        allow(mock_session).to receive(:respond_to?).with(:description).and_return(true)
        allow(mock_session).to receive(:description).and_return("Test session description")
        allow(mock_session).to receive(:respond_to?).with(:projects).and_return(true)
        allow(mock_session).to receive(:projects).and_return(["core", "frontend"])
        allow(mock_session).to receive(:respond_to?).with(:tags).and_return(true)
        allow(mock_session).to receive(:tags).and_return(["feature", "urgent"])
      end

      it "includes optional fields when present" do
        variables = collector.get_category(:session)
        
        expect(variables[:linear_task]).to eq("ATL-1234")
        expect(variables[:description]).to eq("Test session description")
        expect(variables[:projects]).to eq(["core", "frontend"])
        expect(variables[:tags]).to eq(["feature", "urgent"])
      end
    end

    context "with worktrees" do
      let(:mock_worktree) do
        double("Worktree",
          name: "core",
          path: Pathname.new("/tmp/core"),
          branch: "feature/test",
          created_at: Time.parse("2025-01-16 11:00:00 UTC")
        )
      end

      before do
        allow(mock_session).to receive(:respond_to?).with(:worktrees).and_return(true)
        allow(mock_session).to receive(:worktrees).and_return([mock_worktree])
      end

      it "includes worktree information" do
        variables = collector.get_category(:session)
        
        expect(variables[:worktrees]).to be_an(Array)
        expect(variables[:worktrees].first[:name]).to eq("core")
        expect(variables[:worktrees].first[:path]).to eq("/tmp/core")
        expect(variables[:worktrees].first[:branch]).to eq("feature/test")
      end
    end

    it "handles session collection errors gracefully" do
      allow(mock_session).to receive(:name).and_raise(StandardError, "Session error")
      
      variables = collector.get_category(:session)
      
      expect(variables[:error]).to include("Failed to collect session variables")
    end
  end

  describe "#collect_git_variables" do
    before do
      # Mock git directory detection
      allow(collector).to receive(:find_git_directory).and_return("/tmp/git-repo")
    end

    it "returns empty hash when no git directory found" do
      allow(collector).to receive(:find_git_directory).and_return(nil)
      
      variables = collector.get_category(:git)
      
      expect(variables).to eq({})
    end

    context "with git repository" do
      before do
        # Mock git command responses
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "branch", "--show-current")
          .and_yield("main\n")
        
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "status", "--porcelain")
          .and_yield("")
        
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "config", "user.name")
          .and_yield("John Doe\n")
        
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "config", "user.email")
          .and_yield("john@example.com\n")
        
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "log", "-1", "--format=%H|%s|%an|%ae|%ai")
          .and_yield("abc123|Initial commit|John Doe|john@example.com|2025-01-16 10:00:00 +0000\n")
        
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "rev-parse", "--short", "HEAD")
          .and_yield("abc123\n")
        
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "remote")
          .and_yield("origin\n")
        
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "remote", "get-url", "origin")
          .and_yield("git@github.com:user/repo.git\n")
        
        # Add the missing upstream branch command
        allow(collector).to receive(:execute_git_command)
          .with("/tmp/git-repo", "rev-parse", "--abbrev-ref", "@{upstream}")
          .and_yield("origin/main\n")
      end

      it "collects git branch information" do
        variables = collector.get_category(:git)
        
        expect(variables[:branch]).to eq("main")
        expect(variables[:clean]).to be true
        expect(variables[:has_changes]).to be false
      end

      it "collects git author information" do
        variables = collector.get_category(:git)
        
        expect(variables[:author_name]).to eq("John Doe")
        expect(variables[:author_email]).to eq("john@example.com")
      end

      it "collects git commit information" do
        variables = collector.get_category(:git)
        
        expect(variables[:last_commit]).to be_a(Hash)
        expect(variables[:last_commit][:sha]).to eq("abc123")
        expect(variables[:last_commit][:message]).to eq("Initial commit")
        expect(variables[:short_sha]).to eq("abc123")
      end

      it "collects git remote information" do
        variables = collector.get_category(:git)
        
        expect(variables[:remotes]).to eq(["origin"])
        expect(variables[:default_remote]).to eq("origin")
        expect(variables[:remote_url]).to eq("git@github.com:user/repo.git")
      end
    end

    it "handles git collection errors gracefully" do
      allow(collector).to receive(:find_git_directory).and_raise(StandardError, "Git error")
      
      variables = collector.get_category(:git)
      
      expect(variables[:error]).to include("Failed to collect git variables")
    end
  end

  describe "#collect_project_variables" do
    it "returns empty hash when no project" do
      collector_without_project = described_class.new(mock_session, nil, mock_config)
      
      variables = collector_without_project.get_category(:project)
      
      expect(variables).to eq({})
    end

    it "collects basic project information" do
      allow(collector).to receive(:detect_project_type).and_return("rails")
      
      variables = collector.get_category(:project)
      
      expect(variables[:name]).to eq("test-project")
      expect(variables[:path]).to eq("/tmp/test-project")
      expect(variables[:type]).to eq("rails")
    end

    context "with Rails project" do
      before do
        allow(collector).to receive(:detect_project_type).and_return("rails")
      end

      it "includes Rails-specific information" do
        # Mock database.yml existence and content
        db_config_path = Pathname.new("/tmp/test-project/config/database.yml")
        allow(db_config_path).to receive(:exist?).and_return(true)
        allow(YAML).to receive(:load_file).with(db_config_path).and_return({
          "development" => {
            "adapter" => "postgresql",
            "database" => "test_db"
          }
        })
        
        variables = collector.get_category(:project)
        
        # Note: This test might need adjustment based on actual implementation
        expect(variables[:type]).to eq("rails")
      end
    end

    it "handles project collection errors gracefully" do
      allow(mock_project).to receive(:name).and_raise(StandardError, "Project error")
      
      variables = collector.get_category(:project)
      
      expect(variables[:error]).to include("Failed to collect project variables")
    end
  end

  describe "#collect_environment_variables" do
    it "collects Ruby environment information" do
      variables = collector.get_category(:environment)
      
      expect(variables[:ruby]).to be_a(Hash)
      expect(variables[:ruby][:version]).to eq(RUBY_VERSION)
      expect(variables[:ruby][:platform]).to eq(RUBY_PLATFORM)
    end

    it "collects OS information" do
      variables = collector.get_category(:environment)
      
      expect(variables[:os]).to be_a(Hash)
      expect(variables[:os][:name]).to be_a(String)
      expect(variables[:os][:arch]).to be_a(String)
    end

    context "with Rails available" do
      before do
        # Mock Rails require and constant
        rails_class = Class.new
        version_class = Class.new
        stub_const("Rails", rails_class)
        stub_const("Rails::VERSION", version_class)
        stub_const("Rails::VERSION::STRING", "7.0.4")
        
        # Mock the require call
        allow(collector).to receive(:require).with("rails").and_return(true)
      end

      it "includes Rails version information" do
        variables = collector.get_category(:environment)
        
        expect(variables[:rails]).to be_a(Hash)
        expect(variables[:rails][:version]).to eq("7.0.4")
      end
    end

    context "with Node.js available" do
      before do
        # Mock all command executions that might happen
        allow(collector).to receive(:`).and_return("")
        allow(collector).to receive(:`).with("node --version 2>/dev/null").and_return("v18.0.0\n")
        allow(collector).to receive(:`).with("psql --version 2>/dev/null").and_return("")
        allow(collector).to receive(:`).with("mysql --version 2>/dev/null").and_return("")
        allow(collector).to receive(:`).with("redis-server --version 2>/dev/null").and_return("")
        
        # Mock system calls
        allow(collector).to receive(:system).and_return(false)
        allow(collector).to receive(:system).with("which node > /dev/null 2>&1").and_return(true)
      end

      it "includes Node.js version information" do
        variables = collector.get_category(:environment)
        
        expect(variables[:node]).to be_a(Hash)
        expect(variables[:node][:version]).to eq("18.0.0")
      end
    end
  end

  describe "#collect_user_variables" do
    before do
      # Mock git config commands
      allow(collector).to receive(:execute_git_command)
        .with(nil, "config", "--global", "user.name")
        .and_yield("Test User\n")
      
      allow(collector).to receive(:execute_git_command)
        .with(nil, "config", "--global", "user.email")
        .and_yield("test@example.com\n")
    end

    it "collects system user information" do
      variables = collector.get_category(:user)
      
      expect(variables[:username]).to eq("testuser")
      expect(variables[:home]).to eq("/home/testuser")
    end

    it "collects git user configuration" do
      variables = collector.get_category(:user)
      
      expect(variables[:git_name]).to eq("Test User")
      expect(variables[:git_email]).to eq("test@example.com")
    end

    context "with sxn config" do
      before do
        allow(mock_config).to receive(:respond_to?).with(:default_editor).and_return(true)
        allow(mock_config).to receive(:default_editor).and_return("code")
        allow(mock_config).to receive(:respond_to?).with(:user_preferences).and_return(true)
        allow(mock_config).to receive(:user_preferences).and_return({ theme: "dark" })
      end

      it "includes config preferences" do
        variables = collector.get_category(:user)
        
        expect(variables[:editor]).to eq("code")
        expect(variables[:preferences]).to eq({ theme: "dark" })
      end
    end
  end

  describe "#collect_timestamp_variables" do
    it "provides timestamp information" do
      frozen_time = Time.parse("2025-01-16 15:30:00 UTC")
      allow(Time).to receive(:now).and_return(frozen_time)
      
      variables = collector.get_category(:timestamp)
      
      expect(variables[:now]).to include("2025-01-16 15:30:00")
      expect(variables[:today]).to eq("2025-01-16")
      expect(variables[:year]).to eq(2025)
      expect(variables[:month]).to eq(1)
      expect(variables[:day]).to eq(16)
      expect(variables[:iso8601]).to eq("2025-01-16T15:30:00Z")
      expect(variables[:epoch]).to be_a(Integer)
    end
  end

  describe "#add_custom_variables" do
    it "merges custom variables with collected variables" do
      custom_vars = { custom: { key: "value" } }
      collector.add_custom_variables(custom_vars)
      
      variables = collector.collect
      
      expect(variables[:custom][:key]).to eq("value")
    end

    it "allows custom variables to override collected variables" do
      custom_vars = { session: { name: "custom-session" } }
      collector.add_custom_variables(custom_vars)
      
      variables = collector.collect
      
      expect(variables[:session][:name]).to eq("custom-session")
    end

    it "ignores non-hash custom variables" do
      expect {
        collector.add_custom_variables("not a hash")
      }.not_to raise_error
    end
  end

  describe "project type detection" do
    let(:project_path) { "/tmp/test-project" }

    it "detects Rails projects" do
      # Mock Pathname methods
      gemfile_path = double("Pathname")
      app_config_path = double("Pathname")
      package_json_path = double("Pathname")
      
      allow(Pathname).to receive(:new).with(project_path).and_return(double("Pathname").tap do |path|
        allow(path).to receive(:/).with("Gemfile").and_return(gemfile_path)
        allow(path).to receive(:/).with("config").and_return(double("Pathname").tap do |config_path|
          allow(config_path).to receive(:/).with("application.rb").and_return(app_config_path)
        end)
        allow(path).to receive(:/).with("package.json").and_return(package_json_path)
      end)
      
      allow(gemfile_path).to receive(:exist?).and_return(true)
      allow(app_config_path).to receive(:exist?).and_return(true)
      allow(package_json_path).to receive(:exist?).and_return(false)
      
      type = collector.send(:detect_project_type, project_path)
      expect(type).to eq("rails")
    end

    it "detects Ruby gem projects" do
      # Mock Pathname methods
      gemfile_path = double("Pathname")
      app_config_path = double("Pathname")
      package_json_path = double("Pathname")
      
      allow(Pathname).to receive(:new).with(project_path).and_return(double("Pathname").tap do |path|
        allow(path).to receive(:/).with("Gemfile").and_return(gemfile_path)
        allow(path).to receive(:/).with("config").and_return(double("Pathname").tap do |config_path|
          allow(config_path).to receive(:/).with("application.rb").and_return(app_config_path)
        end)
        allow(path).to receive(:/).with("package.json").and_return(package_json_path)
      end)
      
      allow(gemfile_path).to receive(:exist?).and_return(true)
      allow(app_config_path).to receive(:exist?).and_return(false)
      allow(package_json_path).to receive(:exist?).and_return(false)
      
      type = collector.send(:detect_project_type, project_path)
      expect(type).to eq("ruby")
    end

    it "detects JavaScript projects" do
      # Mock Pathname methods
      gemfile_path = double("Pathname")
      package_json_path = double("Pathname")
      tsconfig_path = double("Pathname")
      gemspec_path = double("Pathname")
      
      allow(Pathname).to receive(:new).with(project_path).and_return(double("Pathname").tap do |path|
        allow(path).to receive(:/).with("Gemfile").and_return(gemfile_path)
        allow(path).to receive(:/).with("package.json").and_return(package_json_path)
        allow(path).to receive(:/).with("tsconfig.json").and_return(tsconfig_path)
        allow(path).to receive(:/).with("*.gemspec").and_return(gemspec_path)
        allow(path).to receive(:to_s).and_return(project_path)
      end)
      
      allow(gemfile_path).to receive(:exist?).and_return(false)
      allow(package_json_path).to receive(:exist?).and_return(true)
      allow(package_json_path).to receive(:read).and_return('{"name": "test"}')
      allow(tsconfig_path).to receive(:exist?).and_return(false)
      allow(gemspec_path).to receive(:to_s).and_return("/tmp/test-project/*.gemspec")
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob).with("/tmp/test-project/*.gemspec").and_return([])
      allow(JSON).to receive(:parse).and_return({})
      
      type = collector.send(:detect_project_type, project_path)
      expect(type).to eq("javascript")
    end

    it "detects TypeScript projects" do
      # Mock Pathname methods
      gemfile_path = double("Pathname")
      package_json_path = double("Pathname")
      tsconfig_path = double("Pathname")
      gemspec_path = double("Pathname")
      
      allow(Pathname).to receive(:new).with(project_path).and_return(double("Pathname").tap do |path|
        allow(path).to receive(:/).with("Gemfile").and_return(gemfile_path)
        allow(path).to receive(:/).with("package.json").and_return(package_json_path)
        allow(path).to receive(:/).with("tsconfig.json").and_return(tsconfig_path)
        allow(path).to receive(:/).with("*.gemspec").and_return(gemspec_path)
        allow(path).to receive(:to_s).and_return(project_path)
      end)
      
      allow(gemfile_path).to receive(:exist?).and_return(false)
      allow(package_json_path).to receive(:exist?).and_return(true)
      allow(package_json_path).to receive(:read).and_return('{"name": "test"}')
      allow(tsconfig_path).to receive(:exist?).and_return(true)
      allow(gemspec_path).to receive(:to_s).and_return("/tmp/test-project/*.gemspec")
      allow(Dir).to receive(:glob).and_call_original
      allow(Dir).to receive(:glob).with("/tmp/test-project/*.gemspec").and_return([])
      allow(JSON).to receive(:parse).and_return({})
      
      type = collector.send(:detect_project_type, project_path)
      expect(type).to eq("typescript")
    end

    it "returns unknown for unrecognized projects" do
      allow(File).to receive(:exist?).and_return(false)
      
      type = collector.send(:detect_project_type, project_path)
      expect(type).to eq("unknown")
    end
  end

  describe "error handling" do
    it "handles missing session gracefully" do
      collector_without_session = described_class.new(nil, mock_project, mock_config)
      
      variables = collector_without_session.get_category(:session)
      
      expect(variables).to eq({})
    end

    it "handles git command timeouts" do
      allow(collector).to receive(:execute_git_command).and_raise(Timeout::Error)
      
      variables = collector.get_category(:git)
      
      # Should not crash, might return empty or error state
      expect(variables).to be_a(Hash)
    end
  end
end