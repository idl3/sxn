# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "json"

RSpec.describe Sxn::Commands::Init, "Claude Code Integration" do
  let(:temp_dir) { Dir.mktmpdir("sxn_claude_test") }
  let(:project_dir) { File.join(temp_dir, "project") }
  let(:sessions_folder) { File.join(project_dir, "sessions") }

  # Use real constants from the class
  let(:claude_helpers_dir) { described_class::CLAUDE_HELPERS_DIR }
  let(:claude_hook_path) { described_class::CLAUDE_HOOK_PATH }
  let(:project_claude_dir) { File.join(project_dir, ".claude") }
  let(:project_settings_path) { File.join(project_claude_dir, "settings.json") }

  # Template paths - use temp dir to avoid modifying real source files
  let(:real_template_path) do
    File.join(
      File.dirname(__FILE__), "..", "..", "..", "lib", "sxn",
      "templates", "claude_code", "sxn-session-check.sh.liquid"
    )
  end
  let(:temp_template_dir) { File.join(temp_dir, "lib", "sxn", "templates", "claude_code") }
  let(:temp_template_path) { File.join(temp_template_dir, "sxn-session-check.sh.liquid") }

  let(:init_command) { described_class.new }
  let(:ui_output) { instance_double(Sxn::UI::Output) }
  let(:config_manager) { instance_double(Sxn::Core::ConfigManager) }
  let(:template_processor) { instance_double(Sxn::Templates::TemplateProcessor) }

  before do
    # Set up directory structure
    FileUtils.mkdir_p(project_dir)
    FileUtils.mkdir_p(claude_helpers_dir)

    # Change to project directory
    Dir.chdir(project_dir)

    # Stub Dir.pwd to return project directory
    allow(Dir).to receive(:pwd).and_return(project_dir)

    # Inject dependencies
    init_command.instance_variable_set(:@ui, ui_output)
    init_command.instance_variable_set(:@config_manager, config_manager)

    # Stub UI methods to avoid output during tests
    allow(ui_output).to receive(:subsection)
    allow(ui_output).to receive(:progress_start)
    allow(ui_output).to receive(:progress_done)
    allow(ui_output).to receive(:success)
    allow(ui_output).to receive(:info)
    allow(ui_output).to receive(:warning)

    # Stub template processor
    allow(Sxn::Templates::TemplateProcessor).to receive(:new).and_return(template_processor)
  end

  after do
    FileUtils.rm_rf(temp_dir)
    # Clean up the real claude helpers directory used by tests
    FileUtils.rm_f(claude_hook_path)
  end

  describe "#setup_claude_code_hooks" do
    it "orchestrates hook installation by calling both installation methods" do
      expect(init_command).to receive(:install_claude_hook_script)
      expect(init_command).to receive(:setup_project_claude_settings)

      init_command.send(:setup_claude_code_hooks)

      expect(ui_output).to have_received(:subsection).with("Claude Code Integration")
    end
  end

  describe "#install_claude_hook_script" do
    let(:template_content) { "#!/usr/bin/env bash\n# Template content" }
    let(:processed_content) { "#!/usr/bin/env bash\n# Processed content" }

    before do
      # Create template file in temp directory (not the real source tree!)
      FileUtils.mkdir_p(temp_template_dir)
      File.write(temp_template_path, template_content)

      # Stub the template path lookup to use our temp directory
      stub_const("Sxn::Commands::Init::TEMPLATE_DIR", File.join(temp_dir, "lib", "sxn", "templates"))
      allow(File).to receive(:join).and_call_original
      allow(File).to receive(:join)
        .with(anything, "..", "templates", "claude_code", "sxn-session-check.sh.liquid")
        .and_return(temp_template_path)
    end

    context "when helpers directory does not exist" do
      it "creates the helpers directory" do
        allow(template_processor).to receive(:process).and_return(processed_content)

        init_command.send(:install_claude_hook_script)

        expect(Dir.exist?(claude_helpers_dir)).to be true
      end
    end

    context "when hook script does not exist" do
      it "creates hook script from template" do
        allow(template_processor).to receive(:process)
          .with(template_content, hash_including(:timestamp))
          .and_return(processed_content)

        init_command.send(:install_claude_hook_script)

        expect(File.exist?(claude_hook_path)).to be true
        expect(File.read(claude_hook_path)).to eq(processed_content)
      end

      it "makes hook script executable (0755 permissions)" do
        allow(template_processor).to receive(:process).and_return(processed_content)

        init_command.send(:install_claude_hook_script)

        file_mode = File.stat(claude_hook_path).mode
        expect(file_mode & 0o777).to eq(0o755)
      end

      it "processes template with timestamp" do
        freeze_time = Time.new(2025, 1, 15, 12, 30, 0)
        allow(Time).to receive(:now).and_return(freeze_time)

        expect(template_processor).to receive(:process)
          .with(template_content, { timestamp: freeze_time })
          .and_return(processed_content)

        init_command.send(:install_claude_hook_script)
      end

      it "shows progress and success messages" do
        allow(template_processor).to receive(:process).and_return(processed_content)

        init_command.send(:install_claude_hook_script)

        expect(ui_output).to have_received(:progress_start).with("Installing global hook script")
        expect(ui_output).to have_received(:progress_done)
        expect(ui_output).to have_received(:success).with("Installed hook script to #{claude_hook_path}")
      end
    end

    context "when hook script already exists" do
      before do
        FileUtils.mkdir_p(claude_helpers_dir)
        File.write(claude_hook_path, "existing content")
      end

      context "without --force flag" do
        it "skips installation and shows info message" do
          init_command.send(:install_claude_hook_script)

          expect(File.read(claude_hook_path)).to eq("existing content")
          expect(ui_output).to have_received(:info)
            .with("Global hook script already installed at #{claude_hook_path}")
        end

        it "does not process template" do
          expect(template_processor).not_to receive(:process)

          init_command.send(:install_claude_hook_script)
        end
      end

      context "with --force flag" do
        before do
          init_command.options = { force: true }
        end

        it "overwrites existing hook script" do
          allow(template_processor).to receive(:process).and_return(processed_content)

          init_command.send(:install_claude_hook_script)

          expect(File.read(claude_hook_path)).to eq(processed_content)
        end
      end
    end

    context "when template file does not exist" do
      before do
        # Remove the template file from our temp directory (not the real source!)
        FileUtils.rm_f(temp_template_path)
      end

      it "shows warning and skips installation" do
        init_command.send(:install_claude_hook_script)

        expect(ui_output).to have_received(:warning)
          .with("Template not found, skipping hook script installation")
        expect(ui_output).to have_received(:progress_done)
        expect(File.exist?(claude_hook_path)).to be false
      end
    end

    context "when template processing fails" do
      it "propagates the error" do
        allow(template_processor).to receive(:process)
          .and_raise(StandardError, "Template error")

        expect do
          init_command.send(:install_claude_hook_script)
        end.to raise_error(StandardError, "Template error")
      end
    end
  end

  describe "#setup_project_claude_settings" do
    context "when .claude directory does not exist" do
      it "creates the .claude directory" do
        init_command.send(:setup_project_claude_settings)

        expect(Dir.exist?(project_claude_dir)).to be true
      end
    end

    context "when settings.json does not exist" do
      it "creates new settings file with hooks configuration" do
        expect(init_command).to receive(:create_claude_settings).with(project_settings_path)

        init_command.send(:setup_project_claude_settings)
      end

      it "shows progress and success messages" do
        allow(init_command).to receive(:create_claude_settings)

        init_command.send(:setup_project_claude_settings)

        expect(ui_output).to have_received(:progress_start)
          .with("Configuring project Claude settings")
        expect(ui_output).to have_received(:progress_done)
        expect(ui_output).to have_received(:success)
          .with("Claude Code session enforcement enabled")
        expect(ui_output).to have_received(:info)
          .with("Hook script: #{claude_hook_path}")
      end
    end

    context "when settings.json already exists" do
      before do
        FileUtils.mkdir_p(project_claude_dir)
        File.write(project_settings_path, JSON.pretty_generate({ "existing" => "config" }))
      end

      it "merges hooks into existing settings" do
        expect(init_command).to receive(:merge_claude_hooks_into_settings)
          .with(project_settings_path)

        init_command.send(:setup_project_claude_settings)
      end
    end
  end

  describe "#create_claude_settings" do
    before do
      FileUtils.mkdir_p(project_claude_dir)
    end

    it "creates settings.json with correct hook structure" do
      init_command.send(:create_claude_settings, project_settings_path)

      expect(File.exist?(project_settings_path)).to be true

      settings = JSON.parse(File.read(project_settings_path))
      expect(settings).to have_key("hooks")
      expect(settings["hooks"]).to have_key("UserPromptSubmit")
    end

    it "configures UserPromptSubmit hook with empty matcher" do
      init_command.send(:create_claude_settings, project_settings_path)

      settings = JSON.parse(File.read(project_settings_path))
      user_prompt_hooks = settings["hooks"]["UserPromptSubmit"]

      expect(user_prompt_hooks).to be_an(Array)
      expect(user_prompt_hooks.length).to eq(1)
      expect(user_prompt_hooks.first["matcher"]).to eq("")
    end

    it "configures hook command to point to global script" do
      init_command.send(:create_claude_settings, project_settings_path)

      settings = JSON.parse(File.read(project_settings_path))
      hook_config = settings["hooks"]["UserPromptSubmit"].first["hooks"].first

      expect(hook_config["type"]).to eq("command")
      expect(hook_config["command"]).to eq(claude_hook_path)
      expect(hook_config["timeout"]).to eq(15_000)
    end

    it "creates properly formatted JSON" do
      init_command.send(:create_claude_settings, project_settings_path)

      # Should be able to parse without errors
      expect do
        JSON.parse(File.read(project_settings_path))
      end.not_to raise_error

      # Should be pretty-printed (multiline)
      content = File.read(project_settings_path)
      expect(content.lines.count).to be > 1
    end
  end

  describe "#merge_claude_hooks_into_settings" do
    context "when settings file has no hooks key" do
      before do
        FileUtils.mkdir_p(project_claude_dir)
        File.write(project_settings_path, JSON.pretty_generate({ "other" => "setting" }))
      end

      it "initializes hooks and adds UserPromptSubmit configuration" do
        init_command.send(:merge_claude_hooks_into_settings, project_settings_path)

        settings = JSON.parse(File.read(project_settings_path))
        expect(settings).to have_key("hooks")
        expect(settings["hooks"]).to have_key("UserPromptSubmit")
        expect(settings["other"]).to eq("setting")
      end
    end

    context "when settings file has hooks but no UserPromptSubmit" do
      before do
        FileUtils.mkdir_p(project_claude_dir)
        existing_settings = {
          "hooks" => {
            "OtherHook" => [{ "matcher" => "test" }]
          }
        }
        File.write(project_settings_path, JSON.pretty_generate(existing_settings))
      end

      it "adds UserPromptSubmit hook without affecting other hooks" do
        init_command.send(:merge_claude_hooks_into_settings, project_settings_path)

        settings = JSON.parse(File.read(project_settings_path))
        expect(settings["hooks"]).to have_key("OtherHook")
        expect(settings["hooks"]).to have_key("UserPromptSubmit")
      end
    end

    context "when UserPromptSubmit hook already exists but without sxn hook" do
      before do
        FileUtils.mkdir_p(project_claude_dir)
        existing_settings = {
          "hooks" => {
            "UserPromptSubmit" => [
              {
                "matcher" => "pattern",
                "hooks" => [
                  { "type" => "command", "command" => "/some/other/script" }
                ]
              }
            ]
          }
        }
        File.write(project_settings_path, JSON.pretty_generate(existing_settings))
      end

      it "appends sxn hook to existing UserPromptSubmit hooks" do
        init_command.send(:merge_claude_hooks_into_settings, project_settings_path)

        settings = JSON.parse(File.read(project_settings_path))
        user_prompt_hooks = settings["hooks"]["UserPromptSubmit"]

        expect(user_prompt_hooks.length).to eq(2)
        expect(user_prompt_hooks.first["hooks"].first["command"]).to eq("/some/other/script")

        sxn_hook = user_prompt_hooks.last
        expect(sxn_hook["matcher"]).to eq("")
        expect(sxn_hook["hooks"].first["command"]).to eq(claude_hook_path)
      end
    end

    context "when sxn hook is already configured" do
      before do
        FileUtils.mkdir_p(project_claude_dir)
        existing_settings = {
          "hooks" => {
            "UserPromptSubmit" => [
              {
                "matcher" => "",
                "hooks" => [
                  {
                    "type" => "command",
                    "command" => claude_hook_path,
                    "timeout" => 15_000
                  }
                ]
              }
            ]
          }
        }
        File.write(project_settings_path, JSON.pretty_generate(existing_settings))
      end

      it "detects existing sxn hook and skips installation" do
        init_command.send(:merge_claude_hooks_into_settings, project_settings_path)

        settings = JSON.parse(File.read(project_settings_path))
        user_prompt_hooks = settings["hooks"]["UserPromptSubmit"]

        expect(user_prompt_hooks.length).to eq(1)
        expect(ui_output).to have_received(:info)
          .with("Claude Code hooks already configured in project settings")
      end

      it "does not duplicate hook configuration" do
        original_content = File.read(project_settings_path)

        init_command.send(:merge_claude_hooks_into_settings, project_settings_path)

        new_content = File.read(project_settings_path)
        expect(new_content).to eq(original_content)
      end
    end

    context "when hook command contains 'sxn-session-check' in path" do
      before do
        FileUtils.mkdir_p(project_claude_dir)
        existing_settings = {
          "hooks" => {
            "UserPromptSubmit" => [
              {
                "matcher" => "",
                "hooks" => [
                  {
                    "type" => "command",
                    "command" => "/custom/path/sxn-session-check.sh"
                  }
                ]
              }
            ]
          }
        }
        File.write(project_settings_path, JSON.pretty_generate(existing_settings))
      end

      it "recognizes variations in hook path and skips installation" do
        init_command.send(:merge_claude_hooks_into_settings, project_settings_path)

        settings = JSON.parse(File.read(project_settings_path))
        expect(settings["hooks"]["UserPromptSubmit"].length).to eq(1)
      end
    end

    context "when settings file has invalid JSON" do
      before do
        FileUtils.mkdir_p(project_claude_dir)
        File.write(project_settings_path, "{ invalid json")
      end

      it "raises JSON parse error" do
        expect do
          init_command.send(:merge_claude_hooks_into_settings, project_settings_path)
        end.to raise_error(JSON::ParserError)
      end
    end

    it "preserves all existing settings when merging" do
      FileUtils.mkdir_p(project_claude_dir)
      existing_settings = {
        "hooks" => {
          "OtherHook" => [{ "test" => "data" }]
        },
        "customSetting" => "value",
        "nestedConfig" => {
          "option1" => true,
          "option2" => "test"
        }
      }
      File.write(project_settings_path, JSON.pretty_generate(existing_settings))

      init_command.send(:merge_claude_hooks_into_settings, project_settings_path)

      settings = JSON.parse(File.read(project_settings_path))
      expect(settings["customSetting"]).to eq("value")
      expect(settings["nestedConfig"]["option1"]).to be true
      expect(settings["nestedConfig"]["option2"]).to eq("test")
      expect(settings["hooks"]["OtherHook"]).to eq([{ "test" => "data" }])
    end
  end

  describe "integration with sxn init command" do
    let(:prompt) { instance_double(Sxn::UI::Prompt) }

    before do
      init_command.instance_variable_set(:@prompt, prompt)

      # Stub config_manager methods
      allow(config_manager).to receive(:initialized?).and_return(false)
      allow(config_manager).to receive(:initialize_project).and_return(sessions_folder)
      allow(config_manager).to receive(:detect_projects).and_return([])

      # Stub UI methods
      allow(ui_output).to receive(:section)
      allow(ui_output).to receive(:newline)
      allow(ui_output).to receive(:command_example)
      allow(ui_output).to receive(:recovery_suggestion)

      # Stub prompt
      allow(prompt).to receive(:sessions_folder_setup).and_return("sessions")

      # Create template for hook script in temp directory (not real source!)
      FileUtils.mkdir_p(temp_template_dir)
      File.write(temp_template_path, "#!/usr/bin/env bash\n# Test template")

      # Stub the template path lookup to use our temp directory
      allow(File).to receive(:join).and_call_original
      allow(File).to receive(:join)
        .with(anything, "..", "templates", "claude_code", "sxn-session-check.sh.liquid")
        .and_return(temp_template_path)

      allow(template_processor).to receive(:process).and_return("#!/usr/bin/env bash\n# Processed")
    end

    context "when --claude-code flag is true (default)" do
      before do
        init_command.options = { claude_code: true, auto_detect: false, quiet: true }
      end

      it "calls setup_claude_code_hooks during initialization" do
        expect(init_command).to receive(:setup_claude_code_hooks)

        init_command.init
      end

      it "installs both global hook and project settings" do
        init_command.init

        expect(File.exist?(claude_hook_path)).to be true
        expect(File.exist?(project_settings_path)).to be true
      end
    end

    context "when --no-claude-code flag is used" do
      before do
        init_command.options = { claude_code: false, auto_detect: false, quiet: true }
      end

      it "skips Claude Code setup" do
        expect(init_command).not_to receive(:setup_claude_code_hooks)

        init_command.init
      end

      it "does not create hook script or project settings" do
        init_command.init

        expect(File.exist?(claude_hook_path)).to be false
        expect(File.exist?(project_settings_path)).to be false
      end
    end

    context "when using --force flag" do
      before do
        # Pre-create existing hook
        FileUtils.mkdir_p(claude_helpers_dir)
        File.write(claude_hook_path, "old content")

        init_command.options = { force: true, claude_code: true, auto_detect: false, quiet: true }
      end

      it "overwrites existing hook script" do
        init_command.init

        expect(File.read(claude_hook_path)).to eq("#!/usr/bin/env bash\n# Processed")
      end
    end
  end

  describe "error handling" do
    before do
      # Create template in temp directory (not real source!)
      FileUtils.mkdir_p(temp_template_dir)
      File.write(temp_template_path, "#!/usr/bin/env bash\n")

      # Stub the template path lookup to use our temp directory
      allow(File).to receive(:join).and_call_original
      allow(File).to receive(:join)
        .with(anything, "..", "templates", "claude_code", "sxn-session-check.sh.liquid")
        .and_return(temp_template_path)
    end

    context "when helpers directory creation fails" do
      it "propagates the error" do
        # Remove the directory first
        FileUtils.rm_rf(claude_helpers_dir)

        # Mock mkdir_p to fail only for claude_helpers_dir
        allow(FileUtils).to receive(:mkdir_p).and_call_original
        allow(FileUtils).to receive(:mkdir_p).with(claude_helpers_dir)
                                             .and_raise(Errno::EACCES, "Permission denied")

        expect do
          init_command.send(:install_claude_hook_script)
        end.to raise_error(Errno::EACCES)
      end
    end

    context "when hook script write fails" do
      it "propagates the error" do
        allow(template_processor).to receive(:process).and_return("content")

        # Mock File.write to fail only for claude_hook_path
        allow(File).to receive(:write).and_call_original
        allow(File).to receive(:write).with(claude_hook_path, anything)
                                      .and_raise(Errno::ENOSPC, "No space left")

        expect do
          init_command.send(:install_claude_hook_script)
        end.to raise_error(Errno::ENOSPC)
      end
    end

    context "when chmod fails" do
      it "propagates the error" do
        allow(template_processor).to receive(:process).and_return("content")

        # Mock chmod to fail only for claude_hook_path
        allow(FileUtils).to receive(:chmod).and_call_original
        allow(FileUtils).to receive(:chmod).with(0o755, claude_hook_path)
                                           .and_raise(Errno::EPERM, "Operation not permitted")

        expect do
          init_command.send(:install_claude_hook_script)
        end.to raise_error(Errno::EPERM)
      end
    end

    context "when .claude directory creation fails" do
      it "propagates the error" do
        allow(FileUtils).to receive(:mkdir_p).and_call_original
        allow(FileUtils).to receive(:mkdir_p).with(project_claude_dir)
                                             .and_raise(Errno::EACCES, "Permission denied")

        expect do
          init_command.send(:setup_project_claude_settings)
        end.to raise_error(Errno::EACCES)
      end
    end

    context "when settings.json write fails" do
      it "propagates the error during create" do
        FileUtils.mkdir_p(project_claude_dir)

        allow(File).to receive(:write).and_call_original
        allow(File).to receive(:write).with(project_settings_path, anything)
                                      .and_raise(Errno::ENOSPC, "No space left")

        expect do
          init_command.send(:create_claude_settings, project_settings_path)
        end.to raise_error(Errno::ENOSPC)
      end

      it "propagates the error during merge" do
        FileUtils.mkdir_p(project_claude_dir)
        File.write(project_settings_path, JSON.pretty_generate({ "hooks" => {} }))

        allow(File).to receive(:write).and_call_original
        allow(File).to receive(:write).with(project_settings_path, anything)
                                      .and_raise(Errno::ENOSPC, "No space left")

        expect do
          init_command.send(:merge_claude_hooks_into_settings, project_settings_path)
        end.to raise_error(Errno::ENOSPC)
      end
    end
  end

  describe "file permissions and ownership" do
    before do
      # Create template in temp directory (not real source!)
      FileUtils.mkdir_p(temp_template_dir)
      File.write(temp_template_path, "#!/usr/bin/env bash\n")

      # Stub the template path lookup to use our temp directory
      allow(File).to receive(:join).and_call_original
      allow(File).to receive(:join)
        .with(anything, "..", "templates", "claude_code", "sxn-session-check.sh.liquid")
        .and_return(temp_template_path)

      allow(template_processor).to receive(:process).and_return("#!/usr/bin/env bash\n")
    end

    context "when hook script is created" do
      before do
        init_command.send(:install_claude_hook_script)
      end

      it "sets executable permissions for owner, group, and others" do
        stat = File.stat(claude_hook_path)
        mode = stat.mode

        # Check owner can execute
        expect(mode & 0o100).to eq(0o100)
        # Check group can execute
        expect(mode & 0o010).to eq(0o010)
        # Check others can execute
        expect(mode & 0o001).to eq(0o001)
      end

      it "sets read and write permissions for owner" do
        stat = File.stat(claude_hook_path)
        mode = stat.mode

        expect(mode & 0o400).to eq(0o400) # owner read
        expect(mode & 0o200).to eq(0o200) # owner write
      end
    end
  end

  describe "constants" do
    # Reset Dir.home stub for constant tests since constants are evaluated at class load time
    around do |example|
      original_home = Dir.home
      example.run
      ENV["HOME"] = original_home if original_home
    end

    it "defines CLAUDE_HELPERS_DIR constant" do
      # Constants are set when class loads, so they use real Dir.home
      expect(described_class::CLAUDE_HELPERS_DIR).to be_a(String)
      expect(described_class::CLAUDE_HELPERS_DIR).to end_with(".claude/helpers")
    end

    it "defines CLAUDE_HOOK_SCRIPT constant" do
      expect(described_class::CLAUDE_HOOK_SCRIPT).to eq("sxn-session-check.sh")
    end

    it "defines CLAUDE_HOOK_PATH constant" do
      expect(described_class::CLAUDE_HOOK_PATH).to be_a(String)
      expect(described_class::CLAUDE_HOOK_PATH).to end_with(".claude/helpers/sxn-session-check.sh")
    end
  end

  describe "#install_claude_hooks command" do
    context "when project is not initialized" do
      it "shows error and exits with code 1" do
        # Test lines 103-104 [then] - error path when not initialized
        allow(config_manager).to receive(:initialized?).and_return(false)
        allow(ui_output).to receive(:section)
        allow(ui_output).to receive(:error)

        init_command.options = {}

        expect do
          init_command.install_claude_hooks
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end

        expect(ui_output).to have_received(:error)
          .with("Project not initialized. Run 'sxn init' first.")
      end
    end

    context "when project is initialized" do
      before do
        allow(config_manager).to receive(:initialized?).and_return(true)
        allow(ui_output).to receive(:section)
      end

      context "with install mode (default)" do
        it "calls setup_claude_code_hooks and shows recovery suggestion" do
          # Test lines 111-113 [else] - install path
          init_command.options = { uninstall: false }

          expect(init_command).to receive(:setup_claude_code_hooks)
          allow(ui_output).to receive(:newline)
          allow(ui_output).to receive(:recovery_suggestion)

          init_command.install_claude_hooks

          expect(ui_output).to have_received(:newline)
          expect(ui_output).to have_received(:recovery_suggestion)
            .with("Claude Code will now enforce session-based development in this project")
        end
      end

      context "with uninstall mode" do
        it "calls uninstall_claude_code_hooks" do
          # Test lines 109 [then] - uninstall path
          init_command.options = { uninstall: true }

          expect(init_command).to receive(:uninstall_claude_code_hooks)

          init_command.install_claude_hooks
        end
      end
    end
  end

  describe "#uninstall_claude_code_hooks" do
    before do
      allow(ui_output).to receive(:subsection)
      allow(ui_output).to receive(:info)
    end

    it "shows subsection and calls remove_project_claude_hooks" do
      expect(init_command).to receive(:remove_project_claude_hooks)

      init_command.send(:uninstall_claude_code_hooks)

      expect(ui_output).to have_received(:subsection)
        .with("Removing Claude Code Integration")
    end

    it "shows info about not removing global hook script" do
      allow(init_command).to receive(:remove_project_claude_hooks)

      init_command.send(:uninstall_claude_code_hooks)

      expect(ui_output).to have_received(:info)
        .with("Note: Global hook script at #{claude_hook_path} was not removed")
      expect(ui_output).to have_received(:info)
        .with("      (other projects may still use it)")
    end
  end

  describe "#auto_detect_projects" do
    let(:prompt) { instance_double(Sxn::UI::Prompt) }

    before do
      init_command.instance_variable_set(:@prompt, prompt)
      allow(ui_output).to receive(:subsection)
      allow(ui_output).to receive(:empty_state)
      allow(ui_output).to receive(:info)
    end

    context "when no projects are detected" do
      it "shows empty state and returns early" do
        # Test lines 244-247 - empty detection case
        allow(config_manager).to receive(:detect_projects).and_return([])
        allow(prompt).to receive(:project_detection_confirm)

        init_command.send(:auto_detect_projects)

        expect(ui_output).to have_received(:subsection).with("Project Detection")
        expect(ui_output).to have_received(:empty_state)
          .with("No projects detected in current directory")
        # Should return early without asking for confirmation
        expect(prompt).not_to have_received(:project_detection_confirm)
      end
    end

    context "when projects are detected" do
      let(:detected_projects) do
        [
          { name: "project1", path: "/path/to/project1", type: "rails" },
          { name: "project2", path: "/path/to/project2", type: "node" }
        ]
      end

      before do
        allow(config_manager).to receive(:detect_projects).and_return(detected_projects)
      end

      context "when user confirms registration" do
        it "registers the detected projects" do
          # Test lines 249-251 [then] - user confirms
          allow(prompt).to receive(:project_detection_confirm).and_return(true)
          expect(init_command).to receive(:register_detected_projects).with(detected_projects)

          init_command.send(:auto_detect_projects)
        end
      end

      context "when user rejects registration" do
        it "skips registration and shows info message" do
          # Test lines 252-254 [else] - user rejects
          allow(prompt).to receive(:project_detection_confirm).and_return(false)

          init_command.send(:auto_detect_projects)

          expect(ui_output).to have_received(:info).with("Skipped project registration")
          expect(ui_output).to have_received(:info)
            .with("You can register projects later with: sxn projects add <name> <path>")
        end
      end
    end
  end

  describe "#register_detected_projects" do
    let(:projects) do
      [
        { name: "project1", path: "/path/to/project1", type: "rails" },
        { name: "project2", path: "/path/to/project2", type: "node" }
      ]
    end
    let(:project_manager) { instance_double(Sxn::Core::ProjectManager) }
    let(:progress_bar) { instance_double(Sxn::UI::ProgressBar) }

    before do
      allow(Sxn::Core::ProjectManager).to receive(:new).and_return(project_manager)
      allow(ui_output).to receive(:success)
    end

    context "when all projects register successfully" do
      it "registers each project and shows success" do
        # Test lines 260-272 - successful registration
        allow(Sxn::UI::ProgressBar).to receive(:with_progress).and_yield(projects[0], progress_bar)
                                                              .and_yield(projects[1], progress_bar)
        allow(project_manager).to receive(:add_project).and_return(true)
        allow(progress_bar).to receive(:log)

        init_command.send(:register_detected_projects, projects)

        expect(project_manager).to have_received(:add_project)
          .with("project1", "/path/to/project1", type: "rails")
        expect(project_manager).to have_received(:add_project)
          .with("project2", "/path/to/project2", type: "node")
        expect(ui_output).to have_received(:success).with("Project registration completed")
      end
    end

    context "when a project registration fails" do
      it "catches the error and logs failure" do
        # Test lines 269-272 - error handling in progress bar
        allow(Sxn::UI::ProgressBar).to receive(:with_progress).and_yield(projects[0], progress_bar)
        allow(project_manager).to receive(:add_project).and_raise(StandardError, "Duplicate project")
        allow(progress_bar).to receive(:log)

        init_command.send(:register_detected_projects, projects)

        expect(progress_bar).to have_received(:log).with("❌ project1: Duplicate project")
      end
    end
  end

  describe "#display_next_steps" do
    before do
      allow(ui_output).to receive(:newline)
      allow(ui_output).to receive(:subsection)
      allow(ui_output).to receive(:command_example)
      allow(ui_output).to receive(:info)
      allow(ui_output).to receive(:recovery_suggestion)
    end

    context "when projects were detected" do
      it "shows info about detected projects" do
        # Test lines 296-298 [then] - projects detected
        allow(config_manager).to receive(:detect_projects).and_return([
                                                                        { name: "project1", path: "/path", type: "rails" }
                                                                      ])

        init_command.send(:display_next_steps)

        expect(ui_output).to have_received(:info).with("💡 Detected projects are ready to use!")
      end
    end

    context "when no projects were detected" do
      it "shows recovery suggestion to register projects" do
        # Test lines 299-300 [else] - no projects detected
        allow(config_manager).to receive(:detect_projects).and_return([])

        init_command.send(:display_next_steps)

        expect(ui_output).to have_received(:recovery_suggestion)
          .with("Register your projects with 'sxn projects add <name> <path>'")
      end
    end

    it "always shows next steps commands" do
      allow(config_manager).to receive(:detect_projects).and_return([])

      init_command.send(:display_next_steps)

      expect(ui_output).to have_received(:command_example)
        .with("sxn projects list", "View registered projects")
      expect(ui_output).to have_received(:command_example)
        .with("sxn add my-session", "Create your first session")
      expect(ui_output).to have_received(:command_example)
        .with("sxn worktree add <project> [branch]", "Add a worktree to your session")
    end
  end

  describe "#determine_sessions_folder" do
    let(:prompt) { instance_double(Sxn::UI::Prompt) }

    before do
      init_command.instance_variable_set(:@prompt, prompt)
    end

    context "when folder is provided and not in quiet mode" do
      it "returns the provided folder" do
        # Test line 228 - early return with folder && !quiet
        init_command.options = { quiet: false }
        allow(prompt).to receive(:sessions_folder_setup)

        result = init_command.send(:determine_sessions_folder, "custom-sessions")

        expect(result).to eq("custom-sessions")
        # Should return early without calling prompt
        expect(prompt).not_to have_received(:sessions_folder_setup)
      end
    end

    context "when in quiet mode" do
      before do
        init_command.options = { quiet: true }
      end

      it "returns provided folder in quiet mode" do
        # Test line 232 - quiet mode with folder
        result = init_command.send(:determine_sessions_folder, "my-sessions")

        expect(result).to eq("my-sessions")
      end

      it "returns default folder when no folder provided in quiet mode" do
        # Test line 232 - quiet mode without folder, using default
        allow(Dir).to receive(:pwd).and_return("/path/to/my-project")
        allow(File).to receive(:basename).with("/path/to/my-project").and_return("my-project")

        result = init_command.send(:determine_sessions_folder, nil)

        expect(result).to eq("my-project-sessions")
      end
    end

    context "when in interactive mode without folder" do
      it "calls prompt.sessions_folder_setup" do
        # Test line 236 - interactive mode
        init_command.options = { quiet: false }
        allow(prompt).to receive(:sessions_folder_setup).and_return("interactive-sessions")

        result = init_command.send(:determine_sessions_folder, nil)

        expect(result).to eq("interactive-sessions")
        expect(prompt).to have_received(:sessions_folder_setup)
      end
    end
  end

  describe "#init command" do
    let(:prompt) { instance_double(Sxn::UI::Prompt) }

    before do
      init_command.instance_variable_set(:@prompt, prompt)
      allow(ui_output).to receive(:section)
      allow(prompt).to receive(:sessions_folder_setup).and_return("sessions")
    end

    context "when already initialized without force flag" do
      before do
        allow(config_manager).to receive(:initialized?).and_return(true)
        allow(ui_output).to receive(:warning)
        allow(ui_output).to receive(:info)
        init_command.options = {}
      end

      it "shows warning and returns early without initializing" do
        # Test lines 62-66 - already initialized check
        expect(config_manager).not_to receive(:initialize_project)

        init_command.init

        expect(ui_output).to have_received(:warning)
          .with("Project already initialized")
        expect(ui_output).to have_received(:info)
          .with("Use --force to reinitialize")
      end
    end

    context "when Sxn::Error is raised during initialization" do
      let(:sxn_error) { Sxn::Error.new("Configuration failed", exit_code: 5) }

      before do
        allow(config_manager).to receive(:initialized?).and_return(false)
        allow(config_manager).to receive(:initialize_project).and_raise(sxn_error)
        allow(ui_output).to receive(:progress_start)
        allow(ui_output).to receive(:error)
        init_command.options = { auto_detect: false, claude_code: false, quiet: true }
      end

      it "catches Sxn::Error and exits with error's exit code" do
        # Test lines 86-88 - Sxn::Error rescue block
        expect do
          init_command.init("test-sessions")
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(5)
        end

        expect(ui_output).to have_received(:error)
          .with("Initialization failed: Configuration failed")
      end
    end

    context "when StandardError is raised during initialization" do
      let(:standard_error) { StandardError.new("Unexpected failure") }

      before do
        allow(config_manager).to receive(:initialized?).and_return(false)
        allow(config_manager).to receive(:initialize_project).and_raise(standard_error)
        allow(ui_output).to receive(:progress_start)
        allow(ui_output).to receive(:error)
        allow(ui_output).to receive(:debug)
        init_command.options = { auto_detect: false, claude_code: false, quiet: true }
      end

      it "catches StandardError and exits with code 1" do
        # Test lines 89-93 - StandardError rescue block
        expect do
          init_command.init("test-sessions")
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end

        expect(ui_output).to have_received(:error)
          .with("Unexpected error: Unexpected failure")
      end

      it "does not show debug output when SXN_DEBUG is not set" do
        # Test line 91 [else] - debug not enabled
        ENV.delete("SXN_DEBUG")

        expect do
          init_command.init("test-sessions")
        end.to raise_error(SystemExit)

        expect(ui_output).not_to have_received(:debug)
      end

      it "shows debug backtrace when SXN_DEBUG is set" do
        # Test line 91 [then] - debug enabled
        ENV["SXN_DEBUG"] = "1"

        expect do
          init_command.init("test-sessions")
        end.to raise_error(SystemExit)

        expect(ui_output).to have_received(:debug) do |arg|
          expect(arg).to be_a(String)
          expect(arg).to include("init_claude_code_spec.rb")
        end

        ENV.delete("SXN_DEBUG")
      end
    end
  end

  describe "#remove_project_claude_hooks" do
    context "when settings file does not exist" do
      it "shows info message and returns early" do
        # Test lines 443-444 [then] - file doesn't exist path
        allow(ui_output).to receive(:info)

        init_command.send(:remove_project_claude_hooks)

        expect(ui_output).to have_received(:info)
          .with("No Claude settings file found in this project")
        expect(ui_output).not_to have_received(:progress_start)
      end
    end

    context "when settings file exists" do
      before do
        FileUtils.mkdir_p(project_claude_dir)
        allow(ui_output).to receive(:progress_start)
        allow(ui_output).to receive(:progress_done)
        allow(ui_output).to receive(:success)
        allow(ui_output).to receive(:info)
      end

      context "when settings has no hooks key" do
        it "shows no sxn hooks found message" do
          # Test line 472 [else] - no UserPromptSubmit hooks
          File.write(project_settings_path, JSON.pretty_generate({ "other" => "setting" }))

          init_command.send(:remove_project_claude_hooks)

          expect(ui_output).to have_received(:progress_done)
          expect(ui_output).to have_received(:info)
            .with("No sxn hooks found in project settings")
        end
      end

      context "when settings has hooks but no UserPromptSubmit" do
        it "shows no sxn hooks found message" do
          # Test line 472 [else] - hooks exist but no UserPromptSubmit
          settings = { "hooks" => { "OtherHook" => [] } }
          File.write(project_settings_path, JSON.pretty_generate(settings))

          init_command.send(:remove_project_claude_hooks)

          expect(ui_output).to have_received(:info)
            .with("No sxn hooks found in project settings")
        end
      end

      context "when settings has UserPromptSubmit with sxn hooks" do
        context "and removing hooks leaves settings empty" do
          it "deletes the settings file" do
            # Test lines 452 [then], 454-455, 459 [then], 460 [then], 462-465 [then]
            # Only sxn hooks, so file should be deleted when empty
            settings = {
              "hooks" => {
                "UserPromptSubmit" => [
                  {
                    "matcher" => "",
                    "hooks" => [
                      {
                        "type" => "command",
                        "command" => claude_hook_path,
                        "timeout" => 15_000
                      }
                    ]
                  }
                ]
              }
            }
            File.write(project_settings_path, JSON.pretty_generate(settings))

            init_command.send(:remove_project_claude_hooks)

            expect(File.exist?(project_settings_path)).to be false
            expect(ui_output).to have_received(:success)
              .with("Removed settings.json (was empty after removing hooks)")
          end
        end

        context "and removing hooks leaves other settings" do
          it "writes updated settings file" do
            # Test lines 452 [then], 454-455, 467-469 [else]
            # Has other settings that should be preserved
            settings = {
              "hooks" => {
                "UserPromptSubmit" => [
                  {
                    "matcher" => "",
                    "hooks" => [
                      {
                        "type" => "command",
                        "command" => "/path/to/sxn-session-check.sh",
                        "timeout" => 15_000
                      }
                    ]
                  }
                ]
              },
              "customSetting" => "value"
            }
            File.write(project_settings_path, JSON.pretty_generate(settings))

            init_command.send(:remove_project_claude_hooks)

            expect(File.exist?(project_settings_path)).to be true
            remaining_settings = JSON.parse(File.read(project_settings_path))
            expect(remaining_settings).to have_key("customSetting")
            expect(remaining_settings).not_to have_key("hooks")
            expect(ui_output).to have_received(:success)
              .with("Removed sxn hooks from project settings")
          end
        end

        context "and UserPromptSubmit has both sxn and non-sxn hooks" do
          it "removes only sxn hooks and keeps others" do
            # Test lines 452 [then], 454-455, 459 [else], 467-469 [else]
            # UserPromptSubmit should remain with non-sxn hooks
            settings = {
              "hooks" => {
                "UserPromptSubmit" => [
                  {
                    "matcher" => "",
                    "hooks" => [
                      {
                        "type" => "command",
                        "command" => "/other/script.sh"
                      }
                    ]
                  },
                  {
                    "matcher" => "",
                    "hooks" => [
                      {
                        "type" => "command",
                        "command" => "/path/sxn-session-check.sh"
                      }
                    ]
                  }
                ]
              }
            }
            File.write(project_settings_path, JSON.pretty_generate(settings))

            init_command.send(:remove_project_claude_hooks)

            expect(File.exist?(project_settings_path)).to be true
            remaining_settings = JSON.parse(File.read(project_settings_path))
            expect(remaining_settings["hooks"]["UserPromptSubmit"].length).to eq(1)
            expect(remaining_settings["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"])
              .to eq("/other/script.sh")
          end
        end

        context "and UserPromptSubmit has other hooks plus empty hooks" do
          it "handles cleanup of UserPromptSubmit array correctly" do
            # Test line 459 with empty array after removal
            settings = {
              "hooks" => {
                "UserPromptSubmit" => [
                  {
                    "matcher" => "pattern",
                    "hooks" => [
                      {
                        "type" => "command",
                        "command" => "#{claude_helpers_dir}/sxn-session-check.sh"
                      }
                    ]
                  }
                ],
                "OtherHook" => [{ "matcher" => "test" }]
              }
            }
            File.write(project_settings_path, JSON.pretty_generate(settings))

            init_command.send(:remove_project_claude_hooks)

            remaining_settings = JSON.parse(File.read(project_settings_path))
            # UserPromptSubmit should be deleted (was empty after removal)
            expect(remaining_settings["hooks"]).not_to have_key("UserPromptSubmit")
            # But OtherHook should remain
            expect(remaining_settings["hooks"]).to have_key("OtherHook")
          end
        end

        context "with nested hooks containing sxn-session-check in command" do
          it "correctly identifies and removes hooks with sxn-session-check in path" do
            # Test line 455 - the any? check for command inclusion
            # The entire hook group is removed if ANY inner hook contains sxn-session-check
            settings = {
              "hooks" => {
                "UserPromptSubmit" => [
                  {
                    "matcher" => "",
                    "hooks" => [
                      {
                        "type" => "command",
                        "command" => "/custom/path/to/sxn-session-check.sh",
                        "timeout" => 20_000
                      },
                      {
                        "type" => "command",
                        "command" => "/another/script.sh"
                      }
                    ]
                  }
                ]
              }
            }
            File.write(project_settings_path, JSON.pretty_generate(settings))

            init_command.send(:remove_project_claude_hooks)

            # The entire hook group should be removed because it contains sxn-session-check
            # Since that was the only hook group, the file should be deleted
            expect(File.exist?(project_settings_path)).to be false
            expect(ui_output).to have_received(:success)
              .with("Removed settings.json (was empty after removing hooks)")
          end
        end
      end
    end
  end
end
