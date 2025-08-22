# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in sxn.gemspec
gemspec

gem "irb"
gem "rake", "~> 13.0"

gem "rubocop", "~> 1.21"

# Test coverage and parallel testing
group :test do
  gem "simplecov", "~> 0.22", require: false
  gem "simplecov-console", require: false
  gem "parallel_tests", "~> 4.0"
end

# Type checking dependencies
group :development do
  gem "rbs", "~> 3.4"
  gem "rbs_rails", "~> 0.12"
  gem "steep", "~> 1.6"
end
