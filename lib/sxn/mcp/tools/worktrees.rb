# frozen_string_literal: true

module Sxn
  module MCP
    module Tools
      module Worktrees
        # List worktrees in a session
        class ListWorktrees < ::MCP::Tool
          description "List all worktrees in a session"

          input_schema(
            type: "object",
            properties: {
              session_name: {
                type: "string",
                description: "Session name (defaults to current session)"
              }
            },
            required: []
          )

          class << self
            def call(server_context:, session_name: nil)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                worktree_manager = server_context[:worktree_manager]
                worktrees = worktree_manager.list_worktrees(session_name: session_name)

                if worktrees.empty?
                  BaseTool.text_response("No worktrees found in the session.")
                else
                  formatted = worktrees.map do |w|
                    status_icon = case w[:status]
                                  when "clean" then "[clean]"
                                  when "modified" then "[modified]"
                                  when "staged" then "[staged]"
                                  when "untracked" then "[untracked]"
                                  when "missing" then "[missing]"
                                  else "[#{w[:status]}]"
                                  end
                    "- #{w[:project]} (#{w[:branch]}) #{status_icon}\n  #{w[:path]}"
                  end.join("\n")

                  BaseTool.text_response("Worktrees (#{worktrees.length}):\n#{formatted}")
                end
              end
            end
          end
        end

        # Add a worktree to a session
        class AddWorktree < ::MCP::Tool
          description "Add a project worktree to the current or specified session. " \
                      "Automatically applies project rules after creation."

          input_schema(
            type: "object",
            properties: {
              project_name: {
                type: "string",
                description: "Registered project name"
              },
              branch: {
                type: "string",
                description: "Branch name (defaults to session's default branch)"
              },
              session_name: {
                type: "string",
                description: "Target session (defaults to current session)"
              },
              apply_rules: {
                type: "boolean",
                default: true,
                description: "Apply project rules after creation (copy files, etc.)"
              }
            },
            required: ["project_name"]
          )

          class << self
            def call(project_name:, server_context:, branch: nil, session_name: nil, apply_rules: true)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                worktree_manager = server_context[:worktree_manager]

                result = worktree_manager.add_worktree(
                  project_name,
                  branch,
                  session_name: session_name
                )

                # Apply rules if requested
                rules_result = nil
                if apply_rules && server_context[:rules_manager]
                  rules_result = apply_project_rules(
                    server_context,
                    project_name,
                    result[:session]
                  )
                end

                output = <<~RESULT
                  Worktree created successfully:
                  - Project: #{result[:project]}
                  - Branch: #{result[:branch]}
                  - Path: #{result[:path]}
                  - Session: #{result[:session]}
                RESULT

                if rules_result
                  output += "\nRules applied: #{rules_result[:applied_count]} rule(s)"
                  output += "\nRule errors: #{rules_result[:errors].join(", ")}" unless rules_result[:errors].empty?
                end

                BaseTool.text_response(output.strip)
              end
            end

            private

            def apply_project_rules(server_context, project_name, session_name)
              rules_manager = server_context[:rules_manager]
              rules_manager.apply_rules(project_name, session_name)
            rescue StandardError => e
              # Don't fail worktree creation if rules fail
              { applied_count: 0, errors: [e.message] }
            end
          end
        end

        # Remove a worktree from a session
        class RemoveWorktree < ::MCP::Tool
          description "Remove a worktree from a session"

          input_schema(
            type: "object",
            properties: {
              project_name: {
                type: "string",
                description: "Project name of the worktree to remove"
              },
              session_name: {
                type: "string",
                description: "Session name (defaults to current session)"
              }
            },
            required: ["project_name"]
          )

          class << self
            def call(project_name:, server_context:, session_name: nil)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                worktree_manager = server_context[:worktree_manager]
                worktree_manager.remove_worktree(project_name, session_name: session_name)

                BaseTool.text_response("Worktree for '#{project_name}' removed successfully.")
              end
            end
          end
        end
      end
    end
  end
end
