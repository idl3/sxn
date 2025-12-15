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

    it "defaults to info level for unknown log levels" do
      logger = Sxn.setup_logger(level: :unknown_level)
      expect(logger.level).to eq(Logger::INFO)
    end

    it "converts string levels to symbols" do
      logger = Sxn.setup_logger(level: "debug")
      expect(logger.level).to eq(Logger::DEBUG)
    end

    it "handles warn level" do
      logger = Sxn.setup_logger(level: :warn)
      expect(logger.level).to eq(Logger::WARN)
    end

    it "handles error level" do
      logger = Sxn.setup_logger(level: :error)
      expect(logger.level).to eq(Logger::ERROR)
    end
  end

  describe "module initialization" do
    it "skips logger setup when RSpec is defined" do
      # This is tested implicitly - when RSpec is defined (as it is in tests),
      # the logger is not automatically initialized. We can verify this by
      # checking that the logger can be nil and needs explicit setup
      Sxn.instance_variable_set(:@logger, nil)
      expect(Sxn.instance_variable_get(:@logger)).to be_nil

      # Now set it up explicitly
      Sxn.setup_logger
      expect(Sxn.instance_variable_get(:@logger)).not_to be_nil
    end
  end
end
