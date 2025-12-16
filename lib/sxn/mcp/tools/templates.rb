# frozen_string_literal: true

module Sxn
  module MCP
    module Tools
      module Templates
        # List available templates
        class ListTemplates < ::MCP::Tool
          description "List available session templates"

          input_schema(
            type: "object",
            properties: {},
            required: []
          )

          class << self
            def call(server_context:)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                template_manager = server_context[:template_manager]
                templates = template_manager.list_templates

                if templates.empty?
                  BaseTool.text_response(
                    "No templates defined. Templates can be created in .sxn/templates.yml"
                  )
                else
                  formatted = templates.map do |t|
                    desc = t[:description] ? " - #{t[:description]}" : ""
                    "- #{t[:name]} (#{t[:project_count]} projects)#{desc}"
                  end.join("\n")

                  BaseTool.text_response("Available templates:\n#{formatted}")
                end
              end
            end
          end
        end

        # Apply a template to a session
        class ApplyTemplate < ::MCP::Tool
          description "Apply a template to create multiple worktrees in a session"

          input_schema(
            type: "object",
            properties: {
              template_name: {
                type: "string",
                description: "Template name to apply"
              },
              session_name: {
                type: "string",
                description: "Target session (defaults to current session)"
              }
            },
            required: ["template_name"]
          )

          class << self
            def call(template_name:, server_context:, session_name: nil)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                template_manager = server_context[:template_manager]
                worktree_manager = server_context[:worktree_manager]
                session_manager = server_context[:session_manager]
                config_manager = server_context[:config_manager]

                # Get session (use current if not specified)
                session_name ||= config_manager.current_session
                raise Sxn::NoActiveSessionError, "No active session" unless session_name

                session = session_manager.get_session(session_name)
                raise Sxn::SessionNotFoundError, "Session '#{session_name}' not found" unless session

                # Validate template
                template_manager.validate_template(template_name)

                # Get template projects with default branch
                default_branch = session[:default_branch] || session_name
                projects = template_manager.get_template_projects(template_name, default_branch: default_branch)

                # Create worktrees for each project
                results = []
                projects.each do |project|
                  result = worktree_manager.add_worktree(
                    project[:name],
                    project[:branch],
                    session_name: session_name
                  )
                  results << { project: project[:name], status: "success", path: result[:path] }
                rescue StandardError => e
                  results << { project: project[:name], status: "error", error: e.message }
                end

                # Format output
                successful = results.select { |r| r[:status] == "success" }
                failed = results.select { |r| r[:status] == "error" }

                output = "Template '#{template_name}' applied to session '#{session_name}'.\n\n"
                output += "Created #{successful.length} worktree(s):\n"
                successful.each { |r| output += "  - #{r[:project]}: #{r[:path]}\n" }

                unless failed.empty?
                  output += "\nFailed (#{failed.length}):\n"
                  failed.each { |r| output += "  - #{r[:project]}: #{r[:error]}\n" }
                end

                BaseTool.text_response(output.strip)
              end
            end
          end
        end
      end
    end
  end
end
