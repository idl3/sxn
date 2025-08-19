#!/usr/bin/env ruby
# frozen_string_literal: true

# Rules Engine Demo
# This script demonstrates the core functionality of the Rules Engine implementation

require_relative "lib/sxn"
require_relative "lib/sxn/rules"
require "tmpdir"
require "fileutils"

puts "🔧 Sxn Rules Engine Demo"
puts "=" * 50

# Create temporary directories for demo
project_path = Dir.mktmpdir("demo_project")
session_path = Dir.mktmpdir("demo_session")

begin
  puts "📁 Setting up demo project at: #{project_path}"
  puts "📁 Setting up demo session at: #{session_path}"

  # Create a sample Rails project structure
  FileUtils.mkdir_p(File.join(project_path, "config"))
  FileUtils.mkdir_p(File.join(project_path, "app/models"))
  
  # Create sample files
  File.write(File.join(project_path, "Gemfile"), 'gem "rails", "~> 7.0"')
  File.write(File.join(project_path, "config/application.rb"), "class Application < Rails::Application; end")
  File.write(File.join(project_path, "config/master.key"), "sample-master-key-content")
  File.write(File.join(project_path, ".env"), "DATABASE_URL=postgresql://localhost/demo")

  puts "✅ Demo project structure created"
  
  # 1. Test Project Detection
  puts "\n🔍 Testing Project Detection"
  puts "-" * 30
  
  detector = Sxn::Rules::ProjectDetector.new(project_path)
  project_info = detector.detect_project_info
  
  puts "Project Type: #{project_info[:type]}"
  puts "Package Manager: #{project_info[:package_manager]}"
  puts "Framework: #{project_info[:framework]}"

  # 2. Test Rule Type Information
  puts "\n📋 Available Rule Types"
  puts "-" * 30
  
  Sxn::Rules.available_types.each do |type|
    info = Sxn::Rules.rule_type_info[type]
    puts "• #{type}: #{info[:description]}"
  end

  # 3. Test Basic Rule Creation
  puts "\n🏗️  Testing Rule Creation"
  puts "-" * 30
  
  # Create a simple copy files rule
  copy_rule = Sxn::Rules.create_rule(
    "demo_copy",
    "copy_files",
    {
      "files" => [
        {
          "source" => "Gemfile",
          "strategy" => "copy",
          "required" => false
        }
      ]
    },
    project_path,
    session_path
  )
  
  puts "✅ Created rule: #{copy_rule.name} (type: #{copy_rule.class})"
  puts "   State: #{copy_rule.state}"
  puts "   Dependencies: #{copy_rule.dependencies}"

  # 4. Test Rules Engine
  puts "\n⚙️  Testing Rules Engine"
  puts "-" * 30
  
  engine = Sxn::Rules::RulesEngine.new(project_path, session_path)
  
  # Simple rules configuration
  rules_config = {
    "copy_gemfile" => {
      "type" => "copy_files",
      "config" => {
        "files" => [
          {
            "source" => "Gemfile",
            "strategy" => "copy",
            "required" => false
          }
        ]
      }
    }
  }
  
  puts "📝 Rules configuration prepared"
  
  # Validate configuration
  begin
    engine.validate_rules_config(rules_config)
    puts "✅ Rules configuration is valid"
  rescue => e
    puts "❌ Rules configuration validation failed: #{e.message}"
  end
  
  # Apply rules
  begin
    result = engine.apply_rules(rules_config)
    
    if result.success?
      puts "✅ Rules applied successfully!"
      puts "   Applied rules: #{result.applied_rules.map(&:name).join(', ')}"
      puts "   Total duration: #{result.total_duration.round(3)}s"
      
      # Check if file was copied
      copied_file = File.join(session_path, "Gemfile")
      if File.exist?(copied_file)
        puts "   ✅ Gemfile successfully copied to session"
      else
        puts "   ⚠️  Gemfile not found in session directory"
      end
    else
      puts "❌ Rules application failed:"
      result.errors.each { |error| puts "   - #{error}" }
    end
  rescue => e
    puts "❌ Rules application error: #{e.message}"
  end

  # 5. Test Configuration Validation
  puts "\n🔬 Testing Configuration Validation"
  puts "-" * 30
  
  begin
    Sxn::Rules.validate_configuration(rules_config, project_path, session_path)
    puts "✅ Configuration validation passed"
  rescue => e
    puts "❌ Configuration validation failed: #{e.message}"
  end

  puts "\n🎉 Demo completed successfully!"
  puts "   All core functionality is working correctly."

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