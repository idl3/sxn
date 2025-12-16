# frozen_string_literal: true

module Sxn
  module MCP
    module Prompts
      # Guided new session creation workflow
      class NewSession < ::MCP::Prompt
        prompt_name "new-session"
        description "Guided workflow for creating a new development session"

        arguments [
          ::MCP::Prompt::Argument.new(
            name: "task_description",
            description: "Brief description of what you're working on",
            required: false
          ),
          ::MCP::Prompt::Argument.new(
            name: "projects",
            description: "Comma-separated list of projects to include",
            required: false
          )
        ]

        class << self
          def template(args = {}, _server_context: nil)
            # Handle both string and symbol keys
            task_description = args["task_description"] || args[:task_description]
            projects = args["projects"] || args[:projects]
            project_list = projects ? projects.split(",").map(&:strip).join(", ") : "Not specified"

            <<~PROMPT
              # Create a New Development Session

              Help me create a new sxn development session.

              ## Task Information
              - Description: #{task_description || "Not provided"}
              - Requested projects: #{project_list}

              ## Steps to Complete

              1. **Generate session name** based on the task description
              2. **Create the session** using sxn_sessions_create
              3. **Add worktrees** for each requested project using sxn_worktrees_add
              4. **Navigate to the session** using sxn_sessions_swap

              ## Guidelines
              - Session names should be descriptive but concise (e.g., "user-auth", "api-refactor")
              - Use alphanumeric characters, hyphens, and underscores only
              - Apply project rules automatically when creating worktrees
            PROMPT
          end
        end
      end

      # Multi-repo setup workflow
      class MultiRepoSetup < ::MCP::Prompt
        prompt_name "multi-repo-setup"
        description "Set up a multi-repository development environment"

        arguments [
          ::MCP::Prompt::Argument.new(
            name: "feature_name",
            description: "Name of the feature being developed across repos",
            required: true
          ),
          ::MCP::Prompt::Argument.new(
            name: "repos",
            description: "Comma-separated list of repository names to include",
            required: false
          )
        ]

        class << self
          def template(args = {}, _server_context: nil)
            # Handle both string and symbol keys
            feature_name = args["feature_name"] || args[:feature_name]
            repos = args["repos"] || args[:repos]
            repo_list = repos ? repos.split(",").map(&:strip) : []

            <<~PROMPT
              # Multi-Repository Development Setup

              Set up a coordinated development environment for: **#{feature_name}**

              ## Repositories to Include
              #{repo_list.empty? ? "- (Will use sxn_projects_list to find available projects)" : repo_list.map { |r| "- #{r}" }.join("\n")}

              ## Setup Process

              1. **Check registered projects** with sxn_projects_list
              2. **Create the session** with sxn_sessions_create
                 - Name: #{feature_name.downcase.gsub(/\s+/, "-")}
              3. **Add worktrees** for each repository with sxn_worktrees_add
              4. **Apply rules** with sxn_rules_apply for each project
              5. **Navigate** using sxn_sessions_swap

              ## Best Practices
              - Use the same branch name across all repos
              - Apply rules to copy environment files
            PROMPT
          end
        end
      end
    end
  end
end
