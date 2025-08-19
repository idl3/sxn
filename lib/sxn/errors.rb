# frozen_string_literal: true

module Sxn
  # Base error class for all Sxn-specific errors
  class Error < StandardError
    attr_reader :exit_code

    def initialize(message = nil, exit_code: 1)
      super(message)
      @exit_code = exit_code
    end
  end

  # Configuration-related errors
  class ConfigurationError < Error; end

  # Session management errors
  class SessionError < Error; end
  class SessionNotFoundError < SessionError; end
  class SessionAlreadyExistsError < SessionError; end
  class SessionExistsError < SessionError; end
  class SessionHasChangesError < SessionError; end
  class InvalidSessionNameError < SessionError; end
  class NoActiveSessionError < SessionError; end

  # Project management errors
  class ProjectError < Error; end
  class ProjectNotFoundError < ProjectError; end
  class ProjectAlreadyExistsError < ProjectError; end
  class ProjectExistsError < ProjectError; end
  class ProjectInUseError < ProjectError; end
  class InvalidProjectNameError < ProjectError; end
  class InvalidProjectPathError < ProjectError; end

  # Git operation errors
  class GitError < Error; end
  class WorktreeError < GitError; end
  class WorktreeExistsError < WorktreeError; end
  class WorktreeNotFoundError < WorktreeError; end
  class WorktreeCreationError < WorktreeError; end
  class WorktreeRemovalError < WorktreeError; end
  class BranchError < GitError; end

  # Security-related errors
  class SecurityError < Error; end
  class PathValidationError < SecurityError; end
  class CommandExecutionError < SecurityError; end

  # Rule execution errors
  class RuleError < Error; end
  class RuleValidationError < RuleError; end
  class RuleExecutionError < RuleError; end
  class RuleNotFoundError < RuleError; end
  class InvalidRuleTypeError < RuleError; end
  class InvalidRuleConfigError < RuleError; end

  # Template processing errors
  class TemplateError < Error; end
  class TemplateNotFoundError < TemplateError; end
  class TemplateProcessingError < TemplateError; end

  # Database errors
  class DatabaseError < Error; end
  class DatabaseConnectionError < DatabaseError; end
  class DatabaseMigrationError < DatabaseError; end

  # MCP server errors
  class MCPError < Error; end
  class MCPServerError < MCPError; end
  class MCPValidationError < MCPError; end
end