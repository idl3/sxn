# frozen_string_literal: true

SimpleCov.configure do
  # Load SimpleCov config
  load_profile "test_frameworks"
  
  # Coverage output directory
  coverage_dir "coverage"
  
  # Minimum coverage requirements
  minimum_coverage 90
  minimum_coverage_by_file 85
  
  # Files to track
  track_files "lib/**/*.rb"
  
  # Files to exclude from coverage
  add_filter "/spec/"
  add_filter "/vendor/"
  add_filter "/coverage/"
  add_filter "lib/sxn/version.rb"  # Version file is just a constant
  
  # Group coverage by functional areas
  add_group "Commands", "lib/sxn/commands"
  add_group "Core Logic", "lib/sxn/core"
  add_group "Security", "lib/sxn/security"
  add_group "Rules Engine", "lib/sxn/rules"
  add_group "Database", "lib/sxn/database"
  add_group "Git Operations", "lib/sxn/git"
  add_group "MCP Server", "lib/sxn/mcp"
  add_group "UI Components", "lib/sxn/ui"
  add_group "Templates", "lib/sxn/templates"
  
  # Merge results from multiple test runs
  merge_timeout 3600
  
  # Enable branch coverage (requires Ruby 2.5+)
  enable_coverage :branch if respond_to?(:enable_coverage)
  
  # Formatters
  if ENV["CI"]
    # In CI, use simple formatter for logs
    formatter SimpleCov::Formatter::SimpleFormatter
  else
    # Locally, generate HTML report
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::SimpleFormatter,
      SimpleCov::Formatter::HTMLFormatter
    ])
  end
end