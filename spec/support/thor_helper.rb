# frozen_string_literal: true

# Thor Testing Helper
# 
# This helper provides utilities for testing Thor-based commands without
# causing Thor command warnings in the test output.
module ThorHelper
  # Safely mock Thor instance methods on specific instances rather than globally
  def mock_thor_methods(thor_instance, methods = {})
    default_methods = {
      ask: "test-input",
      yes?: true,
      no?: false
    }
    
    methods = default_methods.merge(methods)
    
    methods.each do |method, return_value|
      allow(thor_instance).to receive(method).and_return(return_value)
    end
  end
  
  # Helper to create a Thor command instance with mocked methods
  def create_mocked_thor_command(command_class, methods = {})
    command = command_class.new
    mock_thor_methods(command, methods)
    command
  end
  
  # Suppress Thor warnings during test execution
  def suppress_thor_warnings
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original_stderr
  end
end

RSpec.configure do |config|
  config.include ThorHelper
end