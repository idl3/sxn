# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::ProgressBar do
  let(:mock_tty_progress) { instance_double(TTY::ProgressBar) }

  before do
    allow(TTY::ProgressBar).to receive(:new).and_return(mock_tty_progress)
    allow(mock_tty_progress).to receive(:advance)
    allow(mock_tty_progress).to receive(:finish)
    allow(mock_tty_progress).to receive(:current).and_return(5)
    allow(mock_tty_progress).to receive(:total).and_return(10)
    allow(mock_tty_progress).to receive(:percent).and_return(50)
    allow(mock_tty_progress).to receive(:log)
  end

  describe "#initialize" do
    it "creates TTY::ProgressBar with classic format by default" do
      expect(TTY::ProgressBar).to receive(:new).with(
        "Processing [:bar] :percent :elapsed",
        total: 100,
        clear: true
      )

      described_class.new("Processing")
    end

    it "creates TTY::ProgressBar with detailed format" do
      expect(TTY::ProgressBar).to receive(:new).with(
        "Loading [:bar] :current/:total (:percent) :elapsed ETA: :eta",
        total: 50,
        clear: true
      )

      described_class.new("Loading", total: 50, format: :detailed)
    end

    it "creates TTY::ProgressBar with simple format" do
      expect(TTY::ProgressBar).to receive(:new).with(
        "Uploading :percent",
        total: 100,
        clear: true
      )

      described_class.new("Uploading", format: :simple)
    end

    it "creates TTY::ProgressBar with custom format" do
      expect(TTY::ProgressBar).to receive(:new).with(
        "Custom",
        total: 100,
        clear: true
      )

      described_class.new("Custom", format: :custom)
    end

    it "accepts custom total" do
      expect(TTY::ProgressBar).to receive(:new).with(
        anything,
        total: 25,
        clear: true
      )

      described_class.new("Test", total: 25)
    end
  end

  describe "#advance" do
    let(:progress_bar) { described_class.new("Test") }

    it "advances the progress bar by 1 step by default" do
      progress_bar.advance

      expect(mock_tty_progress).to have_received(:advance).with(1)
    end

    it "advances the progress bar by custom step" do
      progress_bar.advance(5)

      expect(mock_tty_progress).to have_received(:advance).with(5)
    end
  end

  describe "#finish" do
    let(:progress_bar) { described_class.new("Test") }

    it "finishes the progress bar" do
      progress_bar.finish

      expect(mock_tty_progress).to have_received(:finish)
    end
  end

  describe "#current" do
    let(:progress_bar) { described_class.new("Test") }

    it "returns current progress" do
      result = progress_bar.current

      expect(result).to eq(5)
      expect(mock_tty_progress).to have_received(:current)
    end
  end

  describe "#total" do
    let(:progress_bar) { described_class.new("Test") }

    it "returns total steps" do
      result = progress_bar.total

      expect(result).to eq(10)
      expect(mock_tty_progress).to have_received(:total)
    end
  end

  describe "#percent" do
    let(:progress_bar) { described_class.new("Test") }

    it "returns completion percentage" do
      result = progress_bar.percent

      expect(result).to eq(50)
      expect(mock_tty_progress).to have_received(:percent)
    end
  end

  describe "#log" do
    let(:progress_bar) { described_class.new("Test") }

    it "logs a message" do
      progress_bar.log("Processing item 1")

      expect(mock_tty_progress).to have_received(:log).with("Processing item 1")
    end
  end

  describe ".with_progress" do
    let(:items) { ["item1", "item2", "item3"] }
    let(:progress_bar_instance) { instance_double(described_class) }

    before do
      allow(described_class).to receive(:new).and_return(progress_bar_instance)
      allow(progress_bar_instance).to receive(:advance)
      allow(progress_bar_instance).to receive(:finish)
    end

    it "creates progress bar with correct parameters" do
      expect(described_class).to receive(:new).with(
        "Processing items",
        total: 3,
        format: :classic
      )

      described_class.with_progress("Processing items", items) { |item, progress| item.upcase }
    end

    it "processes each item and collects results" do
      results = described_class.with_progress("Processing", items) do |item, progress|
        item.upcase
      end

      expect(results).to eq(["ITEM1", "ITEM2", "ITEM3"])
    end

    it "advances progress bar for each item" do
      described_class.with_progress("Processing", items) { |item, progress| item }

      expect(progress_bar_instance).to have_received(:advance).exactly(3).times
    end

    it "finishes progress bar after processing all items" do
      described_class.with_progress("Processing", items) { |item, progress| item }

      expect(progress_bar_instance).to have_received(:finish)
    end

    it "passes progress bar instance to block" do
      described_class.with_progress("Processing", items) do |item, progress|
        expect(progress).to eq(progress_bar_instance)
        item
      end
    end

    it "accepts custom format" do
      expect(described_class).to receive(:new).with(
        "Processing",
        total: 3,
        format: :detailed
      )

      described_class.with_progress("Processing", items, format: :detailed) { |item, progress| item }
    end

    it "returns empty array for empty items" do
      results = described_class.with_progress("Processing", []) { |item, progress| item }

      expect(results).to eq([])
      expect(described_class).not_to have_received(:new)
    end
  end

  describe ".for_operation" do
    let(:progress_bar_instance) { instance_double(described_class) }
    let(:stepper_instance) { instance_double(described_class::Stepper) }

    before do
      allow(described_class).to receive(:new).and_return(progress_bar_instance)
      allow(described_class::Stepper).to receive(:new).and_return(stepper_instance)
      allow(progress_bar_instance).to receive(:finish)
    end

    it "creates progress bar with detailed format and default steps" do
      expect(described_class).to receive(:new).with(
        "Operation",
        total: 5,
        format: :detailed
      )

      described_class.for_operation("Operation") { |stepper| "result" }
    end

    it "accepts custom total steps" do
      expect(described_class).to receive(:new).with(
        "Custom operation",
        total: 10,
        format: :detailed
      )

      described_class.for_operation("Custom operation", total_steps: 10) { |stepper| "result" }
    end

    it "creates stepper with progress bar" do
      expect(described_class::Stepper).to receive(:new).with(progress_bar_instance)

      described_class.for_operation("Operation") { |stepper| "result" }
    end

    it "passes stepper to block and returns result" do
      result = described_class.for_operation("Operation") do |stepper|
        expect(stepper).to eq(stepper_instance)
        "operation_result"
      end

      expect(result).to eq("operation_result")
    end

    it "finishes progress bar after operation" do
      described_class.for_operation("Operation") { |stepper| "result" }

      expect(progress_bar_instance).to have_received(:finish)
    end
  end

  describe described_class::Stepper do
    let(:mock_progress) { instance_double(described_class) }
    let(:stepper) { described_class::Stepper.new(mock_progress) }

    before do
      allow(mock_progress).to receive(:log)
      allow(mock_progress).to receive(:advance)
    end

    describe "#initialize" do
      it "stores progress bar reference" do
        stepper = described_class::Stepper.new(mock_progress)
        expect(stepper.instance_variable_get(:@progress)).to eq(mock_progress)
      end
    end

    describe "#step" do
      it "advances progress without message" do
        stepper.step

        expect(mock_progress).to have_received(:advance)
        expect(mock_progress).not_to have_received(:log)
      end

      it "logs message and advances progress" do
        stepper.step("Completed step 1")

        expect(mock_progress).to have_received(:log).with("Completed step 1")
        expect(mock_progress).to have_received(:advance)
      end
    end

    describe "#log" do
      it "logs message to progress bar" do
        stepper.log("Status update")

        expect(mock_progress).to have_received(:log).with("Status update")
      end
    end
  end

  describe "integration behavior" do
    it "creates functional progress bar for real operations" do
      # This test verifies the actual flow without mocking TTY::ProgressBar
      allow(TTY::ProgressBar).to receive(:new).and_call_original
      
      items = ["a", "b", "c"]
      results = []
      
      # Capture output to avoid cluttering test output
      expect {
        results = described_class.with_progress("Test", items) do |item, progress|
          progress.log("Processing #{item}")
          item.upcase
        end
      }.not_to raise_error
      
      expect(results).to eq(["A", "B", "C"])
    end

    it "creates functional stepper for operations" do
      allow(TTY::ProgressBar).to receive(:new).and_call_original
      
      result = nil
      
      expect {
        result = described_class.for_operation("Test operation", total_steps: 3) do |stepper|
          stepper.step("Step 1")
          stepper.step("Step 2")
          stepper.log("Almost done")
          stepper.step("Step 3")
          "completed"
        end
      }.not_to raise_error
      
      expect(result).to eq("completed")
    end
  end
end