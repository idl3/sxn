# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::Error do
  describe "#initialize" do
    it "sets default exit code to 1" do
      error = described_class.new("Test message")
      expect(error.exit_code).to eq(1)
      expect(error.message).to eq("Test message")
    end

    it "accepts custom exit code" do
      error = described_class.new("Test message", exit_code: 42)
      expect(error.exit_code).to eq(42)
      expect(error.message).to eq("Test message")
    end

    it "can be created without message" do
      error = described_class.new
      expect(error.exit_code).to eq(1)
      expect(error.message).to eq("Sxn::Error")
    end

    it "can be created with custom exit code and no message" do
      error = described_class.new(exit_code: 5)
      expect(error.exit_code).to eq(5)
      expect(error.message).to eq("Sxn::Error")
    end
  end

  describe "inheritance" do
    it "inherits from StandardError" do
      expect(described_class).to be < StandardError
    end
  end
end

RSpec.describe Sxn::ConfigurationError do
  it "inherits from Sxn::Error" do
    expect(described_class).to be < Sxn::Error
  end

  it "can be created with message" do
    error = described_class.new("Config error")
    expect(error.message).to eq("Config error")
    expect(error.exit_code).to eq(1)
  end

  it "can be created with custom exit code" do
    error = described_class.new("Config error", exit_code: 3)
    expect(error.message).to eq("Config error")
    expect(error.exit_code).to eq(3)
  end
end

RSpec.describe "Session Errors" do
  describe Sxn::SessionError do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end
  end

  describe Sxn::SessionNotFoundError do
    it "inherits from Sxn::SessionError" do
      expect(described_class).to be < Sxn::SessionError
    end
  end

  describe Sxn::SessionAlreadyExistsError do
    it "inherits from Sxn::SessionError" do
      expect(described_class).to be < Sxn::SessionError
    end
  end

  describe Sxn::SessionExistsError do
    it "inherits from Sxn::SessionError" do
      expect(described_class).to be < Sxn::SessionError
    end
  end

  describe Sxn::SessionHasChangesError do
    it "inherits from Sxn::SessionError" do
      expect(described_class).to be < Sxn::SessionError
    end
  end

  describe Sxn::InvalidSessionNameError do
    it "inherits from Sxn::SessionError" do
      expect(described_class).to be < Sxn::SessionError
    end
  end

  describe Sxn::NoActiveSessionError do
    it "inherits from Sxn::SessionError" do
      expect(described_class).to be < Sxn::SessionError
    end
  end
end

RSpec.describe "Project Errors" do
  describe Sxn::ProjectError do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end
  end

  describe Sxn::ProjectNotFoundError do
    it "inherits from Sxn::ProjectError" do
      expect(described_class).to be < Sxn::ProjectError
    end
  end

  describe Sxn::ProjectAlreadyExistsError do
    it "inherits from Sxn::ProjectError" do
      expect(described_class).to be < Sxn::ProjectError
    end
  end

  describe Sxn::ProjectExistsError do
    it "inherits from Sxn::ProjectError" do
      expect(described_class).to be < Sxn::ProjectError
    end
  end

  describe Sxn::ProjectInUseError do
    it "inherits from Sxn::ProjectError" do
      expect(described_class).to be < Sxn::ProjectError
    end
  end

  describe Sxn::InvalidProjectNameError do
    it "inherits from Sxn::ProjectError" do
      expect(described_class).to be < Sxn::ProjectError
    end
  end

  describe Sxn::InvalidProjectPathError do
    it "inherits from Sxn::ProjectError" do
      expect(described_class).to be < Sxn::ProjectError
    end
  end
end

RSpec.describe "Git Errors" do
  describe Sxn::GitError do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end
  end

  describe Sxn::WorktreeError do
    it "inherits from Sxn::GitError" do
      expect(described_class).to be < Sxn::GitError
    end
  end

  describe Sxn::WorktreeExistsError do
    it "inherits from Sxn::WorktreeError" do
      expect(described_class).to be < Sxn::WorktreeError
    end
  end

  describe Sxn::WorktreeNotFoundError do
    it "inherits from Sxn::WorktreeError" do
      expect(described_class).to be < Sxn::WorktreeError
    end
  end

  describe Sxn::WorktreeCreationError do
    it "inherits from Sxn::WorktreeError" do
      expect(described_class).to be < Sxn::WorktreeError
    end
  end

  describe Sxn::WorktreeRemovalError do
    it "inherits from Sxn::WorktreeError" do
      expect(described_class).to be < Sxn::WorktreeError
    end
  end

  describe Sxn::BranchError do
    it "inherits from Sxn::GitError" do
      expect(described_class).to be < Sxn::GitError
    end
  end
end

RSpec.describe "Security Errors" do
  describe Sxn::SecurityError do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end
  end

  describe Sxn::PathValidationError do
    it "inherits from Sxn::SecurityError" do
      expect(described_class).to be < Sxn::SecurityError
    end
  end

  describe Sxn::CommandExecutionError do
    it "inherits from Sxn::SecurityError" do
      expect(described_class).to be < Sxn::SecurityError
    end
  end
