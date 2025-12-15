# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::Table do
  let(:table) { described_class.new }
  let(:mock_pastel) { double("Pastel") }
  let(:mock_tty_table) { double("TTY::Table") }

  before do
    allow(Pastel).to receive(:new).and_return(mock_pastel)
    allow(TTY::Table).to receive(:new).and_return(mock_tty_table)
    allow(mock_tty_table).to receive(:render).and_return("rendered_table")

    # Mock pastel color methods
    allow(mock_pastel).to receive(:green).and_return("GREEN")
    allow(mock_pastel).to receive(:red).and_return("RED")
    allow(mock_pastel).to receive(:yellow).and_return("YELLOW")
    allow(mock_pastel).to receive(:dim).and_return("DIM")
  end

  describe "#sessions" do
    context "with sessions data" do
      let(:sessions) do
        [
          {
            name: "session1",
            status: "active",
            projects: %w[project1 project2],
            created_at: "2023-01-01T10:00:00Z",
            updated_at: "2023-01-02T15:30:00Z"
          },
          {
            name: "session2",
            status: "archived",
            projects: [],
            created_at: "2023-01-01T08:00:00Z",
            updated_at: "2023-01-01T09:00:00Z"
          }
        ]
      end

      it "renders sessions table with headers and data" do
        allow(table).to receive(:status_indicator).with("active").and_return("● Active")
        allow(table).to receive(:status_indicator).with("archived").and_return("◌ Archived")
        allow(table).to receive(:format_date).and_return("formatted_date")

        expect do
          table.sessions(sessions)
        end.to output("rendered_table\n").to_stdout

        expect(TTY::Table).to have_received(:new).with(
          header: %w[Name Status Projects Created Updated],
          rows: [
            ["session1", "● Active", "project1, project2", "formatted_date", "formatted_date"],
            ["session2", "◌ Archived", "", "formatted_date", "formatted_date"]
          ]
        )
      end

      it "handles sessions with nil projects" do
        sessions[0][:projects] = nil
        allow(table).to receive(:status_indicator).and_return("status")
        allow(table).to receive(:format_date).and_return("date")

        expect do
          table.sessions(sessions)
        end.to output("rendered_table\n").to_stdout
      end
    end

    context "with empty sessions" do
      it "displays empty state message" do
        expect do
          table.sessions([])
        end.to output("DIM\n").to_stdout

        expect(mock_pastel).to have_received(:dim).with("  No sessions found")
      end
    end
  end

  describe "#projects" do
    context "with projects data" do
      let(:projects) do
        [
          {
            name: "project1",
            type: "rails",
            path: "/very/long/path/to/project1",
            default_branch: "main"
          },
          {
            name: "project2",
            type: nil,
            path: "/short/path",
            default_branch: nil
          }
        ]
      end

      it "renders projects table with headers and data" do
        allow(table).to receive(:truncate_path).and_return("truncated_path")

        expect do
          table.projects(projects)
        end.to output("rendered_table\n").to_stdout

        expect(TTY::Table).to have_received(:new).with(
          header: ["Name", "Type", "Path", "Default Branch"],
          rows: [
            %w[project1 rails truncated_path main],
            %w[project2 unknown truncated_path master]
          ]
        )
      end
    end

    context "with empty projects" do
      it "displays empty state message" do
        expect do
          table.projects([])
        end.to output("DIM\n").to_stdout

        expect(mock_pastel).to have_received(:dim).with("  No projects configured")
      end
    end
  end

  describe "#worktrees" do
    context "with worktrees data" do
      let(:worktrees) do
        [
          {
            project: "project1",
            branch: "main",
            path: "/path/to/worktree1"
          },
          {
            project: "project2",
            branch: "feature",
            path: "/path/to/worktree2"
          }
        ]
      end

      it "renders worktrees table with headers and data" do
        allow(table).to receive(:truncate_path).and_return("truncated_path")
        allow(table).to receive(:worktree_status).and_return("status")

        expect do
          table.worktrees(worktrees)
        end.to output("rendered_table\n").to_stdout

        expect(TTY::Table).to have_received(:new).with(
          header: %w[Project Branch Path Status],
          rows: [
            %w[project1 main truncated_path status],
            %w[project2 feature truncated_path status]
          ]
        )
      end
    end

    context "with empty worktrees" do
      it "displays empty state message" do
        expect do
          table.worktrees([])
        end.to output("DIM\n").to_stdout

        expect(mock_pastel).to have_received(:dim).with("  No worktrees in current session")
      end
    end
  end

  describe "#rules" do
    context "with rules data" do
      let(:rules) do
        [
          {
            project: "project1",
            type: "copy_files",
            config: { source: "file.txt" },
            enabled: true
          },
          {
            project: "project2",
            type: "setup_commands",
            config: { command: %w[npm install] },
            enabled: false
          }
        ]
      end

      it "renders rules table with headers and data" do
        allow(table).to receive(:truncate_config).and_return("truncated_config")

        expect do
          table.rules(rules)
        end.to output("rendered_table\n").to_stdout

        expect(TTY::Table).to have_received(:new).with(
          header: %w[Project Type Config Status],
          rows: [
            %w[project1 copy_files truncated_config GREEN],
            %w[project2 setup_commands truncated_config RED]
          ]
        )
      end

      it "filters rules by project when project_filter provided" do
        allow(table).to receive(:truncate_config).and_return("config")

        expect do
          table.rules(rules, "project1")
        end.to output("rendered_table\n").to_stdout

        expect(TTY::Table).to have_received(:new).with(
          header: %w[Project Type Config Status],
          rows: [%w[project1 copy_files config GREEN]]
        )
      end
    end

    context "with empty rules" do
      it "displays empty state message" do
        expect do
          table.rules([])
        end.to output("DIM\n").to_stdout

        expect(mock_pastel).to have_received(:dim).with("  No rules configured")
      end
    end

    context "with empty filtered rules" do
      let(:rules) do
        [{ project: "project1", type: "copy_files", config: {}, enabled: true }]
      end

      it "displays empty state when no rules match filter" do
        expect do
          table.rules(rules, "nonexistent")
        end.to output("DIM\n").to_stdout
      end
    end
  end

  describe "#templates" do
    context "with templates data" do
      let(:templates) do
        [
          {
            name: "template1",
            description: "A test template",
            project_count: 3
          },
          {
            name: "template2",
            description: nil,
            project_count: 1
          }
        ]
      end

      it "renders templates table with headers and data" do
        expect do
          table.templates(templates)
        end.to output("rendered_table\n").to_stdout

        expect(TTY::Table).to have_received(:new).with(
          header: %w[Name Description Projects],
          rows: [
            ["template1", "A test template", "3"],
            ["template2", "-", "1"]
          ]
        )
      end
    end

    context "with empty templates" do
      it "displays empty state message" do
        expect do
          table.templates([])
        end.to output("DIM\n").to_stdout

        expect(mock_pastel).to have_received(:dim).with("  No templates defined")
      end
    end
  end

  describe "#config_summary" do
    let(:config) do
      {
        sessions_folder: "/path/to/sessions",
        current_session: "my-session",
        auto_cleanup: true,
        max_sessions: 10
      }
    end

    it "renders config summary table" do
      expect do
        table.config_summary(config)
      end.to output("rendered_table\n").to_stdout

      expect(TTY::Table).to have_received(:new).with(
        header: %w[Setting Value Source],
        rows: [
          ["Sessions Folder", "/path/to/sessions", "config"],
          ["Current Session", "my-session", "config"],
          ["Auto Cleanup", "Enabled", "config"],
          ["Max Sessions", 10, "config"]
        ]
      )
    end

    it "handles missing config values" do
      empty_config = {}

      expect do
        table.config_summary(empty_config)
      end.to output("rendered_table\n").to_stdout

      expect(TTY::Table).to have_received(:new).with(
        header: %w[Setting Value Source],
        rows: [
          ["Sessions Folder", "Not set", "config"],
          ["Current Session", "None", "config"],
          ["Auto Cleanup", "Disabled", "config"],
          ["Max Sessions", "Unlimited", "config"]
        ]
      )
    end
  end

  describe "private helper methods" do
    describe "#status_indicator" do
      it "returns green indicator for active status" do
        result = table.send(:status_indicator, "active")
        expect(result).to eq("GREEN")
        expect(mock_pastel).to have_received(:green).with("● Active")
      end

      it "returns yellow indicator for inactive status" do
        result = table.send(:status_indicator, "inactive")
        expect(result).to eq("YELLOW")
        expect(mock_pastel).to have_received(:yellow).with("○ Inactive")
      end

      it "returns dim indicator for archived status" do
        result = table.send(:status_indicator, "archived")
        expect(result).to eq("DIM")
        expect(mock_pastel).to have_received(:dim).with("◌ Archived")
      end

      it "returns dim indicator for unknown status" do
        result = table.send(:status_indicator, "unknown")
        expect(result).to eq("DIM")
        expect(mock_pastel).to have_received(:dim).with("? Unknown")
      end
    end

    describe "#worktree_status" do
      let(:worktree) { { path: "/path/to/worktree" } }

      context "when directory exists and is clean" do
        it "returns green Clean status" do
          allow(File).to receive(:directory?).with("/path/to/worktree").and_return(true)
          allow(table).to receive(:git_clean?).with("/path/to/worktree").and_return(true)

          result = table.send(:worktree_status, worktree)

          expect(result).to eq("GREEN")
          expect(mock_pastel).to have_received(:green).with("Clean")
        end
      end

      context "when directory exists and is modified" do
        it "returns yellow Modified status" do
          allow(File).to receive(:directory?).with("/path/to/worktree").and_return(true)
          allow(table).to receive(:git_clean?).with("/path/to/worktree").and_return(false)

          result = table.send(:worktree_status, worktree)

          expect(result).to eq("YELLOW")
          expect(mock_pastel).to have_received(:yellow).with("Modified")
        end
      end

      context "when directory doesn't exist" do
        it "returns red Missing status" do
          allow(File).to receive(:directory?).with("/path/to/worktree").and_return(false)

          result = table.send(:worktree_status, worktree)

          expect(result).to eq("RED")
          expect(mock_pastel).to have_received(:red).with("Missing")
        end
      end
    end

    describe "#git_clean?" do
      it "returns true when git diff-index succeeds" do
        allow(Dir).to receive(:chdir).with("/path").and_yield
        allow(table).to receive(:system).and_return(true)

        result = table.send(:git_clean?, "/path")

        expect(result).to be(true)
      end

      it "returns false when git diff-index fails" do
        allow(Dir).to receive(:chdir).with("/path").and_yield
        allow(table).to receive(:system).and_return(false)

        result = table.send(:git_clean?, "/path")

        expect(result).to be(false)
      end

      it "returns false when error occurs" do
        allow(Dir).to receive(:chdir).and_raise("Error")

        result = table.send(:git_clean?, "/path")

        expect(result).to be(false)
      end
    end

    describe "#format_date" do
      let(:now) { Time.new(2023, 1, 15, 12, 0, 0) }

      before { allow(Time).to receive(:now).and_return(now) }

      it "returns empty string for nil date" do
        result = table.send(:format_date, nil)
        expect(result).to eq("")
      end

      it "formats time only for dates within 24 hours" do
        recent_date = (now - 3600).iso8601 # 1 hour ago
        allow(Time).to receive(:parse).with(recent_date).and_return(now - 3600)

        result = table.send(:format_date, recent_date)

        expect(result).to eq("11:00")
      end

      it "formats day and time for dates within a week" do
        week_date = (now - (86_400 * 2)).iso8601 # 2 days ago
        week_time = now - (86_400 * 2)
        allow(Time).to receive(:parse).with(week_date).and_return(week_time)

        result = table.send(:format_date, week_date)

        expect(result).to eq(week_time.strftime("%a %H:%M"))
      end

      it "formats month/day for older dates" do
        old_date = (now - (86_400 * 10)).iso8601 # 10 days ago
        old_time = now - (86_400 * 10)
        allow(Time).to receive(:parse).with(old_date).and_return(old_time)

        result = table.send(:format_date, old_date)

        expect(result).to eq("01/05")
      end

      it "returns original string when parsing fails" do
        allow(Time).to receive(:parse).and_raise("Parse error")

        result = table.send(:format_date, "invalid-date")

        expect(result).to eq("invalid-date")
      end
    end

    describe "#truncate_path" do
      it "returns empty string for nil path" do
        result = table.send(:truncate_path, nil)
        expect(result).to eq("")
      end

      it "returns original path when shorter than max_length" do
        short_path = "/short/path"
        result = table.send(:truncate_path, short_path)
        expect(result).to eq(short_path)
      end

      it "truncates path when longer than max_length" do
        long_path = "/very/long/path/that/exceeds/thirty/characters/definitely"
        result = table.send(:truncate_path, long_path, max_length: 30)

        expect(result).to start_with("...")
        expect(result.length).to be <= 30
        expect(result).to eq("...definitely")
      end

      it "accepts custom max_length" do
        path = "/custom/length/test"
        result = table.send(:truncate_path, path, max_length: 10)

        expect(result).to eq("...test")
      end
    end

    describe "#truncate_config" do
      it "returns empty string for nil config" do
        result = table.send(:truncate_config, nil)
        expect(result).to eq("")
      end

      it "returns original string config when shorter than max_length" do
        short_config = "short config"
        result = table.send(:truncate_config, short_config)
        expect(result).to eq(short_config)
      end

      it "truncates string config when longer than max_length" do
        long_config = "this is a very long configuration string that exceeds the limit"
        result = table.send(:truncate_config, long_config, max_length: 20)

        expect(result).to end_with("...")
        expect(result.length).to be <= 20
        expect(result).to eq("this is a very lo...")
      end

      it "converts hash config to string and truncates" do
        hash_config = { source: "file.txt", strategy: "copy", complex: "data" }
        result = table.send(:truncate_config, hash_config, max_length: 30)

        expect(result).to be_a(String)
        expect(result.length).to be <= 30
        expect(result).to end_with("...")
      end

      it "accepts custom max_length" do
        config = "configuration test"
        result = table.send(:truncate_config, config, max_length: 10)

        expect(result).to eq("configu...")
      end
    end

    describe "#render_table" do
      it "creates TTY::Table and renders with appropriate style based on terminal" do
        headers = %w[Col1 Col2]
        rows = [%w[val1 val2]]

        expect do
          table.send(:render_table, headers, rows)
        end.to output("rendered_table\n").to_stdout

        expect(TTY::Table).to have_received(:new).with(header: headers, rows: rows)
        # Uses :basic when stdout is not a TTY (in tests), :unicode when it is
        expected_renderer = $stdout.tty? ? :unicode : :basic
        expect(mock_tty_table).to have_received(:render).with(expected_renderer, padding: [0, 1])
      end

      it "uses unicode renderer when stdout is a TTY" do
        headers = %w[Col1 Col2]
        rows = [%w[val1 val2]]

        # Need to stub tty? before capturing output
        allow($stdout).to receive(:tty?).and_return(true)
        allow($stdout).to receive(:write)
        allow($stdout).to receive(:puts)

        # Reset the mock to clear any previous calls
        allow(TTY::Table).to receive(:new).and_return(mock_tty_table)
        allow(mock_tty_table).to receive(:render).and_return("rendered_table")

        table.send(:render_table, headers, rows)

        expect(mock_tty_table).to have_received(:render).with(:unicode, padding: [0, 1])
      end

      it "uses basic renderer when stdout is not a TTY" do
        headers = %w[Col1 Col2]
        rows = [%w[val1 val2]]

        # Need to stub tty? before capturing output
        allow($stdout).to receive(:tty?).and_return(false)
        allow($stdout).to receive(:write)
        allow($stdout).to receive(:puts)

        # Reset the mock to clear any previous calls
        allow(TTY::Table).to receive(:new).and_return(mock_tty_table)
        allow(mock_tty_table).to receive(:render).and_return("rendered_table")

        table.send(:render_table, headers, rows)

        expect(mock_tty_table).to have_received(:render).with(:basic, padding: [0, 1])
      end
    end

    describe "#empty_table" do
      it "outputs dimmed message" do
        expect do
          table.send(:empty_table, "No data")
        end.to output("DIM\n").to_stdout

        expect(mock_pastel).to have_received(:dim).with("  No data")
      end
    end
  end
end
