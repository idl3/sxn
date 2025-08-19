# frozen_string_literal: true

require "tty-progressbar"

module Sxn
  module UI
    # Progress bars for long-running operations
    class ProgressBar
      def initialize(title, total: 100, format: :classic)
        format_string = case format
                        when :classic
                          "#{title} [:bar] :percent :elapsed"
                        when :detailed
                          "#{title} [:bar] :current/:total (:percent) :elapsed ETA: :eta"
                        when :simple
                          "#{title} :percent"
                        else
                          title
                        end

        @bar = TTY::ProgressBar.new(format_string, total: total, clear: true)
      end

      def advance(step = 1)
        @bar.advance(step)
      end

      def finish
        @bar.finish
      end

      def current
        @bar.current
      end

      def total
        @bar.total
      end

      def percent
        @bar.percent
      end

      def log(message)
        @bar.log(message)
      end

      def self.with_progress(title, items, format: :classic, &block)
        return [] if items.empty?

        progress = new(title, total: items.size, format: format)
        results = []

        items.each do |item|
          result = block.call(item, progress)
          results << result
          progress.advance
        end

        progress.finish
        results
      end

      def self.for_operation(title, total_steps: 5, &block)
        progress = new(title, total: total_steps, format: :detailed)

        stepper = Stepper.new(progress)
        result = block.call(stepper)

        progress.finish
        result
      end

      # Helper class for step-by-step operations
      class Stepper
        def initialize(progress_bar)
          @progress = progress_bar
        end

        def step(message = nil)
          @progress.log(message) if message
          @progress.advance
        end

        def log(message)
          @progress.log(message)
        end
      end
    end
  end
end
