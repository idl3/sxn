# frozen_string_literal: true

module Sxn
  module MCP
    module Tools
      # Base module for MCP tools with shared error handling
      module BaseTool
        # Maps sxn errors to user-friendly messages
        module ErrorMapping
          SXN_ERROR_MESSAGES = {
            # Session errors
            Sxn::SessionNotFoundError => "Session not found",
            Sxn::SessionAlreadyExistsError => "Session already exists",
            Sxn::SessionExistsError => "Session already exists",
            Sxn::SessionHasChangesError => "Session has uncommitted changes",
            Sxn::InvalidSessionNameError => "Invalid session name",
            Sxn::NoActiveSessionError => "No active session",
            # Project errors
            Sxn::ProjectNotFoundError => "Project not found",
            Sxn::ProjectAlreadyExistsError => "Project already exists",
            Sxn::ProjectExistsError => "Project already exists",
            Sxn::ProjectInUseError => "Project is in use",
            Sxn::InvalidProjectNameError => "Invalid project name",
            Sxn::InvalidProjectPathError => "Invalid project path",
            # Worktree errors
            Sxn::WorktreeError => "Worktree error",
            Sxn::WorktreeExistsError => "Worktree already exists",
            Sxn::WorktreeNotFoundError => "Worktree not found",
            Sxn::WorktreeCreationError => "Failed to create worktree",
            Sxn::WorktreeRemovalError => "Failed to remove worktree",
            # Template errors
            Sxn::SessionTemplateNotFoundError => "Template not found",
            Sxn::SessionTemplateValidationError => "Template validation failed",
            # Rule errors
            Sxn::RuleError => "Rule error",
            Sxn::RuleNotFoundError => "Rule not found",
            Sxn::InvalidRuleTypeError => "Invalid rule type",
            Sxn::InvalidRuleConfigError => "Invalid rule configuration",
            # Configuration errors
            Sxn::ConfigurationError => "Configuration error",
            # MCP errors
            Sxn::MCPError => "MCP error",
            Sxn::MCPServerError => "MCP server error",
            Sxn::MCPValidationError => "MCP validation error"
          }.freeze

          # Wrap a block with error handling that converts sxn errors to error responses
          def self.wrap
            yield
          rescue Sxn::ConfigurationError => e
            error_response("sxn not initialized: #{e.message}. Run 'sxn init' first.")
          rescue Sxn::Error => e
            error_type = SXN_ERROR_MESSAGES[e.class] || "Error"
            error_response("#{error_type}: #{e.message}")
          rescue StandardError => e
            error_response("Unexpected error: #{e.message}")
          end

          def self.error_response(message)
            ::MCP::Tool::Response.new([{ type: "text", text: message }], error: true)
          end
        end

        # Helper to check if sxn is initialized
        def self.ensure_initialized!(server_context)
          return true if server_context[:config_manager]

          false
        end

        # Helper to return error response for uninitialized sxn
        def self.not_initialized_response
          ErrorMapping.error_response("sxn not initialized in this workspace. Run 'sxn init' first.")
        end

        # Helper to build a successful text response
        def self.text_response(text)
          ::MCP::Tool::Response.new([{ type: "text", text: text }])
        end

        # Helper to build a JSON response
        def self.json_response(data, summary: nil)
          content = []
          content << { type: "text", text: summary } if summary
          content << { type: "text", text: JSON.pretty_generate(data) }
          ::MCP::Tool::Response.new(content)
        end

        # Helper to build an error response
        def self.error_response(message)
          ErrorMapping.error_response(message)
        end
      end
    end
  end
end
