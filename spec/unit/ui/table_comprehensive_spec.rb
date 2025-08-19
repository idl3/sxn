# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sxn::UI::Table, "comprehensive coverage for missing areas" do
  let(:table) { described_class.new }
  let(:mock_pastel) { instance_double(Pastel) }
  let(:mock_tty_table) { instance_double(TTY::Table) }

  before do
    allow(Pastel).to receive(:new).and_return(mock_pastel)
    allow(TTY::Table).to receive(:new).and_return(mock_tty_table)
    allow(mock_tty_table).to receive(:render).and_return("rendered_table")
    
    # Mock pastel color methods - using more realistic return values
    allow(mock_pastel).to receive(:green).with(any_args).and_return("✓")
    allow(mock_pastel).to receive(:red).with(any_args).and_return("✗")
    allow(mock_pastel).to receive(:yellow).with(any_args).and_return("○ Inactive")
    allow(mock_pastel).to receive(:dim).with(any_args).and_return("◌ Archived")
  end

  describe "comprehensive helper method coverage" do
    describe "#git_clean?" do
      it "returns true when git diff-index succeeds" do
        allow(Dir).to receive(:chdir).with("/clean/repo").and_yield
        allow(table).to receive(:system).with("git diff-index --quiet HEAD --", out: File::NULL, err: File::NULL).and_return(true)
        
        result = table.send(:git_clean?, "/clean/repo")
        expect(result).to be true
      end

      it "returns false when git diff-index fails" do
        allow(Dir).to receive(:chdir).with("/dirty/repo").and_yield
        allow(table).to receive(:system).with("git diff-index --quiet HEAD --", out: File::NULL, err: File::NULL).and_return(false)
        
        result = table.send(:git_clean?, "/dirty/repo")
        expect(result).to be false
      end

      it "returns false when git command raises exception" do
        allow(Dir).to receive(:chdir).with("/error/repo").and_raise(StandardError, "Git error")
        
        result = table.send(:git_clean?, "/error/repo")
        expect(result).to be false
      end

      it "returns false when directory change fails" do
        allow(Dir).to receive(:chdir).with("/nonexistent").and_raise(Errno::ENOENT, "No such directory")
        
        result = table.send(:git_clean?, "/nonexistent")
        expect(result).to be false
      end

      it "returns false when system call raises exception" do
        allow(Dir).to receive(:chdir).with("/system/error").and_yield
        allow(table).to receive(:system).and_raise(StandardError, "System error")
        
        result = table.send(:git_clean?, "/system/error")
        expect(result).to be false
      end
    end

    describe "#format_date edge cases" do
      let(:now) { Time.new(2023, 6, 15, 14, 30, 0) }

      before { allow(Time).to receive(:now).and_return(now) }

      it "handles nil date gracefully" do
        result = table.send(:format_date, nil)
        expect(result).to eq("")
      end

      it "handles empty string date" do
        result = table.send(:format_date, "")
        expect(result).to eq("")
      end

      it "formats recent date within 24 hours" do
        recent_time = now - 3600 # 1 hour ago
        recent_date = recent_time.iso8601
        allow(Time).to receive(:parse).with(recent_date).and_return(recent_time)
        
        result = table.send(:format_date, recent_date)
        expect(result).to eq("13:30") # HH:MM format
      end

      it "formats date within a week with day and time" do
        week_time = now - 86400 * 3 # 3 days ago
        week_date = week_time.iso8601
        allow(Time).to receive(:parse).with(week_date).and_return(week_time)
        
        result = table.send(:format_date, week_date)
        expect(result).to eq(week_time.strftime("%a %H:%M"))
      end

      it "formats old date with month/day" do
        old_time = now - 86400 * 30 # 30 days ago
        old_date = old_time.iso8601
        allow(Time).to receive(:parse).with(old_date).and_return(old_time)
        
        result = table.send(:format_date, old_date)
        expect(result).to eq("05/16") # MM/DD format
      end

      it "returns original string when parsing fails" do
        invalid_date = "invalid-date-format"
        allow(Time).to receive(:parse).with(invalid_date).and_raise(ArgumentError, "Invalid date")
        
        result = table.send(:format_date, invalid_date)
        expect(result).to eq(invalid_date)
      end

      it "handles different date string formats" do
        # Test with different input formats that might be encountered
        dates_and_expected = [
          ["2023-06-15T10:30:00Z", "10:30"],
          ["2023-06-14T14:30:00+00:00", "Thu 14:30"],
          ["2023-05-15T14:30:00Z", "05/15"]
        ]
        
        dates_and_expected.each do |date_string, expected|
          parsed_time = Time.parse(date_string)
          allow(Time).to receive(:parse).with(date_string).and_return(parsed_time)
          
          result = table.send(:format_date, date_string)
          expect(result).to eq(expected)
        end
      end
    end

    describe "#truncate_path edge cases" do
      it "handles nil path" do
        result = table.send(:truncate_path, nil)
        expect(result).to eq("")
      end

      it "handles empty path" do
        result = table.send(:truncate_path, "")
        expect(result).to eq("")
      end

      it "returns original path when shorter than max_length" do
        short_path = "/short"
        result = table.send(:truncate_path, short_path, max_length: 30)
        expect(result).to eq(short_path)
      end

      it "returns original path when exactly max_length" do
        exact_path = "/exactly/thirty/characters/"
        expect(exact_path.length).to eq(30)
        result = table.send(:truncate_path, exact_path, max_length: 30)
        expect(result).to eq(exact_path)
      end

      it "truncates long path correctly" do
        long_path = "/very/long/path/that/definitely/exceeds/the/maximum/length/limit"
        result = table.send(:truncate_path, long_path, max_length: 30)
        
        expect(result).to start_with("...")
        expect(result.length).to eq(30)
        expect(result).to eq("...t/limit")
      end

      it "handles custom max_length parameter" do
        path = "/custom/length/test/path"
        result = table.send(:truncate_path, path, max_length: 15)
        
        expect(result.length).to eq(15)
        expect(result).to eq("...test/path")
      end

      it "handles very short max_length" do
        path = "/test/path"
        result = table.send(:truncate_path, path, max_length: 5)
        
        expect(result.length).to eq(5)
        expect(result).to eq("...th")
      end
    end

    describe "#truncate_config edge cases" do
      it "handles nil config" do
        result = table.send(:truncate_config, nil)
        expect(result).to eq("")
      end

      it "handles string config shorter than max_length" do
        short_config = "short"
        result = table.send(:truncate_config, short_config, max_length: 40)
        expect(result).to eq(short_config)
      end

      it "handles string config exactly max_length" do
        exact_config = "a" * 40
        result = table.send(:truncate_config, exact_config, max_length: 40)
        expect(result).to eq(exact_config)
      end

      it "truncates long string config" do
        long_config = "This is a very long configuration string that definitely exceeds the maximum length"
        result = table.send(:truncate_config, long_config, max_length: 20)
        
        expect(result.length).to eq(20)
        expect(result).to eq("This is a very l...")
      end

      it "converts hash to string and truncates" do
        hash_config = { 
          source: "file.txt", 
          strategy: "copy", 
          permissions: 0644,
          nested: { key: "value" }
        }
        result = table.send(:truncate_config, hash_config, max_length: 30)
        
        expect(result).to be_a(String)
        expect(result.length).to eq(30)
        expect(result).to end_with("...")
      end

      it "converts array to string and truncates" do
        array_config = ["command", "arg1", "arg2", "long_argument_name"]
        result = table.send(:truncate_config, array_config, max_length: 20)
        
        expect(result).to be_a(String)
        expect(result.length).to eq(20)
        expect(result).to end_with("...")
      end

      it "converts numeric config to string" do
        numeric_config = 12345
        result = table.send(:truncate_config, numeric_config, max_length: 3)
        
        expect(result).to eq("123...")
      end

      it "handles custom max_length" do
        config = "test configuration"
        result = table.send(:truncate_config, config, max_length: 8)
        
        expect(result).to eq("test...")
      end
    end
  end

  describe "worktree_status comprehensive coverage" do
    let(:worktree) { { path: "/test/worktree" } }

    it "handles missing directory" do
      allow(File).to receive(:directory?).with("/test/worktree").and_return(false)
      
      result = table.send(:worktree_status, worktree)
      expect(result).to eq("RED")
      expect(mock_pastel).to have_received(:red).with("Missing")
    end

    it "handles directory exists but git_clean? returns true" do
      allow(File).to receive(:directory?).with("/test/worktree").and_return(true)
      allow(table).to receive(:git_clean?).with("/test/worktree").and_return(true)
      
      result = table.send(:worktree_status, worktree)
      expect(result).to eq("GREEN")
      expect(mock_pastel).to have_received(:green).with("Clean")
    end

    it "handles directory exists but git_clean? returns false" do
      allow(File).to receive(:directory?).with("/test/worktree").and_return(true)
      allow(table).to receive(:git_clean?).with("/test/worktree").and_return(false)
      
      result = table.send(:worktree_status, worktree)
      expect(result).to eq("YELLOW")
      expect(mock_pastel).to have_received(:yellow).with("Modified")
    end

    it "handles directory check raising exception" do
      allow(File).to receive(:directory?).with("/test/worktree").and_raise(StandardError, "Permission denied")
      
      result = table.send(:worktree_status, worktree)
      expect(result).to eq("RED")
      expect(mock_pastel).to have_received(:red).with("Missing")
    end
  end

  describe "table rendering edge cases" do
    describe "#sessions with edge cases" do
      it "handles sessions with missing fields" do
        sessions = [
          {
            name: "incomplete",
            # missing status, projects, dates
          }
        ]
        
        allow(table).to receive(:status_indicator).with(nil).and_return("UNKNOWN")
        allow(table).to receive(:format_date).with(nil).and_return("")
        
        expect {
          table.sessions(sessions)
        }.to output("rendered_table\n").to_stdout
        
        expect(TTY::Table).to have_received(:new).with(
          header: ["Name", "Status", "Projects", "Created", "Updated"],
          rows: [["incomplete", "UNKNOWN", "", "", ""]]
        )
      end

      it "handles sessions with various project array states" do
        sessions = [
          { name: "empty_projects", status: "active", projects: [], created_at: "date", updated_at: "date" },
          { name: "nil_projects", status: "active", projects: nil, created_at: "date", updated_at: "date" },
          { name: "single_project", status: "active", projects: ["solo"], created_at: "date", updated_at: "date" }
        ]
        
        allow(table).to receive(:status_indicator).and_return("STATUS")
        allow(table).to receive(:format_date).and_return("DATE")
        
        expect {
          table.sessions(sessions)
        }.to output("rendered_table\n").to_stdout
        
        expect(TTY::Table).to have_received(:new).with(
          header: ["Name", "Status", "Projects", "Created", "Updated"],
          rows: [
            ["empty_projects", "STATUS", "", "DATE", "DATE"],
            ["nil_projects", "STATUS", "", "DATE", "DATE"],
            ["single_project", "STATUS", "solo", "DATE", "DATE"]
          ]
        )
      end
    end

    describe "#projects with edge cases" do
      it "handles projects with missing optional fields" do
        projects = [
          {
            name: "minimal",
            path: "/path"
            # missing type, default_branch
          },
          {
            name: "partial",
            type: "custom",
            path: "/other/path",
            default_branch: "develop"
          }
        ]
        
        allow(table).to receive(:truncate_path).and_return("TRUNCATED")
        
        expect {
          table.projects(projects)
        }.to output("rendered_table\n").to_stdout
        
        expect(TTY::Table).to have_received(:new).with(
          header: ["Name", "Type", "Path", "Default Branch"],
          rows: [
            ["minimal", "unknown", "TRUNCATED", "master"],
            ["partial", "custom", "TRUNCATED", "develop"]
          ]
        )
      end
    end

    describe "#config_summary with different config states" do
      it "handles partially filled config" do
        config = {
          sessions_folder: "/custom/sessions",
          # missing current_session, auto_cleanup, max_sessions
        }
        
        expect {
          table.config_summary(config)
        }.to output("rendered_table\n").to_stdout
        
        expect(TTY::Table).to have_received(:new).with(
          header: ["Setting", "Value", "Source"],
          rows: [
            ["Sessions Folder", "/custom/sessions", "config"],
            ["Current Session", "None", "config"],
            ["Auto Cleanup", "Disabled", "config"],
            ["Max Sessions", "Unlimited", "config"]
          ]
        )
      end

      it "handles config with false boolean values" do
        config = {
          auto_cleanup: false,
          max_sessions: 0
        }
        
        expect {
          table.config_summary(config)
        }.to output("rendered_table\n").to_stdout
        
        expect(TTY::Table).to have_received(:new).with(
          header: ["Setting", "Value", "Source"],
          rows: [
            ["Sessions Folder", "Not set", "config"],
            ["Current Session", "None", "config"],
            ["Auto Cleanup", "Disabled", "config"],
            ["Max Sessions", 0, "config"]
          ]
        )
      end
    end
  end

  describe "empty state handling" do
    it "calls empty_table for all empty collections" do
      # Test all methods that can show empty state
      expect(mock_pastel).to receive(:dim).with("  No sessions found")
      table.sessions([])
      
      expect(mock_pastel).to receive(:dim).with("  No projects configured")
      table.projects([])
      
      expect(mock_pastel).to receive(:dim).with("  No worktrees in current session")
      table.worktrees([])
      
      expect(mock_pastel).to receive(:dim).with("  No rules configured")
      table.rules([])
    end
  end

  describe "status_indicator comprehensive coverage" do
    it "handles all status types" do
      status_tests = [
        ["active", "● Active", :green],
        ["inactive", "○ Inactive", :yellow],
        ["archived", "◌ Archived", :dim],
        ["unknown_status", "? Unknown", :dim],
        [nil, "? Unknown", :dim],
        ["", "? Unknown", :dim]
      ]
      
      status_tests.each do |status, expected_text, expected_color|
        allow(mock_pastel).to receive(expected_color).with(expected_text).and_return("COLORED")
        
        result = table.send(:status_indicator, status)
        expect(result).to eq("COLORED")
        expect(mock_pastel).to have_received(expected_color).with(expected_text)
      end
    end
  end

  describe "rules table filtering" do
    it "filters rules by project correctly" do
      rules = [
        { project: "project1", type: "copy", config: {}, enabled: true },
        { project: "project2", type: "setup", config: {}, enabled: false },
        { project: "project1", type: "template", config: {}, enabled: true }
      ]
      
      allow(table).to receive(:truncate_config).and_return("CONFIG")
      
      expect {
        table.rules(rules, "project1")
      }.to output("rendered_table\n").to_stdout
      
      expect(TTY::Table).to have_received(:new).with(
        header: ["Project", "Type", "Config", "Status"],
        rows: [
          ["project1", "copy", "CONFIG", "GREEN"],
          ["project1", "template", "CONFIG", "GREEN"]
        ]
      )
    end

    it "shows empty state when no rules match filter" do
      rules = [
        { project: "project1", type: "copy", config: {}, enabled: true }
      ]
      
      expect {
        table.rules(rules, "nonexistent_project")
      }.to output("DIM\n").to_stdout
      
      expect(mock_pastel).to have_received(:dim).with("  No rules configured")
    end
  end
end