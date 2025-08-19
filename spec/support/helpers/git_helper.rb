# frozen_string_literal: true

require "English"
module GitHelper
  def setup_test_repository(path)
    Dir.chdir(path) do
      `git init --quiet`
      `git config user.name "Test User"`
      `git config user.email "test@example.com"`

      # Create initial structure
      FileUtils.mkdir_p("app")
      FileUtils.mkdir_p("config")
      FileUtils.mkdir_p("spec")

      File.write("README.md", "# Test Project")
      File.write("Gemfile", 'source "https://rubygems.org"')
      File.write("app/application.rb", "# Application code")

      `git add .`
      `git commit --quiet -m "Initial commit"`

      # Create a feature branch for testing
      `git checkout -b feature/test-branch --quiet`
      File.write("new_feature.rb", "# New feature")
      `git add new_feature.rb`
      `git commit --quiet -m "Add new feature"`
      `git checkout master --quiet`
    end
  end

  def create_git_worktree(repo_path, worktree_path, branch = nil)
    Dir.chdir(repo_path) do
      if branch
        `git worktree add #{worktree_path} #{branch} 2>/dev/null`
      else
        `git worktree add #{worktree_path} 2>/dev/null`
      end

      $CHILD_STATUS.success?
    end
  end

  def remove_git_worktree(repo_path, worktree_path)
    Dir.chdir(repo_path) do
      `git worktree remove #{worktree_path} --force 2>/dev/null`
      $CHILD_STATUS.success?
    end
  end

  def git_branch_exists?(repo_path, branch)
    Dir.chdir(repo_path) do
      `git show-ref --verify --quiet refs/heads/#{branch}`
      $CHILD_STATUS.success?
    end
  end

  def current_git_branch(path = ".")
    Dir.chdir(path) do
      `git branch --show-current`.strip
    end
  end
end
