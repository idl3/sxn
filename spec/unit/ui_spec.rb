# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI do
  describe "module structure" do
    it "is defined as a module" do
      expect(Sxn::UI).to be_a(Module)
    end

    it "is nested within Sxn module" do
      expect(Sxn::UI.name).to eq("Sxn::UI")
    end
  end

  describe "autoloaded constants" do
    it "defines all expected UI autoloads" do
      expected_constants = %i[Prompt Output Table ProgressBar]

      expected_constants.each do |const|
        expect(Sxn::UI.const_defined?(const)).to be true
      end
    end
  end

  describe "autoload functionality" do
    it "can load Prompt class" do
      expect { Sxn::UI::Prompt }.not_to raise_error
      expect(Sxn::UI::Prompt).to be_a(Class)
    end

    it "can load Output class" do
      expect { Sxn::UI::Output }.not_to raise_error
      expect(Sxn::UI::Output).to be_a(Class)
    end

    it "can load Table class" do
      expect { Sxn::UI::Table }.not_to raise_error
      expect(Sxn::UI::Table).to be_a(Class)
    end

    it "can load ProgressBar class" do
      expect { Sxn::UI::ProgressBar }.not_to raise_error
      expect(Sxn::UI::ProgressBar).to be_a(Class)
    end
  end

  describe "UI class availability" do
    before do
      # Force autoload to trigger
      Sxn::UI::ProgressBar
    end

    it "provides access to all UI classes" do
      ui_classes = [
        Sxn::UI::Prompt,
        Sxn::UI::Output,
        Sxn::UI::Table,
        Sxn::UI::ProgressBar
      ]

      ui_classes.each do |ui_class|
        expect(ui_class).to be_a(Class)
        expect(ui_class.name).to start_with("Sxn::UI::")
      end
    end

    it "all UI classes are properly namespaced" do
      constants = Sxn::UI.constants
      expected_constants = %i[Prompt Output Table ProgressBar]

      expected_constants.each do |const|
        expect(constants).to include(const)
      end
    end
  end

  describe "UI component functionality" do
    it "provides interactive prompting capabilities" do
      prompt = Sxn::UI::Prompt.new

      # Check that prompt has expected interface
      expect(prompt).to respond_to(:ask)
      expect(prompt).to respond_to(:ask_yes_no)
      expect(prompt).to respond_to(:select)
      expect(prompt).to respond_to(:multi_select)
    end

    it "provides formatted output capabilities" do
      output = Sxn::UI::Output.new

      # Check that output has expected interface
      expect(output).to respond_to(:success)
      expect(output).to respond_to(:error)
      expect(output).to respond_to(:warning)
      expect(output).to respond_to(:info)
      expect(output).to respond_to(:debug)
      expect(output).to respond_to(:status)
      expect(output).to respond_to(:section)
    end

    it "provides table display capabilities" do
      table = Sxn::UI::Table.new

      # Check that table has expected interface
      expect(table).to respond_to(:sessions)
      expect(table).to respond_to(:projects)
      expect(table).to respond_to(:worktrees)
      expect(table).to respond_to(:rules)
    end

    it "provides progress indication capabilities" do
      progress = Sxn::UI::ProgressBar.new("Test progress", total: 100)

      # Check that progress bar has expected interface
      expect(progress).to respond_to(:advance)
      expect(progress).to respond_to(:finish)
      expect(progress).to respond_to(:current)
      expect(progress).to respond_to(:total)
    end
  end

  describe "UI component instantiation" do
    it "can create prompt instances" do
      expect { Sxn::UI::Prompt.new }.not_to raise_error
    end

    it "can create output instances" do
      expect { Sxn::UI::Output.new }.not_to raise_error
    end

    it "can create table instances" do
      expect { Sxn::UI::Table.new }.not_to raise_error
    end

    it "can create progress bar instances" do
      expect { Sxn::UI::ProgressBar.new("Test", total: 10) }.not_to raise_error
    end
  end

  describe "UI integration patterns" do
    it "output supports various message types" do
      output = Sxn::UI::Output.new

      # Test that we can call different output methods without error
      expect { output.success("Test success") }.not_to raise_error
      expect { output.error("Test error") }.not_to raise_error
      expect { output.warning("Test warning") }.not_to raise_error
      expect { output.info("Test info") }.not_to raise_error
    end

    it "table supports data display" do
      table = Sxn::UI::Table.new

      # Test actual table methods that exist
      expect { table.sessions([]) }.not_to raise_error
      expect { table.projects([]) }.not_to raise_error
      expect { table.worktrees([]) }.not_to raise_error
    end

    it "progress bar supports progress tracking" do
      progress = Sxn::UI::ProgressBar.new("Test Progress", total: 5)

      # Test progress bar operations
      expect { progress.advance }.not_to raise_error
      expect { progress.advance(2) }.not_to raise_error
      expect { progress.finish }.not_to raise_error
    end
  end

  describe "UI module design patterns" do
    it "follows consistent instantiation patterns" do
      # All UI classes should be instantiable with new
      ui_classes = [Sxn::UI::Prompt, Sxn::UI::Output, Sxn::UI::Table]

      ui_classes.each do |ui_class|
        expect(ui_class).to respond_to(:new)
        instance = ui_class.new
        expect(instance).to be_a(ui_class)
      end
    end

    it "provides cohesive user interface components" do
      # The UI module should provide a complete set of tools for CLI interaction
      components = {
        prompt: Sxn::UI::Prompt,
        output: Sxn::UI::Output,
        table: Sxn::UI::Table,
        progress: Sxn::UI::ProgressBar
      }

      components.each_value do |component_class|
        expect(component_class).to be_a(Class)
        expect(component_class.name).to include("Sxn::UI")
      end
    end
  end
end
