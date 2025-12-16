# frozen_string_literal: true

module Sxn
  module MCP
    module Tools
      module Rules
        # List rules for a project
        class ListRules < ::MCP::Tool
          description "List project rules (copy_files, setup_commands, templates)"

          input_schema(
            type: "object",
            properties: {
              project_name: {
                type: "string",
                description: "Project name (lists all rules if not specified)"
              }
            },
            required: []
          )

          class << self
            def call(server_context:, project_name: nil)
              BaseTool.ensure_initialized!(server_context)

              BaseTool::ErrorMapping.wrap do
                rules_manager = server_context[:rules_manager]
                rules = rules_manager.list_rules(project_name)

                if rules.empty?
                  BaseTool.text_response("No rules defined.")
                else
                  # Group by project
                  by_project = rules.group_by { |r| r[:project] }

                  output = by_project.map do |proj, proj_rules|
                    proj_output = "#{proj}:\n"
                    proj_rules.each do |rule|
                      config_preview = case rule[:type]
                                       when "copy_files"
                                         rule[:config]["source"]
                                       when "setup_commands"
                                         rule[:config]["command"]&.join(" ")
                                       when "template"
                                         "#{rule[:config]["source"]} -> #{rule[:config]["destination"]}"
                                       else
                                         rule[:config].to_s
                                       end
                      proj_output += "  - [#{rule[:type]}] #{config_preview}\n"
                    end
                    proj_output
                  end.join("\n")

                  BaseTool.text_response("Project rules:\n\n#{output}")
                end
              end
            end
          end
        end

        # Apply rules to a worktree
        class ApplyRules < ::MCP::Tool
          description "Apply project-specific rules to a worktree (copy files, run setup commands)"

          input_schema(
            type: "object",
            properties: {
              project_name: {
                type: "string",
                description: "Project name"
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
                rules_manager = server_context[:rules_manager]

                result = rules_manager.apply_rules(project_name, session_name)

                if result[:success]
                  BaseTool.text_response(
                    "Rules applied successfully to '#{project_name}'.\n" \
                    "Applied: #{result[:applied_count]} rule(s)"
                  )
                else
                  BaseTool.text_response(
                    "Some rules failed for '#{project_name}'.\n" \
                    "Applied: #{result[:applied_count]} rule(s)\n" \
                    "Errors:\n#{result[:errors].map { |e| "  - #{e}" }.join("\n")}"
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
