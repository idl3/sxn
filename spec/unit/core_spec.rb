# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Core do
  describe "module structure" do
    it "is defined as a module" do
      expect(Sxn::Core).to be_a(Module)
    end

    it "is nested within Sxn module" do
      expect(Sxn::Core.name).to eq("Sxn::Core")
    end
  end

  describe "autoloaded constants" do
    it "defines all expected autoloads" do
      # These constants should be available for autoloading or already loaded
      expected_constants = [:ConfigManager, :SessionManager, :ProjectManager, :WorktreeManager, :RulesManager]
      
      expected_constants.each do |const|
        expect(Sxn::Core.const_defined?(const)).to be true
      end
    end
  end

  describe "autoload functionality" do
    it "can load ConfigManager class" do
      expect { Sxn::Core::ConfigManager }.not_to raise_error
      expect(Sxn::Core::ConfigManager).to be_a(Class)
    end

    it "can load SessionManager class" do
      expect { Sxn::Core::SessionManager }.not_to raise_error
      expect(Sxn::Core::SessionManager).to be_a(Class)
    end

    it "can load ProjectManager class" do
      expect { Sxn::Core::ProjectManager }.not_to raise_error
      expect(Sxn::Core::ProjectManager).to be_a(Class)
    end

    it "can load WorktreeManager class" do
      expect { Sxn::Core::WorktreeManager }.not_to raise_error
      expect(Sxn::Core::WorktreeManager).to be_a(Class)
    end

    it "can load RulesManager class" do
      expect { Sxn::Core::RulesManager }.not_to raise_error
      expect(Sxn::Core::RulesManager).to be_a(Class)
    end
  end

  describe "manager class availability" do
    before do
      # Force autoload to trigger
      Sxn::Core::ConfigManager
      Sxn::Core::SessionManager
      Sxn::Core::ProjectManager
      Sxn::Core::WorktreeManager
      Sxn::Core::RulesManager
    end

    it "provides access to all manager classes" do
      manager_classes = [
        Sxn::Core::ConfigManager,
        Sxn::Core::SessionManager,
        Sxn::Core::ProjectManager,
        Sxn::Core::WorktreeManager,
        Sxn::Core::RulesManager
      ]

      manager_classes.each do |manager_class|
        expect(manager_class).to be_a(Class)
        expect(manager_class.name).to start_with("Sxn::Core::")
      end
    end

    it "all manager classes are properly namespaced" do
      constants = Sxn::Core.constants
      expected_constants = [:ConfigManager, :SessionManager, :ProjectManager, :WorktreeManager, :RulesManager]
      
      expected_constants.each do |const|
        expect(constants).to include(const)
      end
    end
  end
end