end

RSpec.describe "Rule Errors" do
  describe Sxn::RuleError do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end
  end

  describe Sxn::RuleValidationError do
    it "inherits from Sxn::RuleError" do
      expect(described_class).to be < Sxn::RuleError
    end
  end

  describe Sxn::RuleExecutionError do
    it "inherits from Sxn::RuleError" do
      expect(described_class).to be < Sxn::RuleError
    end
  end

  describe Sxn::RuleNotFoundError do
    it "inherits from Sxn::RuleError" do
      expect(described_class).to be < Sxn::RuleError
    end
  end

  describe Sxn::InvalidRuleTypeError do
    it "inherits from Sxn::RuleError" do
      expect(described_class).to be < Sxn::RuleError
    end
  end

  describe Sxn::InvalidRuleConfigError do
    it "inherits from Sxn::RuleError" do
      expect(described_class).to be < Sxn::RuleError
    end
  end
end

RSpec.describe "Template Errors" do
  describe Sxn::TemplateError do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end
  end

  describe Sxn::TemplateNotFoundError do
    it "inherits from Sxn::TemplateError" do
      expect(described_class).to be < Sxn::TemplateError
    end
  end

  describe Sxn::TemplateProcessingError do
    it "inherits from Sxn::TemplateError" do
      expect(described_class).to be < Sxn::TemplateError
    end
  end
end

RSpec.describe "Database Errors" do
  describe Sxn::DatabaseError do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end
  end

  describe Sxn::DatabaseConnectionError do
    it "inherits from Sxn::DatabaseError" do
      expect(described_class).to be < Sxn::DatabaseError
    end
  end

  describe Sxn::DatabaseMigrationError do
    it "inherits from Sxn::DatabaseError" do
      expect(described_class).to be < Sxn::DatabaseError
    end
  end
end

RSpec.describe "MCP Errors" do
  describe Sxn::MCPError do
    it "inherits from Sxn::Error" do
      expect(described_class).to be < Sxn::Error
    end
  end

  describe Sxn::MCPServerError do
    it "inherits from Sxn::MCPError" do
      expect(described_class).to be < Sxn::MCPError
    end
  end

  describe Sxn::MCPValidationError do
    it "inherits from Sxn::MCPError" do
      expect(described_class).to be < Sxn::MCPError
    end
  end
end

# Integration tests for error behavior
RSpec.describe "Error integration" do
  it "all errors can be raised and caught" do
    error_classes = [
      Sxn::Error,
      Sxn::ConfigurationError,
      Sxn::SessionError,
      Sxn::SessionNotFoundError,
      Sxn::SessionAlreadyExistsError,
      Sxn::SessionExistsError,
      Sxn::SessionHasChangesError,
      Sxn::InvalidSessionNameError,
      Sxn::NoActiveSessionError,
      Sxn::ProjectError,
      Sxn::ProjectNotFoundError,
      Sxn::ProjectAlreadyExistsError,
      Sxn::ProjectExistsError,
      Sxn::ProjectInUseError,
      Sxn::InvalidProjectNameError,
      Sxn::InvalidProjectPathError,
      Sxn::GitError,
      Sxn::WorktreeError,
      Sxn::WorktreeExistsError,
      Sxn::WorktreeNotFoundError,
      Sxn::WorktreeCreationError,
      Sxn::WorktreeRemovalError,
      Sxn::BranchError,
      Sxn::SecurityError,
      Sxn::PathValidationError,
      Sxn::CommandExecutionError,
      Sxn::RuleError,
      Sxn::RuleValidationError,
      Sxn::RuleExecutionError,
      Sxn::RuleNotFoundError,
      Sxn::InvalidRuleTypeError,
      Sxn::InvalidRuleConfigError,
      Sxn::TemplateError,
      Sxn::TemplateNotFoundError,
      Sxn::TemplateProcessingError,
      Sxn::DatabaseError,
      Sxn::DatabaseConnectionError,
      Sxn::DatabaseMigrationError,
      Sxn::MCPError,
      Sxn::MCPServerError,
      Sxn::MCPValidationError
    ]

    error_classes.each do |error_class|
      expect {
        begin
          raise error_class.new("Test message")
        rescue error_class => e
          expect(e.message).to eq("Test message")
          expect(e.exit_code).to eq(1)
          raise
        end
      }.to raise_error(error_class)
    end
  end

  it "all errors can be created with custom exit codes" do
    custom_exit_code = 42
    
    error = Sxn::ConfigurationError.new("Test", exit_code: custom_exit_code)
    expect(error.exit_code).to eq(custom_exit_code)
    
    error = Sxn::SessionError.new("Test", exit_code: custom_exit_code)
    expect(error.exit_code).to eq(custom_exit_code)
    
    error = Sxn::RuleError.new("Test", exit_code: custom_exit_code)
    expect(error.exit_code).to eq(custom_exit_code)
  end
end