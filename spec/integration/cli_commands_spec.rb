# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "CLI Command Integration" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_project_path) { File.join(temp_dir, "test-project") }
  let(:git_repo_path) { File.join(temp_dir, "git-repo") }
  let(:original_dir) { Dir.pwd }

  before do
    # Create a test project directory
    FileUtils.mkdir_p(test_project_path)
    File.write(File.join(test_project_path, "Gemfile"), "source 'https://rubygems.org'\ngem 'rails'")
    File.write(File.join(test_project_path, ".gitignore"), "node_modules/\n.env")
    
    # Make it a git repository for project validation to work
    Dir.chdir(test_project_path) do
      system("git init --quiet")
      system("git config user.email 'test@example.com'")
      system("git config user.name 'Test User'")
      File.write("README.md", "# Test Project")
      system("git add .")
      system("git commit --quiet -m 'Initial commit'")
    end
    
    # Ensure test isolation by resetting environment
    ENV.delete("SXN_CONFIG_PATH")
    ENV.delete("SXN_DATABASE_PATH")
  end

  after do
    # Clean up git worktrees first before removing directories
    cleanup_git_worktrees
    # Clean up temp directory
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end
  
  def cleanup_git_worktrees
    return unless Dir.exist?(git_repo_path)
    
    Dir.chdir(git_repo_path) do
      # List and remove all worktrees
      worktrees_output = `git worktree list --porcelain 2>/dev/null` rescue ""
      worktree_paths = worktrees_output.lines
                                        .select { |line| line.start_with?("worktree ") }
                                        .map { |line| line.sub(/^worktree /, "").strip }
                                        .reject { |path| path == git_repo_path } # Skip main repo
      
      worktree_paths.each do |path|
        system("git worktree remove #{path} --force 2>/dev/null")
      end
    end
  rescue => e
    # Ignore cleanup errors
  end

  describe "sxn init workflow" do
    it "initializes a project and creates required directories" do
      # Initialize directly with ConfigManager using explicit path
      config_manager = Sxn::Core::ConfigManager.new(test_project_path)
      sessions_folder = File.join(test_project_path, "sessions")
      
      # Initialize project
      result_sessions_folder = config_manager.initialize_project(sessions_folder)
      
      # Verify initialization
      expect(File.exist?(File.join(test_project_path, ".sxn", "config.yml"))).to be true
      expect(File.exist?(File.join(test_project_path, ".sxn", "sessions.db"))).to be true
      expect(Dir.exist?(result_sessions_folder)).to be true
      expect(result_sessions_folder).to eq(sessions_folder)
      
      # Verify config manager works
      expect(config_manager.initialized?).to be true
      expect(config_manager.sessions_folder_path).to eq(sessions_folder)
    end
  end

  describe "end-to-end session workflow" do
    let(:config_manager) { Sxn::Core::ConfigManager.new(test_project_path) }

    before do
      # Initialize sxn first
      sessions_folder = File.join(test_project_path, "sessions")
      config_manager.initialize_project(sessions_folder)
    end

    it "creates, lists, and manages sessions" do
      session_manager = Sxn::Core::SessionManager.new(config_manager)

      # Create a session
      session = session_manager.create_session("test-session", description: "Test session")
      expect(session[:name]).to eq("test-session")
      expect(session[:status]).to eq("active")
      expect(session[:path]).to start_with(test_project_path)

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
      sessions_folder = File.join(test_project_path, "sessions")
      config_manager.initialize_project(sessions_folder)
    end

    it "registers and manages projects" do
      project_manager = Sxn::Core::ProjectManager.new(config_manager)

      # Add project
      project = project_manager.add_project("test-project", test_project_path, type: "rails")
      expect(project[:name]).to eq("test-project")
      expect(project[:type]).to eq("rails")
      expect(project[:path]).to eq(test_project_path)

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
        # Ensure we have the main branch set up properly
        current_branch = `git branch --show-current`.strip
        if current_branch != "main"
          system("git branch -m #{current_branch} main", out: File::NULL, err: File::NULL)
        end
      end

      # Initialize sxn
      sessions_folder = File.join(test_project_path, "sessions")
      config_manager.initialize_project(sessions_folder)

      # Register the git repo as a project
      project_manager = Sxn::Core::ProjectManager.new(config_manager)
      project_manager.add_project("git-project", git_repo_path, type: "unknown")
    end

    it "creates and manages worktrees" do
      session_manager = Sxn::Core::SessionManager.new(config_manager)
      worktree_manager = Sxn::Core::WorktreeManager.new(config_manager, session_manager)

      # Create session
      session_manager.create_session("test-session")
      session_manager.use_session("test-session")

      # Add worktree using a new branch (worktrees can't share the same branch)
      worktree = worktree_manager.add_worktree("git-project", "feature-branch")
      expect(worktree[:project]).to eq("git-project")
      expect(worktree[:branch]).to eq("feature-branch")
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
    it "handles uninitialized project gracefully" do
      # Create a new directory that is NOT initialized
      uninitialized_path = File.join(temp_dir, "uninitialized-project")
      FileUtils.mkdir_p(uninitialized_path)
      
      # Change to uninitialized project directory temporarily for CLI test
      original_dir = Dir.pwd
      Dir.chdir(uninitialized_path)
      
      begin
        # Try to create session without initialization
        # The Sessions constructor will fail when trying to initialize the database
        expect { Sxn::Commands::Sessions.new }.to raise_error(Sxn::ConfigurationError)
      ensure
        Dir.chdir(original_dir)
      end
    end

    it "provides helpful error messages" do
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
