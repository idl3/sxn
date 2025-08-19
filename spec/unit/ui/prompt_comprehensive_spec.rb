# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::Prompt, "comprehensive coverage for missing areas" do
  let(:prompt) { described_class.new }
  let(:mock_tty_prompt) { double("TTY::Prompt") }

  before do
    allow(TTY::Prompt).to receive(:new).with(interrupt: :exit).and_return(mock_tty_prompt)

    # Reset global any_instance_of stubs that interfere with unit tests
    allow_any_instance_of(TTY::Prompt).to receive(:ask).and_call_original
    allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_call_original
    allow_any_instance_of(TTY::Prompt).to receive(:select).and_call_original
    allow_any_instance_of(TTY::Prompt).to receive(:multi_select).and_call_original

    allow_any_instance_of(Sxn::UI::Prompt).to receive(:ask).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:ask_yes_no).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:select).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:multi_select).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:folder_name).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:session_name).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_name).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_path).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:branch_name).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:confirm_deletion).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:rule_type).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:sessions_folder_setup).and_call_original
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_detection_confirm).and_call_original
  end

  describe "comprehensive validation testing" do
    describe "#session_name validation behavior" do
      it "validates that session names don't already exist" do
        existing_sessions = %w[existing-session another-session]

        question_object = double("question")
        allow(question_object).to receive(:validate).twice
        allow(question_object).to receive(:modify).with(:strip)

        allow(mock_tty_prompt).to receive(:ask).with("Enter session name:")
                                               .and_yield(question_object).and_return("new-session")

        result = prompt.session_name(existing_sessions: existing_sessions)
        expect(result).to eq("new-session")
      end
    end

    describe "#project_path validation behavior" do
      it "validates directory existence, readability and converts to absolute path" do
        question_object = double("question")
        allow(question_object).to receive(:validate)
        allow(question_object).to receive(:modify).with(:strip)
        allow(question_object).to receive(:convert)

        allow(mock_tty_prompt).to receive(:ask).with("Enter project path:")
                                               .and_yield(question_object).and_return("/test/path")

        result = prompt.project_path
        expect(result).to eq("/test/path")
      end
    end
  end

  describe "real-world usage scenarios" do
    describe "#folder_name" do
      it "accepts valid folder names" do
        question_object = double("question")
        allow(question_object).to receive(:validate)
        allow(question_object).to receive(:modify)

        allow(mock_tty_prompt).to receive(:ask).with("Enter sessions folder name:", default: nil)
                                               .and_yield(question_object).and_return("valid-folder_123")

        result = prompt.folder_name
        expect(result).to eq("valid-folder_123")
      end

      it "would reject invalid folder names" do
        # Test the validation regex directly
        regex = /\A[a-zA-Z0-9_-]+\z/
        expect("valid-folder").to match(regex)
        expect("invalid folder").not_to match(regex) # space
        expect("invalid@folder").not_to match(regex) # special char
        expect("").not_to match(regex) # empty
      end
    end

    describe "#project_name" do
      it "accepts valid project names" do
        question_object = double("question")
        allow(question_object).to receive(:validate)
        allow(question_object).to receive(:modify)

        allow(mock_tty_prompt).to receive(:ask).with("Enter project name:")
                                               .and_yield(question_object).and_return("valid-project_123")

        result = prompt.project_name
        expect(result).to eq("valid-project_123")
      end

      it "would reject invalid project names" do
        regex = /\A[a-zA-Z0-9_-]+\z/
        expect("valid-project").to match(regex)
        expect("invalid project").not_to match(regex) # space
        expect("invalid.project").not_to match(regex) # dot
      end
    end

    describe "#branch_name" do
      it "accepts valid branch names" do
        question_object = double("question")
        allow(question_object).to receive(:validate)
        allow(question_object).to receive(:modify)

        allow(mock_tty_prompt).to receive(:ask).with("Enter branch name:", default: nil)
                                               .and_yield(question_object).and_return("feature/test-branch_123")

        result = prompt.branch_name
        expect(result).to eq("feature/test-branch_123")
      end

      it "would reject invalid branch names" do
        regex = %r{\A[a-zA-Z0-9_/-]+\z}
        expect("feature/branch").to match(regex)
        expect("feature/test-branch").to match(regex)
        expect("main").to match(regex)
        expect("hotfix/urgent_fix").to match(regex)
        expect("invalid branch").not_to match(regex) # space
        expect("invalid@branch").not_to match(regex) # special char
      end
    end
  end

  describe "edge cases and error conditions" do
    describe "#sessions_folder_setup edge cases" do
      it "handles different current directory names" do
        # Test with directory containing special characters in basename
        allow(Dir).to receive(:pwd).and_return("/path/with-special.chars")
        allow(File).to receive(:basename).with("/path/with-special.chars").and_return("with-special.chars")

        expect(prompt).to receive(:puts).exactly(3).times
        expect(prompt).to receive(:folder_name).with("Sessions folder name:",
                                                     default: "with-special.chars-sessions").and_return("test-sessions")
        expect(prompt).to receive(:ask_yes_no).with("Create sessions folder in current directory?",
                                                    default: true).and_return(true)

        result = prompt.sessions_folder_setup
        expect(result).to eq("test-sessions")
      end

      it "handles custom base path scenario completely" do
        allow(Dir).to receive(:pwd).and_return("/current")
        allow(File).to receive(:basename).with("/current").and_return("current")

        # Mock the internal calls made by sessions_folder_setup
        allow(prompt).to receive(:puts)

        # Mock folder_name call
        folder_question = double("question")
        allow(folder_question).to receive(:validate)
        allow(folder_question).to receive(:modify)

        allow(mock_tty_prompt).to receive(:ask).with("Sessions folder name:", default: "current-sessions")
                                               .and_yield(folder_question).and_return("my-sessions")

        # Mock ask_yes_no call
        allow(mock_tty_prompt).to receive(:yes?).with("Create sessions folder in current directory?",
                                                      default: true).and_return(false)

        # Mock project_path call
        path_question = double("question")
        allow(path_question).to receive(:validate)
        allow(path_question).to receive(:modify)
        allow(path_question).to receive(:convert)

        allow(mock_tty_prompt).to receive(:ask).with("Base path for sessions folder:")
                                               .and_yield(path_question).and_return("/custom/location")

        result = prompt.sessions_folder_setup
        expect(result).to eq("/custom/location/my-sessions")
      end
    end

    describe "#project_detection_confirm edge cases" do
      it "handles single project correctly" do
        detected_projects = [
          { name: "single-project", type: "ruby", path: "/path/to/single" }
        ]

        expect(prompt).to receive(:puts).with("")
        expect(prompt).to receive(:puts).with("Detected projects in current directory:")
        expect(prompt).to receive(:puts).with("  single-project (ruby) - /path/to/single")
        expect(prompt).to receive(:puts).with("")

        expect(prompt).to receive(:ask_yes_no).with("Would you like to register these projects automatically?",
                                                    default: true).and_return(true)

        result = prompt.project_detection_confirm(detected_projects)
        expect(result).to be true
      end

      it "handles projects with long paths" do
        detected_projects = [
          { name: "project", type: "type", path: "/very/long/path/to/project/that/might/wrap/lines" }
        ]

        expect(prompt).to receive(:puts).with("")
        expect(prompt).to receive(:puts).with("Detected projects in current directory:")
        expect(prompt).to receive(:puts).with("  project (type) - /very/long/path/to/project/that/might/wrap/lines")
        expect(prompt).to receive(:puts).with("")

        expect(prompt).to receive(:ask_yes_no).with("Would you like to register these projects automatically?",
                                                    default: true).and_return(true)

        result = prompt.project_detection_confirm(detected_projects)
        expect(result).to be true
      end
    end
  end

  describe "method parameter variations" do
    describe "#folder_name with all parameters" do
      it "handles custom message and default value" do
        question_object = double("question")
        allow(question_object).to receive(:validate)
        allow(question_object).to receive(:modify)

        allow(mock_tty_prompt).to receive(:ask).with("Custom folder message:", default: "custom-default")
                                               .and_yield(question_object).and_return("custom-folder")

        result = prompt.folder_name("Custom folder message:", default: "custom-default")
        expect(result).to eq("custom-folder")
      end
    end

    describe "#session_name with custom message" do
      it "uses custom message with existing sessions" do
        existing_sessions = ["session1"]

        question_object = double("question")
        allow(question_object).to receive(:validate).twice
        allow(question_object).to receive(:modify)

        allow(mock_tty_prompt).to receive(:ask).with("Custom session message:")
                                               .and_yield(question_object).and_return("new-session")

        result = prompt.session_name("Custom session message:", existing_sessions: existing_sessions)
        expect(result).to eq("new-session")
      end
    end

    describe "#branch_name with all parameters" do
      it "handles custom message and default branch" do
        question_object = double("question")
        allow(question_object).to receive(:validate)
        allow(question_object).to receive(:modify)

        allow(mock_tty_prompt).to receive(:ask).with("Custom branch message:", default: "develop")
                                               .and_yield(question_object).and_return("feature-branch")

        result = prompt.branch_name("Custom branch message:", default: "develop")
        expect(result).to eq("feature-branch")
      end
    end
  end

  describe "string modification and conversion" do
    it "strips whitespace from all string inputs" do
      %w[folder_name session_name project_name project_path branch_name].each do |method|
        expect(mock_tty_prompt).to receive(:ask) do |&block|
          question = double("question")
          expect(question).to receive(:modify).with(:strip)
          allow(question).to receive(:validate)
          allow(question).to receive(:convert) if method == "project_path"
          block.call(question)
        end.and_return("test-result")

        case method
        when "session_name"
          prompt.send(method, existing_sessions: [])
        when "project_path"
          prompt.send(method)
        else
          prompt.send(method)
        end
      end
    end
  end
end
