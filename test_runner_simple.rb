#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test runner to verify that no tests hang waiting for user input
# This runs a subset of tests that were most likely to have prompt issues

puts "Testing critical spec files for hanging prompts..."

test_files = [
  "spec/unit/commands/init_spec.rb",
  "spec/unit/commands/sessions_spec.rb", 
  "spec/unit/commands/projects_spec.rb",
  "spec/unit/commands/rules_spec.rb",
  "spec/unit/commands/worktrees_spec.rb",
  "spec/unit/cli_spec.rb"
]

test_files.each do |test_file|
  puts "\n=== Testing #{test_file} ==="
  
  # Run with timeout to detect hanging tests
  start_time = Time.now
  
  # Use a Ruby-based timeout since macOS doesn't have timeout command by default
  begin
    require 'timeout'
    
    Timeout::timeout(30) do
      system("rspec #{test_file} --format progress > /dev/null 2>&1")
      exit_status = $?.exitstatus
      duration = Time.now - start_time
      
      if exit_status != 0
        puts "⚠️  #{test_file} - FAILED (exit code: #{exit_status}) in #{duration.round(2)}s"
      else
        puts "✅ #{test_file} - PASSED in #{duration.round(2)}s"
      end
    end
  rescue Timeout::Error
    duration = Time.now - start_time
    puts "❌ #{test_file} - TIMED OUT after #{duration.round(2)}s (likely hanging on prompt)"
  end
end

puts "\n=== Test Summary ==="
puts "If any tests timed out, they likely have unresolved interactive prompts."
puts "All tests should complete within 30 seconds."