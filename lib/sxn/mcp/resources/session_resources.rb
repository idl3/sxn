# frozen_string_literal: true

module Sxn
  module MCP
    module Resources
      # Factory methods for creating MCP Resource objects
      module SessionResources
        class << self
          # Build all resources for the server
          def build_all(server_context)
            [
              build_current_session(server_context),
              build_all_sessions(server_context),
              build_all_projects(server_context)
            ].compact
          end

          private

          def build_current_session(server_context)
            return nil unless server_context[:config_manager]

            ::MCP::Resource.new(
              uri: "sxn://session/current",
              name: "Current Session",
              description: "Information about the currently active sxn session",
              mime_type: "application/json"
            )
          end

          def build_all_sessions(server_context)
            return nil unless server_context[:config_manager]

            ::MCP::Resource.new(
              uri: "sxn://sessions",
              name: "All Sessions",
              description: "Summary of all sxn sessions",
              mime_type: "application/json"
            )
          end

          def build_all_projects(server_context)
            return nil unless server_context[:config_manager]

            ::MCP::Resource.new(
              uri: "sxn://projects",
              name: "Registered Projects",
              description: "All registered projects in the sxn workspace",
              mime_type: "application/json"
            )
          end
        end
      end

      # Resource content readers
      module ResourceContentReader
        class << self
          def read_content(uri, server_context)
            case uri
            when "sxn://session/current"
              read_current_session(server_context)
            when "sxn://sessions"
              read_all_sessions(server_context)
            when "sxn://projects"
              read_all_projects(server_context)
            else
              JSON.generate({ error: "Unknown resource: #{uri}" })
            end
          end

          private

          def read_current_session(server_context)
            config_manager = server_context[:config_manager]
            return JSON.generate({ error: "sxn not initialized" }) unless config_manager

            session_manager = server_context[:session_manager]
            session = session_manager.current_session

            unless session
              return JSON.generate({
                                     current_session: nil,
                                     message: "No active session"
                                   })
            end

            JSON.generate({
                            name: session[:name],
                            status: session[:status],
                            path: session[:path],
                            created_at: session[:created_at],
                            default_branch: session[:default_branch],
                            worktrees: session[:worktrees],
                            projects: session[:projects]
                          })
          rescue StandardError => e
            JSON.generate({ error: e.message })
          end

          def read_all_sessions(server_context)
            config_manager = server_context[:config_manager]
            return JSON.generate({ error: "sxn not initialized" }) unless config_manager

            session_manager = server_context[:session_manager]
            sessions = session_manager.list_sessions

            JSON.generate({
                            total: sessions.length,
                            sessions: sessions.map do |s|
                              {
                                name: s[:name],
                                status: s[:status],
                                worktree_count: s[:worktrees].keys.length
                              }
                            end
                          })
          rescue StandardError => e
            JSON.generate({ error: e.message })
          end

          def read_all_projects(server_context)
            config_manager = server_context[:config_manager]
            return JSON.generate({ error: "sxn not initialized" }) unless config_manager

            project_manager = server_context[:project_manager]
            projects = project_manager.list_projects

            JSON.generate({
                            total: projects.length,
                            projects: projects.map do |p|
                              {
                                name: p[:name],
                                type: p[:type],
                                path: p[:path]
                              }
                            end
                          })
          rescue StandardError => e
            JSON.generate({ error: e.message })
          end
        end
      end
    end
  end
end
