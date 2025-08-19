# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Rules System Integration" do
  let(:temp_base) { File.expand_path(Dir.mktmpdir("rules_integration_base")) }
  let(:project_path) { File.join(temp_base, "project") }
  let(:session_path) { File.join(temp_base, "session") }
  let(:rules_engine) { Sxn::Rules::RulesEngine.new(project_path, session_path) }

  before do
    # Create realistic project structure
    setup_rails_project
  end

  after do
    FileUtils.rm_rf(temp_base)
  end

  describe "complete rule application workflow" do
    before do
      # Mock SecureFileCopier to bypass path validation for all tests in this context
      mock_copier = instance_double("Sxn::Security::SecureFileCopier")
      allow(Sxn::Security::SecureFileCopier).to receive(:new).and_return(mock_copier)

      mock_copy_result = instance_double("Sxn::Security::SecureFileCopier::CopyResult")
      allow(mock_copy_result).to receive(:source_path).and_return("config/master.key")
      allow(mock_copy_result).to receive(:destination_path).and_return("config/master.key")
      allow(mock_copy_result).to receive(:operation).and_return("copy")
      allow(mock_copy_result).to receive(:encrypted).and_return(false)
      allow(mock_copy_result).to receive(:checksum).and_return("abc123")
      allow(mock_copy_result).to receive(:duration).and_return(0.1)
      allow(mock_copy_result).to receive(:to_h).and_return({
                                                             source_path: "config/master.key",
                                                             destination_path: "config/master.key",
                                                             operation: "copy",
                                                             encrypted: false,
                                                             checksum: "abc123",
                                                             duration: 0.1
                                                           })
      allow(mock_copier).to receive(:copy_file) do |source, destination, **options|
        # Create the actual files for tests that check file existence
        src_path = File.join(project_path, source)
        dst_path = File.join(session_path, destination)

        if File.exist?(src_path)
          FileUtils.mkdir_p(File.dirname(dst_path))
          FileUtils.cp(src_path, dst_path)
          File.chmod(options[:permissions] || 0o644, dst_path) if options[:permissions]
        end

        mock_copy_result
      end

      allow(mock_copier).to receive(:create_symlink) do |source, destination, **_options|
        # Create actual symlinks for tests that check symlink existence
        src_path = File.join(project_path, source)
        dst_path = File.join(session_path, destination)

        if File.exist?(src_path)
          FileUtils.mkdir_p(File.dirname(dst_path))
          File.symlink(src_path, dst_path)
        end

        mock_copy_result
      end

      allow(mock_copier).to receive(:sensitive_file?).and_return(false)
    end

    let(:comprehensive_rules_config) do
      {
        "copy_sensitive_files" => {
          "type" => "copy_files",
          "config" => {
            "files" => [
              {
                "source" => "config/master.key",
                "strategy" => "copy",
                "permissions" => "0600",
                "encrypt" => true
              },
              {
                "source" => ".env",
                "strategy" => "symlink"
              },
              {
                "source" => ".env.development",
                "strategy" => "symlink",
                "required" => false
              }
            ]
          }
        },
        "install_dependencies" => {
          "type" => "setup_commands",
          "config" => {
            "commands" => [
              {
                "command" => %w[bundle install],
                "description" => "Install Ruby dependencies",
                "timeout" => 120
              }
            ]
          },
          "dependencies" => ["copy_sensitive_files"]
        },
        "generate_documentation" => {
          "type" => "template",
          "config" => {
            "templates" => [
              {
                "source" => ".sxn/templates/session-info.md.liquid",
                "destination" => "SESSION_INFO.md"
              }
            ]
          },
          "dependencies" => ["install_dependencies"]
        }
      }
    end

    context "with successful execution" do
      before do
        # Mock successful command execution
        mock_executor = instance_double("Sxn::Security::SecureCommandExecutor")
        allow(Sxn::Security::SecureCommandExecutor).to receive(:new).and_return(mock_executor)
        allow(mock_executor).to receive(:command_allowed?).and_return(true)

        mock_result = instance_double("Sxn::Security::SecureCommandExecutor::CommandResult")
        allow(mock_result).to receive(:success?).and_return(true)
        allow(mock_result).to receive(:failure?).and_return(false)
        allow(mock_result).to receive(:exit_status).and_return(0)
        allow(mock_result).to receive(:stdout).and_return("Bundle complete!")
        allow(mock_result).to receive(:stderr).and_return("")
        allow(mock_result).to receive(:duration).and_return(5.2)
        allow(mock_executor).to receive(:execute).and_return(mock_result)

        # Mock template processing
        mock_processor = instance_double("Sxn::Templates::TemplateProcessor")
        allow(Sxn::Templates::TemplateProcessor).to receive(:new).and_return(mock_processor)
        allow(mock_processor).to receive(:validate_syntax).and_return(true)
        allow(mock_processor).to receive(:process) do |_template_content, _variables|
          # Return processed template content
          "# Session Information\n\nCreated: 2025-01-16\nProject: Rails Application"
        end
        allow(mock_processor).to receive(:extract_variables).and_return(["session.name"])

        mock_variables = instance_double("Sxn::Templates::TemplateVariables")
        allow(Sxn::Templates::TemplateVariables).to receive(:new).and_return(mock_variables)
        allow(mock_variables).to receive(:collect).and_return({
                                                                session: {
                                                                  name: "test-session",
                                                                  path: session_path,
                                                                  created_at: "2025-01-16 10:00:00 UTC",
                                                                  updated_at: "2025-01-16 10:00:00 UTC",
                                                                  status: "active"
                                                                },
                                                                project: {
                                                                  name: "test-project",
                                                                  type: "rails",
                                                                  path: project_path
                                                                },
                                                                git: {
                                                                  branch: "main",
                                                                  author_name: "Test User",
                                                                  author_email: "test@example.com"
                                                                },
                                                                environment: {
                                                                  ruby: { version: "3.3.0" },
                                                                  os: { name: "darwin", arch: "x86_64" }
                                                                },
                                                                user: {
                                                                  username: "testuser",
                                                                  git_name: "Test User"
                                                                },
                                                                timestamp: {
                                                                  now: "2025-01-16 10:00:00 UTC"
                                                                }
                                                              })
        allow(mock_variables).to receive(:build_variables).and_return({
                                                                        session: {
                                                                          name: "test-session",
                                                                          path: session_path,
                                                                          created_at: "2025-01-16 10:00:00 UTC",
                                                                          updated_at: "2025-01-16 10:00:00 UTC",
                                                                          status: "active"
                                                                        },
                                                                        project: {
                                                                          name: "test-project",
                                                                          type: "rails",
                                                                          path: project_path
                                                                        },
                                                                        git: {
                                                                          branch: "main",
                                                                          author_name: "Test User",
                                                                          author_email: "test@example.com"
                                                                        },
                                                                        environment: {
                                                                          ruby: { version: "3.3.0" },
                                                                          os: { name: "darwin", arch: "x86_64" }
                                                                        },
                                                                        user: {
                                                                          username: "testuser",
                                                                          git_name: "Test User"
                                                                        },
                                                                        timestamp: {
                                                                          now: "2025-01-16 10:00:00 UTC"
                                                                        }
                                                                      })
      end

      it "applies all rules in correct dependency order" do
        result = rules_engine.apply_rules(comprehensive_rules_config)

        expect(result.success?).to be true
        expect(result.applied_rules.size).to eq(3)
        expect(result.failed_rules).to be_empty

        # Verify rule execution order
        applied_rule_names = result.applied_rules.map(&:name)
        copy_index = applied_rule_names.index("copy_sensitive_files")
        setup_index = applied_rule_names.index("install_dependencies")
        template_index = applied_rule_names.index("generate_documentation")

        expect(copy_index).to be < setup_index
        expect(setup_index).to be < template_index
      end

      it "creates expected files and structures" do
        rules_engine.apply_rules(comprehensive_rules_config)

        # Check copied files
        expect(File.exist?(File.join(session_path, "config/master.key"))).to be true
        expect(File.symlink?(File.join(session_path, ".env"))).to be true

        # Check generated documentation
        expect(File.exist?(File.join(session_path, "SESSION_INFO.md"))).to be true

        session_info_content = File.read(File.join(session_path, "SESSION_INFO.md"))
        expect(session_info_content).to include("Session Information")
      end

      it "sets appropriate file permissions" do
        rules_engine.apply_rules(comprehensive_rules_config)

        master_key_path = File.join(session_path, "config/master.key")
        stat = File.stat(master_key_path)
        expect(stat.mode & 0o777).to eq(0o600)
      end

      it "provides comprehensive execution summary" do
        result = rules_engine.apply_rules(comprehensive_rules_config)

        result_hash = result.to_h
        expect(result_hash[:success]).to be true
        expect(result_hash[:total_rules]).to eq(3)
        expect(result_hash[:applied_rules]).to contain_exactly(
          "copy_sensitive_files", "install_dependencies", "generate_documentation"
        )
        expect(result_hash[:total_duration]).to be > 0
      end
    end

    context "with rule failure and rollback" do
      before do
        # Mock command executor failure
        mock_executor = instance_double("Sxn::Security::SecureCommandExecutor")
        allow(Sxn::Security::SecureCommandExecutor).to receive(:new).and_return(mock_executor)
        allow(mock_executor).to receive(:command_allowed?).and_return(true)

        mock_result = instance_double("Sxn::Security::SecureCommandExecutor::CommandResult")
        allow(mock_result).to receive(:success?).and_return(false)
        allow(mock_result).to receive(:failure?).and_return(true)
        allow(mock_result).to receive(:exit_status).and_return(1)
        allow(mock_result).to receive(:stdout).and_return("")
        allow(mock_result).to receive(:stderr).and_return("Bundle install failed")
        allow(mock_result).to receive(:duration).and_return(2.1)
        allow(mock_executor).to receive(:execute).and_return(mock_result)
      end

      it "handles failures gracefully and attempts rollback" do
        result = rules_engine.apply_rules(comprehensive_rules_config)

        expect(result.success?).to be false
        expect(result.failed_rules).not_to be_empty
        expect(result.errors).not_to be_empty

        # First rule should succeed, second should fail
        expect(result.applied_rules.size).to eq(1) # Only copy_sensitive_files
        expect(result.failed_rules.size).to eq(1) # install_dependencies fails
      end

      it "can rollback applied rules" do
        # First apply copy_sensitive_files (which should succeed)
        simple_copy_config = {
          "copy_sensitive_files" => comprehensive_rules_config["copy_sensitive_files"]
        }

        result = rules_engine.apply_rules(simple_copy_config)
        expect(result.success?).to be true

        # Verify files were created
        expect(File.exist?(File.join(session_path, "config/master.key"))).to be true
        expect(File.symlink?(File.join(session_path, ".env"))).to be true

        # Rollback
        expect(rules_engine.rollback_rules).to be true

        # Verify files were removed
        expect(File.exist?(File.join(session_path, "config/master.key"))).to be false
        expect(File.exist?(File.join(session_path, ".env"))).to be false
      end
    end

    context "with parallel execution" do
      let(:parallel_rules_config) do
        {
          "copy_files_1" => {
            "type" => "copy_files",
            "config" => {
              "files" => [
                { "source" => "config/master.key", "strategy" => "copy", "required" => false }
              ]
            }
          },
          "copy_files_2" => {
            "type" => "copy_files",
            "config" => {
              "files" => [
                { "source" => ".env", "strategy" => "copy", "required" => false }
              ]
            }
          },
          "copy_files_3" => {
            "type" => "copy_files",
            "config" => {
              "files" => [
                { "source" => "Gemfile", "strategy" => "copy", "required" => false }
              ]
            }
          }
        }
      end

      it "executes independent rules in parallel" do
        result = rules_engine.apply_rules(parallel_rules_config, parallel: true, max_parallelism: 2)

        expect(result.success?).to be true
        expect(result.applied_rules.size).to eq(3)

        # All files should be copied
        expect(File.exist?(File.join(session_path, "config/master.key"))).to be true
        expect(File.exist?(File.join(session_path, ".env"))).to be true
        expect(File.exist?(File.join(session_path, "Gemfile"))).to be true
      end
    end

    context "with continue_on_failure option" do
      before do
        # Override the parent context's successful command executor with one that fails first
        mock_executor = instance_double("Sxn::Security::SecureCommandExecutor")

        # Clear any existing mocks and set new ones
        allow(Sxn::Security::SecureCommandExecutor).to receive(:new).and_return(mock_executor)
        allow(mock_executor).to receive(:command_allowed?).and_return(true)

        allow(mock_executor).to receive(:execute) do |command, description:, **|
          mock_result = instance_double("Sxn::Security::SecureCommandExecutor::CommandResult")

          # Make bundle install fail, others succeed
          if command.include?("bundle") && command.include?("install")
            # Bundle install command fails
            allow(mock_result).to receive(:success?).and_return(false)
            allow(mock_result).to receive(:failure?).and_return(true)
            allow(mock_result).to receive(:exit_status).and_return(1)
            allow(mock_result).to receive(:stderr).and_return("Bundle install failed")
            allow(mock_result).to receive(:stdout).and_return("")
          else
            # Other commands succeed
            allow(mock_result).to receive(:success?).and_return(true)
            allow(mock_result).to receive(:failure?).and_return(false)
            allow(mock_result).to receive(:exit_status).and_return(0)
            allow(mock_result).to receive(:stderr).and_return("")
            allow(mock_result).to receive(:stdout).and_return("Output")
          end

          allow(mock_result).to receive(:duration).and_return(1.0)
          mock_result
        end

        # Mock template processing
        mock_processor = instance_double("Sxn::Templates::TemplateProcessor")
        allow(Sxn::Templates::TemplateProcessor).to receive(:new).and_return(mock_processor)
        allow(mock_processor).to receive(:validate_syntax).and_return(true)
        allow(mock_processor).to receive(:process) do |_template_content, _variables|
          "Documentation"
        end
        allow(mock_processor).to receive(:extract_variables).and_return([])

        mock_variables = instance_double("Sxn::Templates::TemplateVariables")
        allow(Sxn::Templates::TemplateVariables).to receive(:new).and_return(mock_variables)
        allow(mock_variables).to receive(:collect).and_return({})
        allow(mock_variables).to receive(:build_variables).and_return({})
      end

      it "continues execution despite individual rule failures" do
        config_with_continue = comprehensive_rules_config.merge(
          "install_dependencies" => comprehensive_rules_config["install_dependencies"].merge(
            "config" => comprehensive_rules_config["install_dependencies"]["config"].merge(
              "continue_on_failure" => true
            )
          )
        )

        result = rules_engine.apply_rules(config_with_continue, continue_on_failure: true)

        # Should succeed overall with continue_on_failure enabled
        expect(result.success?).to be true
        expect(result.applied_rules.size).to eq(3) # All rules should be applied
        expect(result.failed_rules.size).to eq(0) # No rules marked as failed due to continue_on_failure
      end
    end
  end

  describe "project detection integration" do
    let(:detector) { Sxn::Rules::ProjectDetector.new(project_path) }

    it "detects Rails project and suggests appropriate rules" do
      project_info = detector.detect_project_info
      expect(project_info[:type]).to eq(:rails)
      expect(project_info[:package_manager]).to eq(:bundler)
      expect(project_info[:framework]).to eq(:rails)

      suggested_rules = detector.suggest_default_rules
      expect(suggested_rules).to have_key("copy_files")
      expect(suggested_rules).to have_key("setup_commands")
      expect(suggested_rules).to have_key("templates")

      # Verify Rails-specific suggestions
      copy_files = suggested_rules["copy_files"]["config"]["files"]
      sources = copy_files.map { |f| f["source"] }
      expect(sources).to include("config/master.key", ".env")

      setup_commands = suggested_rules["setup_commands"]["config"]["commands"]
      commands = setup_commands.map { |c| c["command"] }
      expect(commands).to include(%w[bundle install])
    end

    it "validates suggested rules configuration" do
      # Mock SecureCommandExecutor to accept bin/rails commands during validation
      mock_executor = instance_double("Sxn::Security::SecureCommandExecutor")
      allow(Sxn::Security::SecureCommandExecutor).to receive(:new).and_return(mock_executor)
      allow(mock_executor).to receive(:command_allowed?).and_return(true)

      suggested_rules = detector.suggest_default_rules

      # Should be able to validate the suggested configuration
      expect do
        rules_engine.validate_rules_config(suggested_rules)
      end.not_to raise_error
    end
  end

  describe "error recovery and validation" do
    context "with invalid rule configuration" do
      let(:invalid_config) do
        {
          "invalid_rule" => {
            "type" => "copy_files",
            "config" => {
              "files" => [
                { "source" => "nonexistent.file", "strategy" => "copy" } # Missing required file
              ]
            }
          }
        }
      end

      it "provides clear validation errors" do
        expect do
          rules_engine.validate_rules_config(invalid_config)
        end.to raise_error(Sxn::Rules::ValidationError, /Required source file does not exist/)
      end
    end

    context "with circular dependencies" do
      let(:circular_config) do
        {
          "rule_a" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => "Gemfile", "strategy" => "copy", "required" => false }] },
            "dependencies" => ["rule_b"]
          },
          "rule_b" => {
            "type" => "copy_files",
            "config" => { "files" => [{ "source" => ".env", "strategy" => "copy", "required" => false }] },
            "dependencies" => ["rule_a"]
          }
        }
      end

      it "detects and reports circular dependencies" do
        expect do
          rules_engine.validate_rules_config(circular_config)
        end.to raise_error(Sxn::Rules::ValidationError, /Circular dependency detected/)
      end
    end
  end

  describe "security integration" do
    before do
      # Mock SecureFileCopier to bypass path validation
      mock_copier = instance_double("Sxn::Security::SecureFileCopier")
      allow(Sxn::Security::SecureFileCopier).to receive(:new).and_return(mock_copier)

      mock_copy_result = instance_double("Sxn::Security::SecureFileCopier::CopyResult")
      allow(mock_copy_result).to receive(:source_path).and_return("config/master.key")
      allow(mock_copy_result).to receive(:destination_path).and_return("config/master.key")
      allow(mock_copy_result).to receive(:operation).and_return("copy")
      allow(mock_copy_result).to receive(:encrypted).and_return(false)
      allow(mock_copy_result).to receive(:checksum).and_return("abc123")
      allow(mock_copy_result).to receive(:duration).and_return(0.1)
      allow(mock_copy_result).to receive(:to_h).and_return({
                                                             source_path: "config/master.key",
                                                             destination_path: "config/master.key",
                                                             operation: "copy",
                                                             encrypted: false,
                                                             checksum: "abc123",
                                                             duration: 0.1
                                                           })
      allow(mock_copier).to receive(:copy_file) do |source, destination, **options|
        # Create the actual files for tests that check file existence
        src_path = File.join(project_path, source)
        dst_path = File.join(session_path, destination)

        if File.exist?(src_path)
          FileUtils.mkdir_p(File.dirname(dst_path))
          FileUtils.cp(src_path, dst_path)
          File.chmod(options[:permissions] || 0o644, dst_path) if options[:permissions]
        end

        mock_copy_result
      end
    end

    it "properly handles sensitive files with encryption" do
      sensitive_config = {
        "copy_secrets" => {
          "type" => "copy_files",
          "config" => {
            "files" => [
              {
                "source" => "config/master.key",
                "strategy" => "copy",
                "encrypt" => true,
                "permissions" => "0600"
              }
            ]
          }
        }
      }

      result = rules_engine.apply_rules(sensitive_config)
      expect(result.success?).to be true

      # Verify file was created with correct permissions
      copied_file = File.join(session_path, "config/master.key")
      expect(File.exist?(copied_file)).to be true

      stat = File.stat(copied_file)
      expect(stat.mode & 0o777).to eq(0o600)
    end

    it "validates command whitelisting" do
      dangerous_config = {
        "dangerous_command" => {
          "type" => "setup_commands",
          "config" => {
            "commands" => [
              { "command" => ["rm", "-rf", "/"] } # Should be rejected
            ]
          }
        }
      }

      expect do
        rules_engine.validate_rules_config(dangerous_config)
      end.to raise_error(Sxn::Rules::ValidationError, /Command config 0: command not whitelisted/)
    end
  end

  describe "performance characteristics" do
    before do
      # Mock SecureFileCopier to bypass path validation
      mock_copier = instance_double("Sxn::Security::SecureFileCopier")
      allow(Sxn::Security::SecureFileCopier).to receive(:new).and_return(mock_copier)

      mock_copy_result = instance_double("Sxn::Security::SecureFileCopier::CopyResult")
      allow(mock_copy_result).to receive(:source_path).and_return("Gemfile")
      allow(mock_copy_result).to receive(:destination_path).and_return("Gemfile")
      allow(mock_copy_result).to receive(:operation).and_return("copy")
      allow(mock_copy_result).to receive(:encrypted).and_return(false)
      allow(mock_copy_result).to receive(:checksum).and_return("abc123")
      allow(mock_copy_result).to receive(:duration).and_return(0.1)
      allow(mock_copy_result).to receive(:to_h).and_return({
                                                             source_path: "Gemfile",
                                                             destination_path: "Gemfile",
                                                             operation: "copy",
                                                             encrypted: false,
                                                             checksum: "abc123",
                                                             duration: 0.1
                                                           })
      allow(mock_copier).to receive(:copy_file) do |source, destination, **options|
        # Create the actual files for tests that check file existence
        src_path = File.join(project_path, source)
        dst_path = File.join(session_path, destination)

        if File.exist?(src_path)
          FileUtils.mkdir_p(File.dirname(dst_path))
          FileUtils.cp(src_path, dst_path)
          File.chmod(options[:permissions] || 0o644, dst_path) if options[:permissions]
        end

        mock_copy_result
      end

      allow(mock_copier).to receive(:sensitive_file?).and_return(false)
    end

    let(:large_rules_config) do
      rules = {}

      # Create 20 independent copy file rules
      20.times do |i|
        rules["copy_rule_#{i}"] = {
          "type" => "copy_files",
          "config" => {
            "files" => [
              { "source" => "Gemfile", "destination" => "copy_#{i}/Gemfile", "strategy" => "copy", "required" => false }
            ]
          }
        }
      end

      rules
    end

    it "handles many rules efficiently", :performance do
      start_time = Time.now
      result = rules_engine.apply_rules(large_rules_config, parallel: true, max_parallelism: 4)
      duration = Time.now - start_time

      expect(result.success?).to be true
      expect(result.applied_rules.size).to eq(20)
      expect(duration).to be < 10.0 # Should complete within 10 seconds
    end
  end

  private

  def setup_rails_project
    # Create base directories
    FileUtils.mkdir_p(project_path)
    FileUtils.mkdir_p(session_path)

    # Create Rails project structure
    FileUtils.mkdir_p(File.join(project_path, "config"))
    FileUtils.mkdir_p(File.join(project_path, "app/models"))
    FileUtils.mkdir_p(File.join(project_path, "app/controllers"))
    FileUtils.mkdir_p(File.join(project_path, "spec"))
    FileUtils.mkdir_p(File.join(project_path, ".sxn/templates"))
    FileUtils.mkdir_p(File.join(project_path, "bin"))

    # Create Gemfile with Rails
    gemfile_content = <<~GEMFILE
      source 'https://rubygems.org'
      git_source(:github) { |repo| "https://github.com/\#{repo}.git" }

      ruby '3.2.0'

      gem 'rails', '~> 7.0.4'
      gem 'sqlite3', '~> 1.4'
      gem 'puma', '~> 5.0'

      group :development, :test do
        gem 'rspec-rails'
        gem 'factory_bot_rails'
      end
    GEMFILE
    File.write(File.join(project_path, "Gemfile"), gemfile_content)

    # Create Rails application.rb
    application_rb = <<~RUBY
      require_relative "boot"

      require "rails/all"

      Bundler.require(*Rails.groups)

      module TestApp
        class Application < Rails::Application
          config.load_defaults 7.0
        end
      end
    RUBY
    File.write(File.join(project_path, "config/application.rb"), application_rb)

    # Create sensitive files
    File.write(File.join(project_path, "config/master.key"), "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6")
    File.write(File.join(project_path, ".env"), "DATABASE_URL=postgresql://localhost:5432/test\nRAILS_ENV=development")
    File.write(File.join(project_path, ".env.development"), "DEBUG=true\nVERBOSE=true")

    # Create template
    template_content = <<~LIQUID
      # Session Information

      - **Name**: {{session.name}}
      - **Created**: {{session.created_at}}
      - **Project**: {{project.name}}
      - **Type**: {{project.type}}

      ## Setup Commands

      ```bash
      cd {{session.path}}
      bundle install
      rails db:create db:migrate
      rails server
      ```
    LIQUID
    File.write(File.join(project_path, ".sxn/templates/session-info.md.liquid"), template_content)

    # Create test files
    File.write(File.join(project_path, "spec/spec_helper.rb"), "require 'rspec'\nrequire 'rails_helper'")
    File.write(File.join(project_path, "spec/rails_helper.rb"), "require 'spec_helper'\nrequire 'rspec/rails'")

    # Create basic model and controller
    File.write(File.join(project_path, "app/models/user.rb"), "class User < ApplicationRecord\nend")
    File.write(File.join(project_path, "app/controllers/application_controller.rb"), "class ApplicationController < ActionController::Base\nend")

    # Create bin/rails executable
    rails_content = <<~RAILS
      #!/usr/bin/env ruby
      require_relative "../config/application"
      require "rails/commands"
    RAILS
    bin_rails_path = File.join(project_path, "bin/rails")
    File.write(bin_rails_path, rails_content)
    FileUtils.chmod(0o755, bin_rails_path)
  end
end
