# frozen_string_literal: true

require "pastel"

module Sxn
  module UI
    # Formatted output with colors and status indicators
    class Output
      def initialize
        @pastel = Pastel.new
      end

      def success(message)
        puts @pastel.green("✅ #{message}")
      end

      def error(message)
        puts @pastel.red("❌ #{message}")
      end

      def warning(message)
        puts @pastel.yellow("⚠️  #{message}")
      end

      def info(message)
        puts @pastel.blue("ℹ️  #{message}")
      end

      def debug(message)
        puts @pastel.dim("🔍 #{message}") if debug_mode?
      end

      def status(label, message, color = :blue)
        colored_label = @pastel.public_send(color, "[#{label.upcase}]")
        puts "#{colored_label} #{message}"
      end

      def section(title)
        puts ""
        puts @pastel.bold(@pastel.cyan("═" * 60))
        puts @pastel.bold(@pastel.cyan("  #{title}"))
        puts @pastel.bold(@pastel.cyan("═" * 60))
        puts ""
      end

      def subsection(title)
        puts ""
        puts @pastel.bold(title.to_s)
        puts @pastel.dim("─" * title.length)
      end

      def list_item(item, description = nil)
        if description
          puts "  • #{@pastel.bold(item)} - #{description}"
        else
          puts "  • #{item}"
        end
      end

      def empty_state(message)
        puts @pastel.dim("  #{message}")
      end

      def key_value(key, value, indent: 0)
        spacing = " " * indent
        puts "#{spacing}#{@pastel.bold(key)}: #{value}"
      end

      def progress_start(message)
        print "#{message}... "
      end

      def progress_done
        puts @pastel.green("✅")
      end

      def progress_failed
        puts @pastel.red("❌")
      end

      def newline
        puts ""
      end

      def recovery_suggestion(message)
        puts ""
        puts @pastel.yellow("💡 Suggestion: #{message}")
      end

      def command_example(command, description = nil)
        puts "  #{@pastel.dim(description)}" if description
        puts "  #{@pastel.cyan("$ #{command}")}"
        puts ""
      end

      private

      def debug_mode?
        ENV["SXN_DEBUG"] == "true"
      end
    end
  end
end
