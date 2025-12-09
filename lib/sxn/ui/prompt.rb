# frozen_string_literal: true

require "tty-prompt"

module Sxn
  module UI
    # Interactive prompts with validation
    class Prompt
      def initialize
        @prompt = TTY::Prompt.new(interrupt: :exit)
      end

      def ask(message, options = {}, &)
        @prompt.ask(message, **options, &)
      end

      def ask_yes_no(message, default: false)
        @prompt.yes?(message, default: default)
      end

      def select(message, choices, options = {})
        @prompt.select(message, choices, **options)
      end

      def multi_select(message, choices, options = {})
        @prompt.multi_select(message, choices, **options)
      end

      def folder_name(message = "Enter sessions folder name:", default: nil)
        ask(message, default: default) do |q|
          q.validate(/\A[a-zA-Z0-9_-]+\z/, "Folder name must contain only letters, numbers, hyphens, and underscores")
          q.modify :strip
        end
      end

      def session_name(message = "Enter session name:", existing_sessions: [])
        ask(message) do |q|
          q.validate(/\A[a-zA-Z0-9_-]+\z/, "Session name must contain only letters, numbers, hyphens, and underscores")
          q.validate(lambda { |name|
            !existing_sessions.include?(name)
          }, "Session name already exists")
          q.modify :strip
        end
      end

      def project_name(message = "Enter project name:")
        ask(message) do |q|
          q.validate(/\A[a-zA-Z0-9_-]+\z/, "Project name must contain only letters, numbers, hyphens, and underscores")
          q.modify :strip
        end
      end

      def project_path(message = "Enter project path:")
        ask(message) do |q|
          q.validate(lambda { |path|
            expanded = File.expand_path(path)
            File.directory?(expanded) && File.readable?(expanded)
          }, "Path must be a readable directory")
          q.modify :strip
          q.convert ->(path) { File.expand_path(path) }
        end
      end

      def branch_name(message = "Enter branch name:", default: nil)
        ask(message, default: default) do |q|
          q.validate(%r{\A[a-zA-Z0-9_/-]+\z}, "Branch name must be a valid git branch name")
          q.modify :strip
        end
      end

      def default_branch(session_name:)
        branch_name("Default branch for worktrees:", default: session_name)
      end

      def confirm_deletion(item_name, item_type = "item")
        ask_yes_no("Are you sure you want to delete #{item_type} '#{item_name}'? This action cannot be undone.",
                   default: false)
      end

      def rule_type
        select("Select rule type:", [
                 { name: "Copy Files", value: "copy_files" },
                 { name: "Setup Commands", value: "setup_commands" },
                 { name: "Template", value: "template" }
               ])
      end

      def sessions_folder_setup
        puts "Setting up sessions folder..."
        puts "This will create a folder where all your development sessions will be stored."
        puts ""

        default_folder = "#{File.basename(Dir.pwd)}-sessions"
        folder = folder_name("Sessions folder name:", default: default_folder)

        current_dir = ask_yes_no("Create sessions folder in current directory?", default: true)

        unless current_dir
          base_path = project_path("Base path for sessions folder:")
          folder = File.join(base_path, folder)
        end

        folder
      end

      def project_detection_confirm(detected_projects)
        return false if detected_projects.empty?

        puts ""
        puts "Detected projects in current directory:"
        detected_projects.each do |project|
          puts "  #{project[:name]} (#{project[:type]}) - #{project[:path]}"
        end
        puts ""

        ask_yes_no("Would you like to register these projects automatically?", default: true)
      end
    end
  end
end
