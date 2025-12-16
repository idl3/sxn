# frozen_string_literal: true

module Sxn
  module MCP
    module Tools
      module Sessions
        # List all sessions with optional filtering
        class ListSessions < ::MCP::Tool
          description "List all sxn development sessions with optional status filtering"

          input_schema(
            type: "object",
            properties: {
              status: {
                type: "string",
                enum: %w[active inactive archived],
                description: "Filter sessions by status"
              },
              limit: {
                type: "integer",
                default: 100,
                description: "Maximum number of sessions to return"
              }
            },
            required: []
          )

          class << self
            def call(server_context:, status: nil, limit: 100)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                session_manager = server_context[:session_manager]
                sessions = session_manager.list_sessions(status: status, limit: limit)

                if sessions.empty?
                  BaseTool.text_response("No sessions found.")
                else
                  summary = "Found #{sessions.length} session(s):"
                  formatted = sessions.map do |s|
                    "- #{s[:name]} (#{s[:status]}) - #{s[:worktrees].keys.length} worktrees"
                  end.join("\n")

                  BaseTool.text_response("#{summary}\n#{formatted}")
                end
              end
            end
          end
        end

        # Create a new session
        class CreateSession < ::MCP::Tool
          description "Create a new sxn development session with optional template"

          input_schema(
            type: "object",
            properties: {
              name: {
                type: "string",
                pattern: "^[a-zA-Z0-9_-]+$",
                description: "Session name (alphanumeric, hyphens, underscores only)"
              },
              description: {
                type: "string",
                description: "Optional session description"
              },
              default_branch: {
                type: "string",
                description: "Default branch for worktrees (defaults to session name)"
              },
              template_id: {
                type: "string",
                description: "Template to apply (creates predefined worktrees)"
              },
              linear_task: {
                type: "string",
                description: "Associated Linear task ID (e.g., ATL-1234)"
              }
            },
            required: ["name"]
          )

          class << self
            def call(name:, server_context:, description: nil, default_branch: nil, template_id: nil, linear_task: nil)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                session_manager = server_context[:session_manager]

                session = session_manager.create_session(
                  name,
                  description: description,
                  default_branch: default_branch,
                  template_id: template_id,
                  linear_task: linear_task
                )

                # If template specified, apply it
                apply_template(server_context, name, template_id, default_branch || name) if template_id && server_context[:template_manager]

                BaseTool.text_response(
                  "Session '#{name}' created successfully.\n" \
                  "Path: #{session[:path]}\n" \
                  "Branch: #{session[:default_branch]}"
                )
              end
            end

            private

            def apply_template(server_context, session_name, template_id, default_branch)
              template_manager = server_context[:template_manager]
              worktree_manager = server_context[:worktree_manager]

              # Get template projects
              projects = template_manager.get_template_projects(template_id, default_branch: default_branch)

              # Create worktrees for each project
              projects.each do |project|
                worktree_manager.add_worktree(
                  project[:name],
                  project[:branch],
                  session_name: session_name
                )
              end
            rescue StandardError => e
              # Log template application error but don't fail session creation
              Sxn.logger&.warn("Failed to apply template: #{e.message}")
            end
          end
        end

        # Get detailed session info
        class GetSession < ::MCP::Tool
          description "Get detailed information about a specific session"

          input_schema(
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Session name to retrieve"
              }
            },
            required: ["name"]
          )

          class << self
            def call(name:, server_context:)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                session_manager = server_context[:session_manager]
                session = session_manager.get_session(name)

                raise Sxn::SessionNotFoundError, "Session '#{name}' not found" unless session

                # Format session info
                worktrees_info = session[:worktrees].map do |project, info|
                  "  - #{project}: #{info[:branch] || info["branch"]} (#{info[:path] || info["path"]})"
                end.join("\n")

                output = <<~INFO
                  Session: #{session[:name]}
                  Status: #{session[:status]}
                  Path: #{session[:path]}
                  Created: #{session[:created_at]}
                  Default Branch: #{session[:default_branch]}
                  #{"Description: #{session[:description]}" if session[:description]}
                  #{"Linear Task: #{session[:linear_task]}" if session[:linear_task]}
                  #{"Template: #{session[:template_id]}" if session[:template_id]}

                  Worktrees (#{session[:worktrees].keys.length}):
                  #{worktrees_info.empty? ? "  (none)" : worktrees_info}
                INFO

                BaseTool.text_response(output.strip)
              end
            end
          end
        end

        # Delete a session
        class DeleteSession < ::MCP::Tool
          description "Delete a session and its worktrees"

          input_schema(
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Session name to delete"
              },
              force: {
                type: "boolean",
                default: false,
                description: "Force deletion even with uncommitted changes"
              }
            },
            required: ["name"]
          )

          class << self
            def call(name:, server_context:, force: false)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                session_manager = server_context[:session_manager]
                session_manager.remove_session(name, force: force)

                BaseTool.text_response("Session '#{name}' deleted successfully.")
              end
            end
          end
        end

        # Archive a session
        class ArchiveSession < ::MCP::Tool
          description "Archive a session (preserves data but marks as archived)"

          input_schema(
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Session name to archive"
              }
            },
            required: ["name"]
          )

          class << self
            def call(name:, server_context:)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                session_manager = server_context[:session_manager]
                session_manager.archive_session(name)

                BaseTool.text_response("Session '#{name}' archived successfully.")
              end
            end
          end
        end

        # Activate an archived session
        class ActivateSession < ::MCP::Tool
          description "Activate an archived session"

          input_schema(
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Session name to activate"
              }
            },
            required: ["name"]
          )

          class << self
            def call(name:, server_context:)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                session_manager = server_context[:session_manager]
                session_manager.activate_session(name)

                BaseTool.text_response("Session '#{name}' activated successfully.")
              end
            end
          end
        end

        # Swap to a different session with navigation info
        class SwapSession < ::MCP::Tool
          description "Switch to a different session and get navigation instructions. " \
                      "Returns the session path and shell commands for changing directory."

          input_schema(
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Session name to switch to"
              },
              project: {
                type: "string",
                description: "Specific project worktree to navigate to (optional)"
              }
            },
            required: ["name"]
          )

          class << self
            def call(name:, server_context:, project: nil)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                session_manager = server_context[:session_manager]
                workspace_path = server_context[:workspace_path]

                # Activate the session
                session = session_manager.use_session(name)

                # Determine target path
                target_path = if project
                                worktrees = session[:worktrees]
                                worktree_info = worktrees[project]
                                if worktree_info
                                  worktree_info[:path] || worktree_info["path"]
                                else
                                  session[:path]
                                end
                              else
                                session[:path]
                              end

                # Determine navigation strategy
                navigation = determine_navigation_strategy(workspace_path, target_path)

                # Build response
                worktrees_list = session[:worktrees].map do |proj, info|
                  "- #{proj}: #{info[:path] || info["path"]}"
                end.join("\n")

                output = <<~SWAP
                  Switched to session '#{name}'.

                  Session path: #{session[:path]}
                  Target path: #{target_path}

                  Navigation (#{navigation[:strategy]}):
                  #{navigation[:instruction]}

                  Worktrees:
                  #{worktrees_list.empty? ? "(none)" : worktrees_list}
                SWAP

                # Add structured data for programmatic use
                BaseTool.text_response(output.strip)
              end
            end

            private

            def determine_navigation_strategy(workspace_path, target_path)
              # Check if target is within or contains workspace
              target_expanded = File.expand_path(target_path)
              workspace_expanded = File.expand_path(workspace_path)

              if target_expanded.start_with?(workspace_expanded) ||
                 workspace_expanded.start_with?(target_expanded)
                {
                  strategy: "bash_cd",
                  instruction: "Run: cd #{target_path}",
                  bash_command: "cd #{target_path}",
                  reason: "Session is within the current workspace"
                }
              else
                {
                  strategy: "new_instance",
                  instruction: "Session is outside current workspace. " \
                               "Start a new Claude Code instance with:\n  claude --cwd #{target_path}",
                  shell_command: "claude --cwd #{target_path}",
                  reason: "Session is outside the current workspace"
                }
              end
            end
          end
        end
      end
    end
  end
end
