# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Sxn::Core::TemplateManager do
  let(:temp_dir) { Dir.mktmpdir("sxn_template_manager_test") }
  let(:sxn_path) { File.join(temp_dir, ".sxn") }

  let(:mock_config_manager) do
    instance_double(Sxn::Core::ConfigManager).tap do |mgr|
      allow(mgr).to receive(:sxn_folder_path).and_return(sxn_path)
      allow(mgr).to receive(:get_project).and_return(nil)
    end
  end

  let(:template_manager) { described_class.new(mock_config_manager) }

  before { FileUtils.mkdir_p(sxn_path) }
  after { FileUtils.rm_rf(temp_dir) }

  describe "#initialize" do
    it "sets config_manager and templates_config" do
      expect(template_manager.config_manager).to eq(mock_config_manager)
      expect(template_manager.templates_config).to be_a(Sxn::Config::TemplatesConfig)
    end
  end

  describe "#list_templates" do
    context "when no templates exist" do
      it "returns empty array" do
        expect(template_manager.list_templates).to eq([])
      end
    end

    context "when templates exist" do
      before do
        content = <<~YAML
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
        File.write(File.join(sxn_path, "templates.yml"), content)
      end

      it "returns array of template info hashes" do
        templates = template_manager.list_templates

        expect(templates.size).to eq(2)
        expect(templates).to include(
          { name: "kiosk", description: "Kiosk development", project_count: 2 },
          { name: "backend", description: "Backend only", project_count: 1 }
        )
      end
    end
  end

  describe "#get_template" do
    before do
      content = <<~YAML
        version: 1
        templates:
          kiosk:
            description: "Kiosk development"
            projects:
              - name: atlas-core
      YAML
      File.write(File.join(sxn_path, "templates.yml"), content)
    end

    it "returns the template when found" do
      template = template_manager.get_template("kiosk")

      expect(template["name"]).to eq("kiosk")
      expect(template["description"]).to eq("Kiosk development")
    end

    it "raises SessionTemplateNotFoundError when not found" do
      expect do
        template_manager.get_template("nonexistent")
      end.to raise_error(Sxn::SessionTemplateNotFoundError, /Session template 'nonexistent' not found/)
    end

    it "includes available templates in error message" do
      expect do
        template_manager.get_template("nonexistent")
      end.to raise_error(Sxn::SessionTemplateNotFoundError, /Available templates: kiosk/)
    end
  end

  describe "#list_template_names" do
    before do
      content = <<~YAML
        version: 1
        templates:
          first: { projects: [] }
          second: { projects: [] }
      YAML
      File.write(File.join(sxn_path, "templates.yml"), content)
    end

    it "returns array of template names" do
      names = template_manager.list_template_names
      expect(names).to contain_exactly("first", "second")
    end
  end

  describe "#validate_template" do
    before do
      content = <<~YAML
        version: 1
        templates:
          valid:
            projects:
              - name: existing-project
          empty:
            projects: []
          invalid:
            projects:
              - name: missing-project
      YAML
      File.write(File.join(sxn_path, "templates.yml"), content)

      # Mock project lookup
      allow(mock_config_manager).to receive(:get_project).with("existing-project").and_return({ name: "existing-project" })
      allow(mock_config_manager).to receive(:get_project).with("missing-project").and_return(nil)
    end

    it "returns true for valid template" do
      expect(template_manager.validate_template("valid")).to be true
    end

    it "raises error for empty projects" do
      expect do
        template_manager.validate_template("empty")
      end.to raise_error(Sxn::SessionTemplateValidationError, /Template has no projects defined/)
    end

    it "raises error for missing projects" do
      expect do
        template_manager.validate_template("invalid")
      end.to raise_error(Sxn::SessionTemplateValidationError, /Project 'missing-project' not found/)
    end

    it "raises error for non-existent template" do
      expect do
        template_manager.validate_template("nonexistent")
      end.to raise_error(Sxn::SessionTemplateNotFoundError)
    end
  end

  describe "#create_template" do
    before do
      allow(mock_config_manager).to receive(:get_project).with("project1").and_return({ name: "project1" })
      allow(mock_config_manager).to receive(:get_project).with("project2").and_return({ name: "project2" })
    end

    it "creates a new template" do
      template = template_manager.create_template(
        "new-template",
        description: "New template",
        projects: %w[project1 project2]
      )

      expect(template["name"]).to eq("new-template")
      expect(template["description"]).to eq("New template")
      expect(template["projects"].size).to eq(2)
    end

    it "raises error for invalid template name" do
      expect do
        template_manager.create_template("invalid name!")
      end.to raise_error(Sxn::SessionTemplateValidationError, /Template name must contain only/)
    end

    it "raises error if template already exists" do
      template_manager.create_template("existing", projects: ["project1"])

      expect do
        template_manager.create_template("existing", projects: ["project1"])
      end.to raise_error(Sxn::SessionTemplateValidationError, /Template already exists/)
    end

    it "raises error for non-existent projects" do
      allow(mock_config_manager).to receive(:get_project).with("missing").and_return(nil)

      expect do
        template_manager.create_template("test", projects: ["missing"])
      end.to raise_error(Sxn::SessionTemplateValidationError, /Project 'missing' not found/)
    end

    it "accepts valid template names" do
      %w[my-template my_template MyTemplate template123].each do |name|
        expect do
          template_manager.create_template(name, projects: ["project1"])
        end.not_to raise_error
      end
    end
  end

  describe "#update_template" do
    before do
      allow(mock_config_manager).to receive(:get_project).with("project1").and_return({ name: "project1" })
      allow(mock_config_manager).to receive(:get_project).with("project2").and_return({ name: "project2" })

      template_manager.create_template("test", description: "Original", projects: ["project1"])
    end

    it "updates description" do
      updated = template_manager.update_template("test", description: "Updated")
      expect(updated["description"]).to eq("Updated")
    end

    it "updates projects" do
      updated = template_manager.update_template("test", projects: %w[project1 project2])
      expect(updated["projects"].size).to eq(2)
    end

    it "validates new projects exist" do
      allow(mock_config_manager).to receive(:get_project).with("missing").and_return(nil)

      expect do
        template_manager.update_template("test", projects: ["missing"])
      end.to raise_error(Sxn::SessionTemplateValidationError, /Project 'missing' not found/)
    end

    it "raises error for non-existent template" do
      expect do
        template_manager.update_template("nonexistent", description: "Test")
      end.to raise_error(Sxn::SessionTemplateNotFoundError)
    end
  end

  describe "#remove_template" do
    before do
      allow(mock_config_manager).to receive(:get_project).with("project1").and_return({ name: "project1" })
      template_manager.create_template("to-remove", projects: ["project1"])
    end

    it "removes the template" do
      result = template_manager.remove_template("to-remove")
      expect(result).to be true
      expect(template_manager.template_exists?("to-remove")).to be false
    end

    it "raises error for non-existent template" do
      expect do
        template_manager.remove_template("nonexistent")
      end.to raise_error(Sxn::SessionTemplateNotFoundError)
    end
  end

  describe "#template_exists?" do
    before do
      allow(mock_config_manager).to receive(:get_project).with("project1").and_return({ name: "project1" })
      template_manager.create_template("existing", projects: ["project1"])
    end

    it "returns true when template exists" do
      expect(template_manager.template_exists?("existing")).to be true
    end

    it "returns false when template does not exist" do
      expect(template_manager.template_exists?("nonexistent")).to be false
    end
  end

  describe "#get_template_projects" do
    before do
      content = <<~YAML
        version: 1
        templates:
          mixed:
            projects:
              - name: project1
                branch: custom-branch
              - name: project2
              - name: project3
                rules:
                  - copy_file: .env.local
      YAML
      File.write(File.join(sxn_path, "templates.yml"), content)

      allow(mock_config_manager).to receive(:get_project).with("project1").and_return({ name: "project1", path: "/path/to/project1" })
      allow(mock_config_manager).to receive(:get_project).with("project2").and_return({ name: "project2", path: "/path/to/project2" })
      allow(mock_config_manager).to receive(:get_project).with("project3").and_return({ name: "project3", path: "/path/to/project3" })
    end

    it "returns project configurations with resolved branches" do
      projects = template_manager.get_template_projects("mixed", default_branch: "default-branch")

      expect(projects.size).to eq(3)

      # Project with custom branch
      p1 = projects.find { |p| p[:name] == "project1" }
      expect(p1[:branch]).to eq("custom-branch")
      expect(p1[:path]).to eq("/path/to/project1")

      # Project without custom branch uses default
      p2 = projects.find { |p| p[:name] == "project2" }
      expect(p2[:branch]).to eq("default-branch")

      # Project with rules
      p3 = projects.find { |p| p[:name] == "project3" }
      expect(p3[:rules]).not_to be_nil
    end

    it "raises error for non-existent template" do
      expect do
        template_manager.get_template_projects("nonexistent", default_branch: "main")
      end.to raise_error(Sxn::SessionTemplateNotFoundError)
    end
  end
end
