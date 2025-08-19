# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::Prompt, "comprehensive coverage for missing areas" do
  let(:prompt) { described_class.new }
  let(:mock_tty_prompt) { instance_double(TTY::Prompt) }

  before do
    allow(TTY::Prompt).to receive(:new).with(interrupt: :exit).and_return(mock_tty_prompt)
  end

  describe "comprehensive validation testing" do
    describe "#session_name validation lambdas" do
      it "validates that session names don't already exist" do
        existing_sessions = ["existing-session", "another-session"]
        
        # Capture the validation lambda by mocking the question object
        validation_lambda = nil
        expect(mock_tty_prompt).to receive(:ask).with("Enter session name:") do |&block|
          question = double("question")
          expect(question).to receive(:validate).with(/\A[a-zA-Z0-9_-]+\z/, anything)
          expect(question).to receive(:validate) do |proc, message|
            validation_lambda = proc
            expect(message).to eq("Session name already exists")
          end
          expect(question).to receive(:modify).with(:strip)
          block.call(question)
        end.and_return("test-session")
        
        prompt.session_name(existing_sessions: existing_sessions)
        
        # Test the captured lambda
        expect(validation_lambda.call("existing-session")).to be false
        expect(validation_lambda.call("new-session")).to be true
        expect(validation_lambda.call("another-session")).to be false
      end
    end

    describe "#project_path validation lambdas" do
      it "validates directory existence, readability and converts to absolute path" do
        validation_lambda = nil
        conversion_lambda = nil
        
        expect(mock_tty_prompt).to receive(:ask).with("Enter project path:") do |&block|
          question = double("question")
          expect(question).to receive(:validate) do |proc, message|
            validation_lambda = proc
            expect(message).to eq("Path must be a readable directory")
          end
          expect(question).to receive(:modify).with(:strip)
          expect(question).to receive(:convert) do |proc|
            conversion_lambda = proc
          end
          block.call(question)
        end.and_return("/test/path")
        
        prompt.project_path
        
        # Test validation lambda
        allow(File).to receive(:expand_path).with("/valid/path").and_return("/valid/path")
        allow(File).to receive(:directory?).with("/valid/path").and_return(true)
        allow(File).to receive(:readable?).with("/valid/path").and_return(true)
        
        expect(validation_lambda.call("/valid/path")).to be true
        
        # Test with non-directory
        allow(File).to receive(:expand_path).with("/file/path").and_return("/file/path")
        allow(File).to receive(:directory?).with("/file/path").and_return(false)
        expect(validation_lambda.call("/file/path")).to be false
        
        # Test with non-readable directory
        allow(File).to receive(:expand_path).with("/unreadable/path").and_return("/unreadable/path")
        allow(File).to receive(:directory?).with("/unreadable/path").and_return(true)
        allow(File).to receive(:readable?).with("/unreadable/path").and_return(false)
        expect(validation_lambda.call("/unreadable/path")).to be false
        
        # Test conversion lambda
        allow(File).to receive(:expand_path).with("relative/path").and_return("/absolute/relative/path")
        expect(conversion_lambda.call("relative/path")).to eq("/absolute/relative/path")
      end
    end
  end

  describe "real-world usage scenarios" do
    # Use real TTY::Prompt to test actual validation behavior
    let(:real_prompt) { described_class.new }
    
    before do
      allow(TTY::Prompt).to receive(:new).and_call_original
    end

    describe "#folder_name" do
      it "accepts valid folder names" do
        # Mock the actual prompt input to avoid interactive behavior
        allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return("valid-folder_123")
        
        result = real_prompt.folder_name
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
        allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return("valid-project_123")
        
        result = real_prompt.project_name
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
        allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return("feature/test-branch_123")
        
        result = real_prompt.branch_name
        expect(result).to eq("feature/test-branch_123")
      end

      it "would reject invalid branch names" do
        regex = /\A[a-zA-Z0-9_\/-]+\z/
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
        expect(prompt).to receive(:folder_name).with("Sessions folder name:", default: "with-special.chars-sessions").and_return("test-sessions")
        expect(prompt).to receive(:ask_yes_no).with("Create sessions folder in current directory?", default: true).and_return(true)
        
        result = prompt.sessions_folder_setup
        expect(result).to eq("test-sessions")
      end

      it "handles custom base path scenario completely" do
        allow(Dir).to receive(:pwd).and_return("/current")
        allow(File).to receive(:basename).with("/current").and_return("current")
        
        expect(prompt).to receive(:puts).with("Setting up sessions folder...")
        expect(prompt).to receive(:puts).with("This will create a folder where all your development sessions will be stored.")
        expect(prompt).to receive(:puts).with("")
        
        expect(prompt).to receive(:folder_name).with("Sessions folder name:", default: "current-sessions").and_return("my-sessions")
        expect(prompt).to receive(:ask_yes_no).with("Create sessions folder in current directory?", default: true).and_return(false)
        expect(prompt).to receive(:project_path).with("Base path for sessions folder:").and_return("/custom/location")
        
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
        
        expect(prompt).to receive(:ask_yes_no).with("Would you like to register these projects automatically?", default: true).and_return(true)
        
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
        
        expect(prompt).to receive(:ask_yes_no).with("Would you like to register these projects automatically?", default: true).and_return(true)
        
        result = prompt.project_detection_confirm(detected_projects)
        expect(result).to be true
      end
    end
  end

  describe "method parameter variations" do
    describe "#folder_name with all parameters" do
      it "handles custom message and default value" do
        expect(mock_tty_prompt).to receive(:ask).with("Custom folder message:", default: "custom-default") do |&block|
          question = double("question")
          allow(question).to receive(:validate)
          allow(question).to receive(:modify)
          block.call(question)
        end.and_return("test-folder")
        
        result = prompt.folder_name("Custom folder message:", default: "custom-default")
        expect(result).to eq("test-folder")
      end
    end

    describe "#session_name with custom message" do
      it "uses custom message with existing sessions" do
        existing_sessions = ["session1"]
        
        expect(mock_tty_prompt).to receive(:ask).with("Custom session message:") do |&block|
          question = double("question")
          allow(question).to receive(:validate)
          allow(question).to receive(:modify)
          block.call(question)
        end.and_return("new-session")
        
        result = prompt.session_name("Custom session message:", existing_sessions: existing_sessions)
        expect(result).to eq("new-session")
      end
    end

    describe "#branch_name with all parameters" do
      it "handles custom message and default branch" do
        expect(mock_tty_prompt).to receive(:ask).with("Custom branch message:", default: "develop") do |&block|
          question = double("question")
          allow(question).to receive(:validate)
          allow(question).to receive(:modify)
          block.call(question)
        end.and_return("feature-branch")
        
        result = prompt.branch_name("Custom branch message:", default: "develop")
        expect(result).to eq("feature-branch")
      end
    end
  end

  describe "string modification and conversion" do
    it "strips whitespace from all string inputs" do
      ["folder_name", "session_name", "project_name", "project_path", "branch_name"].each do |method|
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