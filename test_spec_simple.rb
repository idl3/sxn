#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test to verify prompt stubbing works without SimpleCov
puts "Testing prompt stubbing without coverage tracking..."

# Load the SXN library without coverage
require_relative "lib/sxn"

# Mock TTY::Prompt to ensure no interactive prompts
require 'rspec'

RSpec.configure do |config|
  config.before(:each) do
    # Global stub to prevent any interactive prompts
    allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return("test-input")
    allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_return(true)
    allow_any_instance_of(TTY::Prompt).to receive(:select).and_return("test-selection")
    
    # Stub Sxn::UI::Prompt methods
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:ask).and_return("test-input")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:ask_yes_no).and_return(true)
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:select).and_return("test-selection")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:sessions_folder_setup).and_return("test-sessions")
    allow_any_instance_of(Sxn::UI::Prompt).to receive(:project_detection_confirm).and_return(false)
    
    # Suppress output
    allow(STDOUT).to receive(:puts)
    allow(STDOUT).to receive(:print)
  end
end

# Simple test case
RSpec.describe "Prompt Prevention Test" do
  it "creates a prompt instance without triggering interactive prompts" do
    prompt = Sxn::UI::Prompt.new
    
    # These should not hang because they're stubbed
    result1 = prompt.ask("Test question?")
    result2 = prompt.ask_yes_no("Test yes/no?")
    result3 = prompt.sessions_folder_setup
    
    expect(result1).to eq("test-input")
    expect(result2).to be true
    expect(result3).to eq("test-sessions")
  end
  
  it "can create command instances without hanging" do
    init_cmd = Sxn::Commands::Init.new
    expect(init_cmd).to be_a(Sxn::Commands::Init)
    
    sessions_cmd = Sxn::Commands::Sessions.new
    expect(sessions_cmd).to be_a(Sxn::Commands::Sessions)
  end
end

# Run the test
if __FILE__ == $0
  require 'timeout'
  
  puts "Running quick prompt prevention test..."
  
  begin
    Timeout::timeout(10) do
      RSpec::Core::Runner.run(['--format', 'documentation'])
    end
    puts "\n✅ SUCCESS: All tests completed without hanging!"
  rescue Timeout::Error
    puts "\n❌ FAILURE: Tests timed out - interactive prompts not properly stubbed"
    exit 1
  end
end