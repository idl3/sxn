# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "json"

RSpec.describe Sxn::Commands::MCP do
  let(:temp_dir) { Dir.mktmpdir("sxn_mcp_cmd_test") }

  after { FileUtils.rm_rf(temp_dir) }

  describe "#find_sxn_mcp_executable" do
    it "finds executable in gem bin directory" do
      cmd = described_class.new
      path = cmd.send(:find_sxn_mcp_executable)

      # Should find the gem's bin/sxn-mcp
      expect(path).not_to be_nil
      expect(path).to include("bin/sxn-mcp")
    end
  end

  describe "status" do
    it "shows status without error" do
      Dir.chdir(temp_dir) do
        expect { described_class.new.status }.to output(/MCP Server Status/i).to_stdout
      end
    end

    it "shows Claude Code installation status" do
      Dir.chdir(temp_dir) do
        expect { described_class.new.status }.to output(/Claude Code.*:/i).to_stdout
      end
    end

    it "shows project installation status" do
      Dir.chdir(temp_dir) do
        expect { described_class.new.status }.to output(/Project.*:/i).to_stdout
      end
    end
  end

  describe "install --project" do
    it "creates .mcp.json file" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new
        cmd.options = { project: true }

        expect { cmd.install }.to output(/Created.*\.mcp\.json/i).to_stdout

        # Verify file was created
        mcp_json_path = File.join(temp_dir, ".mcp.json")
        expect(File.exist?(mcp_json_path)).to be true

        # Verify content
        mcp_config = JSON.parse(File.read(mcp_json_path))
        expect(mcp_config["mcpServers"]["sxn"]).not_to be_nil
        expect(mcp_config["mcpServers"]["sxn"]["command"]).to include("sxn-mcp")
      end
    end

    it "updates existing .mcp.json file" do
      Dir.chdir(temp_dir) do
        # Create existing .mcp.json with another server
        mcp_json_path = File.join(temp_dir, ".mcp.json")
        File.write(mcp_json_path, JSON.pretty_generate({
                                                         "mcpServers" => {
                                                           "other-server" => {
                                                             "command" => "other-command"
                                                           }
                                                         }
                                                       }))

        cmd = described_class.new
        cmd.options = { project: true }

        expect { cmd.install }.to output(/Created.*\.mcp\.json/i).to_stdout

        # Verify both servers exist
        mcp_config = JSON.parse(File.read(mcp_json_path))
        expect(mcp_config["mcpServers"]["other-server"]).not_to be_nil
        expect(mcp_config["mcpServers"]["sxn"]).not_to be_nil
      end
    end
  end

  describe "uninstall --project" do
    context "when .mcp.json exists with sxn" do
      it "removes sxn from .mcp.json" do
        Dir.chdir(temp_dir) do
          # Create .mcp.json with sxn
          mcp_json_path = File.join(temp_dir, ".mcp.json")
          File.write(mcp_json_path, JSON.pretty_generate({
                                                           "mcpServers" => {
                                                             "sxn" => { "command" => "sxn-mcp" },
                                                             "other" => { "command" => "other" }
                                                           }
                                                         }))

          cmd = described_class.new
          cmd.options = { project: true }

          expect { cmd.uninstall }.to output(/Removed sxn from/i).to_stdout

          # Verify sxn was removed but other remains
          mcp_config = JSON.parse(File.read(mcp_json_path))
          expect(mcp_config["mcpServers"]["sxn"]).to be_nil
          expect(mcp_config["mcpServers"]["other"]).not_to be_nil
        end
      end

      it "deletes .mcp.json when no servers remain" do
        Dir.chdir(temp_dir) do
          mcp_json_path = File.join(temp_dir, ".mcp.json")
          File.write(mcp_json_path, JSON.pretty_generate({
                                                           "mcpServers" => {
                                                             "sxn" => { "command" => "sxn-mcp" }
                                                           }
                                                         }))

          cmd = described_class.new
          cmd.options = { project: true }

          expect { cmd.uninstall }.to output(/Removed.*no servers remaining/i).to_stdout

          # Verify file was deleted
          expect(File.exist?(mcp_json_path)).to be false
        end
      end
    end

    context "when .mcp.json does not exist" do
      it "shows info message" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = { project: true }

          expect { cmd.uninstall }.to output(/No \.mcp\.json file found/i).to_stdout
        end
      end
    end

    context "when sxn is not in .mcp.json" do
      it "shows info message" do
        Dir.chdir(temp_dir) do
          mcp_json_path = File.join(temp_dir, ".mcp.json")
          File.write(mcp_json_path, JSON.pretty_generate({
                                                           "mcpServers" => {
                                                             "other" => { "command" => "other" }
                                                           }
                                                         }))

          cmd = described_class.new
          cmd.options = { project: true }

          expect { cmd.uninstall }.to output(/sxn not found in \.mcp\.json/i).to_stdout
        end
      end
    end
  end

  describe "#check_project_installation" do
    context "when .mcp.json exists with sxn" do
      it "returns true" do
        Dir.chdir(temp_dir) do
          File.write(".mcp.json", JSON.pretty_generate({
                                                         "mcpServers" => {
                                                           "sxn" => { "command" => "sxn-mcp" }
                                                         }
                                                       }))

          cmd = described_class.new
          expect(cmd.send(:check_project_installation)).to be true
        end
      end
    end

    context "when .mcp.json exists without sxn" do
      it "returns false" do
        Dir.chdir(temp_dir) do
          File.write(".mcp.json", JSON.pretty_generate({
                                                         "mcpServers" => {
                                                           "other" => { "command" => "other" }
                                                         }
                                                       }))

          cmd = described_class.new
          expect(cmd.send(:check_project_installation)).to be false
        end
      end
    end

    context "when .mcp.json does not exist" do
      it "returns false" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          expect(cmd.send(:check_project_installation)).to be false
        end
      end
    end

    context "when .mcp.json is invalid JSON" do
      it "returns false" do
        Dir.chdir(temp_dir) do
          File.write(".mcp.json", "not valid json")

          cmd = described_class.new
          expect(cmd.send(:check_project_installation)).to be false
        end
      end
    end
  end

  describe "install (to Claude Code)" do
    context "when claude CLI is not available" do
      it "shows error and recovery suggestion" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = {}

          # Mock claude_cli_available? to return false
          allow(cmd).to receive(:claude_cli_available?).and_return(false)

          expect do
            cmd.install
          end.to raise_error(SystemExit).and output(/Claude CLI not found/i).to_stdout
        end
      end
    end
  end

  describe "uninstall (from Claude Code)" do
    context "when claude CLI is not available" do
      it "shows error" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = {}

          # Mock claude_cli_available? to return false
          allow(cmd).to receive(:claude_cli_available?).and_return(false)

          expect do
            cmd.uninstall
          end.to raise_error(SystemExit).and output(/Claude CLI not found/i).to_stdout
        end
      end
    end

    context "when claude CLI is available" do
      it "successfully uninstalls from Claude Code" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = {}

          # Mock claude_cli_available? to return true
          allow(cmd).to receive(:claude_cli_available?).and_return(true)
          # Mock successful system call
          allow(cmd).to receive(:system).with("claude", "mcp", "remove", "sxn").and_return(true)

          expect { cmd.uninstall }.to output(/removed from Claude Code/i).to_stdout
        end
      end

      it "handles failed uninstallation from Claude Code" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = {}

          # Mock claude_cli_available? to return true
          allow(cmd).to receive(:claude_cli_available?).and_return(true)
          # Mock failed system call
          allow(cmd).to receive(:system).with("claude", "mcp", "remove", "sxn").and_return(false)

          expect { cmd.uninstall }.to output(/Failed to remove MCP server/i).to_stdout
        end
      end
    end
  end

  describe "install (to Claude Code)" do
    context "when claude CLI is available" do
      it "successfully installs to Claude Code" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = {}

          # Mock claude_cli_available? to return true
          allow(cmd).to receive(:claude_cli_available?).and_return(true)
          # Mock successful system call
          allow(cmd).to receive(:system).with(
            "claude", "mcp", "add", "--transport", "stdio", "sxn", "--", anything
          ).and_return(true)

          expect { cmd.install }.to output(/installed to Claude Code/i).to_stdout
        end
      end

      it "handles failed installation to Claude Code" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new
          cmd.options = {}

          # Mock claude_cli_available? to return true
          allow(cmd).to receive(:claude_cli_available?).and_return(true)
          # Mock failed system call
          allow(cmd).to receive(:system).with(
            "claude", "mcp", "add", "--transport", "stdio", "sxn", "--", anything
          ).and_return(false)

          expect do
            cmd.install
          end.to raise_error(SystemExit).and output(/Failed to install MCP server/i).to_stdout
        end
      end
    end
  end

  describe "install when sxn-mcp executable not found" do
    it "shows error when sxn_mcp_path is nil" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new
        cmd.options = {}

        # Mock find_sxn_mcp_executable to return nil
        allow(cmd).to receive(:find_sxn_mcp_executable).and_return(nil)

        expect do
          cmd.install
        end.to raise_error(SystemExit).and output(/Could not find sxn-mcp executable/i).to_stdout
      end
    end
  end

  describe "#check_claude_installation" do
    context "when claude CLI is available" do
      it "returns true when sxn is installed" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new

          # Mock claude_cli_available? to return true
          allow(cmd).to receive(:claude_cli_available?).and_return(true)
          # Mock successful command with output
          allow(cmd).to receive(:`).with("claude mcp get sxn 2>/dev/null") do
            # Set $? to a successful status
            `true`
            "some config"
          end

          expect(cmd.send(:check_claude_installation)).to be true
        end
      end

      it "returns false when sxn is not installed" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new

          # Mock claude_cli_available? to return true
          allow(cmd).to receive(:claude_cli_available?).and_return(true)
          # Mock command with no output
          allow(cmd).to receive(:`).with("claude mcp get sxn 2>/dev/null") do
            # Set $? to a failed status
            `false`
            ""
          end

          expect(cmd.send(:check_claude_installation)).to be false
        end
      end
    end

    context "when claude CLI is not available" do
      it "returns false" do
        Dir.chdir(temp_dir) do
          cmd = described_class.new

          # Mock claude_cli_available? to return false
          allow(cmd).to receive(:claude_cli_available?).and_return(false)

          expect(cmd.send(:check_claude_installation)).to be false
        end
      end
    end
  end

  describe "status with various installation states" do
    it "shows install commands when nothing is installed" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new

        # Mock both installations as false
        allow(cmd).to receive(:check_claude_installation).and_return(false)
        allow(cmd).to receive(:check_project_installation).and_return(false)

        expect { cmd.status }.to output(/Install Commands/i).to_stdout
      end
    end

    it "does not show install commands when Claude Code is installed" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new

        # Mock Claude installation as true
        allow(cmd).to receive(:check_claude_installation).and_return(true)
        allow(cmd).to receive(:check_project_installation).and_return(false)

        # Should not output install commands
        expect { cmd.status }.not_to output(/Install Commands/i).to_stdout
      end
    end

    it "does not show install commands when project is installed" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new

        # Mock project installation as true
        allow(cmd).to receive(:check_claude_installation).and_return(false)
        allow(cmd).to receive(:check_project_installation).and_return(true)

        # Should not output install commands
        expect { cmd.status }.not_to output(/Install Commands/i).to_stdout
      end
    end

    it "shows warning when executable not found" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new

        # Mock find_sxn_mcp_executable to return nil
        allow(cmd).to receive(:find_sxn_mcp_executable).and_return(nil)
        allow(cmd).to receive(:check_claude_installation).and_return(false)
        allow(cmd).to receive(:check_project_installation).and_return(false)

        expect { cmd.status }.to output(/sxn-mcp executable not found/i).to_stdout
      end
    end
  end

  describe "server command" do
    before do
      # Require the MCP server classes
      require "sxn/mcp"
    end

    it "starts server with stdio transport" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new
        cmd.options = { transport: "stdio" }

        # Mock the MCP server
        mock_server = instance_double(Sxn::MCP::Server)
        allow(Sxn::MCP::Server).to receive(:new).and_return(mock_server)
        allow(mock_server).to receive(:run_stdio)

        expect { cmd.server }.to output(/Starting MCP server with STDIO/i).to_stdout
        expect(mock_server).to have_received(:run_stdio)
      end
    end

    it "starts server with http transport" do
      Dir.chdir(temp_dir) do
        cmd = described_class.new
        cmd.options = { transport: "http", port: 3000 }

        # Mock the MCP server
        mock_server = instance_double(Sxn::MCP::Server)
        allow(Sxn::MCP::Server).to receive(:new).and_return(mock_server)
        allow(mock_server).to receive(:run_http)

        expect { cmd.server }.to output(/Starting MCP server on port 3000/i).to_stdout
        expect(mock_server).to have_received(:run_http).with(port: 3000)
      end
    end
  end

  describe "#find_sxn_mcp_executable" do
    context "when sxn-mcp is in PATH" do
      it "returns the path from which command" do
        cmd = described_class.new

        # Mock which command to return a path
        allow(cmd).to receive(:`).with("which sxn-mcp 2>/dev/null").and_return("/usr/local/bin/sxn-mcp\n")

        path = cmd.send(:find_sxn_mcp_executable)
        expect(path).to eq("/usr/local/bin/sxn-mcp")
      end
    end

    context "when sxn-mcp is not in PATH but exists in gem bin" do
      it "returns the gem bin path" do
        cmd = described_class.new

        # Mock which command to return empty
        allow(cmd).to receive(:`).with("which sxn-mcp 2>/dev/null").and_return("")

        # The gem_bin_path should actually exist in this test environment
        path = cmd.send(:find_sxn_mcp_executable)
        expect(path).not_to be_nil
        expect(path).to include("bin/sxn-mcp")
      end
    end

    context "when sxn-mcp is not found anywhere" do
      it "returns nil" do
        cmd = described_class.new

        # Mock which command to return empty
        allow(cmd).to receive(:`).with("which sxn-mcp 2>/dev/null").and_return("")
        # Mock File.exist? to return false for gem bin path
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(anything).and_return(false)

        path = cmd.send(:find_sxn_mcp_executable)
        expect(path).to be_nil
      end
    end
  end
end
