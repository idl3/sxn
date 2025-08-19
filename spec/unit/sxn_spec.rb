# frozen_string_literal: true

RSpec.describe Sxn do
  describe ".version" do
    it "returns the version number" do
      expect(Sxn.version).to eq(Sxn::VERSION)
    end
  end

  describe ".root" do
    it "returns the gem root directory" do
      expect(Sxn.root).to be_a(String)
      expect(File.exist?(Sxn.root)).to be true
    end
  end

  describe ".lib_root" do
    it "returns the lib directory" do
      expect(Sxn.lib_root).to end_with("lib")
      expect(File.exist?(Sxn.lib_root)).to be true
    end
  end

  describe ".setup_logger" do
    it "creates a logger with specified level" do
      logger = Sxn.setup_logger(level: :debug)
      expect(logger).to be_a(Logger)
      expect(logger.level).to eq(Logger::DEBUG)
    end

    it "defaults to info level" do
      logger = Sxn.setup_logger
      expect(logger.level).to eq(Logger::INFO)
    end
  end
end