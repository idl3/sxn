# frozen_string_literal: true

require_relative "lib/sxn/version"

Gem::Specification.new do |spec|
  spec.name          = "sxn"
  spec.version       = Sxn::VERSION
  spec.authors       = ["Ernest Sim"]
  spec.email         = ["ernest.codes@gmail.com"]

  spec.summary       = "Session management for multi-repository development"
  spec.description   = "Sxn simplifies git worktree management with intelligent project rules and secure automation"
  spec.homepage      = "https://github.com/idl3/sxn"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) ||
        f.match(%r{\A(?:(?:test|spec|features)/|\.(?:git|travis|circleci)|appveyor)}) ||
        f.match(/\.db-(?:shm|wal)\z/) || # Exclude SQLite temp files
        f.match(/\.gem\z/) # Exclude gem files
    end
  end

  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core CLI dependencies
  spec.add_dependency "pastel", "~> 0.8"                  # Terminal colors
  spec.add_dependency "thor", "~> 1.3"                    # CLI framework
  spec.add_dependency "tty-progressbar", "~> 0.18"        # Progress bars
  spec.add_dependency "tty-prompt", "~> 0.23"             # Interactive prompts
  spec.add_dependency "tty-table", "~> 0.12"              # Table formatting

  # Configuration and data management
  spec.add_dependency "dry-configurable", "~> 1.0"       # Configuration management
  spec.add_dependency "sqlite3", "~> 1.6"                # Session database
  spec.add_dependency "zeitwerk", "~> 2.6"               # Code loading

  # Template engine (secure, sandboxed)
  spec.add_dependency "liquid", "~> 5.4" # Safe template processing

  # MCP server dependencies
  spec.add_dependency "async", "~> 2.0"                  # Async operations
  spec.add_dependency "json-schema", "~> 4.0"            # Schema validation

  # Security and encryption
  spec.add_dependency "bcrypt", "~> 3.1"                 # Password hashing
  spec.add_dependency "openssl", ">= 3.0"                # Encryption support
  spec.add_dependency "ostruct"                          # OpenStruct for Ruby 3.5+ compatibility

  # File system operations
  spec.add_dependency "listen", "~> 3.8"                 # File watching for config cache
  spec.add_dependency "parallel", "~> 1.23"              # Parallel execution

  # Development dependencies
  spec.add_development_dependency "aruba", "~> 2.1" # CLI testing
  spec.add_development_dependency "benchmark" # Benchmark for Ruby 3.5+ compatibility
  spec.add_development_dependency "benchmark-ips", "~> 2.12" # Performance benchmarking
  spec.add_development_dependency "bundler", "~> 2.4"
  spec.add_development_dependency "climate_control", "~> 1.2" # Environment variable testing
  spec.add_development_dependency "faker", "~> 3.2" # Test data generation
  spec.add_development_dependency "memory_profiler", "~> 1.0" # Memory profiling
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50" # Code linting
  spec.add_development_dependency "rubocop-performance", "~> 1.16"
  spec.add_development_dependency "rubocop-rspec", "~> 2.19"
  spec.add_development_dependency "simplecov", "~> 0.22" # Code coverage
  spec.add_development_dependency "vcr", "~> 6.2" # HTTP interaction recording
  spec.add_development_dependency "webmock", "~> 3.19" # HTTP mocking for MCP tests

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
