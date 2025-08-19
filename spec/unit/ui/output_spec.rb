# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::Output do
  let(:ui_output) { described_class.new }
  let(:mock_pastel) { double("Pastel") }

  before do
    allow(Pastel).to receive(:new).and_return(mock_pastel)
    allow(mock_pastel).to receive(:green) { |text| "GREEN[#{text}]" }
    allow(mock_pastel).to receive(:red) { |text| "RED[#{text}]" }
    allow(mock_pastel).to receive(:yellow) { |text| "YELLOW[#{text}]" }
    allow(mock_pastel).to receive(:blue) { |text| "BLUE[#{text}]" }
    allow(mock_pastel).to receive(:cyan) { |text| "CYAN[#{text}]" }
    allow(mock_pastel).to receive(:dim) { |text| "DIM[#{text}]" }
    allow(mock_pastel).to receive(:bold) { |text| "BOLD[#{text}]" }
    allow(mock_pastel).to receive(:public_send) { |color, text| "#{color.upcase}[#{text}]" }
  end

  describe "#success" do
    it "outputs green success message with checkmark" do
      expect { ui_output.success("Operation completed") }.to output("GREEN[✅ Operation completed]\n").to_stdout
      expect(mock_pastel).to have_received(:green).with("✅ Operation completed")
    end
  end

  describe "#error" do
    it "outputs red error message with X mark" do
      expect { ui_output.error("Something went wrong") }.to output("RED[❌ Something went wrong]\n").to_stdout
      expect(mock_pastel).to have_received(:red).with("❌ Something went wrong")
    end
  end

  describe "#warning" do
    it "outputs yellow warning message with warning icon" do
      expect { ui_output.warning("Be careful") }.to output("YELLOW[⚠️  Be careful]\n").to_stdout
      expect(mock_pastel).to have_received(:yellow).with("⚠️  Be careful")
    end
  end

  describe "#info" do
    it "outputs blue info message with info icon" do
      expect { ui_output.info("Information here") }.to output("BLUE[ℹ️  Information here]\n").to_stdout
      expect(mock_pastel).to have_received(:blue).with("ℹ️  Information here")
    end
  end

  describe "#debug" do
    context "when debug mode is enabled" do
      before { allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("true") }

      it "outputs dim debug message with magnifying glass" do
        expect { ui_output.debug("Debug info") }.to output("DIM[🔍 Debug info]\n").to_stdout
        expect(mock_pastel).to have_received(:dim).with("🔍 Debug info")
      end
    end

    context "when debug mode is disabled" do
      before { allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("false") }

      it "does not output anything" do
        expect { ui_output.debug("Debug info") }.not_to output.to_stdout
      end
    end

    context "when debug mode is not set" do
      before { allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return(nil) }

      it "does not output anything" do
        expect { ui_output.debug("Debug info") }.not_to output.to_stdout
      end
    end
  end

  describe "#status" do
    it "outputs status with default blue color" do
      expect { ui_output.status("info", "Processing") }.to output("BLUE[[INFO]] Processing\n").to_stdout
      expect(mock_pastel).to have_received(:public_send).with(:blue, "[INFO]")
    end

    it "outputs status with custom color" do
      expect { ui_output.status("success", "Done", :green) }.to output("GREEN[[SUCCESS]] Done\n").to_stdout
      expect(mock_pastel).to have_received(:public_send).with(:green, "[SUCCESS]")
    end
  end

  describe "#section" do
    it "outputs section header with decorative borders" do
      expect do
        ui_output.section("Test Section")
      end.to output(/BOLD\[CYAN\[.*Test Section.*\]\]/m).to_stdout

      expect(mock_pastel).to have_received(:cyan).with("═" * 60).twice
      expect(mock_pastel).to have_received(:cyan).with("  Test Section")
      expect(mock_pastel).to have_received(:bold).exactly(3).times
    end
  end

  describe "#subsection" do
    it "outputs subsection with underline" do
      expect do
        ui_output.subsection("Subsection Title")
      end.to output(/BOLD.*DIM/m).to_stdout

      expect(mock_pastel).to have_received(:bold).with("Subsection Title")
      expect(mock_pastel).to have_received(:dim).with("─" * "Subsection Title".length)
    end
  end

  describe "#list_item" do
    it "outputs simple list item" do
      expect { ui_output.list_item("Item 1") }.to output("  • Item 1\n").to_stdout
    end

    it "outputs list item with description" do
      allow(mock_pastel).to receive(:bold).with("Item").and_return("BOLD_ITEM")

      expect { ui_output.list_item("Item", "Description") }.to output("  • BOLD_ITEM - Description\n").to_stdout
      expect(mock_pastel).to have_received(:bold).with("Item")
    end
  end

  describe "#empty_state" do
    it "outputs dimmed empty state message" do
      expect { ui_output.empty_state("No items found") }.to output("DIM[  No items found]\n").to_stdout
      expect(mock_pastel).to have_received(:dim).with("  No items found")
    end
  end

  describe "#key_value" do
    it "outputs key-value pair with default indentation" do
      allow(mock_pastel).to receive(:bold).with("Key").and_return("BOLD_KEY")

      expect { ui_output.key_value("Key", "Value") }.to output("BOLD_KEY: Value\n").to_stdout
      expect(mock_pastel).to have_received(:bold).with("Key")
    end

    it "outputs key-value pair with custom indentation" do
      allow(mock_pastel).to receive(:bold).with("Key").and_return("BOLD_KEY")

      expect { ui_output.key_value("Key", "Value", indent: 4) }.to output("    BOLD_KEY: Value\n").to_stdout
    end
  end

  describe "#progress_start" do
    it "outputs progress start message without newline" do
      expect { ui_output.progress_start("Loading") }.to output("Loading... ").to_stdout
    end
  end

  describe "#progress_done" do
    it "outputs green checkmark" do
      expect { ui_output.progress_done }.to output("GREEN[✅]\n").to_stdout
      expect(mock_pastel).to have_received(:green).with("✅")
    end
  end

  describe "#progress_failed" do
    it "outputs red X mark" do
      expect { ui_output.progress_failed }.to output("RED[❌]\n").to_stdout
      expect(mock_pastel).to have_received(:red).with("❌")
    end
  end

  describe "#newline" do
    it "outputs empty line" do
      expect { ui_output.newline }.to output("\n").to_stdout
    end
  end

  describe "#recovery_suggestion" do
    it "outputs suggestion with lightbulb icon" do
      expect do
        ui_output.recovery_suggestion("Try this solution")
      end.to output(/YELLOW/).to_stdout

      expect(mock_pastel).to have_received(:yellow).with("💡 Suggestion: Try this solution")
    end
  end

  describe "#command_example" do
    it "outputs command without description" do
      allow(mock_pastel).to receive(:cyan).with("$ sxn init").and_return("CYAN_COMMAND")

      expect do
        ui_output.command_example("sxn init")
      end.to output("  CYAN_COMMAND\n\n").to_stdout
    end

    it "outputs command with description" do
      allow(mock_pastel).to receive(:cyan).with("$ sxn init").and_return("CYAN_COMMAND")
      allow(mock_pastel).to receive(:dim).with("Initialize sxn").and_return("DIM_DESC")

      expect do
        ui_output.command_example("sxn init", "Initialize sxn")
      end.to output("  DIM_DESC\n  CYAN_COMMAND\n\n").to_stdout
    end
  end

  describe "private methods" do
    describe "#debug_mode?" do
      it "returns true when SXN_DEBUG is 'true'" do
        allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("true")
        expect(ui_output.send(:debug_mode?)).to be(true)
      end

      it "returns false when SXN_DEBUG is 'false'" do
        allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("false")
        expect(ui_output.send(:debug_mode?)).to be(false)
      end

      it "returns false when SXN_DEBUG is not set" do
        allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return(nil)
        expect(ui_output.send(:debug_mode?)).to be(false)
      end

      it "returns false when SXN_DEBUG is any other value" do
        allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("1")
        expect(ui_output.send(:debug_mode?)).to be(false)
      end
    end
  end
end
