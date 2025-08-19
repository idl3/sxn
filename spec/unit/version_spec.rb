# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::VERSION do
  it "is defined as a string" do
    expect(Sxn::VERSION).to be_a(String)
  end

  it "follows semantic versioning format" do
    expect(Sxn::VERSION).to match(/\A\d+\.\d+\.\d+(\.\w+)?\z/)
  end

  it "is not empty" do
    expect(Sxn::VERSION).not_to be_empty
  end

  it "is accessible as a constant" do
    expect(defined?(Sxn::VERSION)).to eq("constant")
  end

  it "has a valid version value" do
    expect(Sxn::VERSION).to eq("0.1.0")
  end
end

RSpec.describe "Version module" do
  it "defines VERSION constant in Sxn module" do
    expect(Sxn.constants).to include(:VERSION)
  end

  it "defines expected Sxn module methods" do
    # The Sxn module defines some utility methods for configuration and logging
    expected_methods = [:config, :version, :logger, :logger=, :setup_logger, :load_config, :config=, :root, :lib_root]
    sxn_methods = Sxn.methods - Object.methods
    
    # Check that expected methods are present
    expected_methods.each do |method|
      expect(Sxn).to respond_to(method)
    end
  end
end