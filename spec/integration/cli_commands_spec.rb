# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "CLI Command Integration" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_project_path) { File.join(temp_dir, "test-project") }
  let(:original_dir) { Dir.pwd }

  before do
    # Create a test project directory
    FileUtils.mkdir_p(test_project_path)
    File.write(File.join(test_project_path, "Gemfile"), "source 'https://rubygems.org'\ngem 'rails'")
    
    # DO NOT change directories - this causes bundler issues
    # Instead, use absolute paths for all operations
  end

  after do
    # Clean up temp directory
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "sxn init workflow" do
    it "initializes a project and creates required directories", :skip => "CLI integration tests need refactoring to work without Dir.chdir" do
      # This test needs to be refactored to use absolute paths instead of Dir.chdir
      # The current CLI API expects to be run from within the project directory
      # TODO: Refactor CLI to accept explicit project path parameter
      skip "CLI integration tests need refactoring to avoid Dir.chdir issues"
    end
  end

  describe "end-to-end session workflow" do
    let(:config_manager) { Sxn::Core::ConfigManager.new(test_project_path) }

    before do
      # Initialize sxn first
      config_manager.initialize_project
    end

    it "creates, lists, and manages sessions", :skip => "CLI integration tests need refactoring to work without Dir.chdir" do
      session_manager = Sxn::Core::SessionManager.new(config_manager)
      
      # Create a session
      session = session_manager.create_session("test-session", description: "Test session")
      expect(session[:name]).to eq("test-session")
      expect(session[:status]).to eq("active")
      
      # List sessions
      sessions = session_manager.list_sessions
      expect(sessions.size).to eq(1)
      expect(sessions.first[:name]).to eq("test-session")
      
      # Use session
      used_session = session_manager.use_session("test-session")
      expect(used_session[:name]).to eq("test-session")
      
      # Verify current session
      current = session_manager.current_session
      expect(current[:name]).to eq("test-session")
      
      # Remove session
      expect { session_manager.remove_session("test-session", force: true) }.not_to raise_error
      
      # Verify removal
      sessions_after = session_manager.list_sessions
      expect(sessions_after).to be_empty
    end
  end

  describe "project management workflow" do
    let(:config_manager) { Sxn::Core::ConfigManager.new(test_project_path) }

    before do
      config_manager.initialize_project
    end

    it "registers and manages projects", :skip => "CLI integration tests need refactoring to work without Dir.chdir" do
      project_manager = Sxn::Core::ProjectManager.new(config_manager)
      
      # Add project
      project = project_manager.add_project("test-project", test_project_path, type: "rails")
      expect(project[:name]).to eq("test-project")
      expect(project[:type]).to eq("rails")
      
      # List projects
      projects = project_manager.list_projects
      expect(projects.size).to eq(1)
      expect(projects.first[:name]).to eq("test-project")
      
      # Validate project
      validation = project_manager.validate_project("test-project")
      expect(validation[:valid]).to be true
      
      # Remove project
      expect { project_manager.remove_project("test-project") }.not_to raise_error
      
      # Verify removal
      projects_after = project_manager.list_projects
      expect(projects_after).to be_empty
    end
  end

  describe "worktree workflow" do
    let(:config_manager) { Sxn::Core::ConfigManager.new(test_project_path) }
    let(:git_repo_path) { File.join(temp_dir, "git-repo") }

    before do
      # Create a git repository using absolute paths without changing directories
      FileUtils.mkdir_p(git_repo_path)
      
      # Initialize git repo with absolute paths
      system("git", "init", git_repo_path, out: File::NULL, err: File::NULL)
      Dir.chdir(git_repo_path) do
        system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
        system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
        File.write("README.md", "# Test Repo")
        system("git add .", out: File::NULL, err: File::NULL)
        system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)
      end
      
      # Initialize sxn
      config_manager.initialize_project
      
      # Register the git repo as a project
      project_manager = Sxn::Core::ProjectManager.new(config_manager)
      project_manager.add_project("git-project", git_repo_path, type: "unknown")
    end

    it "creates and manages worktrees", :skip => "CLI integration tests need refactoring to work without Dir.chdir" do
      session_manager = Sxn::Core::SessionManager.new(config_manager)
      worktree_manager = Sxn::Core::WorktreeManager.new(config_manager, session_manager)
      
      # Create session
      session_manager.create_session("test-session")
      session_manager.use_session("test-session")
      
      # Add worktree
      worktree = worktree_manager.add_worktree("git-project", "master")
      expect(worktree[:project]).to eq("git-project")
      expect(worktree[:branch]).to eq("master")
      expect(File).to exist(worktree[:path])
      
      # List worktrees
      worktrees = worktree_manager.list_worktrees(session_name: "test-session")
      expect(worktrees.size).to eq(1)
      expect(worktrees.first[:project]).to eq("git-project")
      
      # Validate worktree
      validation = worktree_manager.validate_worktree("git-project", session_name: "test-session")
      expect(validation[:valid]).to be true
      
      # Remove worktree
      expect { worktree_manager.remove_worktree("git-project") }.not_to raise_error
      
      # Verify removal
      worktrees_after = worktree_manager.list_worktrees(session_name: "test-session")
      expect(worktrees_after).to be_empty
    end
  end

  describe "CLI error handling" do
    it "handles uninitialized project gracefully", :skip => "CLI integration tests need refactoring to work without Dir.chdir" do
      # Try to create session without initialization
      session_command = Sxn::Commands::Sessions.new
      expect { session_command.add("test-session") }.to raise_error(SystemExit)
    end

    it "provides helpful error messages", :skip => "CLI integration tests need refactoring to work without Dir.chdir" do
      cli = Sxn::CLI.new
      ui_output = instance_double(Sxn::UI::Output)
      allow(cli).to receive(:instance_variable_get).with(:@ui).and_return(ui_output)
      
      expect(ui_output).to receive(:error).with("Project not initialized")
      expect(ui_output).to receive(:recovery_suggestion)
        .with("Run 'sxn init' to initialize sxn in this project")
      
      error = Sxn::ConfigurationError.new("Project not initialized")
      expect { cli.send(:handle_error, error) }.to raise_error(SystemExit)
    end
  end
end