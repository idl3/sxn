# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Commands do
  describe "module structure" do
    it "is defined as a module" do
      expect(Sxn::Commands).to be_a(Module)
    end

    it "is nested within Sxn module" do
      expect(Sxn::Commands.name).to eq("Sxn::Commands")
    end
  end

  describe "autoloaded constants" do
    it "defines all expected command autoloads" do
      expected_constants = %i[Init Sessions Projects Worktrees Rules]

      expected_constants.each do |const|
        expect(Sxn::Commands.const_defined?(const)).to be true
      end
    end
  end

  describe "autoload functionality" do
    it "can load Init command class" do
      expect { Sxn::Commands::Init }.not_to raise_error
      expect(Sxn::Commands::Init).to be_a(Class)
    end

    it "can load Sessions command class" do
      expect { Sxn::Commands::Sessions }.not_to raise_error
      expect(Sxn::Commands::Sessions).to be_a(Class)
    end

    it "can load Projects command class" do
      expect { Sxn::Commands::Projects }.not_to raise_error
      expect(Sxn::Commands::Projects).to be_a(Class)
    end

    it "can load Worktrees command class" do
      expect { Sxn::Commands::Worktrees }.not_to raise_error
      expect(Sxn::Commands::Worktrees).to be_a(Class)
    end

    it "can load Rules command class" do
      expect { Sxn::Commands::Rules }.not_to raise_error
      expect(Sxn::Commands::Rules).to be_a(Class)
    end
  end

  describe "command class availability" do
    before do
      # Force autoload to trigger
      Sxn::Commands::Rules
    end

    it "provides access to all command classes" do
      command_classes = [
        Sxn::Commands::Init,
        Sxn::Commands::Sessions,
        Sxn::Commands::Projects,
        Sxn::Commands::Worktrees,
        Sxn::Commands::Rules
      ]

      command_classes.each do |command_class|
        expect(command_class).to be_a(Class)
        expect(command_class.name).to start_with("Sxn::Commands::")
      end
    end

    it "all command classes are properly namespaced" do
      constants = Sxn::Commands.constants
      expected_constants = %i[Init Sessions Projects Worktrees Rules]

      expected_constants.each do |const|
        expect(constants).to include(const)
      end
    end
  end
end
