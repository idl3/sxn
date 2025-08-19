#!/bin/bash

# Test runner script for sxn gem
# Ensures tests run with the correct Ruby version

set -e

# Check if mise is available
if ! command -v mise &> /dev/null; then
    echo "Error: mise is not installed or not in PATH"
    exit 1
fi

# Use mise to run tests with the correct Ruby version
echo "Running tests with Ruby $(mise exec ruby@3.4.5 -- ruby -v)"
echo "----------------------------------------"

if [ $# -eq 0 ]; then
    # Run all config and config_manager related tests by default
    mise exec ruby@3.4.5 -- bundle exec rspec \
        spec/unit/config_spec.rb \
        spec/unit/config/config_cache_spec.rb \
        spec/unit/config/config_discovery_spec.rb \
        spec/unit/config/config_manager_spec.rb \
        spec/unit/config/config_validator_spec.rb \
        spec/unit/core/config_manager_spec.rb \
        --format progress
else
    # Run specific test files provided as arguments
    mise exec ruby@3.4.5 -- bundle exec rspec "$@"
fi