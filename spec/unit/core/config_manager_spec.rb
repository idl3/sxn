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
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
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
          actual_basename = File.basename(File.dirname(File.dirname(manager.config_path)))
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
        config = YAML.safe_load(File.read(config_path))
        
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
        expect {
          config_manager.initialize_project(sessions_folder)
        }.to raise_error(Sxn::ConfigurationError, /already initialized/)
      end

      it "reinitializes with force flag" do
        expect {
          config_manager.initialize_project(sessions_folder, force: true)
        }.not_to raise_error
      end
    end
  end

  describe "#get_config" do
    context "when not initialized" do
      it "raises configuration error" do
        expect {
          config_manager.get_config
        }.to raise_error(Sxn::ConfigurationError, /not initialized/)
      end
    end

    context "when initialized" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "returns config through discovery" do
        discovery_double = instance_double(Sxn::Config::ConfigDiscovery)
        expected_config = { "test" => "config" }
        
        allow(Sxn::Config::ConfigDiscovery).to receive(:new).with(temp_dir).and_return(discovery_double)
        allow(discovery_double).to receive(:discover_config).and_return(expected_config)
        
        result = config_manager.get_config
        expect(result).to eq(expected_config)
      end
    end
  end

  describe "#update_current_session" do
    before do
      config_manager.initialize_project(sessions_folder)
    end

    it "updates current session in config file" do
      config_manager.update_current_session("test_session")
      
      config = YAML.safe_load(File.read(config_path))
      expect(config["current_session"]).to eq("test_session")
    end

    it "handles nil session name" do
      config_manager.update_current_session(nil)
      
      config = YAML.safe_load(File.read(config_path))
      expect(config["current_session"]).to be_nil
    end

    it "overwrites existing current session" do
      config_manager.update_current_session("session1")
      config_manager.update_current_session("session2")
      
      config = YAML.safe_load(File.read(config_path))
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
      
      config = YAML.safe_load(File.read(config_path))
      project = config["projects"]["test_project"]
      
      expect(project["path"]).to eq("test_project")
      expect(project["type"]).to eq("rails")
      expect(project["default_branch"]).to eq("main")
    end

    it "adds project with minimal parameters" do
      project_path = File.join(temp_dir, "minimal_project")
      
      config_manager.add_project("minimal_project", project_path)
      
      config = YAML.safe_load(File.read(config_path))
      project = config["projects"]["minimal_project"]
      
      expect(project["path"]).to eq("minimal_project")
      expect(project["type"]).to be_nil
      expect(project["default_branch"]).to eq("master")
    end

    it "converts absolute paths to relative paths" do
      absolute_path = File.join(temp_dir, "absolute_project")
      
      config_manager.add_project("absolute_project", absolute_path)
      
      config = YAML.safe_load(File.read(config_path))
      project = config["projects"]["absolute_project"]
      
      expect(project["path"]).to eq("absolute_project")
    end

    it "initializes projects hash if it doesn't exist" do
      # Manually remove projects from config
      config = YAML.safe_load(File.read(config_path))
      config.delete("projects")
      File.write(config_path, YAML.dump(config))
      
      project_path = File.join(temp_dir, "new_project")
      config_manager.add_project("new_project", project_path)
      
      config = YAML.safe_load(File.read(config_path))
      expect(config["projects"]).to be_a(Hash)
      expect(config["projects"]["new_project"]).not_to be_nil
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
      
      config = YAML.safe_load(File.read(config_path))
      expect(config["projects"]["test_project"]).to be_nil
    end

    it "handles removal of non-existent project" do
      expect {
        config_manager.remove_project("non_existent")
      }.not_to raise_error
      
      config = YAML.safe_load(File.read(config_path))
      expect(config["projects"]["test_project"]).not_to be_nil
    end

    it "handles removal when projects hash is nil" do
      # Manually set projects to nil
      config = YAML.safe_load(File.read(config_path))
      config["projects"] = nil
      File.write(config_path, YAML.dump(config))
      
      expect {
        config_manager.remove_project("test_project")
      }.not_to raise_error
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
        config = YAML.safe_load(File.read(config_path))
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
        
        expect {
          config_manager.send(:load_config_file)
        }.to raise_error(Sxn::ConfigurationError, /Invalid configuration file/)
      end
    end

    describe "#save_config_file" do
      before do
        FileUtils.mkdir_p(File.dirname(config_path))
      end

      it "saves config as YAML" do
        test_config = { "test" => "value", "number" => 42 }
        config_manager.send(:save_config_file, test_config)
        
        loaded_config = YAML.safe_load(File.read(config_path))
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
        config = YAML.safe_load(File.read(config_path))
        
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

  # Edge cases and error conditions
  describe "edge cases" do
    context "with permission errors" do
      before do
        config_manager.initialize_project(sessions_folder)
      end

      it "handles config file read permission errors gracefully" do
        allow(File).to receive(:read).with(config_path).and_raise(Errno::EACCES, "Permission denied")
        
        expect {
          config_manager.send(:load_config_file)
        }.to raise_error(Errno::EACCES)
      end
    end

    context "with disk space errors" do
      it "handles disk full errors during initialization" do
        allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::ENOSPC, "No space left on device")
        
        expect {
          config_manager.initialize_project(sessions_folder)
        }.to raise_error(Errno::ENOSPC)
      end
    end

    context "with invalid paths" do
      it "handles invalid session folder paths" do
        invalid_path = "/invalid/\0/path"
        
        expect {
          config_manager.initialize_project(invalid_path)
        }.to raise_error(ArgumentError)
      end
    end
  end
end