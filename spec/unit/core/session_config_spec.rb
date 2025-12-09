# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Sxn::Core::SessionConfig do
  let(:temp_dir) { Dir.mktmpdir("sxn_session_test") }
  let(:session_config) { described_class.new(temp_dir) }

  after { FileUtils.rm_rf(temp_dir) }

  describe "#initialize" do
    it "sets session_path and config_path" do
      expect(session_config.session_path).to eq(temp_dir)
      expect(session_config.config_path).to eq(File.join(temp_dir, ".sxnrc"))
    end
  end

  describe "#create" do
    it "creates .sxnrc file with correct content" do
      result = session_config.create(
        parent_sxn_path: "/path/to/.sxn",
        default_branch: "feature-branch",
        session_name: "my-session"
      )

      expect(session_config.exists?).to be true
      expect(result["version"]).to eq(1)
      expect(result["parent_sxn_path"]).to eq("/path/to/.sxn")
      expect(result["default_branch"]).to eq("feature-branch")
      expect(result["session_name"]).to eq("my-session")
      expect(result["created_at"]).not_to be_nil
    end

    it "creates valid YAML file" do
      session_config.create(
        parent_sxn_path: "/path/to/.sxn",
        default_branch: "main",
        session_name: "test"
      )

      content = File.read(session_config.config_path)
      parsed = YAML.safe_load(content)
      expect(parsed).to be_a(Hash)
      expect(parsed["default_branch"]).to eq("main")
    end
  end

  describe "#exists?" do
    it "returns false when .sxnrc does not exist" do
      expect(session_config.exists?).to be false
    end

    it "returns true when .sxnrc exists" do
      session_config.create(
        parent_sxn_path: "/path",
        default_branch: "main",
        session_name: "test"
      )
      expect(session_config.exists?).to be true
    end
  end

  describe "#read" do
    it "returns nil when file does not exist" do
      expect(session_config.read).to be_nil
    end

    it "returns config hash when file exists" do
      session_config.create(
        parent_sxn_path: "/path/to/.sxn",
        default_branch: "develop",
        session_name: "my-session"
      )

      result = session_config.read
      expect(result).to be_a(Hash)
      expect(result["default_branch"]).to eq("develop")
    end

    it "returns nil for invalid YAML" do
      File.write(session_config.config_path, "invalid: yaml: content: {")
      expect(session_config.read).to be_nil
    end
  end

  describe "#parent_sxn_path" do
    it "returns parent_sxn_path from config" do
      session_config.create(
        parent_sxn_path: "/my/project/.sxn",
        default_branch: "main",
        session_name: "test"
      )
      expect(session_config.parent_sxn_path).to eq("/my/project/.sxn")
    end

    it "returns nil when config does not exist" do
      expect(session_config.parent_sxn_path).to be_nil
    end
  end

  describe "#default_branch" do
    it "returns default_branch from config" do
      session_config.create(
        parent_sxn_path: "/path",
        default_branch: "feature/awesome",
        session_name: "test"
      )
      expect(session_config.default_branch).to eq("feature/awesome")
    end

    it "returns nil when config does not exist" do
      expect(session_config.default_branch).to be_nil
    end
  end

  describe "#session_name" do
    it "returns session_name from config" do
      session_config.create(
        parent_sxn_path: "/path",
        default_branch: "main",
        session_name: "awesome-session"
      )
      expect(session_config.session_name).to eq("awesome-session")
    end

    it "returns nil when config does not exist" do
      expect(session_config.session_name).to be_nil
    end
  end

  describe "#project_root" do
    it "returns parent of parent_sxn_path" do
      session_config.create(
        parent_sxn_path: "/my/awesome/project/.sxn",
        default_branch: "main",
        session_name: "test"
      )
      expect(session_config.project_root).to eq("/my/awesome/project")
    end

    it "returns nil when config does not exist" do
      expect(session_config.project_root).to be_nil
    end
  end

  describe "#update" do
    before do
      session_config.create(
        parent_sxn_path: "/path",
        default_branch: "main",
        session_name: "test"
      )
    end

    it "updates existing config values" do
      session_config.update(default_branch: "develop")
      expect(session_config.default_branch).to eq("develop")
    end

    it "preserves existing values not being updated" do
      session_config.update(default_branch: "develop")
      expect(session_config.session_name).to eq("test")
      expect(session_config.parent_sxn_path).to eq("/path")
    end

    it "adds new values" do
      session_config.update(custom_field: "custom_value")
      expect(session_config.read["custom_field"]).to eq("custom_value")
    end

    it "handles string keys" do
      session_config.update("default_branch" => "feature")
      expect(session_config.default_branch).to eq("feature")
    end
  end

  describe ".find_from_path" do
    let(:nested_dir) { File.join(temp_dir, "worktree", "src", "deep") }

    before do
      FileUtils.mkdir_p(nested_dir)
      session_config.create(
        parent_sxn_path: "/path/to/.sxn",
        default_branch: "main",
        session_name: "test-session"
      )
    end

    it "finds .sxnrc from session directory" do
      found = described_class.find_from_path(temp_dir)

      expect(found).not_to be_nil
      expect(found.session_name).to eq("test-session")
    end

    it "finds .sxnrc from nested directory" do
      found = described_class.find_from_path(nested_dir)

      expect(found).not_to be_nil
      expect(found.session_name).to eq("test-session")
      expect(found.session_path).to eq(temp_dir)
    end

    it "returns nil when not in a session" do
      other_dir = Dir.mktmpdir
      begin
        found = described_class.find_from_path(other_dir)
        expect(found).to be_nil
      ensure
        FileUtils.rm_rf(other_dir)
      end
    end

    it "handles root directory gracefully" do
      found = described_class.find_from_path("/")
      expect(found).to be_nil
    end
  end

  describe ".in_session?" do
    before do
      session_config.create(
        parent_sxn_path: "/path/to/.sxn",
        default_branch: "main",
        session_name: "test"
      )
    end

    it "returns true when in session directory" do
      expect(described_class.in_session?(temp_dir)).to be true
    end

    it "returns true when in nested directory within session" do
      nested = File.join(temp_dir, "subdir")
      FileUtils.mkdir_p(nested)
      expect(described_class.in_session?(nested)).to be true
    end

    it "returns false when not in session" do
      other_dir = Dir.mktmpdir
      begin
        expect(described_class.in_session?(other_dir)).to be false
      ensure
        FileUtils.rm_rf(other_dir)
      end
    end
  end
end
