# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::Output do
  let(:output) { described_class.new }
  let(:mock_pastel) { instance_double(Pastel) }

  before do
    allow(Pastel).to receive(:new).and_return(mock_pastel)
    allow(mock_pastel).to receive(:green).and_return("GREEN")
    allow(mock_pastel).to receive(:red).and_return("RED")
    allow(mock_pastel).to receive(:yellow).and_return("YELLOW")
    allow(mock_pastel).to receive(:blue).and_return("BLUE")
    allow(mock_pastel).to receive(:cyan).and_return("CYAN")
    allow(mock_pastel).to receive(:dim).and_return("DIM")
    allow(mock_pastel).to receive(:bold).and_return("BOLD")
    allow(mock_pastel).to receive(:public_send).and_return("COLORED")
  end

  describe "#success" do
    it "outputs green success message with checkmark" do
      expect { output.success("Operation completed") }.to output("GREEN\n").to_stdout
      expect(mock_pastel).to have_received(:green).with("✅ Operation completed")
    end
  end

  describe "#error" do
    it "outputs red error message with X mark" do
      expect { output.error("Something went wrong") }.to output("RED\n").to_stdout
      expect(mock_pastel).to have_received(:red).with("❌ Something went wrong")
    end
  end

  describe "#warning" do
    it "outputs yellow warning message with warning icon" do
      expect { output.warning("Be careful") }.to output("YELLOW\n").to_stdout
      expect(mock_pastel).to have_received(:yellow).with("⚠️  Be careful")
    end
  end

  describe "#info" do
    it "outputs blue info message with info icon" do
      expect { output.info("Information here") }.to output("BLUE\n").to_stdout
      expect(mock_pastel).to have_received(:blue).with("ℹ️  Information here")
    end
  end

  describe "#debug" do
    context "when debug mode is enabled" do
      before { allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("true") }

      it "outputs dim debug message with magnifying glass" do
        expect { output.debug("Debug info") }.to output("DIM\n").to_stdout
        expect(mock_pastel).to have_received(:dim).with("🔍 Debug info")
      end
    end

    context "when debug mode is disabled" do
      before { allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("false") }

      it "does not output anything" do
        expect { output.debug("Debug info") }.not_to output.to_stdout
      end
    end

    context "when debug mode is not set" do
      before { allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return(nil) }

      it "does not output anything" do
        expect { output.debug("Debug info") }.not_to output.to_stdout
      end
    end
  end

  describe "#status" do
    it "outputs status with default blue color" do
      expect { output.status("info", "Processing") }.to output("COLORED Processing\n").to_stdout
      expect(mock_pastel).to have_received(:public_send).with(:blue, "[INFO]")
    end

    it "outputs status with custom color" do
      expect { output.status("success", "Done", :green) }.to output("COLORED Done\n").to_stdout
      expect(mock_pastel).to have_received(:public_send).with(:green, "[SUCCESS]")
    end
  end

  describe "#section" do
    it "outputs section header with decorative borders" do
      expect {
        output.section("Test Section")
      }.to output(/CYAN.*Test Section.*CYAN/m).to_stdout

      expect(mock_pastel).to have_received(:bold).with(mock_pastel.cyan("═" * 60)).twice
      expect(mock_pastel).to have_received(:bold).with(mock_pastel.cyan("  Test Section"))
    end
  end

  describe "#subsection" do
    it "outputs subsection with underline" do
      expect {
        output.subsection("Subsection Title")
      }.to output(/BOLD.*DIM/m).to_stdout

      expect(mock_pastel).to have_received(:bold).with("Subsection Title")
      expect(mock_pastel).to have_received(:dim).with("─" * "Subsection Title".length)
    end
  end

  describe "#list_item" do
    it "outputs simple list item" do
      expect { output.list_item("Item 1") }.to output("  • Item 1\n").to_stdout
    end

    it "outputs list item with description" do
      allow(mock_pastel).to receive(:bold).with("Item").and_return("BOLD_ITEM")
      
      expect { output.list_item("Item", "Description") }.to output("  • BOLD_ITEM - Description\n").to_stdout
      expect(mock_pastel).to have_received(:bold).with("Item")
    end
  end

  describe "#empty_state" do
    it "outputs dimmed empty state message" do
      expect { output.empty_state("No items found") }.to output("DIM\n").to_stdout
      expect(mock_pastel).to have_received(:dim).with("  No items found")
    end
  end

  describe "#key_value" do
    it "outputs key-value pair with default indentation" do
      allow(mock_pastel).to receive(:bold).with("Key").and_return("BOLD_KEY")
      
      expect { output.key_value("Key", "Value") }.to output("BOLD_KEY: Value\n").to_stdout
      expect(mock_pastel).to have_received(:bold).with("Key")
    end

    it "outputs key-value pair with custom indentation" do
      allow(mock_pastel).to receive(:bold).with("Key").and_return("BOLD_KEY")
      
      expect { output.key_value("Key", "Value", indent: 4) }.to output("    BOLD_KEY: Value\n").to_stdout
    end
  end

  describe "#progress_start" do
    it "outputs progress start message without newline" do
      expect { output.progress_start("Loading") }.to output("Loading... ").to_stdout
    end
  end

  describe "#progress_done" do
    it "outputs green checkmark" do
      expect { output.progress_done }.to output("GREEN\n").to_stdout
      expect(mock_pastel).to have_received(:green).with("✅")
    end
  end

  describe "#progress_failed" do
    it "outputs red X mark" do
      expect { output.progress_failed }.to output("RED\n").to_stdout
      expect(mock_pastel).to have_received(:red).with("❌")
    end
  end

  describe "#newline" do
    it "outputs empty line" do
      expect { output.newline }.to output("\n").to_stdout
    end
  end

  describe "#recovery_suggestion" do
    it "outputs suggestion with lightbulb icon" do
      expect {
        output.recovery_suggestion("Try this solution")
      }.to output(/YELLOW/).to_stdout

      expect(mock_pastel).to have_received(:yellow).with("💡 Suggestion: Try this solution")
    end
  end

  describe "#command_example" do
    it "outputs command without description" do
      allow(mock_pastel).to receive(:cyan).with("$ sxn init").and_return("CYAN_COMMAND")
      
      expect {
        output.command_example("sxn init")
      }.to output("  CYAN_COMMAND\n\n").to_stdout
    end

    it "outputs command with description" do
      allow(mock_pastel).to receive(:cyan).with("$ sxn init").and_return("CYAN_COMMAND")
      allow(mock_pastel).to receive(:dim).with("Initialize sxn").and_return("DIM_DESC")
      
      expect {
        output.command_example("sxn init", "Initialize sxn")
      }.to output("  DIM_DESC\n  CYAN_COMMAND\n\n").to_stdout
    end
  end

  describe "private methods" do
    describe "#debug_mode?" do
      it "returns true when SXN_DEBUG is 'true'" do
        allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("true")
        expect(output.send(:debug_mode?)).to be(true)
      end

      it "returns false when SXN_DEBUG is 'false'" do
        allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("false")
        expect(output.send(:debug_mode?)).to be(false)
      end

      it "returns false when SXN_DEBUG is not set" do
        allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return(nil)
        expect(output.send(:debug_mode?)).to be(false)
      end

      it "returns false when SXN_DEBUG is any other value" do
        allow(ENV).to receive(:[]).with("SXN_DEBUG").and_return("1")
        expect(output.send(:debug_mode?)).to be(false)
      end
    end
  end
end