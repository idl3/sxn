# frozen_string_literal: true

module Sxn
  module MCP
    module Tools
      module Projects
        # List registered projects
        class ListProjects < ::MCP::Tool
          description "List all registered projects in the sxn workspace"

          input_schema(
            type: "object",
            properties: {},
            required: []
          )

          class << self
            def call(server_context:)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                project_manager = server_context[:project_manager]
                projects = project_manager.list_projects

                if projects.empty?
                  BaseTool.text_response("No projects registered. Use sxn_projects_add to register a project.")
                else
                  formatted = projects.map do |p|
                    "- #{p[:name]} (#{p[:type]})\n  #{p[:path]}\n  Default branch: #{p[:default_branch]}"
                  end.join("\n")

                  BaseTool.text_response("Registered projects (#{projects.length}):\n#{formatted}")
                end
              end
            end
          end
        end

        # Register a new project
        class AddProject < ::MCP::Tool
          description "Register a new git repository as a project. " \
                      "Automatically detects project type and default branch."

          input_schema(
            type: "object",
            properties: {
              name: {
                type: "string",
                pattern: "^[a-zA-Z0-9_-]+$",
                description: "Project name (alphanumeric, hyphens, underscores only)"
              },
              path: {
                type: "string",
                description: "Path to the git repository (absolute or relative)"
              },
              type: {
                type: "string",
                description: "Project type (auto-detected if not specified). " \
                             "Options: rails, ruby, javascript, typescript, react, nextjs, etc."
              },
              default_branch: {
                type: "string",
                description: "Default branch for worktrees (auto-detected if not specified)"
              }
            },
            required: %w[name path]
          )

          class << self
            def call(name:, path:, server_context:, type: nil, default_branch: nil)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                project_manager = server_context[:project_manager]

                result = project_manager.add_project(
                  name,
                  path,
                  type: type,
                  default_branch: default_branch
                )

                BaseTool.text_response(
                  "Project '#{result[:name]}' registered successfully.\n" \
                  "Type: #{result[:type]}\n" \
                  "Path: #{result[:path]}\n" \
                  "Default branch: #{result[:default_branch]}"
                )
              end
            end
          end
        end

        # Get project details
        class GetProject < ::MCP::Tool
          description "Get detailed information about a registered project"

          input_schema(
            type: "object",
            properties: {
              name: {
                type: "string",
                description: "Project name to retrieve"
              }
            },
            required: ["name"]
          )

          class << self
            def call(name:, server_context:)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                project_manager = server_context[:project_manager]
                project = project_manager.get_project(name)

                # Validate the project
                validation = project_manager.validate_project(name)

                # Get project rules
                rules = project_manager.get_project_rules(name)
                rules_summary = rules.map { |type, configs| "#{type}: #{Array(configs).length}" }.join(", ")

                output = <<~INFO
                  Project: #{project[:name]}
                  Type: #{project[:type]}
                  Path: #{project[:path]}
                  Default branch: #{project[:default_branch]}

                  Validation: #{validation[:valid] ? "Valid" : "Invalid"}
                  #{validation[:issues].map { |i| "  - #{i}" }.join("\n") unless validation[:valid]}

                  Rules: #{rules_summary.empty? ? "(none)" : rules_summary}
                INFO

                BaseTool.text_response(output.strip)
              end
            end
          end
        end
      end
    end
  end
end
