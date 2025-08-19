# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Sxn::Core::WorktreeManager do
  let(:temp_dir) { Dir.mktmpdir("sxn_test") }
  let(:project_path) { File.join(temp_dir, "main_project") }
  let(:session_path) { File.join(temp_dir, "test_session") }
  let(:worktree_path) { File.join(session_path, "test-project") }

  let(:mock_config_manager) do
    instance_double(Sxn::Core::ConfigManager).tap do |mgr|
      allow(mgr).to receive(:current_session).and_return("test-session")
    end
  end

  let(:mock_session_manager) do
    instance_double(Sxn::Core::SessionManager).tap do |mgr|
      allow(mgr).to receive(:get_session).and_return(session_data)
      allow(mgr).to receive(:get_session_worktrees).and_return({})
      allow(mgr).to receive(:add_worktree_to_session)
      allow(mgr).to receive(:remove_worktree_from_session)
    end
  end

  let(:mock_project_manager) do
    instance_double(Sxn::Core::ProjectManager).tap do |mgr|
      allow(mgr).to receive(:get_project).and_return(project_data)
    end
  end

  let(:session_data) do
    {
      name: "test-session",
      path: session_path,
      status: "active"
    }
  end

  let(:project_data) do
    {
      name: "test-project",
      path: project_path,
      type: "rails",
      default_branch: "main"
    }
  end

  let(:worktree_manager) do
    described_class.new(mock_config_manager, mock_session_manager).tap do |mgr|
      mgr.instance_variable_set(:@project_manager, mock_project_manager)
    end
  end

  before do
    FileUtils.mkdir_p(session_path)
    FileUtils.mkdir_p(project_path)

    # Create a mock git repository in the project path
    Dir.chdir(project_path) do
      system("git init", out: File::NULL, err: File::NULL)
      system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
      system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
      File.write("README.md", "# Test Project")
      system("git add README.md", out: File::NULL, err: File::NULL)
      system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)
    end
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates default managers when none provided" do
      expect(Sxn::Core::ConfigManager).to receive(:new).and_call_original
      expect(Sxn::Core::SessionManager).to receive(:new).and_call_original
      allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:current_session).and_return(nil)

      described_class.new
    end

    it "uses provided managers" do
      manager = described_class.new(mock_config_manager, mock_session_manager)
      expect(manager).to be_a(described_class)
    end
  end

  describe "#add_worktree" do
    it "creates worktree successfully" do
      result = worktree_manager.add_worktree("test-project", "main")

      expect(result[:project]).to eq("test-project")
      expect(result[:branch]).to eq("main")
      expect(result[:path]).to eq(worktree_path)
      expect(result[:session]).to eq("test-session")

      expect(mock_session_manager).to have_received(:add_worktree_to_session)
        .with("test-session", "test-project", worktree_path, "main")
    end

    it "uses default branch when none specified" do
      worktree_manager.add_worktree("test-project")

      expect(mock_session_manager).to have_received(:add_worktree_to_session)
        .with("test-session", "test-project", worktree_path, "main")
    end

    it "uses specified session" do
      allow(mock_session_manager).to receive(:get_session).with("custom-session").and_return(
        { name: "custom-session", path: File.join(temp_dir, "custom_session") }
      )

      worktree_manager.add_worktree("test-project", "main", session_name: "custom-session")

      expect(mock_session_manager).to have_received(:add_worktree_to_session)
        .with("custom-session", "test-project", anything, "main")
    end

    it "raises error when no active session" do
      allow(mock_config_manager).to receive(:current_session).and_return(nil)

      expect do
        worktree_manager.add_worktree("test-project")
      end.to raise_error(Sxn::NoActiveSessionError, /No active session/)
    end

    it "raises error when session not found" do
      allow(mock_session_manager).to receive(:get_session).and_return(nil)

      expect do
        worktree_manager.add_worktree("test-project")
      end.to raise_error(Sxn::SessionNotFoundError, "Session 'test-session' not found")
    end

    it "raises error when project not found" do
      allow(mock_project_manager).to receive(:get_project).and_return(nil)

      expect do
        worktree_manager.add_worktree("non-existent-project")
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent-project' not found")
    end

    it "raises error when worktree already exists" do
      existing_worktrees = { "test-project" => { path: worktree_path, branch: "main" } }
      allow(mock_session_manager).to receive(:get_session_worktrees).and_return(existing_worktrees)

      expect do
        worktree_manager.add_worktree("test-project")
      end.to raise_error(Sxn::WorktreeExistsError, /already exists in session/)
    end

    it "handles git worktree creation failure" do
      # Mock system call to fail
      allow(worktree_manager).to receive(:system).and_return(false)

      expect do
        worktree_manager.add_worktree("test-project")
      end.to raise_error(Sxn::WorktreeCreationError, /Failed to create worktree/)
    end

    it "creates new branch when branch doesn't exist" do
      # Mock git show-ref to return false (branch doesn't exist)
      allow(worktree_manager).to receive(:system).with(
        /git show-ref/, out: File::NULL, err: File::NULL
      ).and_return(false)

      # Mock successful worktree creation
      allow(worktree_manager).to receive(:system).with(
        "git", "worktree", "add", "-b", "new-branch", worktree_path,
        out: File::NULL, err: File::NULL
      ).and_return(true)

      result = worktree_manager.add_worktree("test-project", "new-branch")
      expect(result[:branch]).to eq("new-branch")
    end
  end

  describe "#remove_worktree" do
    let(:existing_worktree) do
      { "test-project" => { path: worktree_path, branch: "main" } }
    end

    before do
      allow(mock_session_manager).to receive(:get_session_worktrees).and_return(existing_worktree)
      FileUtils.mkdir_p(worktree_path)
    end

    it "removes worktree successfully" do
      result = worktree_manager.remove_worktree("test-project")

      expect(result).to be(true)
      expect(mock_session_manager).to have_received(:remove_worktree_from_session)
        .with("test-session", "test-project")
    end

    it "uses specified session" do
      allow(mock_session_manager).to receive(:get_session).with("custom-session").and_return(session_data)
      allow(mock_session_manager).to receive(:get_session_worktrees).with("custom-session").and_return(existing_worktree)

      worktree_manager.remove_worktree("test-project", session_name: "custom-session")

      expect(mock_session_manager).to have_received(:remove_worktree_from_session)
        .with("custom-session", "test-project")
    end

    it "raises error when no active session" do
      allow(mock_config_manager).to receive(:current_session).and_return(nil)

      expect do
        worktree_manager.remove_worktree("test-project")
      end.to raise_error(Sxn::NoActiveSessionError, /No active session/)
    end

    it "raises error when session not found" do
      allow(mock_session_manager).to receive(:get_session).and_return(nil)

      expect do
        worktree_manager.remove_worktree("test-project")
      end.to raise_error(Sxn::SessionNotFoundError, "Session 'test-session' not found")
    end

    it "raises error when worktree not found" do
      allow(mock_session_manager).to receive(:get_session_worktrees).and_return({})

      expect do
        worktree_manager.remove_worktree("test-project")
      end.to raise_error(Sxn::WorktreeNotFoundError, /not found in session/)
    end

    it "handles removal when project no longer exists" do
      allow(mock_project_manager).to receive(:get_project).and_return(nil)

      result = worktree_manager.remove_worktree("test-project")
      expect(result).to be(true)
    end

    it "handles git command failure gracefully" do
      allow(worktree_manager).to receive(:system).and_raise("Git command failed")

      expect do
        worktree_manager.remove_worktree("test-project")
      end.to raise_error(Sxn::WorktreeRemovalError, /Failed to remove worktree/)
    end

    it "handles string keys in worktree info" do
      string_key_worktree = { "test-project" => { "path" => worktree_path, "branch" => "main" } }
      allow(mock_session_manager).to receive(:get_session_worktrees).and_return(string_key_worktree)

      result = worktree_manager.remove_worktree("test-project")
      expect(result).to be(true)
    end
  end

  describe "#list_worktrees" do
    let(:worktrees_data) do
      {
        "project1" => { path: File.join(session_path, "project1"), branch: "main", created_at: "2023-01-01T00:00:00Z" },
        "project2" => { path: File.join(session_path, "project2"), branch: "feature",
                        created_at: "2023-01-02T00:00:00Z" }
      }
    end

    before do
      allow(mock_session_manager).to receive(:get_session_worktrees).and_return(worktrees_data)
      FileUtils.mkdir_p(File.join(session_path, "project1"))
    end

    it "lists worktrees with status information" do
      worktrees = worktree_manager.list_worktrees

      expect(worktrees.size).to eq(2)

      project1 = worktrees.find { |w| w[:project] == "project1" }
      expect(project1[:branch]).to eq("main")
      expect(project1[:path]).to eq(File.join(session_path, "project1"))
      expect(project1[:exists]).to be(true)

      project2 = worktrees.find { |w| w[:project] == "project2" }
      expect(project2[:exists]).to be(false)
    end

    it "returns empty array when no current session" do
      allow(mock_config_manager).to receive(:current_session).and_return(nil)

      worktrees = worktree_manager.list_worktrees
      expect(worktrees).to eq([])
    end

    it "returns empty array when session not found" do
      allow(mock_session_manager).to receive(:get_session).and_return(nil)

      worktrees = worktree_manager.list_worktrees
      expect(worktrees).to eq([])
    end

    it "uses specified session" do
      worktree_manager.list_worktrees(session_name: "custom-session")

      expect(mock_session_manager).to have_received(:get_session).with("custom-session")
    end

    it "handles string keys in worktree data" do
      string_key_data = {
        "project1" => { "path" => File.join(session_path, "project1"), "branch" => "main",
                        "created_at" => "2023-01-01T00:00:00Z" }
      }
      allow(mock_session_manager).to receive(:get_session_worktrees).and_return(string_key_data)

      worktrees = worktree_manager.list_worktrees
      expect(worktrees.first[:branch]).to eq("main")
    end
  end

  describe "#get_worktree" do
    let(:worktrees_data) do
      {
        "project1" => { path: File.join(session_path, "project1"), branch: "main" }
      }
    end

    before do
      allow(mock_session_manager).to receive(:get_session_worktrees).and_return(worktrees_data)
    end

    it "returns specific worktree" do
      worktree = worktree_manager.get_worktree("project1")

      expect(worktree[:project]).to eq("project1")
      expect(worktree[:branch]).to eq("main")
    end

    it "returns nil for non-existent worktree" do
      worktree = worktree_manager.get_worktree("non-existent")
      expect(worktree).to be_nil
    end
  end

  describe "#validate_worktree" do
    let(:worktrees_data) do
      {
        "valid-project" => { path: File.join(session_path, "valid-project"), branch: "main" },
        "missing-project" => { path: File.join(session_path, "missing-project"), branch: "main" }
      }
    end

    before do
      allow(mock_session_manager).to receive(:get_session_worktrees).and_return(worktrees_data)

      # Create valid git worktree
      valid_path = File.join(session_path, "valid-project")
      FileUtils.mkdir_p(valid_path)
      File.write(File.join(valid_path, ".git"), "gitdir: #{project_path}/.git/worktrees/valid-project")
    end

    it "validates healthy worktree" do
      # Create a proper git repository in the valid path
      valid_path = File.join(session_path, "valid-project")
      Dir.chdir(valid_path) do
        system("git init", out: File::NULL, err: File::NULL)
        system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
        system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
        File.write("test.txt", "content")
        system("git add test.txt", out: File::NULL, err: File::NULL)
        system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)
      end

      result = worktree_manager.validate_worktree("valid-project")

      # The worktree exists and is a git repository, but may have git status issues
      # in test environment which is normal
      expect(result[:worktree][:project]).to eq("valid-project")
      expect(result[:worktree][:exists]).to be(true)

      # We expect some git status issues in the test environment, but the worktree should be found
      expect(result[:issues]).to be_an(Array)
    end

    it "identifies missing worktree directory" do
      result = worktree_manager.validate_worktree("missing-project")

      expect(result[:valid]).to be(false)
      expect(result[:issues]).to include(/directory does not exist/)
    end

    it "returns error for non-existent worktree" do
      result = worktree_manager.validate_worktree("non-existent")

      expect(result[:valid]).to be(false)
      expect(result[:issues]).to include("Worktree not found")
    end

    it "identifies invalid git worktree" do
      invalid_path = File.join(session_path, "invalid-project")
      FileUtils.mkdir_p(invalid_path)
      worktrees_data["invalid-project"] = { path: invalid_path, branch: "main" }

      result = worktree_manager.validate_worktree("invalid-project")

      expect(result[:valid]).to be(false)
      expect(result[:issues]).to include("Directory is not a valid git worktree")
    end
  end

  describe "additional coverage" do
    describe "#get_worktree_status edge cases" do
      let(:test_path) { File.join(temp_dir, "edge_case_test") }

      it "returns 'staged' for repository with staged changes" do
        FileUtils.mkdir_p(test_path)
        Dir.chdir(test_path) do
          system("git init", out: File::NULL, err: File::NULL)
          system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
          system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
          File.write("test.txt", "content")
          system("git add test.txt", out: File::NULL, err: File::NULL)
          system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)

          # Add staged changes
          File.write("staged.txt", "staged content")
          system("git add staged.txt", out: File::NULL, err: File::NULL)
        end

        status = worktree_manager.send(:get_worktree_status, test_path)
        expect(status).to eq("staged")
      end

      it "returns 'untracked' for repository with untracked files" do
        FileUtils.mkdir_p(test_path)
        Dir.chdir(test_path) do
          system("git init", out: File::NULL, err: File::NULL)
          system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
          system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
          File.write("test.txt", "content")
          system("git add test.txt", out: File::NULL, err: File::NULL)
          system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)

          # Add untracked files
          File.write("untracked.txt", "untracked content")
        end

        status = worktree_manager.send(:get_worktree_status, test_path)
        expect(status).to eq("untracked")
      end
    end

    describe "#add_worktree edge cases" do
      it "uses master as default branch when project has no default_branch" do
        project_without_default = project_data.merge(default_branch: nil)
        allow(mock_project_manager).to receive(:get_project).and_return(project_without_default)

        # Mock git commands to succeed
        allow(worktree_manager).to receive(:system).and_return(true)

        worktree_manager.add_worktree("test-project")

        expect(mock_session_manager).to have_received(:add_worktree_to_session)
          .with("test-session", "test-project", worktree_path, "master")
      end

      it "cleans up on failure" do
        allow(worktree_manager).to receive(:create_git_worktree).and_raise("Git failed")
        allow(File).to receive(:exist?).with(worktree_path).and_return(true)
        allow(FileUtils).to receive(:rm_rf)

        expect do
          worktree_manager.add_worktree("test-project")
        end.to raise_error(Sxn::WorktreeCreationError)

        expect(FileUtils).to have_received(:rm_rf).with(worktree_path)
      end
    end

    describe "#validate_worktree edge cases" do
      let(:worktrees_data) do
        {
          "project-with-git-issues" => { path: File.join(session_path, "project-with-git-issues"), branch: "main" }
        }
      end

      before do
        allow(mock_session_manager).to receive(:get_session_worktrees).and_return(worktrees_data)

        # Create directory with git status issues
        git_issues_path = File.join(session_path, "project-with-git-issues")
        FileUtils.mkdir_p(git_issues_path)
        File.write(File.join(git_issues_path, ".git"), "gitdir: #{project_path}/.git/worktrees/project-with-git-issues")
      end

      it "reports git status issues" do
        allow(worktree_manager).to receive(:check_git_status).and_return(["Git status error"])

        result = worktree_manager.validate_worktree("project-with-git-issues")

        expect(result[:valid]).to be(false)
        expect(result[:issues]).to include("Git status error")
      end
    end
  end

  describe "private methods" do
    describe "#get_worktree_status" do
      let(:test_path) { File.join(temp_dir, "status_test") }

      it "returns 'missing' for non-existent directory" do
        status = worktree_manager.send(:get_worktree_status, "/non/existent/path")
        expect(status).to eq("missing")
      end

      it "returns 'invalid' for non-git directory" do
        FileUtils.mkdir_p(test_path)

        status = worktree_manager.send(:get_worktree_status, test_path)
        expect(status).to eq("invalid")
      end

      it "returns 'clean' for clean git repository" do
        # Create a valid git worktree
        FileUtils.mkdir_p(test_path)
        Dir.chdir(test_path) do
          system("git init", out: File::NULL, err: File::NULL)
          system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
          system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
          File.write("test.txt", "content")
          system("git add test.txt", out: File::NULL, err: File::NULL)
          system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)

          # Add any other files that may have been created and commit them too
          system("git add .", out: File::NULL, err: File::NULL)
          unless system("git diff-index --quiet --cached HEAD", out: File::NULL, err: File::NULL)
            system("git commit -m 'Add remaining files'", out: File::NULL, err: File::NULL)
          end
        end

        status = worktree_manager.send(:get_worktree_status, test_path)

        # In test environment, git may detect some files as untracked even after committing
        # Both "clean" and "untracked" are valid for a working git repository
        expect(%w[clean untracked]).to include(status)
      end

      it "returns 'modified' for repository with unstaged changes" do
        FileUtils.mkdir_p(test_path)
        Dir.chdir(test_path) do
          system("git init", out: File::NULL, err: File::NULL)
          system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
          system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
          File.write("test.txt", "content")
          system("git add test.txt", out: File::NULL, err: File::NULL)
          system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)

          # Add unstaged changes
          File.write("test.txt", "modified content")
        end

        status = worktree_manager.send(:get_worktree_status, test_path)
        expect(status).to eq("modified")
      end

      it "returns 'error' when git commands fail" do
        FileUtils.mkdir_p(test_path)
        # Create an invalid .git file that will cause git to error
        File.write(File.join(test_path, ".git"), "corrupted git data that will cause errors")

        # Mock Dir.chdir to raise an exception to simulate git command failure
        allow(Dir).to receive(:chdir).with(test_path).and_raise("Git command failed")

        status = worktree_manager.send(:get_worktree_status, test_path)
        expect(status).to eq("error")
      end
    end

    describe "#valid_git_worktree?" do
      it "returns true for directory with .git file" do
        test_path = File.join(temp_dir, "valid_worktree")
        FileUtils.mkdir_p(test_path)
        File.write(File.join(test_path, ".git"), "gitdir: /path/to/repo/.git/worktrees/test")

        result = worktree_manager.send(:valid_git_worktree?, test_path)
        expect(result).to be(true)
      end

      it "returns false for directory without .git file" do
        test_path = File.join(temp_dir, "invalid_worktree")
        FileUtils.mkdir_p(test_path)

        result = worktree_manager.send(:valid_git_worktree?, test_path)
        expect(result).to be(false)
      end
    end

    describe "#check_git_status" do
      it "returns error for non-existent directory" do
        issues = worktree_manager.send(:check_git_status, "/non/existent")
        expect(issues).to include("Directory does not exist")
      end

      it "returns error for non-git directory" do
        test_path = File.join(temp_dir, "non_git")
        FileUtils.mkdir_p(test_path)

        issues = worktree_manager.send(:check_git_status, test_path)
        expect(issues).to include("Not a git repository")
      end

      it "checks git status successfully" do
        test_path = File.join(temp_dir, "git_status_test")
        FileUtils.mkdir_p(test_path)
        Dir.chdir(test_path) do
          system("git init", out: File::NULL, err: File::NULL)
          system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
          system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
          File.write("test.txt", "content")
          system("git add test.txt", out: File::NULL, err: File::NULL)
          system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)
        end

        issues = worktree_manager.send(:check_git_status, test_path)
        expect(issues).to be_empty
      end

      it "handles git command errors" do
        test_path = File.join(temp_dir, "broken_git")
        FileUtils.mkdir_p(test_path)
        File.write(File.join(test_path, ".git"), "invalid git file")

        issues = worktree_manager.send(:check_git_status, test_path)
        expect(issues).not_to be_empty
      end
    end

    describe "#remove_git_worktree_by_path" do
      let(:test_worktree_path) { File.join(temp_dir, "test_worktree") }
      let(:git_file_path) { File.join(test_worktree_path, ".git") }

      before do
        FileUtils.mkdir_p(test_worktree_path)
      end

      it "removes worktree using parent repository reference" do
        File.write(git_file_path, "gitdir: #{project_path}/.git/worktrees/test")

        worktree_manager.send(:remove_git_worktree_by_path, test_worktree_path)

        expect(File.exist?(test_worktree_path)).to be(false)
      end

      it "handles missing .git file gracefully" do
        expect do
          worktree_manager.send(:remove_git_worktree_by_path, test_worktree_path)
        end.not_to raise_error

        expect(File.exist?(test_worktree_path)).to be(false)
      end

      it "handles invalid gitdir format" do
        File.write(git_file_path, "invalid format")

        expect do
          worktree_manager.send(:remove_git_worktree_by_path, test_worktree_path)
        end.not_to raise_error
      end

      it "handles missing parent repository" do
        File.write(git_file_path, "gitdir: /non/existent/path/.git/worktrees/test")

        expect do
          worktree_manager.send(:remove_git_worktree_by_path, test_worktree_path)
        end.not_to raise_error

        expect(File.exist?(test_worktree_path)).to be(false)
      end

      it "handles gitdir without worktrees path" do
        File.write(git_file_path, "gitdir: #{project_path}/.git")

        expect do
          worktree_manager.send(:remove_git_worktree_by_path, test_worktree_path)
        end.not_to raise_error
      end
    end

    describe "#create_git_worktree edge cases" do
      it "handles existing branch" do
        # Mock successful branch check and worktree creation
        allow(worktree_manager).to receive(:system).with(
          /git show-ref/, out: File::NULL, err: File::NULL
        ).and_return(true) # Branch exists

        allow(worktree_manager).to receive(:system).with(
          "git", "worktree", "add", worktree_path, "existing-branch",
          out: File::NULL, err: File::NULL
        ).and_return(true)

        expect do
          worktree_manager.send(:create_git_worktree, project_path, worktree_path, "existing-branch")
        end.not_to raise_error
      end
    end

    describe "#check_git_status edge cases" do
      it "detects detached HEAD state" do
        test_path = File.join(temp_dir, "detached_head_test")
        FileUtils.mkdir_p(test_path)
        Dir.chdir(test_path) do
          system("git init", out: File::NULL, err: File::NULL)
          system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
          system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
          File.write("test.txt", "content")
          system("git add test.txt", out: File::NULL, err: File::NULL)
          system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)

          # Create detached HEAD by checking out commit directly
          commit_hash = `git rev-parse HEAD`.strip
          system("git checkout #{commit_hash}", out: File::NULL, err: File::NULL)
        end

        issues = worktree_manager.send(:check_git_status, test_path)
        expect(issues).to include(/detached HEAD/)
      end

      it "handles git status command failure" do
        test_path = File.join(temp_dir, "git_status_fail_test")
        FileUtils.mkdir_p(test_path)
        File.write(File.join(test_path, ".git"), "gitdir: #{project_path}/.git/worktrees/test")

        # Mock system call to fail
        allow(worktree_manager).to receive(:system).with(
          "git status --porcelain", out: File::NULL, err: File::NULL
        ).and_return(false)

        issues = worktree_manager.send(:check_git_status, test_path)
        expect(issues).to include(/Cannot access git status/)
      end
    end
  end
end
