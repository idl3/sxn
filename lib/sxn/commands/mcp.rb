# frozen_string_literal: true

require "thor"
require "json"
require "English"

module Sxn
  module Commands
    # Manage MCP server for Claude Code integration
    class MCP < Thor
      include Thor::Actions

      def initialize(args = ARGV, local_options = {}, config = {})
        super
        @ui = Sxn::UI::Output.new
      end

      desc "install", "Install sxn MCP server to Claude Code"
      option :project, type: :boolean, aliases: "-p", desc: "Install to project .mcp.json instead of user config"
      def install
        sxn_mcp_path = find_sxn_mcp_executable

        if sxn_mcp_path.nil?
          @ui.error("Could not find sxn-mcp executable")
          @ui.recovery_suggestion("Ensure the sxn gem is properly installed")
          exit(1)
        end

        if options[:project]
          install_to_project(sxn_mcp_path)
        else
          install_to_claude_code(sxn_mcp_path)
        end
      end

      desc "uninstall", "Remove sxn MCP server from Claude Code"
      option :project, type: :boolean, aliases: "-p", desc: "Remove from project .mcp.json"
      def uninstall
        if options[:project]
          uninstall_from_project
        else
          uninstall_from_claude_code
        end
      end

      desc "status", "Check if sxn MCP server is installed"
      def status
        @ui.section("MCP Server Status")

        claude_installed = check_claude_installation
        project_installed = check_project_installation

        @ui.newline
        @ui.key_value("Claude Code (user)", claude_installed ? "Installed" : "Not installed")
        @ui.key_value("Project (.mcp.json)", project_installed ? "Installed" : "Not installed")

        sxn_mcp_path = find_sxn_mcp_executable
        @ui.newline
        if sxn_mcp_path
          @ui.key_value("Executable", sxn_mcp_path)
        else
          @ui.warning("sxn-mcp executable not found in PATH")
        end

        @ui.newline
        display_install_commands unless claude_installed || project_installed
      end

      desc "server", "Run the MCP server directly (for testing)"
      option :transport, type: :string, default: "stdio", enum: %w[stdio http], desc: "Transport type"
      option :port, type: :numeric, default: 3000, desc: "Port for HTTP transport"
      def server
        require "sxn/mcp"

        mcp_server = Sxn::MCP::Server.new

        case options[:transport]
        when "stdio"
          @ui.info("Starting MCP server with STDIO transport...")
          mcp_server.run_stdio
        when "http"
          @ui.info("Starting MCP server on port #{options[:port]}...")
          mcp_server.run_http(port: options[:port])
        end
      end

      private

      def find_sxn_mcp_executable
        # Check if sxn-mcp is in PATH
        path = `which sxn-mcp 2>/dev/null`.strip
        return path unless path.empty?

        # Check relative to this gem's installation
        gem_bin_path = File.expand_path("../../../bin/sxn-mcp", __dir__)
        return gem_bin_path if File.exist?(gem_bin_path)

        nil
      end

      def install_to_claude_code(sxn_mcp_path)
        unless claude_cli_available?
          @ui.error("Claude CLI not found")
          @ui.recovery_suggestion("Install Claude Code CLI first: https://claude.ai/code")
          exit(1)
        end

        @ui.progress_start("Installing sxn MCP server to Claude Code")

        # claude mcp add --transport stdio sxn -- /path/to/sxn-mcp
        success = system("claude", "mcp", "add", "--transport", "stdio", "sxn", "--", sxn_mcp_path)

        if success
          @ui.progress_done
          @ui.success("sxn MCP server installed to Claude Code")
          @ui.info("Restart Claude Code to use the new server")
        else
          @ui.progress_failed
          @ui.error("Failed to install MCP server")
          @ui.recovery_suggestion("Try running manually: claude mcp add --transport stdio sxn -- #{sxn_mcp_path}")
          exit(1)
        end
      end

      def install_to_project(sxn_mcp_path)
        mcp_json_path = File.join(Dir.pwd, ".mcp.json")

        mcp_config = if File.exist?(mcp_json_path)
                       JSON.parse(File.read(mcp_json_path))
                     else
                       { "mcpServers" => {} }
                     end

        mcp_config["mcpServers"] ||= {}
        mcp_config["mcpServers"]["sxn"] = {
          "command" => sxn_mcp_path,
          "args" => [],
          "env" => { "SXN_WORKSPACE" => "${PWD}" }
        }

        File.write(mcp_json_path, JSON.pretty_generate(mcp_config))

        @ui.success("Created/updated .mcp.json with sxn MCP server")
        @ui.info("This file can be version controlled to share with your team")
      end

      def uninstall_from_claude_code
        unless claude_cli_available?
          @ui.error("Claude CLI not found")
          exit(1)
        end

        @ui.progress_start("Removing sxn MCP server from Claude Code")

        success = system("claude", "mcp", "remove", "sxn")

        if success
          @ui.progress_done
          @ui.success("sxn MCP server removed from Claude Code")
        else
          @ui.progress_failed
          @ui.error("Failed to remove MCP server (it may not be installed)")
        end
      end

      def uninstall_from_project
        mcp_json_path = File.join(Dir.pwd, ".mcp.json")

        unless File.exist?(mcp_json_path)
          @ui.info("No .mcp.json file found in current directory")
          return
        end

        mcp_config = JSON.parse(File.read(mcp_json_path))

        if mcp_config.dig("mcpServers", "sxn")
          mcp_config["mcpServers"].delete("sxn")

          if mcp_config["mcpServers"].empty?
            File.delete(mcp_json_path)
            @ui.success("Removed .mcp.json file (no servers remaining)")
          else
            File.write(mcp_json_path, JSON.pretty_generate(mcp_config))
            @ui.success("Removed sxn from .mcp.json")
          end
        else
          @ui.info("sxn not found in .mcp.json")
        end
      end

      def check_claude_installation
        return false unless claude_cli_available?

        output = `claude mcp get sxn 2>/dev/null`
        $CHILD_STATUS.success? && !output.strip.empty?
      end

      def check_project_installation
        mcp_json_path = File.join(Dir.pwd, ".mcp.json")
        return false unless File.exist?(mcp_json_path)

        mcp_config = JSON.parse(File.read(mcp_json_path))
        !mcp_config.dig("mcpServers", "sxn").nil?
      rescue JSON::ParserError
        false
      end

      def claude_cli_available?
        system("which claude > /dev/null 2>&1")
      end

      def display_install_commands
        @ui.subsection("Install Commands")
        @ui.command_example("sxn mcp install", "Install to Claude Code (user scope)")
        @ui.command_example("sxn mcp install --project", "Install to project .mcp.json")
      end
    end
  end
end
