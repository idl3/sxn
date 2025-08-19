#!/usr/bin/env ruby
# frozen_string_literal: true

# Security module coverage analysis script

require_relative 'lib/sxn'

puts "=== Security Module Coverage Analysis ==="
puts

# Define the security classes to analyze
security_classes = [
  'Sxn::Security::SecurePathValidator',
  'Sxn::Security::SecureCommandExecutor', 
  'Sxn::Security::SecureFileCopier'
]

security_classes.each do |class_name|
  puts "Analyzing #{class_name}:"
  
  begin
    klass = Object.const_get(class_name)
    
    # Get all instance methods (excluding inherited ones)
    instance_methods = klass.instance_methods(false)
    puts "  Instance methods: #{instance_methods.sort}"
    
    # Get all private methods
    private_methods = klass.private_instance_methods(false)
    puts "  Private methods: #{private_methods.sort}"
    
    # Get class methods
    class_methods = klass.methods(false) - Class.methods
    puts "  Class methods: #{class_methods.sort}"
    
    # Get constants
    constants = klass.constants(false)
    puts "  Constants: #{constants.sort}"
    
    puts
  rescue NameError => e
    puts "  ERROR: Could not load #{class_name}: #{e.message}"
    puts
  end
end

puts "=== Areas needing additional test coverage ==="
puts
puts "1. Edge cases and error conditions"
puts "2. Performance under load"
puts "3. Integration between security components"
puts "4. Advanced encryption scenarios"
puts "5. Complex symlink scenarios"
puts "6. Environment variable validation edge cases"
puts "7. Audit logging completeness"
puts "8. Resource cleanup and memory management"
puts "9. Race conditions and concurrent access"
puts "10. Platform-specific behaviors"