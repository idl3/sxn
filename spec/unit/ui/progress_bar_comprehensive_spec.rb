# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::ProgressBar, "comprehensive coverage for missing areas" do
  let(:mock_tty_progress) { instance_double(TTY::ProgressBar) }

  before do
    allow(TTY::ProgressBar).to receive(:new).and_return(mock_tty_progress)
    allow(mock_tty_progress).to receive(:advance)
    allow(mock_tty_progress).to receive(:finish)
    allow(mock_tty_progress).to receive(:current).and_return(50)
    allow(mock_tty_progress).to receive(:total).and_return(100)
    allow(mock_tty_progress).to receive(:percent).and_return(50.0)
    allow(mock_tty_progress).to receive(:log)
  end

  describe "#initialize" do
    context "with different format options" do
      it "creates classic format progress bar" do
        expected_format = "Test Progress [:bar] :percent :elapsed"
        expect(TTY::ProgressBar).to receive(:new).with(expected_format, total: 100, clear: true).and_return(mock_tty_progress)
        
        described_class.new("Test Progress", total: 100, format: :classic)
      end

      it "creates detailed format progress bar" do
        expected_format = "Detailed Progress [:bar] :current/:total (:percent) :elapsed ETA: :eta"
        expect(TTY::ProgressBar).to receive(:new).with(expected_format, total: 50, clear: true).and_return(mock_tty_progress)
        
        described_class.new("Detailed Progress", total: 50, format: :detailed)
      end

      it "creates simple format progress bar" do
        expected_format = "Simple Progress :percent"
        expect(TTY::ProgressBar).to receive(:new).with(expected_format, total: 200, clear: true).and_return(mock_tty_progress)
        
        described_class.new("Simple Progress", total: 200, format: :simple)
      end

      it "uses title as format for unknown format types" do
        expected_format = "Unknown Format"
        expect(TTY::ProgressBar).to receive(:new).with(expected_format, total: 100, clear: true).and_return(mock_tty_progress)
        
        described_class.new("Unknown Format", total: 100, format: :unknown)
      end

      it "defaults to classic format when no format specified" do
        expected_format = "Default [:bar] :percent :elapsed"
        expect(TTY::ProgressBar).to receive(:new).with(expected_format, total: 100, clear: true)
        
        described_class.new("Default")
      end
    end
  end

  describe "instance methods delegation" do
    let(:progress_bar) { described_class.new("Test") }

    describe "#advance" do
      it "advances by 1 step by default" do
        expect(mock_tty_progress).to receive(:advance).with(1)
        progress_bar.advance
      end

      it "advances by specified step" do
        expect(mock_tty_progress).to receive(:advance).with(5)
        progress_bar.advance(5)
      end
    end

    describe "#finish" do
      it "finishes the progress bar" do
        expect(mock_tty_progress).to receive(:finish)
        progress_bar.finish
      end
    end

    describe "#current" do
      it "returns current progress" do
        expect(progress_bar.current).to eq(50)
      end
    end

    describe "#total" do
      it "returns total progress" do
        expect(progress_bar.total).to eq(100)
      end
    end

    describe "#percent" do
      it "returns completion percentage" do
        expect(progress_bar.percent).to eq(50.0)
      end
    end

    describe "#log" do
      it "logs a message" do
        expect(mock_tty_progress).to receive(:log).with("Test message")
        progress_bar.log("Test message")
      end
    end
  end

  describe ".with_progress class method" do
    it "returns empty array for empty items" do
      result = described_class.with_progress("Test", [])
      expect(result).to eq([])
    end

    it "processes items with progress tracking" do
      items = ["item1", "item2", "item3"]
      expected_results = ["result1", "result2", "result3"]
      
      expect(described_class).to receive(:new).with("Processing", total: 3, format: :classic).and_return(mock_tty_progress)
      expect(mock_tty_progress).to receive(:advance).exactly(3).times
      expect(mock_tty_progress).to receive(:finish)
      
      results = described_class.with_progress("Processing", items) do |item, progress|
        expect(progress).to eq(mock_tty_progress)
        case item
        when "item1" then "result1"
        when "item2" then "result2"
        when "item3" then "result3"
        end
      end
      
      expect(results).to eq(expected_results)
    end

    it "accepts custom format for processing" do
      items = ["item1"]
      
      expect(described_class).to receive(:new).with("Custom", total: 1, format: :detailed).and_return(mock_tty_progress)
      
      described_class.with_progress("Custom", items, format: :detailed) do |item, progress|
        "result"
      end
    end

    it "passes progress bar instance to block" do
      items = ["test"]
      progress_instance = nil
      
      expect(described_class).to receive(:new).and_return(mock_tty_progress)
      
      described_class.with_progress("Test", items) do |item, progress|
        progress_instance = progress
        "result"
      end
      
      expect(progress_instance).to eq(mock_tty_progress)
    end
  end

  describe ".for_operation class method" do
    it "creates progress bar for step-by-step operations" do
      expect(described_class).to receive(:new).with("Operation", total: 5, format: :detailed).and_return(mock_tty_progress)
      expect(mock_tty_progress).to receive(:finish)
      
      result = described_class.for_operation("Operation") do |stepper|
        expect(stepper).to be_a(described_class::Stepper)
        "operation_result"
      end
      
      expect(result).to eq("operation_result")
    end

    it "accepts custom total steps" do
      expect(described_class).to receive(:new).with("Custom Operation", total: 10, format: :detailed).and_return(mock_tty_progress)
      expect(mock_tty_progress).to receive(:finish)
      
      described_class.for_operation("Custom Operation", total_steps: 10) do |stepper|
        "result"
      end
    end

    it "passes stepper instance to block" do
      stepper_instance = nil
      
      expect(described_class).to receive(:new).and_return(mock_tty_progress)
      
      described_class.for_operation("Test") do |stepper|
        stepper_instance = stepper
        "result"
      end
      
      expect(stepper_instance).to be_a(described_class::Stepper)
    end
  end

  describe "Stepper class" do
    let(:stepper) { described_class::Stepper.new(mock_tty_progress) }

    describe "#initialize" do
      it "stores the progress bar reference" do
        expect(stepper.instance_variable_get(:@progress)).to eq(mock_tty_progress)
      end
    end

    describe "#step" do
      it "advances progress without message" do
        expect(mock_tty_progress).to receive(:advance)
        expect(mock_tty_progress).not_to receive(:log)
        
        stepper.step
      end

      it "logs message and advances progress" do
        expect(mock_tty_progress).to receive(:log).with("Step message")
        expect(mock_tty_progress).to receive(:advance)
        
        stepper.step("Step message")
      end

      it "handles nil message gracefully" do
        expect(mock_tty_progress).to receive(:advance)
        expect(mock_tty_progress).not_to receive(:log)
        
        stepper.step(nil)
      end
    end

    describe "#log" do
      it "logs message to progress bar" do
        expect(mock_tty_progress).to receive(:log).with("Log message")
        stepper.log("Log message")
      end
    end
  end

  describe "integration scenarios" do
    it "handles complete workflow with real progress tracking" do
      items = (1..3).to_a
      step_count = 0
      
      # Mock the progress bar creation and interactions
      progress_bar = instance_double(TTY::ProgressBar)
      allow(TTY::ProgressBar).to receive(:new).and_return(progress_bar)
      allow(progress_bar).to receive(:advance) { step_count += 1 }
      allow(progress_bar).to receive(:finish)
      
      results = described_class.with_progress("Processing Items", items) do |item, progress|
        item * 2
      end
      
      expect(results).to eq([2, 4, 6])
      expect(step_count).to eq(3)
    end

    it "handles step-by-step operation workflow" do
      steps_taken = []
      
      progress_bar = instance_double(TTY::ProgressBar)
      allow(TTY::ProgressBar).to receive(:new).and_return(progress_bar)
      allow(progress_bar).to receive(:log) { |msg| steps_taken << msg if msg }
      allow(progress_bar).to receive(:advance)
      allow(progress_bar).to receive(:finish)
      
      result = described_class.for_operation("Complex Operation", total_steps: 3) do |stepper|
        stepper.step("Initializing")
        stepper.step("Processing")
        stepper.step("Finalizing")
        "completed"
      end
      
      expect(result).to eq("completed")
      expect(steps_taken).to eq(["Initializing", "Processing", "Finalizing"])
    end
  end

  describe "edge cases and error handling" do
    it "handles zero items gracefully" do
      result = described_class.with_progress("Empty", [])
      expect(result).to eq([])
    end

    it "handles single item processing" do
      items = ["single"]
      
      expect(described_class).to receive(:new).with("Single", total: 1, format: :classic).and_return(mock_tty_progress)
      
      result = described_class.with_progress("Single", items) do |item, progress|
        "processed_#{item}"
      end
      
      expect(result).to eq(["processed_single"])
    end

    it "maintains progress bar reference in stepper" do
      stepper = described_class::Stepper.new(mock_tty_progress)
      
      # Test that stepper maintains the progress bar reference
      expect(stepper.instance_variable_get(:@progress)).to be(mock_tty_progress)
      
      # Test that operations still work through the reference
      expect(mock_tty_progress).to receive(:log).with("test")
      stepper.log("test")
    end
  end

  describe "format string generation edge cases" do
    it "handles empty title" do
      expect(TTY::ProgressBar).to receive(:new).with(" [:bar] :percent :elapsed", total: 100, clear: true)
      described_class.new("", format: :classic)
    end

    it "handles title with special characters" do
      title = "Progress [100%] :test:"
      expected_format = "#{title} [:bar] :percent :elapsed"
      expect(TTY::ProgressBar).to receive(:new).with(expected_format, total: 100, clear: true)
      described_class.new(title, format: :classic)
    end

    it "uses numeric format as unknown format" do
      expect(TTY::ProgressBar).to receive(:new).with("Numeric Format", total: 100, clear: true)
      described_class.new("Numeric Format", format: 123)
    end
  end
end