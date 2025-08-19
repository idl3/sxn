# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Database do
  describe "module structure" do
    it "is defined as a module" do
      expect(Sxn::Database).to be_a(Module)
    end

    it "is nested within Sxn module" do
      expect(Sxn::Database.name).to eq("Sxn::Database")
    end
  end

  describe "autoloaded constants" do
    it "defines SessionDatabase autoload" do
      expect(Sxn::Database.const_defined?(:SessionDatabase)).to be true
    end
  end

  describe "autoload functionality" do
    it "can load SessionDatabase class" do
      expect { Sxn::Database::SessionDatabase }.not_to raise_error
      expect(Sxn::Database::SessionDatabase).to be_a(Class)
    end
  end

  describe "database class availability" do
    before do
      # Force autoload to trigger
      Sxn::Database::SessionDatabase
    end

    it "provides access to SessionDatabase class" do
      expect(Sxn::Database::SessionDatabase).to be_a(Class)
      expect(Sxn::Database::SessionDatabase.name).to eq("Sxn::Database::SessionDatabase")
    end

    it "SessionDatabase class is properly namespaced" do
      constants = Sxn::Database.constants
      expect(constants).to include(:SessionDatabase)
    end
  end

  describe "module documentation" do
    it "provides comprehensive database features" do
      # This test documents the expected features mentioned in the module documentation

      # While we can't test the features directly from the module,
      # we can verify the module is designed to support these capabilities
      expect(Sxn::Database).to be_a(Module)
      expect { Sxn::Database::SessionDatabase }.not_to raise_error
    end
  end

  describe "error handling integration" do
    it "loads database errors" do
      # The module requires database/errors, so these should be available
      expect(defined?(Sxn::Database::Error)).to eq("constant")
      expect(defined?(Sxn::Database::ConnectionError)).to eq("constant")
      expect(defined?(Sxn::Database::MigrationError)).to eq("constant")
    end

    it "database errors inherit properly" do
      expect(Sxn::Database::Error).to be < Sxn::Error
      expect(Sxn::Database::ConnectionError).to be < Sxn::Database::Error
      expect(Sxn::Database::MigrationError).to be < Sxn::Database::Error
    end
  end
end
