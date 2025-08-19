# frozen_string_literal: true

require "bundler/gem_tasks"
require "rubocop/rake_task"

RuboCop::RakeTask.new

# RSpec tasks
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # RSpec not available
end

# Type checking tasks
namespace :rbs do
  desc "Validate RBS files syntax"
  task :validate do
    sh "bundle exec rbs validate"
  end

  desc "Run type checking with Steep"
  task :check do
    sh "bundle exec steep check"
  end

  desc "Generate RBS prototype from Ruby files"
  task :prototype do
    sh "bundle exec rbs prototype rb lib/**/*.rb > sig/generated.rbs"
  end

  desc "Show Steep statistics"
  task :stats do
    sh "bundle exec steep stats"
  end

  desc "Setup RBS collection"
  task :collection do
    sh "bundle exec rbs collection install"
  end

  desc "Run RBS test with runtime type checking"
  task :test do
    ENV["RBS_TEST_TARGET"] = "Sxn::*"
    Rake::Task["spec"].invoke
  end
end

desc "Run all quality checks (rubocop + type checking)"
task quality: [:rubocop, "rbs:validate", "rbs:check"]

task default: :quality
