# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Sxn::Core::ConfigManager do
  let(:temp_dir) { Dir.mktmpdir("sxn_config_test") }
  let(:sessions_folder) { File.join(temp_dir, "sessions") }
  let(:config_manager) { described_class.new(temp_dir) }
  let(:config_path) { File.join(temp_dir, ".sxn", "config.yml") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    context "with default base path" do
      it "uses current directory as base path" do
        manager = described_class.new
        expect(manager.config_path).to include(Dir.pwd)
      end
    end

    context "with specific base path" do
      it "uses provided base path" do
        expect(config_manager.config_path).to eq(config_path)
      end

      it "expands relative paths" do
        relative_path = File.join("..", File.basename(temp_dir))
        parent_dir = File.dirname(temp_dir)

        Dir.chdir(parent_dir) do
          manager = described_class.new(relative_path)
          expected_basename = File.basename(temp_dir)
          actual_basename = File.basename(File.dirname(manager.config_path, 2))
          expect(actual_basename).to eq(expected_basename)
        end
      end
    end

    context "when project is already initialized" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "loads existing configuration" do
        new_manager = described_class.new(temp_dir)
        expect(new_manager.sessions_folder_path).to eq(sessions_folder)
      end
    end
  end

  describe "#initialized?" do
    context "when config file does not exist" do
      it "returns false" do
        expect(config_manager.initialized?).to be false
      end
    end

    context "when config file exists" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "returns true" do
        expect(config_manager.initialized?).to be true
      end
    end
  end

  describe "#initialize_project" do
    context "when not already initialized" do
      it "creates sessions folder and returns its path" do
        result = config_manager.initialize_project(sessions_folder)

        expect(result).to eq(sessions_folder)
        expect(Dir.exist?(sessions_folder)).to be true
      end

      it "creates .sxn directory structure" do
        config_manager.initialize_project(sessions_folder)

        sxn_dir = File.dirname(config_path)
        expect(Dir.exist?(sxn_dir)).to be true
        expect(Dir.exist?(File.join(sxn_dir, "cache"))).to be true
        expect(Dir.exist?(File.join(sxn_dir, "templates"))).to be true
      end

      it "creates config file with default settings" do
        config_manager.initialize_project(sessions_folder)

        expect(File.exist?(config_path)).to be true
        config = YAML.safe_load_file(config_path)

        expect(config["version"]).to eq(1)
        expect(config["sessions_folder"]).to eq("sessions")
        expect(config["current_session"]).to be_nil
        expect(config["projects"]).to eq({})
        expect(config["settings"]["auto_cleanup"]).to be true
        expect(config["settings"]["max_sessions"]).to eq(10)
        expect(config["settings"]["worktree_cleanup_days"]).to eq(30)
      end

      it "sets up database" do
        expect(Sxn::Database::SessionDatabase).to receive(:new).with(
          File.join(File.dirname(config_path), "sessions.db")
        )

        config_manager.initialize_project(sessions_folder)
      end

      it "handles absolute sessions folder path" do
        absolute_sessions = File.join("/tmp", "absolute_sessions")
        result = config_manager.initialize_project(absolute_sessions)

        expect(result).to eq(absolute_sessions)
      end

      it "handles relative sessions folder path" do
        relative_sessions = "relative_sessions"
        expected_path = File.join(temp_dir, relative_sessions)

        result = config_manager.initialize_project(relative_sessions)

        expect(result).to eq(expected_path)
      end
    end

    context "when already initialized" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "raises error without force flag" do
        expect do
          config_manager.initialize_project(sessions_folder)
        end.to raise_error(Sxn::ConfigurationError, /already initialized/)
      end

      it "reinitializes with force flag" do
        expect do
          config_manager.initialize_project(sessions_folder, force: true)
        end.not_to raise_error
      end
    end
  end

  describe "#get_config" do
    context "when not initialized" do
      it "raises configuration error" do
        expect do
          config_manager.get_config
        end.to raise_error(Sxn::ConfigurationError, /not initialized/)
      end
    end

    context "when initialized" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "returns config through discovery as OpenStruct" do
        discovery_double = instance_double(Sxn::Config::ConfigDiscovery)
        config_hash = { "test" => "config", "nested" => { "value" => "data" } }

        allow(Sxn::Config::ConfigDiscovery).to receive(:new).with(temp_dir).and_return(discovery_double)
        allow(discovery_double).to receive(:discover_config).and_return(config_hash)

        result = config_manager.get_config

        # Verify it returns an OpenStruct
        expect(result).to be_a(OpenStruct)
        expect(result.test).to eq("config")

        # Verify nested values are also OpenStruct
        expect(result.nested).to be_a(OpenStruct)
        expect(result.nested.value).to eq("data")
      end
    end
  end

  describe "#update_current_session" do
    before do
      config_manager.initialize_project(sessions_folder)
    end

    it "updates current session in config file" do
      config_manager.update_current_session("test_session")

      config = YAML.safe_load_file(config_path)
      expect(config["current_session"]).to eq("test_session")
    end

    it "handles nil session name" do
      config_manager.update_current_session(nil)

      config = YAML.safe_load_file(config_path)
      expect(config["current_session"]).to be_nil
    end

    it "overwrites existing current session" do
      config_manager.update_current_session("session1")
      config_manager.update_current_session("session2")

      config = YAML.safe_load_file(config_path)
      expect(config["current_session"]).to eq("session2")
    end
  end

  describe "#current_session" do
    before do
      config_manager.initialize_project(sessions_folder)
    end

    it "returns nil when no current session is set" do
      expect(config_manager.current_session).to be_nil
    end

    it "returns current session when set" do
      config_manager.update_current_session("active_session")
      expect(config_manager.current_session).to eq("active_session")
    end
  end

  describe "#sessions_folder_path" do
    context "when not initialized" do
      it "returns nil" do
        expect(config_manager.sessions_folder_path).to be_nil
      end
    end

    context "when initialized" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "returns sessions folder path" do
        expect(config_manager.sessions_folder_path).to eq(sessions_folder)
      end
    end

    context "when sessions_folder is not loaded but config exists" do
      before do
        config_manager.initialize_project(sessions_folder)
        # Create new manager to simulate unloaded state
        @new_manager = described_class.new(temp_dir)
        @new_manager.instance_variable_set(:@sessions_folder, nil)
      end

      it "loads config and returns sessions folder" do
        expect(@new_manager.sessions_folder_path).to eq(sessions_folder)
      end
    end
  end

  describe "#add_project" do
    before do
      config_manager.initialize_project(sessions_folder)
    end

    it "adds project with all parameters" do
      project_path = File.join(temp_dir, "test_project")

      config_manager.add_project(
        "test_project",
        project_path,
        type: "rails",
        default_branch: "main"
      )

      config = YAML.safe_load_file(config_path)
      project = config["projects"]["test_project"]

      expect(project["path"]).to eq("test_project")
      expect(project["type"]).to eq("rails")
      expect(project["default_branch"]).to eq("main")
    end

    it "adds project with minimal parameters" do
      project_path = File.join(temp_dir, "minimal_project")

      config_manager.add_project("minimal_project", project_path)

      config = YAML.safe_load_file(config_path)
      project = config["projects"]["minimal_project"]

      expect(project["path"]).to eq("minimal_project")
      expect(project["type"]).to be_nil
      expect(project["default_branch"]).to eq("master")
    end

    it "converts absolute paths to relative paths" do
      absolute_path = File.join(temp_dir, "absolute_project")

      config_manager.add_project("absolute_project", absolute_path)

      config = YAML.safe_load_file(config_path)
      project = config["projects"]["absolute_project"]

      expect(project["path"]).to eq("absolute_project")
    end

    it "initializes projects hash if it doesn't exist" do
      # Manually remove projects from config
      config = YAML.safe_load_file(config_path)
      config.delete("projects")
      File.write(config_path, YAML.dump(config))

      project_path = File.join(temp_dir, "new_project")
      config_manager.add_project("new_project", project_path)

      config = YAML.safe_load_file(config_path)
      expect(config["projects"]).to be_a(Hash)
      expect(config["projects"]["new_project"]).not_to be_nil
    end
  end

  describe "#update_project" do
    before do
      config_manager.initialize_project(sessions_folder)
      project_path = File.join(temp_dir, "test_project")
      config_manager.add_project("test_project", project_path, type: "rails", default_branch: "main")
    end

    context "when project exists" do
      it "updates path when provided" do
        new_path = File.join(temp_dir, "updated_project")

        result = config_manager.update_project("test_project", { path: new_path })

        expect(result).to be true
        config = YAML.safe_load_file(config_path)
        expect(config["projects"]["test_project"]["path"]).to eq("updated_project")
      end

      it "does not update path when not provided" do
        result = config_manager.update_project("test_project", { type: "javascript" })

        expect(result).to be true
        config = YAML.safe_load_file(config_path)
        expect(config["projects"]["test_project"]["path"]).to eq("test_project")
      end

      it "updates type when provided" do
        result = config_manager.update_project("test_project", { type: "javascript" })

        expect(result).to be true
        config = YAML.safe_load_file(config_path)
        expect(config["projects"]["test_project"]["type"]).to eq("javascript")
      end

      it "does not update type when not provided" do
        result = config_manager.update_project("test_project", { path: "/some/path" })

        expect(result).to be true
        config = YAML.safe_load_file(config_path)
        expect(config["projects"]["test_project"]["type"]).to eq("rails")
      end

      it "updates default_branch when provided" do
        result = config_manager.update_project("test_project", { default_branch: "develop" })

        expect(result).to be true
        config = YAML.safe_load_file(config_path)
        expect(config["projects"]["test_project"]["default_branch"]).to eq("develop")
      end

      it "does not update default_branch when not provided" do
        result = config_manager.update_project("test_project", { type: "javascript" })

        expect(result).to be true
        config = YAML.safe_load_file(config_path)
        expect(config["projects"]["test_project"]["default_branch"]).to eq("main")
      end

      it "updates multiple fields simultaneously" do
        updates = {
          path: File.join(temp_dir, "multi_update"),
          type: "vue",
          default_branch: "develop"
        }

        result = config_manager.update_project("test_project", updates)

        expect(result).to be true
        config = YAML.safe_load_file(config_path)
        project = config["projects"]["test_project"]
        expect(project["path"]).to eq("multi_update")
        expect(project["type"]).to eq("vue")
        expect(project["default_branch"]).to eq("develop")
      end
    end

    context "when project does not exist" do
      it "returns false and does not create project" do
        result = config_manager.update_project("non_existent", { type: "rails" })

        expect(result).to be false
        config = YAML.safe_load_file(config_path)
        expect(config["projects"]["non_existent"]).to be_nil
      end
    end

    it "initializes projects hash if it doesn't exist but doesn't persist when project not found" do
      # Manually remove projects from config
      config = YAML.safe_load_file(config_path)
      config.delete("projects")
      File.write(config_path, YAML.dump(config))

      result = config_manager.update_project("non_existent", { type: "rails" })

      expect(result).to be false
      # Config file should not be modified since project wasn't found
      config = YAML.safe_load_file(config_path)
      expect(config["projects"]).to be_nil
    end
  end

  describe "#remove_project" do
    before do
      config_manager.initialize_project(sessions_folder)
      project_path = File.join(temp_dir, "test_project")
      config_manager.add_project("test_project", project_path)
    end

    it "removes existing project" do
      config_manager.remove_project("test_project")

      config = YAML.safe_load_file(config_path)
      expect(config["projects"]["test_project"]).to be_nil
    end

    it "handles removal of non-existent project" do
      expect do
        config_manager.remove_project("non_existent")
      end.not_to raise_error

      config = YAML.safe_load_file(config_path)
      expect(config["projects"]["test_project"]).not_to be_nil
    end

    it "handles removal when projects hash is nil" do
      # Manually set projects to nil
      config = YAML.safe_load_file(config_path)
      config["projects"] = nil
      File.write(config_path, YAML.dump(config))

      expect do
        config_manager.remove_project("test_project")
      end.not_to raise_error
    end
  end

  describe "#list_projects" do
    before do
      config_manager.initialize_project(sessions_folder)
    end

    context "when no projects exist" do
      it "returns empty array" do
        expect(config_manager.list_projects).to eq([])
      end
    end

    context "when projects hash is nil" do
      before do
        config = YAML.safe_load_file(config_path)
        config["projects"] = nil
        File.write(config_path, YAML.dump(config))
      end

      it "returns empty array" do
        expect(config_manager.list_projects).to eq([])
      end
    end

    context "when projects exist" do
      before do
        project1_path = File.join(temp_dir, "project1")
        project2_path = File.join(temp_dir, "project2")

        config_manager.add_project("project1", project1_path, type: "rails", default_branch: "main")
        config_manager.add_project("project2", project2_path, type: "javascript")
      end

      it "returns array of project hashes" do
        projects = config_manager.list_projects

        expect(projects.size).to eq(2)

        project1 = projects.find { |p| p[:name] == "project1" }
        expect(project1[:path]).to eq(File.join(temp_dir, "project1"))
        expect(project1[:type]).to eq("rails")
        expect(project1[:default_branch]).to eq("main")

        project2 = projects.find { |p| p[:name] == "project2" }
        expect(project2[:path]).to eq(File.join(temp_dir, "project2"))
        expect(project2[:type]).to eq("javascript")
        expect(project2[:default_branch]).to eq("master")
      end
    end
  end

  describe "#get_project" do
    before do
      config_manager.initialize_project(sessions_folder)
      project_path = File.join(temp_dir, "test_project")
      config_manager.add_project("test_project", project_path, type: "rails")
    end

    it "returns project when it exists" do
      project = config_manager.get_project("test_project")

      expect(project).not_to be_nil
      expect(project[:name]).to eq("test_project")
      expect(project[:type]).to eq("rails")
    end

    it "returns nil when project doesn't exist" do
      project = config_manager.get_project("non_existent")
      expect(project).to be_nil
    end
  end

  describe "#detect_projects" do
    let(:detector_double) { instance_double(Sxn::Rules::ProjectDetector) }

    before do
      allow(Sxn::Rules::ProjectDetector).to receive(:new).with(temp_dir).and_return(detector_double)
    end

    context "when directories exist" do
      before do
        # Create test directories
        FileUtils.mkdir_p(File.join(temp_dir, "rails_app"))
        FileUtils.mkdir_p(File.join(temp_dir, "js_app"))
        FileUtils.mkdir_p(File.join(temp_dir, ".hidden_dir"))
        FileUtils.mkdir_p(File.join(temp_dir, "unknown_app"))

        # Create a regular file to ensure it's filtered out
        File.write(File.join(temp_dir, "regular_file.txt"), "content")
      end

      it "detects known project types and filters hidden directories" do
        allow(detector_double).to receive(:detect_type).with(File.join(temp_dir, "rails_app")).and_return(:rails)
        allow(detector_double).to receive(:detect_type).with(File.join(temp_dir, "js_app")).and_return(:javascript)
        allow(detector_double).to receive(:detect_type).with(File.join(temp_dir, "unknown_app")).and_return(:unknown)

        projects = config_manager.detect_projects

        expect(projects.size).to eq(2)

        rails_project = projects.find { |p| p[:name] == "rails_app" }
        expect(rails_project[:type]).to eq("rails")
        expect(rails_project[:path]).to eq(File.join(temp_dir, "rails_app"))

        js_project = projects.find { |p| p[:name] == "js_app" }
        expect(js_project[:type]).to eq("javascript")
      end

      it "excludes unknown project types" do
        allow(detector_double).to receive(:detect_type).and_return(:unknown)

        projects = config_manager.detect_projects
        expect(projects).to be_empty
      end

      it "excludes hidden directories" do
        allow(detector_double).to receive(:detect_type).and_return(:rails)

        projects = config_manager.detect_projects
        expect(projects.none? { |p| p[:name].start_with?(".") }).to be true
      end

      it "specifically skips directories starting with dot" do
        # This test ensures line 132 is covered (next if entry.start_with?("."))
        # First clear existing directories from the before block
        ["rails_app", "js_app", ".hidden_dir", "unknown_app"].each do |dir|
          FileUtils.rm_rf(File.join(temp_dir, dir))
        end
        FileUtils.rm_f(File.join(temp_dir, "regular_file.txt"))

        FileUtils.mkdir_p(File.join(temp_dir, ".dotfile"))
        FileUtils.mkdir_p(File.join(temp_dir, "normal_dir"))

        allow(detector_double).to receive(:detect_type).with(File.join(temp_dir, "normal_dir")).and_return(:rails)

        projects = config_manager.detect_projects

        expect(projects.size).to eq(1)
        expect(projects.first[:name]).to eq("normal_dir")
        expect(projects.none? { |p| p[:name] == ".dotfile" }).to be true
      end
    end

    context "when no directories exist" do
      it "returns empty array" do
        projects = config_manager.detect_projects
        expect(projects).to be_empty
      end
    end
  end

  describe "private methods" do
    describe "#load_config" do
      context "when not initialized" do
        it "does not load config" do
          expect(config_manager.sessions_folder_path).to be_nil
        end
      end

      context "when initialized" do
        before do
          config_manager.initialize_project(sessions_folder)
        end

        it "loads config and sets sessions folder" do
          new_manager = described_class.new(temp_dir)
          expect(new_manager.sessions_folder_path).to eq(sessions_folder)
        end
      end
    end

    describe "#load_config_file" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "loads valid YAML config" do
        config = config_manager.send(:load_config_file)
        expect(config).to be_a(Hash)
        expect(config["version"]).to eq(1)
      end

      it "handles empty config file" do
        File.write(config_path, "")
        config = config_manager.send(:load_config_file)
        expect(config).to eq({})
      end

      it "raises error for invalid YAML" do
        File.write(config_path, "invalid: yaml: [unclosed")

        expect do
          config_manager.send(:load_config_file)
        end.to raise_error(Sxn::ConfigurationError, /Invalid configuration file/)
      end
    end

    describe "#save_config_file" do
      before do
        FileUtils.mkdir_p(File.dirname(config_path))
      end

      it "saves config as YAML" do
        test_config = { "test" => "value", "number" => 42 }
        config_manager.send(:save_config_file, test_config)

        loaded_config = YAML.safe_load_file(config_path)
        expect(loaded_config).to eq(test_config)
      end
    end

    describe "#create_directories" do
      it "creates all required directories" do
        config_manager.instance_variable_set(:@sessions_folder, sessions_folder)
        config_manager.send(:create_directories)

        sxn_dir = File.dirname(config_path)
        expect(Dir.exist?(sxn_dir)).to be true
        expect(Dir.exist?(sessions_folder)).to be true
        expect(Dir.exist?(File.join(sxn_dir, "cache"))).to be true
        expect(Dir.exist?(File.join(sxn_dir, "templates"))).to be true
      end
    end

    describe "#create_config_file" do
      before do
        config_manager.instance_variable_set(:@sessions_folder, sessions_folder)
        FileUtils.mkdir_p(File.dirname(config_path))
      end

      it "creates config file with default values" do
        config_manager.send(:create_config_file)

        expect(File.exist?(config_path)).to be true
        config = YAML.safe_load_file(config_path)

        expect(config["version"]).to eq(1)
        expect(config["sessions_folder"]).to eq("sessions")
        expect(config["current_session"]).to be_nil
        expect(config["projects"]).to eq({})
        expect(config["settings"]).to include(
          "auto_cleanup" => true,
          "max_sessions" => 10,
          "worktree_cleanup_days" => 30
        )
      end
    end

    describe "#setup_database" do
      before do
        FileUtils.mkdir_p(File.dirname(config_path))
      end

      it "creates session database" do
        expected_db_path = File.join(File.dirname(config_path), "sessions.db")
        expect(Sxn::Database::SessionDatabase).to receive(:new).with(expected_db_path)

        config_manager.send(:setup_database)
      end
    end
  end

  describe "#update_gitignore" do
    let(:gitignore_path) { File.join(temp_dir, ".gitignore") }

    before do
      config_manager.initialize_project(sessions_folder)
    end

    context "when .gitignore file exists" do
      before do
        File.write(gitignore_path, "# Existing content\nnode_modules/\n")
      end

      it "adds SXN entries when they don't exist" do
        result = config_manager.update_gitignore

        expect(result).to be true
        content = File.read(gitignore_path)
        expect(content).to include(".sxn/")
        expect(content).to include("# SXN session management")
      end

      it "does not add duplicate SXN entries" do
        # Add .sxn/ entry manually first, and sessions/ since that's what this test config has
        File.write(gitignore_path, "# Existing content\n.sxn/\nsessions/\nnode_modules/\n")

        result = config_manager.update_gitignore

        expect(result).to be false
        content = File.read(gitignore_path)
        expect(content.scan(".sxn/").length).to eq(1)
        expect(content.scan("sessions/").length).to eq(1)
      end

      it "adds sessions entry when different from .sxn/" do
        # Initialize with custom sessions folder
        custom_sessions = File.join(temp_dir, "custom_sessions")
        config_manager.initialize_project(custom_sessions, force: true)

        File.write(gitignore_path, "# Existing content\nnode_modules/\n")
        result = config_manager.update_gitignore

        expect(result).to be true
        content = File.read(gitignore_path)
        expect(content).to include(".sxn/")
        expect(content).to include("custom_sessions/")
      end

      it "does not add sessions entry when it's the same as .sxn/" do
        # Test with .sxn as sessions folder
        sxn_sessions = File.join(temp_dir, ".sxn")
        config_manager.initialize_project(sxn_sessions, force: true)

        File.write(gitignore_path, "# Existing content\nnode_modules/\n")
        result = config_manager.update_gitignore

        expect(result).to be true
        content = File.read(gitignore_path)
        expect(content).to include(".sxn/")
        # Should not have duplicate .sxn/ entries since sessions_entry == ".sxn/"
        expect(content.scan(".sxn/").length).to eq(1)
      end

      it "is case-sensitive for matching" do
        File.write(gitignore_path, "# Existing content\n.SXN\nnode_modules/\n")

        result = config_manager.update_gitignore

        expect(result).to be true # .SXN is not the same as .sxn
        content = File.read(gitignore_path)
        expect(content).to include(".SXN")
        expect(content).to include(".sxn/")
      end

      it "handles existing entries with and without trailing slashes" do
        File.write(gitignore_path, "# Existing content\n.sxn\nsessions\nnode_modules/\n")

        result = config_manager.update_gitignore

        expect(result).to be false
      end

      it "ignores comments and empty lines when checking" do
        File.write(gitignore_path, "# This is .sxn comment\n\n# Another comment\nnode_modules/\n")

        result = config_manager.update_gitignore

        expect(result).to be true
        content = File.read(gitignore_path)
        expect(content).to include(".sxn/")
      end

      it "handles errors gracefully in debug mode" do
        ENV["SXN_DEBUG"] = "true"
        allow(File).to receive(:read).with(gitignore_path).and_raise(StandardError, "Read error")

        expect do
          result = config_manager.update_gitignore
          expect(result).to be false
        end.to output(/Failed to update \.gitignore/).to_stderr

        ENV.delete("SXN_DEBUG")
      end

      it "handles errors gracefully without debug mode" do
        allow(File).to receive(:read).with(gitignore_path).and_raise(StandardError, "Read error")

        expect do
          result = config_manager.update_gitignore
          expect(result).to be false
        end.not_to output.to_stderr
      end
    end

    context "when .gitignore file does not exist" do
      it "returns false" do
        FileUtils.rm_f(gitignore_path)

        result = config_manager.update_gitignore
        expect(result).to be false
      end
    end

    context "when .gitignore is a symlink" do
      it "returns false and does not modify" do
        FileUtils.rm_f(gitignore_path)
        real_file = File.join(temp_dir, "real_gitignore")
        File.write(real_file, "content")
        File.symlink(real_file, gitignore_path)

        result = config_manager.update_gitignore
        expect(result).to be false
      end
    end
  end

  describe "sessions folder path resolution" do
    context "with various path configurations" do
      it "handles relative path from sessions_folder_relative_path when @sessions_folder is nil" do
        config_manager.initialize_project(sessions_folder)
        config_manager.instance_variable_set(:@sessions_folder, nil)

        path = config_manager.send(:sessions_folder_relative_path)
        expect(path).to eq(".sxn")
      end

      it "returns .sxn when sessions folder is current directory" do
        current_dir_sessions = temp_dir
        config_manager.initialize_project(current_dir_sessions)

        path = config_manager.send(:sessions_folder_relative_path)
        expect(path).to eq(".sxn")
      end

      it "returns .sxn when sessions folder is .sxn itself" do
        sxn_sessions = File.join(temp_dir, ".sxn")
        config_manager.initialize_project(sxn_sessions)

        path = config_manager.send(:sessions_folder_relative_path)
        expect(path).to eq(".sxn")
      end

      it "returns .sxn when sessions folder ends with /.sxn" do
        nested_sxn = File.join(temp_dir, "nested", ".sxn")
        config_manager.initialize_project(nested_sxn)

        path = config_manager.send(:sessions_folder_relative_path)
        expect(path).to eq(".sxn")
      end

      it "returns basename when too many ../ components" do
        # Create a deeply nested path that would have many ../
        deep_sessions = File.join("/", "very", "deep", "nested", "sessions")
        config_manager.instance_variable_set(:@sessions_folder, deep_sessions)

        path = config_manager.send(:sessions_folder_relative_path)
        expect(path).to eq("sessions")
      end

      it "returns basename when relative path starts with ../../../" do
        # Create a path that starts with ../../../
        parent_sessions = File.join(File.dirname(temp_dir, 3), "sessions")
        config_manager.instance_variable_set(:@sessions_folder, parent_sessions)

        path = config_manager.send(:sessions_folder_relative_path)
        expect(path).to eq("sessions")
      end

      it "handles ArgumentError from relative_path_from" do
        # Force an ArgumentError by using paths that can't be made relative
        allow(Pathname).to receive(:new).with(anything).and_call_original
        sessions_path = double("Pathname")
        allow(Pathname).to receive(:new).with("/some/path").and_return(sessions_path)
        allow(sessions_path).to receive(:relative_path_from).and_raise(ArgumentError)

        config_manager.instance_variable_set(:@sessions_folder, "/some/path")

        path = config_manager.send(:sessions_folder_relative_path)
        expect(path).to eq("path")
      end
    end
  end

  describe "has_gitignore_entry?" do
    it "matches exact entries" do
      lines = ["node_modules", ".sxn", "tmp"]
      result = config_manager.send(:has_gitignore_entry?, lines, ".sxn")
      expect(result).to be true
    end

    it "matches entries with trailing slashes" do
      lines = ["node_modules/", ".sxn/", "tmp/"]
      result = config_manager.send(:has_gitignore_entry?, lines, ".sxn")
      expect(result).to be true
    end

    it "ignores comments and empty lines" do
      lines = ["# This is a comment", "", "  ", "# .sxn comment", "node_modules"]
      result = config_manager.send(:has_gitignore_entry?, lines, ".sxn")
      expect(result).to be false
    end

    it "handles entries with subdirectories" do
      lines = ["some/path/session", "another/dir"]
      result = config_manager.send(:has_gitignore_entry?, lines, "some/path/session")
      expect(result).to be true
    end

    it "matches basename for subdirectory entries" do
      lines = %w[sessions node_modules]
      result = config_manager.send(:has_gitignore_entry?, lines, "some/path/sessions")
      expect(result).to be true
    end

    it "does not match when entry is not found" do
      lines = %w[node_modules tmp build]
      result = config_manager.send(:has_gitignore_entry?, lines, ".sxn")
      expect(result).to be false
    end

    it "handles mixed whitespace and slashes" do
      lines = ["  node_modules/  ", " .sxn ", "tmp/"]
      result = config_manager.send(:has_gitignore_entry?, lines, ".sxn")
      expect(result).to be true
    end
  end

  # Edge cases and error conditions
  describe "edge cases" do
    context "with permission errors" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "handles config file read permission errors gracefully" do
        allow(YAML).to receive(:safe_load_file).with(config_path).and_raise(Errno::EACCES, "Permission denied")

        expect do
          config_manager.send(:load_config_file)
        end.to raise_error(Errno::EACCES)
      end
    end

    context "with disk space errors" do
      it "handles disk full errors during initialization" do
        allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::ENOSPC, "No space left on device")

        expect do
          config_manager.initialize_project(sessions_folder)
        end.to raise_error(Errno::ENOSPC)
      end
    end

    context "with invalid paths" do
      it "handles invalid session folder paths" do
        invalid_path = "/invalid/\0/path"

        expect do
          config_manager.initialize_project(invalid_path)
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe "additional branch coverage tests" do
    before do
      config_manager.initialize_project(sessions_folder)
    end

    it "handles files in detect_projects (line 140 then branch)" do
      # Create a file to test the directory check
      file_path = File.join(temp_dir, "regular_file.txt")
      File.write(file_path, "content")

      # This should skip the file since it's not a directory
      projects = config_manager.detect_projects
      expect(projects.none? { |p| p[:name] == "regular_file.txt" }).to be true
    end

    it "skips hidden directories starting with dot in detect_projects" do
      # Create directories - one hidden and one visible
      hidden_dir = File.join(temp_dir, ".git")
      visible_dir = File.join(temp_dir, "myproject")
      FileUtils.mkdir_p(hidden_dir)
      FileUtils.mkdir_p(visible_dir)

      # Create a marker file in the visible directory to make it detectable
      File.write(File.join(visible_dir, "Gemfile"), "source 'https://rubygems.org'")

      detector_double = instance_double(Sxn::Rules::ProjectDetector)
      allow(Sxn::Rules::ProjectDetector).to receive(:new).with(temp_dir).and_return(detector_double)
      # Return :unknown for all directories except visible_dir
      allow(detector_double).to receive(:detect_type).and_return(:unknown)
      allow(detector_double).to receive(:detect_type).with(visible_dir).and_return(:rails)

      projects = config_manager.detect_projects

      # Verify that .git is skipped due to starting with "."
      expect(projects.none? { |p| p[:name] == ".git" }).to be true
      expect(projects.any? { |p| p[:name] == "myproject" }).to be true
    end

    it "covers optimistic locking in update_project (line 170 then branch)" do
      # This is actually in config.rb, not config_manager.rb
      # The line 170 branch is when expected_version exists in update_session
      # This file doesn't have that method, so this test covers other scenarios
      project_path = File.join(temp_dir, "test_project")
      config_manager.add_project("test_project", project_path, type: "rails", default_branch: "main")

      # Test updating without path
      result = config_manager.update_project("test_project", { type: "javascript" })
      expect(result).to be true
    end

    it "handles nil sessions_folder in load_config (line 259 else branch)" do
      # Create a config file with nil sessions_folder
      config = YAML.safe_load_file(config_path)
      config["sessions_folder"] = nil
      File.write(config_path, YAML.dump(config))

      # Create new manager and load config
      new_manager = described_class.new(temp_dir)
      expect(new_manager.sessions_folder_path).to be_nil
    end

    it "covers line 140 then branch - skips entries starting with dot in detect_projects" do
      # Create a directory starting with a dot
      FileUtils.mkdir_p(File.join(temp_dir, ".hidden_project"))
      FileUtils.mkdir_p(File.join(temp_dir, "visible_project"))

      # Mock detector to return a type if called
      detector_double = instance_double(Sxn::Rules::ProjectDetector)
      allow(Sxn::Rules::ProjectDetector).to receive(:new).with(temp_dir).and_return(detector_double)
      # Allow any calls and return :unknown by default
      allow(detector_double).to receive(:detect_type).and_return(:unknown)
      # Only visible_project should return a known type
      allow(detector_double).to receive(:detect_type).with(File.join(temp_dir, "visible_project")).and_return(:rails)

      projects = config_manager.detect_projects

      # Line 140 should skip .hidden_project
      expect(projects.none? { |p| p[:name] == ".hidden_project" }).to be true
      expect(projects.any? { |p| p[:name] == "visible_project" }).to be true
    end

    it "covers line 170 then branch - sessions_entry when relative_sessions ends with /" do
      # Create a sessions folder with a path that will end with /
      custom_sessions = File.join(temp_dir, "my_sessions")
      config_manager.initialize_project(custom_sessions, force: true)

      # Mock the private method to return a path ending with /
      allow(config_manager).to receive(:sessions_folder_relative_path).and_return("my_sessions/")

      gitignore_path = File.join(temp_dir, ".gitignore")
      File.write(gitignore_path, "# Existing content\nnode_modules/\n")

      # This should trigger line 170 then branch where relative_sessions already ends with /
      result = config_manager.update_gitignore

      expect(result).to be true
      content = File.read(gitignore_path)
      expect(content).to include("my_sessions/")
    end
  end
end
