# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Sxn::Config::TemplatesConfig do
  let(:temp_dir) { Dir.mktmpdir("sxn_templates_test") }
  let(:sxn_path) { File.join(temp_dir, ".sxn") }
  let(:templates_config) { described_class.new(sxn_path) }

  before { FileUtils.mkdir_p(sxn_path) }
  after { FileUtils.rm_rf(temp_dir) }

  describe "#initialize" do
    it "sets sxn_path and templates_file_path" do
      expect(templates_config.sxn_path.to_s).to eq(sxn_path)
      expect(templates_config.templates_file_path.to_s).to eq(File.join(sxn_path, "templates.yml"))
    end
  end

  describe "#exists?" do
    it "returns false when templates.yml does not exist" do
      expect(templates_config.exists?).to be false
    end

    it "returns true when templates.yml exists" do
      File.write(File.join(sxn_path, "templates.yml"), "version: 1\ntemplates: {}")
      expect(templates_config.exists?).to be true
    end
  end

  describe "#load" do
    context "when templates.yml does not exist" do
      it "returns default configuration" do
        config = templates_config.load
        expect(config["version"]).to eq(1)
        expect(config["templates"]).to eq({})
      end
    end

    context "when templates.yml exists" do
      before do
        content = <<~YAML
          version: 1
          templates:
            kiosk:
              description: "Kiosk development"
              projects:
                - name: atlas-core
                - name: atlas-online
        YAML
        File.write(File.join(sxn_path, "templates.yml"), content)
      end

      it "loads the configuration" do
        config = templates_config.load
        expect(config["version"]).to eq(1)
        expect(config["templates"]["kiosk"]["description"]).to eq("Kiosk development")
        expect(config["templates"]["kiosk"]["projects"].size).to eq(2)
      end
    end

    context "when templates.yml has invalid YAML" do
      before do
        File.write(File.join(sxn_path, "templates.yml"), "invalid: yaml: {")
      end

      it "raises ConfigurationError" do
        expect { templates_config.load }.to raise_error(Sxn::ConfigurationError, /Invalid YAML/)
      end
    end

    context "when templates.yml is empty" do
      before do
        File.write(File.join(sxn_path, "templates.yml"), "")
      end

      it "returns normalized config with defaults" do
        config = templates_config.load
        expect(config["version"]).to eq(1)
        expect(config["templates"]).to eq({})
      end
    end
  end

  describe "#save" do
    it "creates the templates.yml file" do
      templates_config.save({ "templates" => {} })
      expect(templates_config.exists?).to be true
    end

    it "sets version to 1 if not provided" do
      templates_config.save({ "templates" => {} })
      config = templates_config.load
      expect(config["version"]).to eq(1)
    end

    it "writes templates correctly" do
      templates_config.save({
                              "templates" => {
                                "test" => { "description" => "Test template", "projects" => [] }
                              }
                            })

      config = templates_config.load
      expect(config["templates"]["test"]["description"]).to eq("Test template")
    end

    it "creates sxn directory if it does not exist" do
      FileUtils.rm_rf(sxn_path)
      expect(File.directory?(sxn_path)).to be false

      templates_config.save({ "templates" => {} })
      expect(File.directory?(sxn_path)).to be true
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
                branch: main
              - atlas-online
          simple:
            projects:
              - backend
      YAML
      File.write(File.join(sxn_path, "templates.yml"), content)
    end

    it "returns nil for non-existent template" do
      expect(templates_config.get_template("nonexistent")).to be_nil
    end

    it "returns the template with normalized structure" do
      template = templates_config.get_template("kiosk")

      expect(template["name"]).to eq("kiosk")
      expect(template["description"]).to eq("Kiosk development")
      expect(template["projects"]).to be_an(Array)
      expect(template["projects"].size).to eq(2)
    end

    it "normalizes string-only project entries to hashes" do
      template = templates_config.get_template("kiosk")
      project_names = template["projects"].map { |p| p["name"] }

      expect(project_names).to include("atlas-core", "atlas-online")
    end

    it "preserves project configuration options" do
      template = templates_config.get_template("kiosk")
      atlas_core = template["projects"].find { |p| p["name"] == "atlas-core" }

      expect(atlas_core["branch"]).to eq("main")
    end
  end

  describe "#list_template_names" do
    context "when no templates exist" do
      it "returns empty array" do
        expect(templates_config.list_template_names).to eq([])
      end
    end

    context "when templates exist" do
      before do
        content = <<~YAML
          version: 1
          templates:
            kiosk:
              projects: []
            backend:
              projects: []
        YAML
        File.write(File.join(sxn_path, "templates.yml"), content)
      end

      it "returns array of template names" do
        names = templates_config.list_template_names
        expect(names).to contain_exactly("kiosk", "backend")
      end
    end
  end

  describe "#set_template" do
    it "creates a new template" do
      templates_config.set_template("new-template", {
                                      "description" => "New template",
                                      "projects" => [{ "name" => "project1" }]
                                    })

      template = templates_config.get_template("new-template")
      expect(template["description"]).to eq("New template")
    end

    it "updates an existing template" do
      templates_config.set_template("test", { "description" => "Original" })
      templates_config.set_template("test", { "description" => "Updated" })

      template = templates_config.get_template("test")
      expect(template["description"]).to eq("Updated")
    end

    it "preserves other templates when adding new one" do
      templates_config.set_template("first", { "description" => "First" })
      templates_config.set_template("second", { "description" => "Second" })

      expect(templates_config.get_template("first")).not_to be_nil
      expect(templates_config.get_template("second")).not_to be_nil
    end
  end

  describe "#remove_template" do
    before do
      templates_config.set_template("to-remove", { "description" => "Will be removed" })
      templates_config.set_template("to-keep", { "description" => "Will be kept" })
    end

    it "returns true when template is removed" do
      result = templates_config.remove_template("to-remove")
      expect(result).to be true
    end

    it "returns false when template does not exist" do
      result = templates_config.remove_template("nonexistent")
      expect(result).to be false
    end

    it "actually removes the template" do
      templates_config.remove_template("to-remove")
      expect(templates_config.get_template("to-remove")).to be_nil
    end

    it "preserves other templates" do
      templates_config.remove_template("to-remove")
      expect(templates_config.get_template("to-keep")).not_to be_nil
    end
  end
end
