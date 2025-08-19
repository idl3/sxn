# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Rules::ProjectDetector do
  let(:project_path) { Dir.mktmpdir("project") }
  let(:detector) { described_class.new(project_path) }

  after do
    FileUtils.rm_rf(project_path)
  end

  describe "#initialize" do
    it "initializes with valid project path" do
      expect(detector.project_path).to eq(File.realpath(project_path))
    end

    it "raises error for non-existent project path" do
      expect do
        described_class.new("/non/existent")
      end.to raise_error(ArgumentError, /Project path does not exist/)
    end

    it "raises error for non-directory path" do
      file_path = File.join(project_path, "file.txt")
      File.write(file_path, "test")

      expect do
        described_class.new(file_path)
      end.to raise_error(ArgumentError, /Project path is not a directory/)
    end

    it "raises error for unreadable directory" do
      File.chmod(0o000, project_path)

      expect do
        described_class.new(project_path)
      end.to raise_error(ArgumentError, /Project path is not readable/)
    ensure
      File.chmod(0o755, project_path)
    end
  end

  describe "#detect_type" do
    it "returns :unknown for non-existent path" do
      result = detector.detect_type("/non/existent/path")
      expect(result).to eq(:unknown)
    end

    it "detects project type for valid path" do
      File.write(File.join(project_path, "package.json"), '{"name": "test", "dependencies": {"react": "^18.0.0"}}')
      result = detector.detect_type(project_path)
      expect(result).to eq(:react)
    end
  end

  describe "#detect_project_type" do
    it "returns :unknown when no files match" do
      result = detector.detect_project_type
      expect(result).to eq(:unknown)
    end

    context "with Rails project" do
      before do
        File.write(File.join(project_path, "Gemfile"), 'gem "rails", "~> 7.0"')
        FileUtils.mkdir_p(File.join(project_path, "config"))
        File.write(File.join(project_path, "config/application.rb"), "class Application < Rails::Application; end")
      end

      it "detects Rails project" do
        expect(detector.detect_project_type).to eq(:rails)
      end
    end

    context "with Ruby (non-Rails) project" do
      before do
        File.write(File.join(project_path, "Gemfile"), 'gem "nokogiri"')
      end

      it "detects Ruby project" do
        expect(detector.detect_project_type).to eq(:ruby)
      end
    end

    context "with Next.js project" do
      before do
        package_json = {
          "name" => "my-app",
          "dependencies" => {
            "next" => "^13.0.0",
            "react" => "^18.0.0"
          }
        }
        File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))
        File.write(File.join(project_path, "next.config.js"), "module.exports = {}")
      end

      it "detects Next.js project" do
        expect(detector.detect_project_type).to eq(:nextjs)
      end
    end

    context "with React project" do
      before do
        package_json = {
          "name" => "my-app",
          "dependencies" => {
            "react" => "^18.0.0",
            "react-dom" => "^18.0.0"
          }
        }
        File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))
      end

      it "detects React project" do
        expect(detector.detect_project_type).to eq(:react)
      end
    end

    context "with TypeScript project" do
      before do
        File.write(File.join(project_path, "tsconfig.json"), '{"compilerOptions": {}}')
        File.write(File.join(project_path, "index.ts"), "console.log('Hello')")
      end

      it "detects TypeScript project" do
        expect(detector.detect_project_type).to eq(:typescript)
      end
    end

    context "with Node.js project" do
      before do
        package_json = {
          "name" => "my-app",
          "main" => "index.js"
        }
        File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))
      end

      it "detects Node.js project" do
        expect(detector.detect_project_type).to eq(:nodejs)
      end
    end

    context "with Django project" do
      before do
        File.write(File.join(project_path, "manage.py"), "#!/usr/bin/env python")
        File.write(File.join(project_path, "requirements.txt"), "Django==4.2.0")
      end

      it "detects Django project" do
        expect(detector.detect_project_type).to eq(:django)
      end
    end

    context "with Python project" do
      before do
        File.write(File.join(project_path, "requirements.txt"), "requests==2.28.0")
        File.write(File.join(project_path, "main.py"), "print('Hello')")
      end

      it "detects Python project" do
        expect(detector.detect_project_type).to eq(:python)
      end
    end

    context "with Go project" do
      before do
        File.write(File.join(project_path, "go.mod"), "module example.com/myapp")
        File.write(File.join(project_path, "main.go"), "package main")
      end

      it "detects Go project" do
        expect(detector.detect_project_type).to eq(:go)
      end
    end

    context "with Rust project" do
      before do
        File.write(File.join(project_path, "Cargo.toml"), "[package]\nname = \"myapp\"")
        FileUtils.mkdir_p(File.join(project_path, "src"))
        File.write(File.join(project_path, "src/main.rs"), "fn main() {}")
      end

      it "detects Rust project" do
        expect(detector.detect_project_type).to eq(:rust)
      end
    end

    context "with unknown project" do
      before do
        File.write(File.join(project_path, "README.md"), "# My Project")
      end

      it "returns unknown type" do
        expect(detector.detect_project_type).to eq(:unknown)
      end
    end
  end

  describe "#detect_package_manager" do
    context "with Bundler" do
      before do
        File.write(File.join(project_path, "Gemfile"), 'gem "rails"')
        File.write(File.join(project_path, "Gemfile.lock"), "GEM\n  specs:\n    rails (7.0.0)")
      end

      it "detects Bundler" do
        expect(detector.detect_package_manager).to eq(:bundler)
      end
    end

    context "with npm" do
      before do
        File.write(File.join(project_path, "package.json"), '{"name": "app"}')
        File.write(File.join(project_path, "package-lock.json"), '{"name": "app"}')
      end

      it "detects npm" do
        expect(detector.detect_package_manager).to eq(:npm)
      end
    end

    context "with Yarn" do
      before do
        File.write(File.join(project_path, "package.json"), '{"name": "app"}')
        File.write(File.join(project_path, "yarn.lock"), "# yarn lockfile v1")
      end

      it "detects Yarn" do
        expect(detector.detect_package_manager).to eq(:yarn)
      end
    end

    context "with pnpm" do
      before do
        File.write(File.join(project_path, "package.json"), '{"name": "app"}')
        File.write(File.join(project_path, "pnpm-lock.yaml"), "lockfileVersion: 5.4")
      end

      it "detects pnpm" do
        expect(detector.detect_package_manager).to eq(:pnpm)
      end
    end

    context "with pip" do
      before do
        File.write(File.join(project_path, "requirements.txt"), "django==4.2.0")
      end

      it "detects pip" do
        expect(detector.detect_package_manager).to eq(:pip)
      end
    end

    context "with Pipenv" do
      before do
        File.write(File.join(project_path, "Pipfile"), "[packages]\ndjango = \"*\"")
        File.write(File.join(project_path, "Pipfile.lock"), '{"_meta": {}}')
      end

      it "detects Pipenv" do
        expect(detector.detect_package_manager).to eq(:pipenv)
      end
    end

    context "with Poetry" do
      before do
        File.write(File.join(project_path, "pyproject.toml"), "[tool.poetry]\nname = \"myapp\"")
        File.write(File.join(project_path, "poetry.lock"), "[[package]]")
      end

      it "detects Poetry" do
        expect(detector.detect_package_manager).to eq(:poetry)
      end
    end

    context "with Cargo" do
      before do
        File.write(File.join(project_path, "Cargo.toml"), "[package]\nname = \"myapp\"")
        File.write(File.join(project_path, "Cargo.lock"), "[[package]]")
      end

      it "detects Cargo" do
        expect(detector.detect_package_manager).to eq(:cargo)
      end
    end

    context "with Go modules" do
      before do
        File.write(File.join(project_path, "go.mod"), "module example.com/myapp")
        File.write(File.join(project_path, "go.sum"), "example.com/pkg v1.0.0 h1:abc")
      end

      it "detects go mod" do
        expect(detector.detect_package_manager).to eq(:go_mod)
      end
    end

    context "with unknown package manager" do
      before do
        File.write(File.join(project_path, "README.md"), "# My Project")
      end

      it "returns unknown" do
        expect(detector.detect_package_manager).to eq(:unknown)
      end
    end
  end

  describe "#detect_project_info" do
    before do
      # Create a Rails project
      File.write(File.join(project_path, "Gemfile"), 'gem "rails", "~> 7.0"')
      FileUtils.mkdir_p(File.join(project_path, "config"))
      File.write(File.join(project_path, "config/application.rb"), "class Application < Rails::Application; end")
      File.write(File.join(project_path, "config/master.key"), "secret")
      File.write(File.join(project_path, ".env"), "DATABASE_URL=postgresql://localhost/test")
      File.write(File.join(project_path, "Dockerfile"), "FROM ruby:3.2")
      FileUtils.mkdir_p(File.join(project_path, "spec"))
      File.write(File.join(project_path, "spec/rails_helper.rb"), "require 'rspec/rails'")
    end

    it "returns comprehensive project information" do
      info = detector.detect_project_info

      expect(info).to include(
        type: :rails,
        language: :ruby,
        package_manager: :bundler,
        framework: :rails,
        has_docker: true,
        has_tests: true,
        has_ci: false,
        database: :unknown
      )
      expect(info[:sensitive_files]).to include("config/master.key", ".env")
      expect(info[:analysis_timestamp]).to be_a(String)
    end
  end

  describe "#suggest_default_rules" do
    it "returns rules even for unknown project type" do
      rules = detector.suggest_default_rules
      # Even unknown project types get template rules
      expect(rules).to be_a(Hash)
      expect(rules.keys).to include("templates")
    end
    context "for Rails project" do
      before do
        File.write(File.join(project_path, "Gemfile"), 'gem "rails", "~> 7.0"')
        FileUtils.mkdir_p(File.join(project_path, "config"))
        File.write(File.join(project_path, "config/application.rb"), "class Application < Rails::Application; end")
        File.write(File.join(project_path, "config/master.key"), "secret")
        File.write(File.join(project_path, ".env"), "DATABASE_URL=postgresql://localhost/test")
      end

      it "suggests Rails-specific rules" do
        rules = detector.suggest_default_rules

        expect(rules).to have_key("copy_files")
        expect(rules).to have_key("setup_commands")
        expect(rules).to have_key("templates")

        # Check copy_files suggestions
        copy_files = rules["copy_files"]["config"]["files"]
        expect(copy_files.map { |f| f["source"] }).to include("config/master.key", ".env")

        # Check setup_commands suggestions
        setup_commands = rules["setup_commands"]["config"]["commands"]
        expect(setup_commands.map { |c| c["command"] }).to include(%w[bundle install])
      end
    end

    context "for Node.js project" do
      before do
        package_json = {
          "name" => "my-app",
          "dependencies" => { "express" => "^4.18.0" },
          "scripts" => { "build" => "webpack build" }
        }
        File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))
        File.write(File.join(project_path, ".env"), "NODE_ENV=development")
        File.write(File.join(project_path, ".npmrc"), "registry=https://registry.npmjs.org/")
      end

      it "suggests Node.js-specific rules" do
        rules = detector.suggest_default_rules

        expect(rules).to have_key("copy_files")
        expect(rules).to have_key("setup_commands")

        # Check copy_files suggestions
        copy_files = rules["copy_files"]["config"]["files"]
        source_files = copy_files.map { |f| f["source"] }
        expect(source_files).to include(".env", ".npmrc")

        # Check setup_commands suggestions
        setup_commands = rules["setup_commands"]["config"]["commands"]
        commands = setup_commands.map { |c| c["command"] }
        expect(commands).to include(%w[npm install])
      end
    end

    context "for Python project" do
      before do
        File.write(File.join(project_path, "requirements.txt"), "django==4.2.0")
        File.write(File.join(project_path, ".env"), "DEBUG=True")
      end

      it "suggests Python-specific rules" do
        rules = detector.suggest_default_rules

        expect(rules).to have_key("copy_files")
        expect(rules).to have_key("setup_commands")

        # Check setup_commands suggestions
        setup_commands = rules["setup_commands"]["config"]["commands"]
        commands = setup_commands.map { |c| c["command"] }
        expect(commands).to include(["pip", "install", "-r", "requirements.txt"])
      end
    end

    context "for project with no specific type" do
      before do
        File.write(File.join(project_path, "README.md"), "# My Project")
      end

      it "suggests minimal default rules" do
        rules = detector.suggest_default_rules

        # Should still suggest templates
        expect(rules).to have_key("templates")

        # But copy_files and setup_commands should be empty or minimal
        expect(rules["copy_files"]["config"]["files"]).to be_empty if rules.key?("copy_files")

        expect(rules["setup_commands"]["config"]["commands"]).to be_empty if rules.key?("setup_commands")
      end
    end
  end

  describe "#analyze_project_structure" do
    before do
      # Create a comprehensive project structure
      FileUtils.mkdir_p(File.join(project_path, "src"))
      FileUtils.mkdir_p(File.join(project_path, "lib"))
      FileUtils.mkdir_p(File.join(project_path, "test"))
      FileUtils.mkdir_p(File.join(project_path, "docs"))

      File.write(File.join(project_path, "README.md"), "# Project")
      File.write(File.join(project_path, "LICENSE"), "MIT License")
      File.write(File.join(project_path, "Makefile"), "all: build")
      File.write(File.join(project_path, ".gitignore"), "*.log")
      File.write(File.join(project_path, "config.yml"), "setting: value")
      File.write(File.join(project_path, "docs/guide.md"), "# Guide")

      package_json = {
        "name" => "my-app",
        "scripts" => {
          "build" => "webpack build",
          "test" => "jest",
          "dev" => "webpack serve"
        }
      }
      File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))

      FileUtils.mkdir_p(File.join(project_path, "bin"))
      File.write(File.join(project_path, "bin/setup"), "#!/bin/bash\necho 'Setup'")
      File.chmod(0o755, File.join(project_path, "bin/setup"))
    end

    it "analyzes project structure comprehensively" do
      analysis = detector.analyze_project_structure

      expect(analysis).to include(:files, :directories, :dependencies, :configuration, :scripts, :documentation)

      # Check important files
      expect(analysis[:files]).to include("README.md", "LICENSE", "Makefile", ".gitignore")

      # Check directories
      expect(analysis[:directories]).to include("src", "lib", "test", "docs")

      # Check configuration files
      expect(analysis[:configuration]).to include("config.yml", "package.json")

      # Check scripts
      expect(analysis[:scripts][:npm]).to include("build", "test", "dev")
      expect(analysis[:scripts][:executables]).to include("setup")

      # Check documentation
      expect(analysis[:documentation]).to include("README.md", "docs/guide.md")
    end
  end

  describe "framework detection" do
    context "with Express.js" do
      before do
        package_json = {
          "dependencies" => { "express" => "^4.18.0" }
        }
        File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))
      end

      it "detects Express framework" do
        info = detector.detect_project_info
        expect(info[:framework]).to eq(:express)
      end
    end

    context "with Vue.js" do
      before do
        package_json = {
          "dependencies" => { "vue" => "^3.2.0" }
        }
        File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))
      end

      it "detects Vue framework" do
        info = detector.detect_project_info
        expect(info[:framework]).to eq(:vue)
      end
    end

    context "with Flask" do
      before do
        File.write(File.join(project_path, "requirements.txt"), "Flask==2.3.0")
      end

      it "detects Flask framework" do
        info = detector.detect_project_info
        expect(info[:framework]).to eq(:flask)
      end
    end

    context "with FastAPI" do
      before do
        File.write(File.join(project_path, "requirements.txt"), "fastapi==0.100.0")
      end

      it "detects FastAPI framework" do
        info = detector.detect_project_info
        expect(info[:framework]).to eq(:fastapi)
      end
    end
  end

  describe "database detection" do
    context "with PostgreSQL configuration" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "config"))
        database_yml = <<~YAML
          development:
            adapter: postgresql
            database: myapp_development
        YAML
        File.write(File.join(project_path, "config/database.yml"), database_yml)
      end

      it "detects PostgreSQL database" do
        info = detector.detect_project_info
        expect(info[:database]).to eq(:postgresql)
      end
    end

    context "with MySQL configuration" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "config"))
        database_yml = <<~YAML
          development:
            adapter: mysql2
            database: myapp_development
        YAML
        File.write(File.join(project_path, "config/database.yml"), database_yml)
      end

      it "detects MySQL database" do
        info = detector.detect_project_info
        expect(info[:database]).to eq(:mysql)
      end
    end

    context "with SQLite configuration" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "config"))
        database_yml = <<~YAML
          development:
            adapter: sqlite3
            database: db/development.sqlite3
        YAML
        File.write(File.join(project_path, "config/database.yml"), database_yml)
      end

      it "detects SQLite database" do
        info = detector.detect_project_info
        expect(info[:database]).to eq(:sqlite)
      end
    end

    context "with MongoDB in Node.js" do
      before do
        package_json = {
          "dependencies" => { "mongoose" => "^7.0.0" }
        }
        File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))
      end

      it "detects MongoDB database" do
        info = detector.detect_project_info
        expect(info[:database]).to eq(:mongodb)
      end
    end
  end

  describe "CI/CD detection" do
    context "with GitHub Actions" do
      before do
        FileUtils.mkdir_p(File.join(project_path, ".github/workflows"))
        File.write(File.join(project_path, ".github/workflows/test.yml"), "name: Test")
      end

      it "detects CI configuration" do
        info = detector.detect_project_info
        expect(info[:has_ci]).to be true
      end
    end

    context "with GitLab CI" do
      before do
        File.write(File.join(project_path, ".gitlab-ci.yml"), "stages:\n  - test")
      end

      it "detects CI configuration" do
        info = detector.detect_project_info
        expect(info[:has_ci]).to be true
      end
    end

    context "with CircleCI" do
      before do
        FileUtils.mkdir_p(File.join(project_path, ".circleci"))
        File.write(File.join(project_path, ".circleci/config.yml"), "version: 2.1")
      end

      it "detects CI configuration" do
        info = detector.detect_project_info
        expect(info[:has_ci]).to be true
      end
    end
  end

  describe "sensitive file detection" do
    before do
      FileUtils.mkdir_p(File.join(project_path, "config"))
      File.write(File.join(project_path, "config/master.key"), "secret")
      File.write(File.join(project_path, ".env"), "API_KEY=secret")
      File.write(File.join(project_path, ".env.production"), "DATABASE_URL=...")
      File.write(File.join(project_path, "server.pem"), "-----BEGIN CERTIFICATE-----")
      File.write(File.join(project_path, ".npmrc"), "//registry.npmjs.org/:_authToken=...")
      File.write(File.join(project_path, "README.md"), "# Project")
    end

    it "detects sensitive files" do
      info = detector.detect_project_info

      expect(info[:sensitive_files]).to include(
        "config/master.key",
        ".env",
        ".env.production",
        "server.pem",
        ".npmrc"
      )
      expect(info[:sensitive_files]).not_to include("README.md")
    end
  end

  describe "primary language detection" do
    context "with mixed language project" do
      before do
        # Create files for multiple languages
        File.write(File.join(project_path, "main.rb"), "puts 'Hello'")
        File.write(File.join(project_path, "script.py"), "print('Hello')")
        File.write(File.join(project_path, "index.js"), "console.log('Hello')")

        # Create many Ruby files
        FileUtils.mkdir_p(File.join(project_path, "lib"))
        5.times do |i|
          File.write(File.join(project_path, "lib/file#{i}.rb"), "class File#{i}; end")
        end
      end

      it "detects the primary language based on file count" do
        info = detector.detect_project_info
        expect(info[:language]).to eq(:ruby)
      end
    end
  end

  describe "Docker detection" do
    context "with Dockerfile" do
      before do
        File.write(File.join(project_path, "Dockerfile"), "FROM node:18")
      end

      it "detects Docker configuration" do
        info = detector.detect_project_info
        expect(info[:has_docker]).to be true
      end
    end

    context "with docker-compose" do
      before do
        File.write(File.join(project_path, "docker-compose.yml"), "version: '3'")
      end

      it "detects Docker configuration" do
        info = detector.detect_project_info
        expect(info[:has_docker]).to be true
      end
    end
  end

  describe "test detection" do
    context "with RSpec" do
      before do
        FileUtils.mkdir_p(File.join(project_path, "spec"))
        File.write(File.join(project_path, "spec/spec_helper.rb"), "require 'rspec'")
      end

      it "detects test configuration" do
        info = detector.detect_project_info
        expect(info[:has_tests]).to be true
      end
    end

    context "with Jest" do
      before do
        package_json = {
          "devDependencies" => { "jest" => "^29.0.0" }
        }
        File.write(File.join(project_path, "package.json"), JSON.pretty_generate(package_json))
        File.write(File.join(project_path, "jest.config.js"), "module.exports = {}")
      end

      it "detects test configuration" do
        info = detector.detect_project_info
        expect(info[:has_tests]).to be true
      end
    end

    context "with pytest" do
      before do
        File.write(File.join(project_path, "pytest.ini"), "[tool:pytest]")
      end

      it "detects test configuration" do
        info = detector.detect_project_info
        expect(info[:has_tests]).to be true
      end
    end
  end

  describe "private methods" do
    describe "#calculate_type_confidence" do
      it "calculates confidence based on file existence" do
        File.write(File.join(project_path, "package.json"), '{"name": "test"}')
        confidence = detector.send(:calculate_type_confidence, :nodejs, 
          { files: ["package.json"], patterns: {}, confidence: :medium })
        expect(confidence).to be > 0
      end

      it "applies confidence modifiers" do
        File.write(File.join(project_path, "package.json"), '{"name": "test"}')
        
        # Test high confidence modifier
        high_confidence = detector.send(:calculate_type_confidence, :nextjs,
          { files: ["package.json"], patterns: {}, confidence: :high })
        
        # Test medium confidence (no modifier)
        medium_confidence = detector.send(:calculate_type_confidence, :nodejs,
          { files: ["package.json"], patterns: {}, confidence: :medium })
        
        # Test low confidence modifier  
        low_confidence = detector.send(:calculate_type_confidence, :unknown,
          { files: ["package.json"], patterns: {}, confidence: :low })
        
        expect(high_confidence).to be > medium_confidence
        expect(medium_confidence).to be > low_confidence
      end
    end

    describe "#file_exists_in_project?" do
      it "detects existing files" do
        File.write(File.join(project_path, "test.txt"), "content")
        exists = detector.send(:file_exists_in_project?, "test.txt")
        expect(exists).to be true
      end

      it "handles glob patterns" do
        File.write(File.join(project_path, "test.gemspec"), "content")
        exists = detector.send(:file_exists_in_project?, "*.gemspec")
        expect(exists).to be true
      end

      it "returns false for non-existent files" do
        exists = detector.send(:file_exists_in_project?, "nonexistent.txt")
        expect(exists).to be false
      end
    end

    describe "pattern matching methods" do
      describe "#gemfile_contains?" do
        it "detects gems in Gemfile" do
          File.write(File.join(project_path, "Gemfile"), 
            'gem "rails", "~> 7.0"\ngem "rspec"')
          
          contains_rails = detector.send(:gemfile_contains?, "rails")
          contains_sinatra = detector.send(:gemfile_contains?, "sinatra")
          
          expect(contains_rails).to be true
          expect(contains_sinatra).to be false
        end

        it "returns false when Gemfile doesn't exist" do
          contains = detector.send(:gemfile_contains?, "rails")
          expect(contains).to be false
        end
      end

      describe "#package_json_has_dependency?" do
        it "detects dependencies in package.json" do
          File.write(File.join(project_path, "package.json"), 
            '{"dependencies": {"react": "^18.0.0"}, "devDependencies": {"jest": "^29.0.0"}}')
          
          has_react = detector.send(:package_json_has_dependency?, "react")
          has_jest = detector.send(:package_json_has_dependency?, "jest")
          has_angular = detector.send(:package_json_has_dependency?, "angular")
          
          expect(has_react).to be true
          expect(has_jest).to be true
          expect(has_angular).to be false
        end

        it "returns false when package.json doesn't exist" do
          has_dep = detector.send(:package_json_has_dependency?, "react")
          expect(has_dep).to be false
        end

        it "handles malformed JSON gracefully" do
          File.write(File.join(project_path, "package.json"), "invalid json")
          has_dep = detector.send(:package_json_has_dependency?, "react")
          expect(has_dep).to be false
        end
      end

      describe "#requirements_contains?" do
        it "detects requirements in requirements.txt" do
          File.write(File.join(project_path, "requirements.txt"), 
            "django==4.0\nflask>=2.0")
          
          contains_django = detector.send(:requirements_contains?, "django")
          contains_fastapi = detector.send(:requirements_contains?, "fastapi")
          
          expect(contains_django).to be true
          expect(contains_fastapi).to be false
        end

        it "returns false when requirements.txt doesn't exist" do
          contains = detector.send(:requirements_contains?, "django")
          expect(contains).to be false
        end
      end
    end

    describe "suggestion methods" do
      describe "#suggest_copy_files_rules" do
        it "suggests files based on project type" do
          project_info = { type: :rails, package_manager: :bundler, sensitive_files: [] }
          rules = detector.send(:suggest_copy_files_rules, project_info)
          
          expect(rules).to have_key("config")
          expect(rules["config"]).to have_key("files")
          expect(rules["config"]["files"]).to be_an(Array)
          expect(rules["config"]["files"]).not_to be_empty
        end

        it "handles unknown project types" do
          project_info = { type: :unknown, package_manager: nil, sensitive_files: [] }
          rules = detector.send(:suggest_copy_files_rules, project_info)
          
          expect(rules).to have_key("config")
          expect(rules["config"]).to have_key("files")
          expect(rules["config"]["files"]).to be_an(Array)
        end
      end

      describe "#suggest_setup_commands_rules" do
        it "suggests commands based on package manager" do
          project_info = { type: :rails, package_manager: :bundler }
          rules = detector.send(:suggest_setup_commands_rules, project_info)
          
          expect(rules).to have_key("config")
          expect(rules["config"]).to have_key("commands")
          expect(rules["config"]["commands"]).to be_an(Array)
          expect(rules["config"]["commands"].first["command"]).to include("bundle", "install")
        end

        it "handles npm package manager" do
          project_info = { type: :nodejs, package_manager: :npm }
          rules = detector.send(:suggest_setup_commands_rules, project_info)
          
          expect(rules).to have_key("config")
          expect(rules["config"]).to have_key("commands")
          expect(rules["config"]["commands"].first["command"]).to include("npm", "install")
        end
      end

      describe "#suggest_template_rules" do
        it "suggests templates based on project type" do
          project_info = { type: :rails, package_manager: :bundler }
          rules = detector.send(:suggest_template_rules, project_info)
          
          expect(rules).to be_a(Hash)
          expect(rules).to have_key("config")
          expect(rules["config"]).to have_key("templates")
        end
      end
    end
  end
end
