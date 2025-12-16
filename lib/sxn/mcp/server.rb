# frozen_string_literal: true

module Sxn
  module MCP
    # Main MCP server class that orchestrates tools, resources, and prompts
    class Server
      attr_reader :workspace_path, :config_manager

      def initialize(workspace_path: nil)
        @workspace_path = workspace_path || ENV["SXN_WORKSPACE"] || discover_workspace
        @config_manager = initialize_config_manager
        @server = build_mcp_server
      end

      # Run the server with STDIO transport (for Claude Code integration)
      def run_stdio
        transport = ::MCP::Server::Transports::StdioTransport.new(@server)
        transport.open
      end

      # Run the server with HTTP transport (for web-based integrations)
      def run_http(port: 3000)
        transport = ::MCP::Server::Transports::StreamableHTTPTransport.new(@server)
        transport.run(port: port)
      end

      private

      def discover_workspace
        # Try to find .sxn directory in current or parent directories
        current = Dir.pwd
        loop do
          sxn_path = File.join(current, ".sxn")
          return current if File.directory?(sxn_path)

          parent = File.dirname(current)
          break if parent == current

          current = parent
        end

        # Fall back to current directory
        Dir.pwd
      end

      def initialize_config_manager
        Sxn::Core::ConfigManager.new(@workspace_path)
      rescue Sxn::ConfigurationError
        # Allow server to start even if sxn isn't initialized
        # Tools will return appropriate errors
        nil
      end

      def build_mcp_server
        context = build_context

        server = ::MCP::Server.new(
          name: "sxn",
          version: Sxn::VERSION,
          tools: registered_tools,
          resources: registered_resources(context),
          prompts: registered_prompts,
          server_context: context
        )

        # Set up resource read handler
        server.resources_read_handler do |params|
          uri = params[:uri]
          content = Resources::ResourceContentReader.read_content(uri, context)
          [{ uri: uri, text: content, mimeType: "application/json" }]
        end

        server
      end

      def build_context
        {
          config_manager: @config_manager,
          session_manager: @config_manager && Sxn::Core::SessionManager.new(@config_manager),
          project_manager: @config_manager && Sxn::Core::ProjectManager.new(@config_manager),
          worktree_manager: @config_manager && Sxn::Core::WorktreeManager.new(@config_manager),
          template_manager: @config_manager && Sxn::Core::TemplateManager.new(@config_manager),
          rules_manager: @config_manager && Sxn::Core::RulesManager.new(@config_manager),
          workspace_path: @workspace_path
        }
      end

      def registered_tools
        [
          # Session tools
          Tools::Sessions::ListSessions,
          Tools::Sessions::CreateSession,
          Tools::Sessions::GetSession,
          Tools::Sessions::DeleteSession,
          Tools::Sessions::ArchiveSession,
          Tools::Sessions::ActivateSession,
          Tools::Sessions::SwapSession,
          # Worktree tools
          Tools::Worktrees::ListWorktrees,
          Tools::Worktrees::AddWorktree,
          Tools::Worktrees::RemoveWorktree,
          # Project tools
          Tools::Projects::ListProjects,
          Tools::Projects::AddProject,
          Tools::Projects::GetProject,
          # Template tools
          Tools::Templates::ListTemplates,
          Tools::Templates::ApplyTemplate,
          # Rules tools
          Tools::Rules::ListRules,
          Tools::Rules::ApplyRules
        ]
      end

      def registered_resources(context)
        Resources::SessionResources.build_all(context)
      end

      def registered_prompts
        [
          Prompts::NewSession,
          Prompts::MultiRepoSetup
        ]
      end
    end
  end
end
