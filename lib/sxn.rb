# frozen_string_literal: true

require "zeitwerk"
require_relative "sxn/version"
require_relative "sxn/errors"
require_relative "sxn/runtime_validations"
require_relative "sxn/config"
require_relative "sxn/core"
require_relative "sxn/database"
require_relative "sxn/rules"
require_relative "sxn/security"
require_relative "sxn/templates"
require_relative "sxn/ui"
require_relative "sxn/commands"
require_relative "sxn/CLI"
# MCP module is loaded on demand via require "sxn/mcp"

module Sxn
  class << self
    attr_accessor :logger, :config

    def root
      File.expand_path("..", __dir__)
    end

    def lib_root
      File.expand_path(__dir__)
    end

    def version
      VERSION
    end

    def load_config
      @config = Config.current
    end

    def setup_logger(level: :info)
      require "logger"
      @logger = Logger.new($stdout)

      # Convert string level to symbol if needed
      level = level.to_sym if level.is_a?(String)

      @logger.level = case level
                      when :debug then Logger::DEBUG
                      when :info then Logger::INFO
                      when :warn then Logger::WARN
                      when :error then Logger::ERROR
                      else Logger::INFO
                      end

      # Set custom formatter
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S")}] #{severity}: #{msg}\n"
      end

      @logger
    end
  end

  # Initialize logger on module load unless in test environment
  @logger = setup_logger unless defined?(RSpec)
end
