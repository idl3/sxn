# Parallel Testing Guide

## Overview

The sxn project uses `parallel_tests` gem to run RSpec tests in parallel, significantly reducing test execution time from ~35 seconds to ~11 seconds.

## Configuration

### `.parallel_rspec` File

This file configures RSpec formatters for parallel execution:

```
--format progress
--format ParallelTests::RSpec::RuntimeLogger --out tmp/parallel_runtime_rspec.log
```

The RuntimeLogger records execution times for each test file, enabling balanced test distribution across parallel processes.

### Runtime-Based Test Distribution

Tests are distributed across parallel processes based on their historical execution times, ensuring all processes finish at roughly the same time.

## Local Usage

### Run Tests in Parallel

```bash
# Default parallel execution (uses all available CPUs)
bundle exec rake parallel:spec

# With custom processor count
bundle exec rake parallel:spec_custom[2]  # Use 2 processes

# With coverage
bundle exec rake parallel:spec_with_coverage
```

### Generate/Update Runtime Log

```bash
# Generate initial runtime log or update existing one
bundle exec rake parallel:generate_runtime
```

The runtime log is stored at `tmp/parallel_runtime_rspec.log` and contains execution times for each spec file.

### Direct parallel_rspec Command

```bash
# Run with runtime balancing
bundle exec parallel_rspec spec/unit spec/integration spec/performance --runtime-log tmp/parallel_runtime_rspec.log

# Verbose output to see how tests are distributed
bundle exec parallel_rspec spec --verbose-command --runtime-log tmp/parallel_runtime_rspec.log
```

## CI/CD Integration

GitHub Actions is configured to:

1. **Cache Runtime Log**: The runtime log is cached between runs using the spec files' hash as the cache key
2. **Parallel Matrix Jobs**: Tests run across 4 parallel jobs
3. **Automatic Generation**: If no cached runtime log exists, CI generates one automatically
4. **Result Aggregation**: Test results from all parallel jobs are collected and summarized

### CI Configuration

The workflow uses a matrix strategy to run tests in parallel:

```yaml
matrix:
  ruby: ['3.4.5']
  ci_node_total: [4]
  ci_node_index: [0, 1, 2, 3]
```

Each job runs a subset of tests based on the runtime log distribution.

## Benefits

- **Speed**: ~3x faster test execution (35s → 11s)
- **Balanced Distribution**: Tests are distributed based on execution time, not file count
- **CI Optimization**: Parallel jobs in CI reduce overall build time
- **Coverage Support**: SimpleCov properly merges results from parallel processes

## Troubleshooting

### Unbalanced Test Distribution

If tests aren't evenly distributed:

1. Regenerate the runtime log: `bundle exec rake parallel:generate_runtime`
2. Check the log file exists: `ls -la tmp/parallel_runtime_rspec.log`
3. Verify the format (should be `path/to/spec.rb:execution_time`)

### Missing Runtime Log

The system will fall back to file-size-based distribution if no runtime log is found. To ensure runtime-based distribution:

```bash
# Generate if missing
[ -f tmp/parallel_runtime_rspec.log ] || bundle exec rake parallel:generate_runtime
```

### Coverage Issues

Ensure SimpleCov is configured for parallel tests in `spec/spec_helper.rb`:

```ruby
if ENV["TEST_ENV_NUMBER"]
  SimpleCov.command_name "RSpec_#{ENV['TEST_ENV_NUMBER']}"
  SimpleCov.merge_timeout 3600
end
```

## Performance Metrics

Current performance with 4 parallel processes:
- Sequential execution: ~35 seconds
- Parallel execution: ~11 seconds
- Speedup: ~3.2x

The runtime-based distribution ensures all processes finish within 1-2 seconds of each other, maximizing efficiency.