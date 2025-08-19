# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::Prompt do
  let(:prompt) { described_class.new }
  let(:mock_tty_prompt) { instance_double(TTY::Prompt) }

  before do
    allow(TTY::Prompt).to receive(:new).and_return(mock_tty_prompt)
  end

  describe "#initialize" do
    it "creates TTY::Prompt with interrupt: :exit" do
      expect(TTY::Prompt).to receive(:new).with(interrupt: :exit)
      described_class.new
    end
  end

  describe "#ask" do
    it "delegates to TTY::Prompt#ask" do
      allow(mock_tty_prompt).to receive(:ask).with("Question?", {}).and_return("answer")
      
      result = prompt.ask("Question?")
      
      expect(result).to eq("answer")
      expect(mock_tty_prompt).to have_received(:ask).with("Question?", {})
    end

    it "passes options to TTY::Prompt#ask" do
      allow(mock_tty_prompt).to receive(:ask).with("Question?", { default: "default" }).and_return("answer")
      
      result = prompt.ask("Question?", default: "default")
      
      expect(result).to eq("answer")
      expect(mock_tty_prompt).to have_received(:ask).with("Question?", { default: "default" })
    end
  end

  describe "#ask_yes_no" do
    it "delegates to TTY::Prompt#yes? with default false" do
      allow(mock_tty_prompt).to receive(:yes?).with("Confirm?", default: false).and_return(true)
      
      result = prompt.ask_yes_no("Confirm?")
      
      expect(result).to be(true)
      expect(mock_tty_prompt).to have_received(:yes?).with("Confirm?", default: false)
    end

    it "accepts custom default" do
      allow(mock_tty_prompt).to receive(:yes?).with("Confirm?", default: true).and_return(false)
      
      result = prompt.ask_yes_no("Confirm?", default: true)
      
      expect(result).to be(false)
      expect(mock_tty_prompt).to have_received(:yes?).with("Confirm?", default: true)
    end
  end

  describe "#select" do
    it "delegates to TTY::Prompt#select" do
      choices = ["Option 1", "Option 2"]
      allow(mock_tty_prompt).to receive(:select).with("Choose:", choices, {}).and_return("Option 1")
      
      result = prompt.select("Choose:", choices)
      
      expect(result).to eq("Option 1")
      expect(mock_tty_prompt).to have_received(:select).with("Choose:", choices, {})
    end

    it "passes options to TTY::Prompt#select" do
      choices = ["Option 1", "Option 2"]
      options = { per_page: 5 }
      allow(mock_tty_prompt).to receive(:select).with("Choose:", choices, options).and_return("Option 1")
      
      result = prompt.select("Choose:", choices, **options)
      
      expect(result).to eq("Option 1")
      expect(mock_tty_prompt).to have_received(:select).with("Choose:", choices, options)
    end
  end

  describe "#multi_select" do
    it "delegates to TTY::Prompt#multi_select" do
      choices = ["Option 1", "Option 2"]
      allow(mock_tty_prompt).to receive(:multi_select).with("Choose:", choices, {}).and_return(["Option 1"])
      
      result = prompt.multi_select("Choose:", choices)
      
      expect(result).to eq(["Option 1"])
      expect(mock_tty_prompt).to have_received(:multi_select).with("Choose:", choices, {})
    end
  end

  describe "#folder_name" do
    it "asks for folder name with validation" do
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Enter sessions folder name:", 
        default: nil
      ).and_yield(question_object).and_return("valid-folder")
      
      result = prompt.folder_name
      
      expect(result).to eq("valid-folder")
      expect(question_object).to have_received(:validate).with(
        /\A[a-zA-Z0-9_-]+\z/, 
        "Folder name must contain only letters, numbers, hyphens, and underscores"
      )
      expect(question_object).to have_received(:modify).with(:strip)
    end

    it "accepts custom message and default" do
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Custom message:", 
        default: "default-folder"
      ).and_yield(question_object).and_return("custom-folder")
      
      result = prompt.folder_name("Custom message:", default: "default-folder")
      
      expect(result).to eq("custom-folder")
    end
  end

  describe "#session_name" do
    it "asks for session name with validation" do
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Enter session name:"
      ).and_yield(question_object).and_return("valid-session")
      
      result = prompt.session_name
      
      expect(result).to eq("valid-session")
      expect(question_object).to have_received(:validate).with(
        /\A[a-zA-Z0-9_-]+\z/, 
        "Session name must contain only letters, numbers, hyphens, and underscores"
      )
      expect(question_object).to have_received(:modify).with(:strip)
    end

    it "validates against existing sessions" do
      existing_sessions = ["session1", "session2"]
      question_object = double("Question")
      allow(question_object).to receive(:validate).twice
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Enter session name:"
      ).and_yield(question_object).and_return("new-session")
      
      result = prompt.session_name(existing_sessions: existing_sessions)
      
      expect(result).to eq("new-session")
      
      # Check that the lambda validator was called
      expect(question_object).to have_received(:validate).with(
        anything, "Session name already exists"
      )
    end
  end

  describe "#project_name" do
    it "asks for project name with validation" do
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Enter project name:"
      ).and_yield(question_object).and_return("valid-project")
      
      result = prompt.project_name
      
      expect(result).to eq("valid-project")
      expect(question_object).to have_received(:validate).with(
        /\A[a-zA-Z0-9_-]+\z/, 
        "Project name must contain only letters, numbers, hyphens, and underscores"
      )
      expect(question_object).to have_received(:modify).with(:strip)
    end
  end

  describe "#project_path" do
    it "asks for project path with validation and conversion" do
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      allow(question_object).to receive(:convert)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Enter project path:"
      ).and_yield(question_object).and_return("/expanded/path")
      
      result = prompt.project_path
      
      expect(result).to eq("/expanded/path")
      expect(question_object).to have_received(:validate).with(
        anything, "Path must be a readable directory"
      )
      expect(question_object).to have_received(:modify).with(:strip)
      expect(question_object).to have_received(:convert)
    end
  end

  describe "#branch_name" do
    it "asks for branch name with validation" do
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Enter branch name:", 
        default: nil
      ).and_yield(question_object).and_return("feature/branch")
      
      result = prompt.branch_name
      
      expect(result).to eq("feature/branch")
      expect(question_object).to have_received(:validate).with(
        /\A[a-zA-Z0-9_\/-]+\z/, 
        "Branch name must be a valid git branch name"
      )
      expect(question_object).to have_received(:modify).with(:strip)
    end

    it "accepts custom message and default" do
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Custom branch message:", 
        default: "main"
      ).and_yield(question_object).and_return("main")
      
      result = prompt.branch_name("Custom branch message:", default: "main")
      
      expect(result).to eq("main")
    end
  end

  describe "#confirm_deletion" do
    it "asks for deletion confirmation with default false" do
      allow(mock_tty_prompt).to receive(:yes?).with(
        "Are you sure you want to delete item 'test-item'? This action cannot be undone.",
        default: false
      ).and_return(true)
      
      result = prompt.confirm_deletion("test-item")
      
      expect(result).to be(true)
    end

    it "accepts custom item type" do
      allow(mock_tty_prompt).to receive(:yes?).with(
        "Are you sure you want to delete project 'test-project'? This action cannot be undone.",
        default: false
      ).and_return(false)
      
      result = prompt.confirm_deletion("test-project", "project")
      
      expect(result).to be(false)
    end
  end

  describe "#rule_type" do
    it "prompts for rule type selection" do
      expected_choices = [
        { name: "Copy Files", value: "copy_files" },
        { name: "Setup Commands", value: "setup_commands" },
        { name: "Template", value: "template" }
      ]
      
      allow(mock_tty_prompt).to receive(:select).with(
        "Select rule type:", expected_choices
      ).and_return("copy_files")
      
      result = prompt.rule_type
      
      expect(result).to eq("copy_files")
    end
  end

  describe "#sessions_folder_setup" do
    it "guides through sessions folder setup" do
      allow(Dir).to receive(:pwd).and_return("/current/dir")
      
      # Mock the folder_name prompt
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Sessions folder name:", 
        default: "dir-sessions"
      ).and_yield(question_object).and_return("my-sessions")
      
      # Mock the confirmation prompt
      allow(mock_tty_prompt).to receive(:yes?).with(
        "Create sessions folder in current directory?",
        default: true
      ).and_return(true)
      
      expect {
        result = prompt.sessions_folder_setup
        expect(result).to eq("my-sessions")
      }.to output(/Setting up sessions folder/).to_stdout
    end

    it "prompts for custom base path when not using current directory" do
      allow(Dir).to receive(:pwd).and_return("/current/dir")
      
      # Mock the folder_name prompt
      question_object = double("Question")
      allow(question_object).to receive(:validate)
      allow(question_object).to receive(:modify)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Sessions folder name:", 
        default: "dir-sessions"
      ).and_yield(question_object).and_return("custom-sessions")
      
      # Mock the confirmation prompt (user says no to current directory)
      allow(mock_tty_prompt).to receive(:yes?).with(
        "Create sessions folder in current directory?",
        default: true
      ).and_return(false)
      
      # Mock the path validation for base path
      path_question = double("PathQuestion")
      allow(path_question).to receive(:validate)
      allow(path_question).to receive(:modify)
      allow(path_question).to receive(:convert)
      
      allow(mock_tty_prompt).to receive(:ask).with(
        "Base path for sessions folder:"
      ).and_yield(path_question).and_return("/custom/base")
      
      result = prompt.sessions_folder_setup
      
      expect(result).to eq("/custom/base/custom-sessions")
    end
  end

  describe "#project_detection_confirm" do
    it "returns false for empty project list" do
      result = prompt.project_detection_confirm([])
      expect(result).to be(false)
    end

    it "displays detected projects and asks for confirmation" do
      detected_projects = [
        { name: "project1", type: "rails", path: "/path/1" },
        { name: "project2", type: "javascript", path: "/path/2" }
      ]
      
      allow(mock_tty_prompt).to receive(:yes?).with(
        "Would you like to register these projects automatically?",
        default: true
      ).and_return(true)
      
      expect {
        result = prompt.project_detection_confirm(detected_projects)
        expect(result).to be(true)
      }.to output(/Detected projects.*project1.*project2/m).to_stdout
    end

    it "returns user's choice" do
      detected_projects = [
        { name: "project1", type: "rails", path: "/path/1" }
      ]
      
      allow(mock_tty_prompt).to receive(:yes?).and_return(false)
      
      expect {
        result = prompt.project_detection_confirm(detected_projects)
        expect(result).to be(false)
      }.to output.to_stdout
    end
  end

  # Test validation lambdas
  describe "validation logic" do
    describe "session name uniqueness validation" do
      it "rejects existing session names" do
        existing_sessions = ["session1", "session2"]
        question_object = double("Question")
        
        # Capture the lambda validator
        validation_lambda = nil
        allow(question_object).to receive(:validate) do |arg, _message|
          validation_lambda = arg if arg.is_a?(Proc)
        end
        allow(question_object).to receive(:modify)
        
        allow(mock_tty_prompt).to receive(:ask).and_yield(question_object)
        
        prompt.session_name(existing_sessions: existing_sessions)
        
        # Test the captured lambda
        expect(validation_lambda.call("session1")).to be(false)
        expect(validation_lambda.call("session3")).to be(true)
      end
    end

    describe "project path validation" do
      it "validates directory existence and readability" do
        question_object = double("Question")
        
        # Capture the lambda validator
        validation_lambda = nil
        allow(question_object).to receive(:validate) do |arg, _message|
          validation_lambda = arg if arg.is_a?(Proc)
        end
        allow(question_object).to receive(:modify)
        allow(question_object).to receive(:convert)
        
        allow(mock_tty_prompt).to receive(:ask).and_yield(question_object)
        
        prompt.project_path
        
        # Mock File methods for testing
        allow(File).to receive(:expand_path).with("/valid/path").and_return("/valid/path")
        allow(File).to receive(:directory?).with("/valid/path").and_return(true)
        allow(File).to receive(:readable?).with("/valid/path").and_return(true)
        
        allow(File).to receive(:expand_path).with("/invalid/path").and_return("/invalid/path")
        allow(File).to receive(:directory?).with("/invalid/path").and_return(false)
        
        # Test the captured lambda
        expect(validation_lambda.call("/valid/path")).to be(true)
        expect(validation_lambda.call("/invalid/path")).to be(false)
      end
    end
  end
end