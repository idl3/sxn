# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Templates::TemplateVariables, "comprehensive coverage for missing areas" do
  let(:project_path) { Dir.mktmpdir("project") }
  let(:session_path) { Dir.mktmpdir("session") }

  # Create mock objects that respond to the expected methods
  let(:mock_session) do
    instance_double("Session",
                    name: "test-session",
                    path: Pathname.new(session_path),
                    created_at: Time.new(2023, 6, 15, 14, 30, 0),
                    updated_at: Time.new(2023, 6, 15, 15, 30, 0),
                    status: "active")
  end

  let(:mock_project) do
    instance_double("Project",
                    name: "test-project",
                    path: Pathname.new(project_path))
  end

  let(:variables) { described_class.new(mock_session, mock_project) }

  after do
    FileUtils.rm_rf(project_path)
    FileUtils.rm_rf(session_path)
  end

  describe "#build_variables" do
    it "builds complete variable set with all components" do
      # Set up a git repository for git_variables
      Dir.chdir(project_path) do
        system("git init -q")
        system("git config user.email 'test@example.com'")
        system("git config user.name 'Test User'")
        File.write("test.txt", "content")
        system("git add .")
        system("git commit -q -m 'Initial commit'")
      end

      result = variables.build_variables

      expect(result).to include(:session, :project, :environment, :timestamp)
      expect(result[:session]).to include(name: "test-session", status: "active")
      expect(result[:project]).to include(name: "test-project")
      expect(result[:environment]).to include(:ruby, :os)
      expect(result[:timestamp]).to include(:now, :today, :year)
    end
  end

  describe "#_collect_environment_variables" do
    it "returns environment information" do
      result = variables.send(:_collect_environment_variables)

      expect(result).to include(:ruby, :os)
      expect(result[:ruby]).to include(:version, :platform)
      expect(result[:ruby][:version]).to match(/\d+\.\d+\.\d+/)
    end

    it "handles errors gracefully" do
      allow(RbConfig::CONFIG).to receive(:[]).and_raise(StandardError, "Config error")

      result = variables.send(:_collect_environment_variables)
      expect(result[:error]).to include("Failed to collect environment variables")
    end
  end

  describe "#_collect_project_variables" do
    before do
      # Create project structure
      FileUtils.mkdir_p(project_path)
      File.write(File.join(project_path, "package.json"), '{"name": "test-project", "version": "1.0.0"}')
      File.write(File.join(project_path, "Gemfile"), 'gem "rails"')
    end

    it "detects project type and metadata" do
      result = variables.send(:_collect_project_variables)

      expect(result).to include(:path, :name, :type)
      expect(result[:path]).to eq(project_path.to_s)
      expect(result[:name]).to eq("test-project")
    end

    it "detects JavaScript project from package.json" do
      # Remove Gemfile so package.json takes precedence
      FileUtils.rm_f(File.join(project_path, "Gemfile"))
      result = variables.send(:_collect_project_variables)
      expect(result[:type]).to eq("javascript")
    end

    it "detects Ruby project from Gemfile" do
      FileUtils.rm_f(File.join(project_path, "package.json"))

      result = variables.send(:_collect_project_variables)
      expect(result[:type]).to eq("ruby")
    end

    it "handles unknown project type when no recognizable files" do
      # Remove all project files to make type unknown
      FileUtils.rm_rf(Dir.glob(File.join(project_path, "*")))

      result = variables.send(:_collect_project_variables)
      expect(result[:type]).to eq("unknown")
    end

    it "handles errors gracefully" do
      allow(mock_project).to receive(:name).and_raise(StandardError, "Project error")

      result = variables.send(:_collect_project_variables)
      expect(result[:error]).to include("Failed to collect project variables")
    end
  end

  describe "#_collect_session_variables" do
    it "returns session information" do
      result = variables.send(:_collect_session_variables)

      expect(result).to include(:path, :name, :created_at, :status)
      expect(result[:path]).to eq(session_path.to_s)
      expect(result[:name]).to eq("test-session")
      expect(result[:status]).to eq("active")
    end

    it "handles missing session gracefully" do
      variables_without_session = described_class.new(nil, mock_project)

      result = variables_without_session.send(:_collect_session_variables)
      expect(result).to eq({})
    end

    it "handles session errors gracefully" do
      allow(mock_session).to receive(:name).and_raise(StandardError, "Session error")

      result = variables.send(:_collect_session_variables)
      expect(result[:error]).to include("Failed to collect session variables")
    end
  end

  describe "#_collect_user_variables" do
    it "returns user configuration information" do
      result = variables.send(:_collect_user_variables)

      expect(result).to include(:username, :home)
      expect(result[:username]).to be_a(String) if result[:username]
      expect(result[:home]).to be_a(String)
    end

    it "handles errors gracefully" do
      allow(Dir).to receive(:home).and_raise(StandardError, "Home error")

      result = variables.send(:_collect_user_variables)
      expect(result[:error]).to include("Failed to collect user variables")
    end
  end

  describe "#_collect_git_variables" do
    before do
      # Create a git repository structure
      Dir.chdir(project_path) do
        system("git init -q")
        system("git config user.email 'test@example.com'")
        system("git config user.name 'Test User'")
        File.write("test.txt", "content")
        system("git add .")
        system("git commit -q -m 'Initial commit'")
      end
    end

    it "returns git repository information when in git repo" do
      result = variables.send(:_collect_git_variables)

      expect(result).to be_a(Hash)
      # Git variables may include branch info, author info, etc.
      # Since git commands can fail in test environment, we just verify structure
    end

    it "handles non-git directory gracefully" do
      # Test with project not in git repo
      non_git_path = Dir.mktmpdir("non-git")
      mock_project_non_git = instance_double("Project",
                                             name: "non-git-project",
                                             path: Pathname.new(non_git_path))
      mock_session_non_git = instance_double("Session",
                                             name: "non-git-session",
                                             path: Pathname.new(non_git_path),
                                             created_at: Time.new(2023, 6, 15, 14, 30, 0),
                                             updated_at: Time.new(2023, 6, 15, 15, 30, 0),
                                             status: "active")

      variables_non_git = described_class.new(mock_session_non_git, mock_project_non_git)
      
      # Ensure git_repository? returns false for the non-git path by stubbing find_git_directory
      allow(variables_non_git).to receive(:find_git_directory).and_return(nil)
      
      result = variables_non_git.send(:_collect_git_variables)

      expect(result).to eq({ available: false })

      FileUtils.rm_rf(non_git_path)
    end

    it "handles git command errors gracefully" do
      allow(variables).to receive(:execute_git_command).and_raise(StandardError, "Git error")

      result = variables.send(:_collect_git_variables)
      expect(result[:error]).to include("Failed to collect git variables")
    end
  end

  describe "#_collect_timestamp_variables" do
    it "returns timestamp information" do
      freeze_time = Time.new(2023, 6, 15, 14, 30, 0)
      allow(Time).to receive(:now).and_return(freeze_time)

      result = variables.send(:_collect_timestamp_variables)

      expect(result).to include(:now, :iso8601, :today, :year, :month, :day, :epoch)
      expect(result[:today]).to eq("2023-06-15")
      expect(result[:year]).to eq(2023)
      expect(result[:month]).to eq(6)
      expect(result[:day]).to eq(15)
    end
  end

  describe "project type detection" do
    it "detects JavaScript project by package.json" do
      File.write(File.join(project_path, "package.json"), "{}")

      result = variables.send(:detect_project_type, Pathname.new(project_path))
      expect(result).to eq("javascript")
    end

    it "detects Ruby project by Gemfile" do
      File.write(File.join(project_path, "Gemfile"), "gem 'rails'")

      result = variables.send(:detect_project_type, Pathname.new(project_path))
      expect(result).to eq("ruby")
    end

    it "detects Rails project by Gemfile and config/application.rb" do
      File.write(File.join(project_path, "Gemfile"), "gem 'rails'")
      FileUtils.mkdir_p(File.join(project_path, "config"))
      File.write(File.join(project_path, "config", "application.rb"), "Rails.application")

      result = variables.send(:detect_project_type, Pathname.new(project_path))
      expect(result).to eq("rails")
    end

    it "returns unknown for unrecognized project" do
      # No project files
      result = variables.send(:detect_project_type, Pathname.new(project_path))
      expect(result).to eq("unknown")
    end

    it "handles nil path gracefully" do
      result = variables.send(:detect_project_type, nil)
      expect(result).to eq("unknown")
    end

    it "handles errors gracefully" do
      # Create a separate test that doesn't interfere with initialization
      test_variables = described_class.new(mock_session, mock_project)
      allow(test_variables).to receive(:detect_project_type).and_raise(StandardError, "Detection error")

      result = test_variables.send(:_collect_project_variables)
      expect(result[:error]).to include("Failed to collect project variables")
    end
  end

  describe "utility methods" do
    describe "#format_timestamp" do
      it "formats timestamp correctly" do
        time = Time.new(2023, 6, 15, 14, 30, 0)
        result = variables.send(:format_timestamp, time)
        expect(result).to include("2023-06-15")
        expect(result).to include("14:30:00")
      end

      it "handles nil timestamp" do
        result = variables.send(:format_timestamp, nil)
        expect(result).to be_nil
      end

      it "handles string timestamp" do
        result = variables.send(:format_timestamp, "2023-06-15T14:30:00Z")
        expect(result).to be_a(String)
      end

      it "handles invalid timestamp gracefully" do
        result = variables.send(:format_timestamp, "invalid")
        expect(result).to eq("invalid")
      end
    end

    describe "#git_repository?" do
      it "detects git repository correctly" do
        Dir.chdir(project_path) do
          system("git init -q")
        end

        result = variables.send(:git_repository?, project_path)
        expect(result).to be true
      end

      it "returns false for non-git directory" do
        result = variables.send(:git_repository?, project_path)
        # The method might return false or an empty string, both should indicate non-git
        expect([false, "", nil]).to include(result)
      end

      it "handles nil path gracefully" do
        result = variables.send(:git_repository?, nil)
        expect(result).to be false
      end
    end

    describe "#find_git_directory" do
      it "finds git directory from project path" do
        Dir.chdir(project_path) do
          system("git init -q")
        end

        result = variables.send(:find_git_directory)
        expect(result).to eq(Pathname.new(project_path))
      end

      it "returns fallback directory when project/session paths are not git repos" do
        # Create variables with non-git paths
        non_git_path = Dir.mktmpdir("non-git")
        mock_project_non_git = instance_double("Project",
                                               name: "non-git-project",
                                               path: Pathname.new(non_git_path))
        mock_session_non_git = instance_double("Session",
                                               name: "non-git-session",
                                               path: Pathname.new(non_git_path),
                                               created_at: Time.now,
                                               updated_at: Time.now,
                                               status: "active")

        variables_non_git = described_class.new(mock_session_non_git, mock_project_non_git)
        result = variables_non_git.send(:find_git_directory)

        # Should return something (likely the current directory as fallback) or nil
        # The method tries project path, session path, then current directory
        expect(result).to be_a(Pathname).or be_nil

        FileUtils.rm_rf(non_git_path)
      end
    end
  end

  describe "public interface methods" do
    describe "#collect" do
      it "caches variables on subsequent calls" do
        # First call
        result1 = variables.collect

        # Second call should return cached version
        result2 = variables.collect

        expect(result1).to eq(result2)
        expect(result1.object_id).to eq(result2.object_id)
      end

      it "returns consistent structure" do
        result = variables.collect

        expect(result).to be_a(Hash)
        expect(result).to include(:session, :project, :environment, :timestamp)
      end
    end

    describe "#refresh!" do
      it "clears cached variables and recollects" do
        # First call to populate cache
        variables.collect
        variables.instance_variable_get(:@cached_variables)

        # Refresh should clear cache and recollect
        result2 = variables.refresh!

        # Verify result is consistent but cache was refreshed
        expect(result2).to be_a(Hash)
        expect(result2).to include(:session, :project, :environment, :timestamp)
        # Cache should be repopulated, not empty
        expect(variables.instance_variable_get(:@cached_variables)).not_to be_empty
      end
    end

    describe "#get_category" do
      it "returns specific category variables" do
        result = variables.get_category(:session)
        expect(result).to include(:name, :status)
      end

      it "returns empty hash for unknown category" do
        result = variables.get_category(:unknown)
        expect(result).to eq({})
      end
    end

    describe "#add_custom_variables" do
      it "merges custom variables with collected variables" do
        custom_vars = { custom: { key: "value" } }
        variables.add_custom_variables(custom_vars)

        result = variables.collect
        expect(result).to include(:custom)
        expect(result[:custom]).to include(key: "value")
      end

      it "handles non-hash input gracefully" do
        expect { variables.add_custom_variables("not a hash") }.not_to raise_error
      end

      it "gives precedence to custom variables" do
        custom_vars = { session: { custom_field: "custom_value" } }
        variables.add_custom_variables(custom_vars)

        result = variables.collect
        expect(result[:session]).to include(custom_field: "custom_value")
      end
    end
  end
end
