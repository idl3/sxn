#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple Rules Engine Demo
# This script demonstrates the core functionality without complex dependencies

$LOAD_PATH.unshift(File.join(__dir__, 'lib'))

require 'logger'
require 'tmpdir'
require 'fileutils'

# Set up basic logging for Sxn
module Sxn
  def self.logger
    @logger ||= Logger.new($stdout).tap do |l|
      l.level = Logger::INFO
      l.formatter = proc { |severity, datetime, _progname, msg| "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n" }
    end
  end
end

# Load just the error handling and basic rules
require 'sxn/errors'
require 'sxn/rules/errors'
require 'sxn/rules/base_rule'

puts "🔧 Simple Sxn Rules Engine Demo"
puts "=" * 50

# Create temporary directories for demo
project_path = Dir.mktmpdir("demo_project")
session_path = Dir.mktmpdir("demo_session")

begin
  puts "📁 Setting up demo project at: #{project_path}"
  puts "📁 Setting up demo session at: #{session_path}"

  # Create a sample project structure
  FileUtils.mkdir_p(File.join(project_path, "config"))
  File.write(File.join(project_path, "Gemfile"), 'gem "rails", "~> 7.0"')
  File.write(File.join(project_path, "README.md"), "# Demo Project")

  puts "✅ Demo project structure created"
  
  # 1. Test BaseRule creation and basic functionality
  puts "\n🏗️  Testing BaseRule Implementation"
  puts "-" * 30
  
  # Create a simple test rule class
  class TestRule < Sxn::Rules::BaseRule
    protected
    
    def validate_rule_specific!
      raise Sxn::Rules::ValidationError, "Test config missing" unless @config.key?("test_setting")
      true
    end

    public
    
    def apply
      change_state!(APPLYING)
      
      begin
        test_file = File.join(@session_path, "test_rule.txt")
        File.write(test_file, "Rule applied successfully at #{Time.now}")
        track_change(:file_created, test_file)
        puts "   ✅ Test rule applied - created #{test_file}"
        
        change_state!(APPLIED)
        true
      rescue => e
        @errors << e
        change_state!(FAILED)
        raise Sxn::Rules::ApplicationError, "Failed to apply test rule: #{e.message}"
      end
    end

    def rollback
      return true if @state == PENDING || @state == FAILED

      change_state!(ROLLING_BACK)
      
      begin
        puts "   🔄 Rolling back test rule changes"
        @changes.reverse_each(&:rollback)
        change_state!(ROLLED_BACK)
        true
      rescue => e
        @errors << e
        change_state!(FAILED)
        raise Sxn::Rules::RollbackError, "Failed to rollback test rule: #{e.message}"
      end
    end
  end
  
  # Create and test the rule
  test_rule = TestRule.new(
    "demo_test_rule",
    { "test_setting" => "demo_value" },
    project_path,
    session_path,
    dependencies: []
  )
  
  puts "✅ Created test rule: #{test_rule.name}"
  puts "   State: #{test_rule.state}"
  puts "   Type: #{test_rule.class}"

  # 2. Test Rule Validation
  puts "\n🔬 Testing Rule Validation"
  puts "-" * 30
  
  begin
    test_rule.validate
    puts "✅ Rule validation passed"
  rescue => e
    puts "❌ Rule validation failed: #{e.message}"
  end

  # 3. Test Rule Application
  puts "\n⚙️  Testing Rule Application"
  puts "-" * 30
  
  begin
    test_rule.apply
    puts "✅ Rule applied successfully"
    puts "   State: #{test_rule.state}"
    
    # Check if file was created
    test_file = File.join(session_path, "test_rule.txt")
    if File.exist?(test_file)
      puts "   ✅ Test file created: #{File.read(test_file).strip}"
    else
      puts "   ⚠️  Test file not found"
    end
  rescue => e
    puts "❌ Rule application failed: #{e.message}"
  end

  # 4. Test Rule State Management
  puts "\n📊 Testing Rule State Management"
  puts "-" * 30
  
  puts "Current state: #{test_rule.state}"
  puts "Is applied?: #{test_rule.applied?}"
  puts "Is rollbackable?: #{test_rule.rollbackable?}"
  puts "Number of changes: #{test_rule.changes.size}"
  
  if test_rule.changes.any?
    puts "Changes made:"
    test_rule.changes.each_with_index do |change, index|
      puts "  #{index + 1}. #{change.type}: #{change.target}"
    end
  end

  # 5. Test Rule Rollback
  puts "\n↩️  Testing Rule Rollback"
  puts "-" * 30
  
  if test_rule.rollbackable?
    begin
      test_rule.rollback
      puts "✅ Rule rollback completed"
      puts "   State: #{test_rule.state}"
      
      # Check if file was removed
      test_file = File.join(session_path, "test_rule.txt")
      if File.exist?(test_file)
        puts "   ⚠️  Test file still exists (rollback may not have completed)"
      else
        puts "   ✅ Test file successfully removed"
      end
    rescue => e
      puts "❌ Rule rollback failed: #{e.message}"
    end
  else
    puts "⚠️  Rule is not rollbackable"
  end

  # 6. Test Error Handling
  puts "\n🚨 Testing Error Handling"
  puts "-" * 30
  
  begin
    # Create a rule with invalid configuration
    invalid_rule = TestRule.new(
      "invalid_rule",
      {}, # Missing test_setting
      project_path,
      session_path
    )
    
    invalid_rule.validate
    puts "❌ Expected validation to fail, but it passed"
  rescue Sxn::Rules::ValidationError => e
    puts "✅ Validation error correctly caught: #{e.message}"
  rescue => e
    puts "⚠️  Unexpected error type: #{e.class} - #{e.message}"
  end

  # 7. Test Rule Serialization
  puts "\n📄 Testing Rule Serialization"
  puts "-" * 30
  
  rule_hash = test_rule.to_h
  puts "Rule serialized to hash:"
  puts "  Name: #{rule_hash[:name]}"
  puts "  Type: #{rule_hash[:type]}"
  puts "  State: #{rule_hash[:state]}"
  puts "  Dependencies: #{rule_hash[:dependencies]}"
  puts "  Duration: #{rule_hash[:duration]}"

  puts "\n🎉 Simple demo completed successfully!"
  puts "   Core BaseRule functionality is working correctly."

rescue => e
  puts "❌ Demo failed with error: #{e.message}"
  puts "   Backtrace:"
  e.backtrace.take(10).each { |line| puts "     #{line}" }
ensure
  # Cleanup
  FileUtils.rm_rf(project_path) if project_path
  FileUtils.rm_rf(session_path) if session_path
  puts "\n🧹 Cleanup completed"
end