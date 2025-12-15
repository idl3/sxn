# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Sxn::Commands::Templates do
  let(:temp_dir) { Dir.mktmpdir("sxn_templates_cmd_test") }
  let(:sxn_path) { File.join(temp_dir, ".sxn") }
  let(:config_file) { File.join(sxn_path, "config.yml") }
  let(:templates_file) { File.join(sxn_path, "templates.yml") }

  before do
    FileUtils.mkdir_p(sxn_path)
    # Create minimal config.yml for initialization check
    File.write(config_file, <<~YAML)
      sessions_folder: sessions
    YAML
  end

  after { FileUtils.rm_rf(temp_dir) }

  describe "list" do
    context "when not initialized" do
      before { FileUtils.rm_rf(sxn_path) }

      it "shows error message" do
        Dir.chdir(temp_dir) do
          expect do
            described_class.new.list
          end.to raise_error(SystemExit).and output(/not initialized/i).to_stdout
        end
      end
    end

    context "when no templates exist" do
      it "shows empty state message" do
        expect do
          Dir.chdir(temp_dir) { described_class.new.list }
        end.to output(/No templates defined/i).to_stdout
      end
    end

    context "when templates exist" do
      before do
        File.write(templates_file, <<~YAML)
          version: 1
          templates:
            kiosk:
              description: "Kiosk development"
              projects:
                - name: atlas-core
                - name: atlas-online
            backend:
              description: "Backend only"
              projects:
                - name: api
        YAML
      end

      it "lists all templates without error" do
        Dir.chdir(temp_dir) do
          # Just verify it runs without raising an error
          expect { described_class.new.list }.not_to raise_error
        end
      end
    end
  end

  describe "show" do
    before do
      File.write(templates_file, <<~YAML)
        version: 1
        templates:
          kiosk:
            description: "Kiosk development"
            projects:
              - name: atlas-core
                branch: main
              - name: atlas-online
      YAML
    end

    it "shows template details" do
      expect do
        Dir.chdir(temp_dir) { described_class.new.show("kiosk") }
      end.to output(/Template: kiosk/i).to_stdout
    end

    it "shows project list" do
      expect do
        Dir.chdir(temp_dir) { described_class.new.show("kiosk") }
      end.to output(/atlas-core/i).to_stdout
    end

    it "shows error for non-existent template" do
      Dir.chdir(temp_dir) do
        expect do
          described_class.new.show("nonexistent")
        end.to raise_error(SystemExit).and output(/not found/i).to_stdout
      end
    end

    context "when template has no projects" do
      before do
        File.write(templates_file, <<~YAML)
          version: 1
          templates:
            empty:
              description: "Empty template"
              projects: []
        YAML
      end

      it "shows empty state message for projects" do
        expect do
          Dir.chdir(temp_dir) { described_class.new.show("empty") }
        end.to output(/No projects in this template/i).to_stdout
      end
    end

    context "when project with branch and rules" do
      before do
        File.write(templates_file, <<~YAML)
          version: 1
          templates:
            advanced:
              description: "Advanced template"
              projects:
                - name: my-project
                  branch: feature-branch
                  rules:
                    - some-rule
        YAML
      end

      it "shows branch and rules info" do
        expect do
          Dir.chdir(temp_dir) { described_class.new.show("advanced") }
        end.to output(/branch: feature-branch.*has custom rules/m).to_stdout
      end
    end

    context "when project doesn't exist in config" do
      before do
        # Create template with project that doesn't exist
        File.write(templates_file, <<~YAML)
          version: 1
          templates:
            missing-proj:
              description: "Missing project"
              projects:
                - name: nonexistent-project
        YAML
      end

      it "shows project not found status" do
        expect do
          Dir.chdir(temp_dir) { described_class.new.show("missing-proj") }
        end.to output(/nonexistent-project.*✗.*not found/m).to_stdout
      end
    end

    context "when project exists in config" do
      before do
        # Add project to config
        File.write(config_file, <<~YAML)
          sessions_folder: sessions
          projects:
            existing-project:
              path: /path/to/project
              type: ruby
        YAML

        # Create template with that project
        File.write(templates_file, <<~YAML)
          version: 1
          templates:
            with-existing:
              description: "Template with existing project"
              projects:
                - name: existing-project
        YAML
      end

      it "shows project found status with checkmark" do
        expect do
          Dir.chdir(temp_dir) { described_class.new.show("with-existing") }
        end.to output(/existing-project.*✓/m).to_stdout
      end
    end
  end

  describe "remove" do
    before do
      File.write(templates_file, <<~YAML)
        version: 1
        templates:
          to-remove:
            description: "Will be removed"
            projects: []
      YAML
    end

    it "removes template with force flag" do
      expect do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { force: true }
          cmd.remove("to-remove")
        end
      end.to output(/removed/i).to_stdout

      # Verify template is gone
      config = Sxn::Config::TemplatesConfig.new(sxn_path)
      expect(config.get_template("to-remove")).to be_nil
    end

    it "shows error for non-existent template" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new
        cmd.options = { force: true }

        expect do
          cmd.remove("nonexistent")
        end.to raise_error(SystemExit).and output(/not found/i).to_stdout
      end
    end

    context "without name argument" do
      before do
        File.write(templates_file, <<~YAML)
          version: 1
          templates:
            template1:
              description: "First template"
              projects: []
            template2:
              description: "Second template"
              projects: []
        YAML
      end

      it "prompts for selection and removes template" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { force: true }

          # Mock the prompt to select a template
          prompt = instance_double(Sxn::UI::Prompt)
          allow(Sxn::UI::Prompt).to receive(:new).and_return(prompt)
          allow(prompt).to receive(:select).and_return("template1")
          cmd.instance_variable_set(:@prompt, prompt)

          expect do
            cmd.remove(nil)
          end.to output(/removed/i).to_stdout
        end
      end

      it "shows empty state when no templates exist" do
        # Remove all templates
        File.write(templates_file, <<~YAML)
          version: 1
          templates: {}
        YAML

        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { force: true }

          expect do
            cmd.remove(nil)
          end.to output(/No templates to remove/i).to_stdout
        end
      end
    end

    context "without force flag" do
      it "prompts for confirmation and removes when confirmed" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { force: false }

          # Mock the prompt to confirm deletion
          prompt = instance_double(Sxn::UI::Prompt)
          allow(Sxn::UI::Prompt).to receive(:new).and_return(prompt)
          allow(prompt).to receive(:confirm_deletion).with("to-remove", "template").and_return(true)
          cmd.instance_variable_set(:@prompt, prompt)

          expect do
            cmd.remove("to-remove")
          end.to output(/removed/i).to_stdout
        end
      end

      it "does not remove when confirmation is declined" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { force: false }

          # Mock the prompt to decline deletion
          prompt = instance_double(Sxn::UI::Prompt)
          allow(Sxn::UI::Prompt).to receive(:new).and_return(prompt)
          allow(prompt).to receive(:confirm_deletion).with("to-remove", "template").and_return(false)
          cmd.instance_variable_set(:@prompt, prompt)

          expect do
            cmd.remove("to-remove")
          end.not_to output(/removed/i).to_stdout

          # Verify template still exists
          config = Sxn::Config::TemplatesConfig.new(sxn_path)
          expect(config.get_template("to-remove")).not_to be_nil
        end
      end
    end
  end

  describe "create" do
    before do
      # Create config with projects - ConfigManager reads from config.yml
      File.write(config_file, <<~YAML)
        sessions_folder: sessions
        projects:
          project1:
            path: /path/to/project1
            type: ruby
          project2:
            path: /path/to/project2
            type: ruby
      YAML
    end

    context "with name and description options" do
      it "creates template with provided options" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { name: "my-template", description: "Test template" }

          # Mock the prompt to select projects
          prompt = instance_double(Sxn::UI::Prompt)
          allow(Sxn::UI::Prompt).to receive(:new).and_return(prompt)
          allow(prompt).to receive(:multi_select).and_return(%w[project1 project2])
          cmd.instance_variable_set(:@prompt, prompt)

          expect do
            cmd.create
          end.to output(/created.*2 project/i).to_stdout

          # Verify template was created
          config = Sxn::Config::TemplatesConfig.new(sxn_path)
          template = config.get_template("my-template")
          expect(template).not_to be_nil
          expect(template["description"]).to eq("Test template")
        end
      end
    end

    context "without name option" do
      it "prompts for name and creates template" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { description: "Test template" }

          # Mock the prompt to provide name and select projects
          prompt = instance_double(Sxn::UI::Prompt)
          allow(Sxn::UI::Prompt).to receive(:new).and_return(prompt)
          allow(prompt).to receive(:ask).with("Template name:").and_return("prompted-template")
          allow(prompt).to receive(:multi_select).and_return(%w[project1])
          cmd.instance_variable_set(:@prompt, prompt)

          expect do
            cmd.create
          end.to output(/created/i).to_stdout
        end
      end

      it "exits with error when prompted name is nil" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = {}

          prompt = instance_double(Sxn::UI::Prompt)
          allow(Sxn::UI::Prompt).to receive(:new).and_return(prompt)
          allow(prompt).to receive(:ask).with("Template name:").and_return(nil)
          cmd.instance_variable_set(:@prompt, prompt)

          expect do
            cmd.create
          end.to raise_error(SystemExit).and output(/Template name is required/i).to_stdout
        end
      end

      it "exits with error when prompted name is empty" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = {}

          prompt = instance_double(Sxn::UI::Prompt)
          allow(Sxn::UI::Prompt).to receive(:new).and_return(prompt)
          allow(prompt).to receive(:ask).with("Template name:").and_return("  ")
          cmd.instance_variable_set(:@prompt, prompt)

          expect do
            cmd.create
          end.to raise_error(SystemExit).and output(/Template name is required/i).to_stdout
        end
      end
    end

    context "when no projects are selected" do
      it "shows error message" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { name: "test-template", description: "Test" }

          # Mock the prompt to select no projects
          prompt = instance_double(Sxn::UI::Prompt)
          allow(Sxn::UI::Prompt).to receive(:new).and_return(prompt)
          allow(prompt).to receive(:multi_select).and_return([])
          cmd.instance_variable_set(:@prompt, prompt)

          expect do
            cmd.create
          end.to raise_error(SystemExit).and output(/At least one project must be selected/i).to_stdout
        end
      end
    end

    context "when template already exists" do
      before do
        File.write(templates_file, <<~YAML)
          version: 1
          templates:
            existing:
              description: "Existing template"
              projects: []
        YAML
      end

      it "shows error and recovery suggestion" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { name: "existing" }

          expect do
            cmd.create
          end.to raise_error(SystemExit).and output(/already exists/i).to_stdout
        end
      end
    end

    context "when no projects are configured" do
      before do
        # Overwrite config with no projects
        File.write(config_file, <<~YAML)
          sessions_folder: sessions
          projects: {}
        YAML
      end

      it "shows error message" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { name: "test-template" }

          expect do
            cmd.create
          end.to raise_error(SystemExit).and output(/No projects configured/i).to_stdout
        end
      end
    end

    context "when not initialized" do
      before { FileUtils.rm_rf(sxn_path) }

      it "shows error message" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { name: "test" }

          expect do
            cmd.create
          end.to raise_error(SystemExit).and output(/not initialized/i).to_stdout
        end
      end
    end
  end
end
