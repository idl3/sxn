# frozen_string_literal: true

require_relative "../errors"

module Sxn
  module Rules
    # Base error class for all rule-related errors
    class RulesError < Sxn::Error; end

    # Raised when rule validation fails
    class ValidationError < RulesError; end

    # Raised when rule application fails
    class ApplicationError < RulesError; end

    # Raised when rule rollback fails
    class RollbackError < RulesError; end

    # Raised when dependency resolution fails
    class DependencyError < RulesError; end

    # Raised when command execution fails
    class CommandExecutionError < RulesError; end

    # Raised when path validation fails
    class PathValidationError < RulesError; end
  end
end
