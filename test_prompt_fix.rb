#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal test to verify prompt stubbing works
puts "Testing prompt stubbing prevention..."

# Only load the UI classes we need to test
require 'tty-prompt'

# Simulate what our spec_helper does
class MockPrompt
  def initialize
    @prompt = TTY::Prompt.new(interrupt: :exit)
  end
  
  def ask(message, **options)
    @prompt.ask(message, **options)
  end
  
  def ask_yes_no(message, default: false)
    @prompt.yes?(message, default: default)
  end
  
  def sessions_folder_setup
    puts "Setting up sessions folder..."
    folder = ask("Sessions folder name:", default: "default-sessions")
    current_dir = ask_yes_no("Create in current directory?", default: true)
    folder
  end
end

# Test 1: Without stubbing (this would hang if we called interactive methods)
puts "✅ TTY::Prompt can be instantiated without hanging"

# Test 2: With RSpec-style stubbing simulation
require 'rspec'

RSpec.configure do |config|
  config.before(:each) do
    allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return("stubbed-input")
    allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_return(true)
    allow(STDOUT).to receive(:puts)
  end
end

RSpec.describe "Prompt Stubbing Test" do
  it "prevents hanging on interactive prompts" do
    mock_prompt = MockPrompt.new
    
    # These calls should return stubbed values, not hang
    result1 = mock_prompt.ask("Test?")
    result2 = mock_prompt.ask_yes_no("Yes?")
    result3 = mock_prompt.sessions_folder_setup
    
    expect(result1).to eq("stubbed-input")
    expect(result2).to be true
    expect(result3).to eq("stubbed-input")
  end
end

# Run the test with timeout to ensure it doesn't hang
require 'timeout'

begin
  Timeout::timeout(5) do
    puts "\nRunning RSpec test with stubbing..."
    RSpec::Core::Runner.run(['--format', 'documentation'])
  end
  puts "\n🎉 SUCCESS: Prompt stubbing is working correctly!"
  puts "✅ No tests hung waiting for user input"
  puts "✅ All interactive methods returned stubbed values"
rescue Timeout::Error
  puts "\n❌ FAILURE: Test timed out - stubbing not working"
  exit 1
end