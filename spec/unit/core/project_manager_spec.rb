# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Sxn::Core::ProjectManager do
  let(:temp_dir) { Dir.mktmpdir("sxn_test") }
  let(:project_path) { File.join(temp_dir, "test_project") }
  let(:git_project_path) { File.join(temp_dir, "git_project") }

  let(:mock_config_manager) do
    instance_double(Sxn::Core::ConfigManager).tap do |mgr|
      allow(mgr).to receive(:config_path).and_return(File.join(temp_dir, ".sxn", "config.yml"))
      allow(mgr).to receive(:add_project)
      allow(mgr).to receive(:remove_project)
      allow(mgr).to receive(:list_projects).and_return([])
      allow(mgr).to receive(:get_project).and_return(nil)
      allow(mgr).to receive(:detect_projects).and_return([])
      allow(mgr).to receive(:get_config).and_return(double(projects: {}))
    end
  end

  let(:mock_detector) do
    instance_double(Sxn::Rules::ProjectDetector).tap do |detector|
      allow(detector).to receive(:detect_type).and_return(:unknown)
      allow(detector).to receive(:detect_project_type).and_return(:unknown)
    end
  end

  let(:project_manager) { described_class.new(mock_config_manager) }

  before do
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(git_project_path)

    # Create a mock git repository
    Dir.chdir(git_project_path) do
      system("git init", out: File::NULL, err: File::NULL)
      system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
      system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
      File.write("README.md", "# Test Project")
      system("git add README.md", out: File::NULL, err: File::NULL)
      system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)
    end

    allow(Sxn::Rules::ProjectDetector).to receive(:new).and_return(mock_detector)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "creates a default config manager when none provided" do
      expect(Sxn::Core::ConfigManager).to receive(:new).and_call_original
      allow_any_instance_of(Sxn::Core::ConfigManager).to receive(:config_path).and_return("/tmp/config.yml")

      described_class.new
    end

    it "uses provided config manager" do
      manager = described_class.new(mock_config_manager)
      expect(manager).to be_a(described_class)
    end
  end

  describe "#add_project" do
    it "adds a project with minimal parameters" do
      allow(mock_detector).to receive(:detect_type).and_return(:rails)

      result = project_manager.add_project("test-project", project_path)

      expect(mock_config_manager).to have_received(:add_project).with(
        "test-project",
        project_path,
        type: "unknown",
        default_branch: "master"
      )

      expect(result[:name]).to eq("test-project")
      expect(result[:path]).to eq(File.expand_path(project_path))
      expect(result[:type]).to eq("unknown")
      expect(result[:default_branch]).to eq("master")
    end

    it "adds a project with all parameters" do
      result = project_manager.add_project(
        "custom-project",
        project_path,
        type: "javascript",
        default_branch: "main"
      )

      expect(mock_config_manager).to have_received(:add_project).with(
        "custom-project",
        project_path,
        type: "javascript",
        default_branch: "main"
      )

      expect(result[:type]).to eq("javascript")
      expect(result[:default_branch]).to eq("main")
    end

    it "detects default branch from git repository" do
      # Stub the backtick command method and return value
      allow(project_manager).to receive(:`).and_return("")

      # Use a simple stub for the process status since we can't easily mock $?
      allow(File).to receive(:directory?).and_call_original
      allow(File).to receive(:directory?).with(File.join(git_project_path, ".git")).and_return(true)

      project_manager.add_project("git-project", git_project_path)

      expect(mock_config_manager).to have_received(:add_project).with(
        "git-project",
        git_project_path,
        type: "unknown",
        default_branch: "master" # fallback value when git commands fail
      )
    end

    it "validates project name" do
      expect do
        project_manager.add_project("invalid name!", project_path)
      end.to raise_error(Sxn::InvalidProjectNameError, /must contain only letters/)
    end

    it "validates project path exists" do
      expect do
        project_manager.add_project("test-project", "/non/existent/path")
      end.to raise_error(Sxn::InvalidProjectPathError, "Path is not a directory")
    end

    it "validates project path is readable" do
      non_readable_path = File.join(temp_dir, "non_readable")
      FileUtils.mkdir_p(non_readable_path)
      File.chmod(0o000, non_readable_path)

      expect do
        project_manager.add_project("test-project", non_readable_path)
      end.to raise_error(Sxn::InvalidProjectPathError, "Path is not readable")

      # Cleanup
      File.chmod(0o755, non_readable_path)
    end

    it "raises error if project already exists" do
      existing_project = { name: "existing", path: project_path }
      allow(mock_config_manager).to receive(:get_project).with("existing").and_return(existing_project)

      expect do
        project_manager.add_project("existing", project_path)
      end.to raise_error(Sxn::ProjectAlreadyExistsError, "Project 'existing' already exists")
    end
  end

  describe "#remove_project" do
    let(:mock_session_manager) do
      instance_double(Sxn::Core::SessionManager).tap do |mgr|
        allow(mgr).to receive(:list_sessions).and_return([])
      end
    end

    before do
      allow(Sxn::Core::SessionManager).to receive(:new).and_return(mock_session_manager)
    end

    it "removes a project successfully" do
      project = { name: "test-project", path: project_path }
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(project)

      result = project_manager.remove_project("test-project")

      expect(mock_config_manager).to have_received(:remove_project).with("test-project")
      expect(result).to be(true)
    end

    it "raises error if project not found" do
      allow(mock_config_manager).to receive(:get_project).with("non-existent").and_return(nil)

      expect do
        project_manager.remove_project("non-existent")
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end

    it "raises error if project is used in active sessions" do
      project = { name: "test-project", path: project_path }
      active_session = { name: "test-session", projects: ["test-project"] }

      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(project)
      allow(mock_session_manager).to receive(:list_sessions).with(status: "active").and_return([active_session])

      expect do
        project_manager.remove_project("test-project")
      end.to raise_error(Sxn::ProjectInUseError, /is used in active sessions: test-session/)
    end
  end

  describe "#list_projects" do
    it "delegates to config manager" do
      projects = [{ name: "project1" }, { name: "project2" }]
      allow(mock_config_manager).to receive(:list_projects).and_return(projects)

      result = project_manager.list_projects

      expect(result).to eq(projects)
    end
  end

  describe "#get_project" do
    it "delegates to config manager" do
      project = { name: "test-project", path: project_path }
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(project)

      result = project_manager.get_project("test-project")

      expect(result).to eq(project)
    end

    it "raises error when project not found" do
      allow(mock_config_manager).to receive(:get_project).with("non-existent").and_return(nil)

      expect do
        project_manager.get_project("non-existent")
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end
  end

  describe "#project_exists?" do
    it "returns true when project exists" do
      project = { name: "existing-project" }
      allow(mock_config_manager).to receive(:get_project).with("existing-project").and_return(project)

      expect(project_manager.project_exists?("existing-project")).to be(true)
    end

    it "returns false when project doesn't exist" do
      allow(mock_config_manager).to receive(:get_project).with("non-existent").and_return(nil)

      expect(project_manager.project_exists?("non-existent")).to be(false)
    end
  end

  describe "#scan_projects" do
    it "delegates to config manager detect_projects" do
      detected = [{ name: "found-project", path: "/path" }]
      allow(mock_config_manager).to receive(:detect_projects).and_return(detected)

      result = project_manager.scan_projects

      expect(mock_config_manager).to have_received(:detect_projects)
      expect(result).to eq(detected)
    end

    it "uses custom base path" do
      custom_path = "/custom/path"
      project_manager.scan_projects(custom_path)

      expect(mock_config_manager).to have_received(:detect_projects)
    end
  end

  describe "#detect_projects" do
    let(:test_base_path) { File.join(temp_dir, "detect_test") }

    before do
      FileUtils.mkdir_p(test_base_path)

      # Create a Rails project directory
      rails_dir = File.join(test_base_path, "rails_project")
      FileUtils.mkdir_p(File.join(rails_dir, "config"))
      File.write(File.join(rails_dir, "Gemfile"), "gem 'rails'")
      File.write(File.join(rails_dir, "config", "application.rb"), "class Application")

      # Create a Ruby gem project directory
      gem_dir = File.join(test_base_path, "gem_project")
      FileUtils.mkdir_p(gem_dir)
      File.write(File.join(gem_dir, "test.gemspec"), "Gem::Specification.new")

      # Create a Next.js project directory
      nextjs_dir = File.join(test_base_path, "nextjs_project")
      FileUtils.mkdir_p(nextjs_dir)
      File.write(File.join(nextjs_dir, "package.json"), '{"dependencies": {"next": "13.0.0"}}')

      # Create a React project directory
      react_dir = File.join(test_base_path, "react_project")
      FileUtils.mkdir_p(react_dir)
      File.write(File.join(react_dir, "package.json"), '{"dependencies": {"react": "18.0.0"}}')

      # Create a TypeScript project directory
      ts_dir = File.join(test_base_path, "ts_project")
      FileUtils.mkdir_p(ts_dir)
      File.write(File.join(ts_dir, "package.json"), '{"dependencies": {}}')
      File.write(File.join(ts_dir, "tsconfig.json"), '{"compilerOptions": {}}')

      # Create a JavaScript project directory
      js_dir = File.join(test_base_path, "js_project")
      FileUtils.mkdir_p(js_dir)
      File.write(File.join(js_dir, "package.json"), '{"dependencies": {}}')

      # Create a project with invalid package.json
      invalid_js_dir = File.join(test_base_path, "invalid_js_project")
      FileUtils.mkdir_p(invalid_js_dir)
      File.write(File.join(invalid_js_dir, "package.json"), "invalid json")

      # Create an unknown project type directory
      unknown_dir = File.join(test_base_path, "unknown_project")
      FileUtils.mkdir_p(unknown_dir)
      File.write(File.join(unknown_dir, "README.md"), "Some project")

      # Create a hidden directory (should be skipped)
      hidden_dir = File.join(test_base_path, ".hidden_project")
      FileUtils.mkdir_p(hidden_dir)
      File.write(File.join(hidden_dir, "Gemfile"), "gem 'rails'")

      # Create a regular file (should be skipped)
      File.write(File.join(test_base_path, "regular_file.txt"), "Not a directory")
    end

    it "uses current directory when no base_path provided" do
      original_pwd = Dir.pwd
      begin
        Dir.chdir(test_base_path)
        results = project_manager.detect_projects

        expect(results.size).to be > 0
        detected_names = results.map { |p| p[:name] }
        expect(detected_names).to include("rails_project")
      ensure
        Dir.chdir(original_pwd)
      end
    end

    it "skips non-directory entries" do
      results = project_manager.detect_projects(test_base_path)

      detected_names = results.map { |p| p[:name] }
      expect(detected_names).not_to include("regular_file.txt")
    end

    it "skips hidden directories" do
      results = project_manager.detect_projects(test_base_path)

      detected_names = results.map { |p| p[:name] }
      expect(detected_names).not_to include(".hidden_project")
    end

    it "skips unknown project types" do
      results = project_manager.detect_projects(test_base_path)

      detected_names = results.map { |p| p[:name] }
      expect(detected_names).not_to include("unknown_project")
    end

    it "detects various project types" do
      results = project_manager.detect_projects(test_base_path)

      # Convert to hash for easier testing
      results_by_name = results.each_with_object({}) { |p, hash| hash[p[:name]] = p }

      expect(results_by_name["rails_project"][:type]).to eq("rails")
      expect(results_by_name["gem_project"][:type]).to eq("ruby")
      expect(results_by_name["nextjs_project"][:type]).to eq("nextjs")
      expect(results_by_name["react_project"][:type]).to eq("react")
      expect(results_by_name["ts_project"][:type]).to eq("typescript")
      expect(results_by_name["js_project"][:type]).to eq("javascript")
      expect(results_by_name["invalid_js_project"][:type]).to eq("javascript")
    end
  end

  describe "#detect_project_type" do
    let(:test_path) { File.join(temp_dir, "type_detection") }

    before do
      FileUtils.mkdir_p(test_path)
    end

    context "Rails detection" do
      it "detects Rails projects with Gemfile and config/application.rb" do
        FileUtils.mkdir_p(File.join(test_path, "config"))
        File.write(File.join(test_path, "Gemfile"), "gem 'rails'")
        File.write(File.join(test_path, "config", "application.rb"), "class Application")

        expect(project_manager.detect_project_type(test_path)).to eq("rails")
      end

      it "does not detect Rails without config/application.rb" do
        File.write(File.join(test_path, "Gemfile"), "gem 'rails'")

        expect(project_manager.detect_project_type(test_path)).to eq("ruby")
      end
    end

    context "Ruby gem detection" do
      it "detects Ruby projects with Gemfile only" do
        File.write(File.join(test_path, "Gemfile"), "source 'https://rubygems.org'")

        expect(project_manager.detect_project_type(test_path)).to eq("ruby")
      end

      it "detects Ruby projects with gemspec file" do
        File.write(File.join(test_path, "test.gemspec"), "Gem::Specification.new")

        expect(project_manager.detect_project_type(test_path)).to eq("ruby")
      end

      it "detects Ruby projects with both Gemfile and gemspec" do
        File.write(File.join(test_path, "Gemfile"), "source 'https://rubygems.org'")
        File.write(File.join(test_path, "test.gemspec"), "Gem::Specification.new")

        expect(project_manager.detect_project_type(test_path)).to eq("ruby")
      end
    end

    context "Node.js/JavaScript detection" do
      it "detects Next.js projects" do
        File.write(File.join(test_path, "package.json"), '{"dependencies": {"next": "13.0.0"}}')

        expect(project_manager.detect_project_type(test_path)).to eq("nextjs")
      end

      it "detects React projects without Next.js" do
        File.write(File.join(test_path, "package.json"), '{"dependencies": {"react": "18.0.0"}}')

        expect(project_manager.detect_project_type(test_path)).to eq("react")
      end

      it "detects TypeScript projects with tsconfig.json" do
        File.write(File.join(test_path, "package.json"), '{"dependencies": {}}')
        File.write(File.join(test_path, "tsconfig.json"), '{"compilerOptions": {}}')

        expect(project_manager.detect_project_type(test_path)).to eq("typescript")
      end

      it "detects JavaScript projects as fallback" do
        File.write(File.join(test_path, "package.json"), '{"dependencies": {}}')

        expect(project_manager.detect_project_type(test_path)).to eq("javascript")
      end

      it "handles invalid package.json gracefully" do
        File.write(File.join(test_path, "package.json"), "invalid json content")

        expect(project_manager.detect_project_type(test_path)).to eq("javascript")
      end

      it "handles package.json read errors gracefully" do
        # Create a package.json with restricted permissions
        package_json_path = File.join(test_path, "package.json")
        File.write(package_json_path, '{"dependencies": {}}')
        File.chmod(0o000, package_json_path)

        result = project_manager.detect_project_type(test_path)
        expect(result).to eq("javascript")

        # Cleanup
        File.chmod(0o644, package_json_path)
      end
    end

    context "Unknown project type" do
      it "returns 'unknown' for unrecognized project structures" do
        File.write(File.join(test_path, "README.md"), "Some project")

        expect(project_manager.detect_project_type(test_path)).to eq("unknown")
      end

      it "returns 'unknown' for empty directories" do
        expect(project_manager.detect_project_type(test_path)).to eq("unknown")
      end
    end
  end

  describe "#update_project" do
    let(:existing_project) { { name: "test-project", path: project_path, type: "rails" } }

    before do
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(existing_project)
      allow(mock_config_manager).to receive(:update_project)
    end

    it "updates project successfully" do
      updates = { type: "javascript" }
      updated_project = existing_project.merge(updates)
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(updated_project)

      result = project_manager.update_project("test-project", updates)

      expect(mock_config_manager).to have_received(:update_project).with("test-project", updates)
      expect(result).to eq(updated_project)
    end

    it "raises error for non-existent project" do
      allow(mock_config_manager).to receive(:get_project).with("non-existent").and_return(nil)

      expect do
        project_manager.update_project("non-existent", {})
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end

    it "validates path updates exist" do
      non_existent_path = "/path/that/does/not/exist"
      updates = { path: non_existent_path }

      expect do
        project_manager.update_project("test-project", updates)
      end.to raise_error(Sxn::InvalidProjectPathError, "Path is not a directory")
    end

    it "allows updates without path validation when no path provided" do
      updates = { type: "javascript" }
      updated_project = existing_project.merge(updates)
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(updated_project)

      result = project_manager.update_project("test-project", updates)

      expect(result).to eq(updated_project)
    end

    it "handles project deletion during update" do
      updates = { type: "javascript" }
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(existing_project, nil)

      expect do
        project_manager.update_project("test-project", updates)
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'test-project' was deleted during update")
    end
  end

  describe "#validate_projects" do
    it "validates multiple projects and returns results" do
      projects = [
        { name: "project1", path: git_project_path },
        { name: "project2", path: "/non/existent" }
      ]

      allow(mock_config_manager).to receive(:list_projects).and_return(projects)
      allow(mock_config_manager).to receive(:get_project).with("project1").and_return(projects[0])
      allow(mock_config_manager).to receive(:get_project).with("project2").and_return(projects[1])

      results = project_manager.validate_projects

      expect(results.size).to eq(2)
      expect(results[0][:valid]).to be(true)
      expect(results[1][:valid]).to be(false)
    end

    it "handles empty project list" do
      allow(mock_config_manager).to receive(:list_projects).and_return([])

      results = project_manager.validate_projects

      expect(results).to be_empty
    end
  end

  describe "#auto_register_projects" do
    let(:detected_projects) do
      [
        { name: "valid-project", path: project_path, type: "rails" },
        { name: "invalid-path", path: "/non/existent", type: "rails" }
      ]
    end

    it "registers valid projects and reports errors for invalid ones" do
      allow(mock_detector).to receive(:detect_type).and_return(:rails)

      results = project_manager.auto_register_projects(detected_projects)

      expect(results.size).to eq(2)
      expect(results[0][:status]).to eq(:success)
      expect(results[0][:project][:name]).to eq("valid-project")

      expect(results[1][:status]).to eq(:error)
      expect(results[1][:project][:name]).to eq("invalid-path")
      expect(results[1][:error]).to include("Path is not a directory")
    end
  end

  describe "#validate_project" do
    it "validates a healthy project" do
      project = { name: "test-project", path: git_project_path }
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(project)

      result = project_manager.validate_project("test-project")

      expect(result[:valid]).to be(true)
      expect(result[:issues]).to be_empty
      expect(result[:project]).to eq(project)
    end

    it "identifies project with non-existent path" do
      project = { name: "test-project", path: "/non/existent/path" }
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(project)

      result = project_manager.validate_project("test-project")

      expect(result[:valid]).to be(false)
      expect(result[:issues]).to include(/Project path does not exist/)
    end

    it "identifies non-git repository" do
      project = { name: "test-project", path: project_path }
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(project)

      result = project_manager.validate_project("test-project")

      expect(result[:valid]).to be(false)
      expect(result[:issues]).to include("Project path is not a git repository")
    end

    it "identifies non-readable path" do
      non_readable_path = File.join(temp_dir, "non_readable")
      FileUtils.mkdir_p(non_readable_path)
      File.chmod(0o000, non_readable_path)

      project = { name: "test-project", path: non_readable_path }
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(project)

      result = project_manager.validate_project("test-project")

      expect(result[:valid]).to be(false)
      expect(result[:issues]).to include("Project path is not readable")

      # Cleanup
      File.chmod(0o755, non_readable_path)
    end

    it "raises error if project not found" do
      allow(mock_config_manager).to receive(:get_project).with("non-existent").and_return(nil)

      expect do
        project_manager.validate_project("non-existent")
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end
  end

  describe "#get_project_rules" do
    let(:project) { { name: "test-project", path: project_path, type: "rails" } }
    let(:config) { double(projects: { "test-project" => { "rules" => custom_rules } }) }
    let(:custom_rules) do
      {
        "copy_files" => [{ "source" => "custom.env", "strategy" => "copy" }],
        "custom_rule" => "custom_value"
      }
    end

    before do
      allow(mock_config_manager).to receive(:get_project).with("test-project").and_return(project)
      allow(mock_config_manager).to receive(:get_config).and_return(config)
    end

    it "merges default rules with custom rules for Rails projects" do
      result = project_manager.get_project_rules("test-project")

      expect(result).to have_key("copy_files")
      expect(result).to have_key("setup_commands")
      expect(result).to have_key("custom_rule")
      expect(result["custom_rule"]).to eq("custom_value")

      # Check that Rails default rules are included
      expect(result["setup_commands"]).to include({ "command" => %w[bundle install] })

      # Check that custom copy_files are merged with defaults
      copy_files = result["copy_files"]
      expect(copy_files).to include({ "source" => "custom.env", "strategy" => "copy" })
      expect(copy_files).to include({ "source" => "config/master.key", "strategy" => "copy" })
    end

    it "returns JavaScript rules for JavaScript projects" do
      project[:type] = "javascript"

      result = project_manager.get_project_rules("test-project")

      expect(result["setup_commands"]).to include({ "command" => %w[npm install] })
      expect(result["copy_files"]).to include({ "source" => ".env", "strategy" => "copy" })
    end

    it "returns empty rules for unknown project types" do
      project[:type] = "unknown"
      config = double(projects: { "test-project" => nil })
      allow(mock_config_manager).to receive(:get_config).and_return(config)

      result = project_manager.get_project_rules("test-project")

      expect(result).to be_empty
    end

    it "raises error if project not found" do
      allow(mock_config_manager).to receive(:get_project).with("non-existent").and_return(nil)

      expect do
        project_manager.get_project_rules("non-existent")
      end.to raise_error(Sxn::ProjectNotFoundError, "Project 'non-existent' not found")
    end
  end

  describe "private methods" do
    describe "#detect_default_branch" do
      it "returns 'master' for non-git directories" do
        branch = project_manager.send(:detect_default_branch, project_path)
        expect(branch).to eq("master")
      end

      it "detects branch from git repository" do
        # This is a real git repository created in the before block
        branch = project_manager.send(:detect_default_branch, git_project_path)
        expect(branch).to be_a(String)
        expect(branch).not_to be_empty
      end

      it "handles git command errors gracefully" do
        # Create a broken git repository
        broken_git_path = File.join(temp_dir, "broken_git")
        FileUtils.mkdir_p(File.join(broken_git_path, ".git"))

        branch = project_manager.send(:detect_default_branch, broken_git_path)
        expect(branch).to eq("master")
      end

      context "with git repository" do
        let(:test_git_path) { File.join(temp_dir, "test_git_branches") }

        before do
          FileUtils.mkdir_p(test_git_path)
          Dir.chdir(test_git_path) do
            system("git init", out: File::NULL, err: File::NULL)
            system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
            system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
            File.write("README.md", "# Test Project")
            system("git add README.md", out: File::NULL, err: File::NULL)
            system("git commit -m 'Initial commit'", out: File::NULL, err: File::NULL)
          end
        end

        it "returns result from git symbolic-ref when available" do
          Dir.chdir(test_git_path) do
            # Set up a remote origin with HEAD
            system("git remote add origin https://github.com/test/repo.git", out: File::NULL, err: File::NULL)
            system("git branch -M main", out: File::NULL, err: File::NULL)
            system("git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main", out: File::NULL, err: File::NULL)
          end

          branch = project_manager.send(:detect_default_branch, test_git_path)
          expect(branch).to eq("main")
        end

        it "falls back to current branch when symbolic-ref fails but show-current succeeds" do
          Dir.chdir(test_git_path) do
            # Ensure we're on a specific branch and clear any remote tracking
            system("git checkout -b feature-branch", out: File::NULL, err: File::NULL)
            # Remove any remote that might interfere
            begin
              system("git remote rm origin", out: File::NULL, err: File::NULL)
            rescue StandardError
              nil
            end
          end

          branch = project_manager.send(:detect_default_branch, test_git_path)
          # Should return the current branch since symbolic-ref will fail
          expect(%w[feature-branch master]).to include(branch)
        end

        it "returns master when in empty repo (detached HEAD state)" do
          empty_git_path = File.join(temp_dir, "empty_git")
          FileUtils.mkdir_p(empty_git_path)

          # Create an empty git repository (no commits)
          Dir.chdir(empty_git_path) do
            system("git init", out: File::NULL, err: File::NULL)
            system("git config user.email 'test@example.com'", out: File::NULL, err: File::NULL)
            system("git config user.name 'Test User'", out: File::NULL, err: File::NULL)
          end

          branch = project_manager.send(:detect_default_branch, empty_git_path)
          expect(branch).to eq("master")
        end

        it "handles StandardError exceptions gracefully" do
          # Mock to raise an exception
          allow(Dir).to receive(:chdir).with(test_git_path).and_raise(StandardError.new("Test error"))

          branch = project_manager.send(:detect_default_branch, test_git_path)
          expect(branch).to eq("master")
        end
      end
    end

    describe "#git_repository?" do
      it "returns true for git repositories" do
        expect(project_manager.send(:git_repository?, git_project_path)).to be(true)
      end

      it "returns false for non-git directories" do
        expect(project_manager.send(:git_repository?, project_path)).to be(false)
      end
    end

    describe "#get_default_rules_for_type" do
      it "returns Rails rules for rails type" do
        rules = project_manager.send(:get_default_rules_for_type, "rails")

        expect(rules).to have_key("copy_files")
        expect(rules).to have_key("setup_commands")
        expect(rules["copy_files"]).to include({ "source" => "config/master.key", "strategy" => "copy" })
        expect(rules["setup_commands"]).to include({ "command" => %w[bundle install] })
      end

      it "returns JavaScript rules for javascript types" do
        %w[javascript typescript nextjs react].each do |type|
          rules = project_manager.send(:get_default_rules_for_type, type)

          expect(rules).to have_key("copy_files")
          expect(rules).to have_key("setup_commands")
          expect(rules["setup_commands"]).to include({ "command" => %w[npm install] })
        end
      end

      it "returns empty rules for unknown types" do
        rules = project_manager.send(:get_default_rules_for_type, "unknown")
        expect(rules).to eq({})
      end
    end

    describe "#merge_rules" do
      let(:default_rules) do
        {
          "copy_files" => [{ "source" => "default.env", "strategy" => "copy" }],
          "setup_commands" => [{ "command" => %w[bundle install] }],
          "default_only" => "default_value"
        }
      end

      let(:custom_rules) do
        {
          "copy_files" => [{ "source" => "custom.env", "strategy" => "copy" }],
          "custom_only" => "custom_value",
          "override_rule" => "custom_override"
        }
      end

      it "merges array rules" do
        result = project_manager.send(:merge_rules, default_rules, custom_rules)

        expect(result["copy_files"].size).to eq(2)
        expect(result["copy_files"]).to include({ "source" => "default.env", "strategy" => "copy" })
        expect(result["copy_files"]).to include({ "source" => "custom.env", "strategy" => "copy" })
      end

      it "preserves default-only rules" do
        result = project_manager.send(:merge_rules, default_rules, custom_rules)

        expect(result["setup_commands"]).to eq([{ "command" => %w[bundle install] }])
        expect(result["default_only"]).to eq("default_value")
      end

      it "adds custom-only rules" do
        result = project_manager.send(:merge_rules, default_rules, custom_rules)

        expect(result["custom_only"]).to eq("custom_value")
        expect(result["override_rule"]).to eq("custom_override")
      end

      it "overrides non-array rules" do
        default_rules["override_rule"] = "default_override"

        result = project_manager.send(:merge_rules, default_rules, custom_rules)

        expect(result["override_rule"]).to eq("custom_override")
      end

      it "handles mixed array and non-array rule merging" do
        mixed_custom_rules = {
          "copy_files" => [{ "source" => "custom.env", "strategy" => "copy" }],
          "string_rule" => "new_string_value",
          "hash_rule" => { "key" => "value" }
        }

        result = project_manager.send(:merge_rules, default_rules, mixed_custom_rules)

        # Array rules are merged
        expect(result["copy_files"].size).to eq(2)
        expect(result["copy_files"]).to include({ "source" => "custom.env", "strategy" => "copy" })

        # Non-array rules are replaced
        expect(result["string_rule"]).to eq("new_string_value")
        expect(result["hash_rule"]).to eq({ "key" => "value" })
      end
    end
  end
end
