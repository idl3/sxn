# frozen_string_literal: true

require "mcp"

require_relative "mcp/server"
require_relative "mcp/tools/base_tool"
require_relative "mcp/tools/sessions"
require_relative "mcp/tools/worktrees"
require_relative "mcp/tools/projects"
require_relative "mcp/tools/templates"
require_relative "mcp/tools/rules"
require_relative "mcp/resources/session_resources"
require_relative "mcp/prompts/workflow_prompts"

module Sxn
  # MCP (Model Context Protocol) server for sxn
  # Enables AI assistants like Claude Code to manage development sessions
  module MCP
  end
end
