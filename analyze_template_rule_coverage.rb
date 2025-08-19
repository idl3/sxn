#!/usr/bin/env ruby

require 'json'

# Read the SimpleCov result file
coverage_file = File.join(__dir__, 'coverage', '.resultset.json')
unless File.exist?(coverage_file)
  puts "Coverage file not found: #{coverage_file}"
  exit 1
end

coverage_data = JSON.parse(File.read(coverage_file))
rspec_data = coverage_data['RSpec']['coverage']

# Find template_rule.rb file
template_rule_file = rspec_data.keys.find { |k| k.end_with?('rules/template_rule.rb') }

unless template_rule_file
  puts "template_rule.rb not found in coverage data"
  exit 1
end

lines = rspec_data[template_rule_file]['lines']
puts "Template Rule Coverage Analysis"
puts "=" * 50

# Read the actual file to get line content
file_content = File.readlines(template_rule_file)

missed_lines = []
covered_lines = []
total_executable_lines = 0

lines.each_with_index do |line_coverage, index|
  next if line_coverage.nil?  # Skip non-executable lines
  
  total_executable_lines += 1
  line_number = index + 1
  line_content = file_content[index].strip
  
  if line_coverage == 0
    missed_lines << { number: line_number, content: line_content }
  else
    covered_lines << { number: line_number, content: line_content, count: line_coverage }
  end
end

puts "Total executable lines: #{total_executable_lines}"
puts "Covered lines: #{covered_lines.length}"
puts "Missed lines: #{missed_lines.length}"
puts "Coverage: #{((covered_lines.length.to_f / total_executable_lines) * 100).round(2)}%"
puts

puts "MISSED LINES (need to be tested):"
puts "-" * 40
missed_lines.each do |line|
  puts "Line #{line[:number]}: #{line[:content]}"
end

puts
puts "COVERED LINES:"
puts "-" * 40
covered_lines.each do |line|
  puts "Line #{line[:number]} (#{line[:count]}x): #{line[:content]}"
end