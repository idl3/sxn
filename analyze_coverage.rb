#!/usr/bin/env ruby

require 'json'

# Load the coverage data
coverage_file = '/Users/ernestsim/Code/base/atlas-one/sxn/coverage/.resultset.json'
coverage_data = JSON.parse(File.read(coverage_file))

files_coverage = {}

# Analyze each file's coverage
coverage_data['RSpec']['coverage'].each do |file_path, data|
  next unless file_path.include?('/lib/sxn/')
  
  lines = data['lines']
  total_lines = lines.count { |line| line.is_a?(Integer) }
  covered_lines = lines.count { |line| line.is_a?(Integer) && line > 0 }
  
  if total_lines > 0
    coverage_percentage = (covered_lines.to_f / total_lines * 100).round(2)
    missed_lines = total_lines - covered_lines
    
    relative_path = file_path.sub('/Users/ernestsim/Code/base/atlas-one/sxn/', '')
    
    files_coverage[relative_path] = {
      coverage: coverage_percentage,
      covered: covered_lines,
      total: total_lines,
      missed: missed_lines
    }
  end
end

# Sort by coverage percentage (lowest first) and missed lines (highest first)
sorted_files = files_coverage.sort_by { |file, data| [data[:coverage], -data[:missed]] }

puts "=" * 80
puts "COVERAGE ANALYSIS - Files needing attention"
puts "=" * 80
puts

sorted_files.each do |file, data|
  next if data[:coverage] >= 100.0
  
  puts "File: #{file}"
  puts "  Coverage: #{data[:coverage]}% (#{data[:covered]}/#{data[:total]} lines)"
  puts "  Missed lines: #{data[:missed]}"
  puts
end

puts "=" * 80
puts "SUMMARY"
puts "=" * 80

total_files = files_coverage.length
files_100_percent = files_coverage.count { |file, data| data[:coverage] >= 100.0 }
files_90_percent = files_coverage.count { |file, data| data[:coverage] >= 90.0 }
files_50_percent = files_coverage.count { |file, data| data[:coverage] >= 50.0 }

puts "Total files: #{total_files}"
puts "Files with 100% coverage: #{files_100_percent}"
puts "Files with 90%+ coverage: #{files_90_percent}"
puts "Files with 50%+ coverage: #{files_50_percent}"
puts "Files needing work: #{total_files - files_100_percent}"

overall_total = files_coverage.sum { |file, data| data[:total] }
overall_covered = files_coverage.sum { |file, data| data[:covered] }
overall_percentage = (overall_covered.to_f / overall_total * 100).round(2)

puts "Overall coverage: #{overall_percentage}% (#{overall_covered}/#{overall_total})"