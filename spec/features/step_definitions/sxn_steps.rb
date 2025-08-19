# frozen_string_literal: true

# Basic step definitions for Aruba CLI testing
# Aruba provides most steps we need, these are custom additions

Given("I have a Rails project") do
  create_directory("rails_project")
  cd("rails_project")

  write_file("Gemfile", <<~GEMFILE)
    source "https://rubygems.org"
    gem "rails", "~> 7.0"
  GEMFILE

  create_directory("config")
  write_file("config/application.rb", "# Rails application")
  write_file("config/master.key", "secret_key_here")
end

Given("I have a JavaScript project") do
  create_directory("js_project")
  cd("js_project")

  write_file("package.json", <<~JSON)
    {
      "name": "test-project",
      "version": "1.0.0",
      "dependencies": {
        "react": "^18.0.0"
      }
    }
  JSON

  write_file(".env", "NODE_ENV=development")
end

Then("the session should be created") do
  expect(last_command_started).to be_successfully_executed
  expect(last_command_started.output).to include("Session created successfully")
end

Then("the project should be added") do
  expect(last_command_started).to be_successfully_executed
  expect(last_command_started.output).to include("Project added successfully")
end
