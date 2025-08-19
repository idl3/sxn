# frozen_string_literal: true

require "tty-table"
require "pastel"

module Sxn
  module UI
    # Table formatting for lists and data display
    class Table
      def initialize
        @pastel = Pastel.new
      end

      def sessions(sessions)
        return empty_table("No sessions found") if sessions.empty?

        headers = ["Name", "Status", "Projects", "Created", "Updated"]
        rows = sessions.map do |session|
          [
            session[:name],
            status_indicator(session[:status]),
            session[:projects]&.join(", ") || "",
            format_date(session[:created_at]),
            format_date(session[:updated_at])
          ]
        end

        render_table(headers, rows)
      end

      def projects(projects)
        return empty_table("No projects configured") if projects.empty?

        headers = ["Name", "Type", "Path", "Default Branch"]
        rows = projects.map do |project|
          [
            project[:name],
            project[:type] || "unknown",
            truncate_path(project[:path]),
            project[:default_branch] || "master"
          ]
        end

        render_table(headers, rows)
      end

      def worktrees(worktrees)
        return empty_table("No worktrees in current session") if worktrees.empty?

        headers = ["Project", "Branch", "Path", "Status"]
        rows = worktrees.map do |worktree|
          [
            worktree[:project],
            worktree[:branch],
            truncate_path(worktree[:path]),
            worktree_status(worktree)
          ]
        end

        render_table(headers, rows)
      end

      def rules(rules, project_filter = nil)
        filtered_rules = project_filter ? rules.select { |r| r[:project] == project_filter } : rules
        return empty_table("No rules configured") if filtered_rules.empty?

        headers = ["Project", "Type", "Config", "Status"]
        rows = filtered_rules.map do |rule|
          [
            rule[:project],
            rule[:type],
            truncate_config(rule[:config]),
            rule[:enabled] ? @pastel.green("✓") : @pastel.red("✗")
          ]
        end

        render_table(headers, rows)
      end

      def config_summary(config)
        headers = ["Setting", "Value", "Source"]
        rows = [
          ["Sessions Folder", config[:sessions_folder] || "Not set", "config"],
          ["Current Session", config[:current_session] || "None", "config"],
          ["Auto Cleanup", config[:auto_cleanup] ? "Enabled" : "Disabled", "config"],
          ["Max Sessions", config[:max_sessions] || "Unlimited", "config"]
        ]

        render_table(headers, rows)
      end

      private

      def render_table(headers, rows)
        table = TTY::Table.new(header: headers, rows: rows)
        puts table.render(:unicode, padding: [0, 1])
      end

      def empty_table(message)
        puts @pastel.dim("  #{message}")
      end

      def status_indicator(status)
        case status
        when "active"
          @pastel.green("● Active")
        when "inactive"
          @pastel.yellow("○ Inactive")
        when "archived"
          @pastel.dim("◌ Archived")
        else
          @pastel.dim("? Unknown")
        end
      end

      def worktree_status(worktree)
        if File.directory?(worktree[:path])
          if git_clean?(worktree[:path])
            @pastel.green("Clean")
          else
            @pastel.yellow("Modified")
          end
        else
          @pastel.red("Missing")
        end
      end

      def git_clean?(path)
        Dir.chdir(path) do
          system("git diff-index --quiet HEAD --", out: File::NULL, err: File::NULL)
        end
      rescue
        false
      end

      def format_date(date_string)
        return "" unless date_string
        
        date = Time.parse(date_string)
        if date > Time.now - 86400 # Within 24 hours
          date.strftime("%H:%M")
        elsif date > Time.now - 604800 # Within a week
          date.strftime("%a %H:%M")
        else
          date.strftime("%m/%d")
        end
      rescue
        date_string
      end

      def truncate_path(path, max_length: 30)
        return "" unless path
        return path if path.length <= max_length
        
        "...#{path[-max_length + 3..-1]}"
      end

      def truncate_config(config, max_length: 40)
        return "" unless config
        
        config_str = config.is_a?(String) ? config : config.to_s
        return config_str if config_str.length <= max_length
        
        "#{config_str[0..max_length - 4]}..."
      end
    end
  end
end