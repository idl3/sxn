# frozen_string_literal: true

require 'benchmark'

# Performance matcher for RSpec
RSpec::Matchers.define :perform_under do |expected_time|
  supports_block_expectations

  match do |block|
    @actual_time = Benchmark.measure(&block).real
    @actual_time <= expected_time
  end

  chain :ms do
    @time_unit = :ms
    @expected_ms = expected_time
    @expected_time = expected_time / 1000.0
  end

  chain :seconds do
    @time_unit = :seconds
    @expected_time = expected_time
  end

  def expected_time
    @expected_time || expected_time
  end

  def time_unit
    @time_unit || :seconds
  end

  def format_time(time)
    case time_unit
    when :ms
      "#{(time * 1000).round(2)}ms"
    else
      "#{time.round(4)}s"
    end
  end

  failure_message do |block|
    expected_str = case time_unit
                   when :ms
                     "#{@expected_ms}ms"
                   else
                     "#{expected_time}s"
                   end
    
    "expected block to perform under #{expected_str}, but took #{format_time(@actual_time)}"
  end

  description do
    expected_str = case time_unit
                   when :ms
                     "#{@expected_ms}ms"
                   else
                     "#{expected_time}s"
                   end
    
    "perform under #{expected_str}"
  end
end