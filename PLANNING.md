# Sxn - Session Management Tool Planning Document

## Executive Summary

**Sxn** is a secure session management CLI tool designed to streamline multi-repository development workflows using git worktrees. It provides both a command-line interface and MCP (Model Context Protocol) server capabilities for AI-assisted development, with intelligent project setup rules that safely handle sensitive files, environment configuration, and language-specific initialization.

## Technology Decision

After comprehensive analysis, we recommend:

- **Primary Implementation**: Ruby CLI using Thor framework
- **State Management**: SQLite for session metadata (performance & consistency)
- **Configuration Cache**: File-based cache with filesystem watchers
- **Command Execution**: Process spawn with argument arrays (no shell interpolation)
- **Template Engine**: Liquid for safe, sandboxed template processing
- **MCP Server**: Ruby-based using FastMCP
- **Testing Framework**: RSpec with Aruba for CLI testing
- **Distribution**: RubyGems for global installation

## Critical Security & Performance Requirements

### Immediate Security Fixes (P0 - Must Have for v0.1)

1. **No Shell Command Interpolation**: All commands executed via Process.spawn with argument arrays
2. **Path Validation**: Strict validation preventing directory traversal
3. **Template Sandboxing**: Only Liquid templates with whitelisted variables
4. **Sensitive File Encryption**: Encrypt credentials at rest using AES-256

### Short-term Performance Fixes (P1 - Must Have for v0.2)

1. **Configuration Caching**: Cache discovered configs with TTL and file watchers
2. **Session Indexing**: SQLite database for session metadata
3. **Lazy Git Operations**: Defer worktree operations until actually needed
4. **Parallel Rule Execution**: Run independent rules concurrently

### Long-term Architectural Improvements (P2 - Roadmap)

1. **Transactional Operations**: All-or-nothing session operations with rollback
2. **Distributed Locking**: Proper concurrency control for team usage
3. **Async Job Queue**: Background processing for long operations
4. **Event Sourcing**: Complete audit trail and state recovery

## Core Requirements

### 1. Session Folder Configuration

```bash
sxn init <folder-name>              # Configure primary sessions folder
sxn init                            # Interactive prompt for folder name
```

### 2. Project Management

```bash
sxn projects add <name> <path>      # Register a project for worktree creation
sxn projects remove <name>          # Remove a registered project
sxn projects list                   # List all registered projects
```

### 3. Session Management

```bash
sxn add <session-name>              # Create a new session
sxn remove <session-name>           # Remove session (with confirmation)
sxn list                           # List all sessions
sxn use <session-name>             # Set current session context
sxn current                        # Show current session
```

### 4. Worktree Management

```bash
sxn worktree add <project> [branch] [--session=name]  # Add worktree to session
sxn worktree list [--session=name]                    # List worktrees in session
sxn worktree remove <project> [--session=name]        # Remove worktree from session
```

### 5. Project Rules Management

```bash
sxn rules add <project> <rule-type> <config>    # Add setup rule for project
sxn rules list [project]                         # List all rules
sxn rules apply [--session=name]                 # Apply rules to current session
sxn rules template <type>                        # Generate rule template
```

### 6. MCP Server Integration

All commands will be exposed as MCP tools for AI agent access, enabling:

- Automated session creation from Linear tickets
- AI-assisted worktree management
- Context-aware development assistance

## Architecture Design

### Module Structure

```
sxn/
├── lib/
│   ├── sxn/
│   │   ├── cli.rb                 # Main CLI entry point (Thor)
│   │   ├── version.rb             # Version management
│   │   ├── config.rb              # Configuration management
│   │   ├── errors.rb              # Custom error classes
│   │   │
│   │   ├── commands/              # Command implementations
│   │   │   ├── init.rb
│   │   │   ├── projects.rb
│   │   │   ├── sessions.rb
│   │   │   ├── worktrees.rb
│   │   │   └── rules.rb           # Project rules management
│   │   │
│   │   ├── core/                  # Core business logic
│   │   │   ├── session_manager.rb
│   │   │   ├── project_manager.rb
│   │   │   ├── worktree_manager.rb
│   │   │   ├── config_manager.rb
│   │   │   └── rules_engine.rb    # Rules processing engine
│   │   │
│   │   ├── git/                   # Git operations
│   │   │   ├── worktree.rb
│   │   │   ├── repository.rb
│   │   │   └── branch.rb
│   │   │
│   │   ├── rules/                 # Rule implementations
│   │   │   ├── base_rule.rb       # Abstract base class
│   │   │   ├── copy_files_rule.rb # File copying logic
│   │   │   ├── setup_commands_rule.rb # Command execution
│   │   │   ├── template_rule.rb   # Template processing
│   │   │   └── detector.rb        # Language detection
│   │   │
│   │   ├── ui/                    # User interface components
│   │   │   ├── prompt.rb          # Interactive prompts (TTY)
│   │   │   ├── output.rb          # Formatted output
│   │   │   └── table.rb           # Table formatting
│   │   │
│   │   ├── mcp/                   # MCP server implementation
│   │   │   ├── server.rb          # FastMCP server
│   │   │   ├── tools.rb           # Tool definitions
│   │   │   └── handlers.rb        # Request handlers
│   │   │
│   │   └── templates/             # Built-in templates
│   │       ├── rails/             # Rails-specific templates
│   │       ├── javascript/        # JS/TS templates
│   │       └── common/            # Language-agnostic templates
│   │
│   └── sxn.rb                    # Main module
│
├── bin/
│   └── sxn                       # Executable
│
├── spec/                          # RSpec tests
│   ├── spec_helper.rb
│   ├── unit/
│   ├── integration/
│   └── fixtures/
│
├── config/
│   └── default.yml                # Default configuration
│
├── .sxn/                         # User configuration directory
│   ├── config.yml                 # User configuration
│   ├── sessions/                  # Session metadata
│   └── mcp/                       # MCP server config
│
├── Gemfile
├── Gemfile.lock
├── Rakefile
├── README.md
├── PLANNING.md
└── sxn.gemspec
```

## Data Models

### Configuration Strategy

**Hierarchical Discovery with Smart Defaults**:

1. Command-line flags (highest priority)
2. Environment variables (SXN\_\*)
3. Local project config (.sxn/config.yml in project root)
4. Workspace config (.sxn-workspace/config.yml)
5. Global user config (~/.sxn/config.yml)
6. System defaults (lowest priority)

### Configuration Schema

```yaml
# Local Project Config (.sxn/config.yml in project root)
version: 1
sessions_folder: atlas-one-sessions # Relative to project root
current_session: ATL-1234-feature
projects:
  atlas-core:
    path: ./atlas-core # Relative paths for portability
    type: rails
    default_branch: master
    rules: # Project-specific setup rules
      copy_files:
        - source: config/master.key
          strategy: copy # or 'symlink'
        - source: config/credentials/development.key
        - source: .env
        - source: .env.development
      setup_commands:
        - "bundle install"
        - "bin/rails db:create"
        - "bin/rails db:migrate"
      templates:
        - source: ../.sxn/templates/CLAUDE.md
          destination: CLAUDE.md
          process: true # Variable substitution
  atlas-pay:
    path: ./atlas-pay
    type: rails
    default_branch: main
    rules:
      copy_files:
        - source: config/master.key
        - source: .env
  atlas-online:
    path: ./atlas-online
    type: javascript
    package_manager: npm
    rules:
      copy_files:
        - source: .env.local
        - source: .npmrc
      setup_commands:
        - "npm install"
        - "npm run build"
settings:
  auto_cleanup: true
  max_sessions: 10
  worktree_cleanup_days: 30
  default_rules: # Default rules for all projects
    templates:
      - source: .sxn/templates/session-info.md
        destination: README.md

# Global User Config (~/.sxn/config.yml)
user_preferences:
  default_editor: code
  git_username: "Your Name"
  git_email: "you@example.com"
global_settings:
  default_sessions_folder: ".sessions"
  session_cleanup_days: 30
  auto_push_branches: false
templates: # User-specific templates
  feature:
    branch_prefix: "feature/"
    projects: ["core", "frontend"]
  bugfix:
    branch_prefix: "fix/"
    projects: ["core"]
```

### Session Metadata

```yaml
# ~/.sxn/sessions/ATL-1234-feature.yml
name: ATL-1234-feature
created_at: 2025-01-16T10:00:00Z
updated_at: 2025-01-16T14:30:00Z
status: active
linear_task: ATL-1234
worktrees:
  atlas-core:
    path: /path/to/sessions/ATL-1234-feature/atlas-core
    branch: feature/ATL-1234-cart-validation
    created_at: 2025-01-16T10:05:00Z
  atlas-pay:
    path: /path/to/sessions/ATL-1234-feature/atlas-pay
    branch: feature/ATL-1234-payment-update
    created_at: 2025-01-16T10:10:00Z
notes: |
  Implementing cart validation logic across services
tags: [feature, backend, urgent]
```

## Project Rules System (Security-First Design)

### Overview

The Project Rules System automates the setup of git worktrees by safely handling files that aren't tracked by git (credentials, environment variables) and executing project-specific initialization commands with strict security controls.

### Rule Types

#### 1. File Copying Rules (With Path Validation)

Handles sensitive files with strict path validation and permission control:

```yaml
copy_files:
  - source: config/master.key
    strategy: copy # 'copy' or 'symlink'
    permissions: 0600 # Enforced, never less restrictive
    validate: true # Ensures path stays within project
  - source: .env
    strategy: symlink
    encrypt: true # Encrypt at rest using AES-256
```

**Security Implementation:**

```ruby
class SecureFileCopier
  def copy_file(source, destination, options = {})
    # Validate paths stay within project boundaries
    validate_path_security!(source, destination)

    # Check source file permissions
    raise SecurityError if world_readable?(source)

    # Copy with strict permissions
    FileUtils.cp(source, destination, preserve: false)
    File.chmod(options[:permissions] || 0600, destination)

    # Encrypt if requested
    encrypt_file!(destination) if options[:encrypt]
  end

  private

  def validate_path_security!(source, dest)
    # Prevent directory traversal attacks
    raise SecurityError if source.include?("..")
    raise SecurityError if dest.include?("..")

    # Ensure paths are within project
    source_realpath = File.realpath(source)
    unless source_realpath.start_with?(@project_root)
      raise SecurityError, "Path outside project boundary"
    end
  end
end
```

#### 2. Setup Commands (No Shell Interpolation)

Executes commands using Process.spawn with argument arrays - NO shell interpolation:

```yaml
setup_commands:
  - command: ["bundle", "install"]
    environment:
      RAILS_ENV: "development"
      BUNDLE_WITHOUT: "production"
  - command: ["bin/rails", "db:create", "db:migrate"]
    condition: "db_not_exists" # Named condition, not arbitrary code
```

**Secure Command Execution:**

```ruby
class SecureCommandExecutor
  # Whitelist of allowed commands
  ALLOWED_COMMANDS = {
    'bundle' => '/usr/local/bin/bundle',
    'npm' => '/usr/local/bin/npm',
    'yarn' => '/usr/local/bin/yarn',
    'bin/rails' => './bin/rails'
  }.freeze

  def execute(command_array, options = {})
    # Validate command is whitelisted
    cmd = command_array.first
    unless ALLOWED_COMMANDS.key?(cmd)
      raise SecurityError, "Command not whitelisted: #{cmd}"
    end

    # Use Process.spawn with array to prevent shell injection
    # This is SAFE - no shell interpolation possible
    pid = Process.spawn(
      options[:environment] || {},
      ALLOWED_COMMANDS[cmd],
      *command_array[1..-1],
      chdir: @project_path,
      unsetenv_others: true  # Clean environment
    )
    Process.wait(pid)

    unless $?.success?
      raise CommandError, "Command failed: #{command_array.join(' ')}"
    end
  end
end
```

#### 3. Template Processing (Sandboxed with Liquid)

Uses Liquid template engine for safe, sandboxed variable substitution - no code execution possible:

**Why Liquid?**

- Sandboxed execution - no arbitrary Ruby code
- Whitelist-based variable access
- No filesystem access from templates
- Battle-tested in production (GitHub Pages, Shopify)

**Template Example (.sxn/templates/CLAUDE.md):**

````markdown
# Session: {{session.name}}

## Context

- **Created**: {{session.created_at}}
- **Linear Task**: [{{session.linear_task}}](https://linear.app/team/issue/{{session.linear_task}})
- **Branch**: {{git.branch}}
- **Projects**: {{session.projects | join: ", "}}

## Session Purpose

{{session.description}}

## Modified Files

{{#each session.modified_files}}

- {{this.path}} ({{this.status}})
  {{/each}}

## Development Notes

- Ruby Version: {{ruby.version}}
- Rails Version: {{rails.version}}
- Database: {{database.name}}

## Commands

```bash
# Navigate to session
cd {{session.path}}

# Run tests
{{test.command}}

# Start server
{{server.command}}
```
````

````

**Available Variables:**
```ruby
variables:
  # Session context
  session:
    name: "ATL-1234-feature"           # Current session name
    path: "/path/to/session"           # Full session path
    created_at: "2025-01-16T10:00:00Z" # ISO timestamp
    updated_at: "2025-01-16T14:30:00Z"
    linear_task: "ATL-1234"            # Linear ticket ID
    description: "Cart validation fix"  # Session description
    projects: ["atlas-core", "atlas-pay"]  # Active projects
    modified_files: [...]              # List of changed files

  # Git information
  git:
    branch: "feature/ATL-1234-cart"    # Current branch name
    remote: "origin"                   # Remote name
    last_commit: "abc123"              # Latest commit SHA
    author: "John Doe"                 # Git author name
    email: "john@example.com"          # Git author email

  # Project details
  project:
    name: "atlas-core"                 # Project name
    type: "rails"                      # Project type
    path: "./atlas-core"               # Project path

  # Environment info
  ruby:
    version: "3.2.0"                   # Ruby version
  rails:
    version: "7.0.4"                   # Rails version
  node:
    version: "18.0.0"                  # Node.js version
  database:
    name: "postgresql"                 # Database type
    version: "14.0"                    # Database version

  # Dynamic commands
  test:
    command: "bundle exec rspec"       # Test command
  server:
    command: "bin/rails server"        # Server start command
  console:
    command: "bin/rails console"       # Console command

  # User preferences
  user:
    name: "{{git config user.name}}"   # From git config
    email: "{{git config user.email}}"
    editor: "code"                     # Preferred editor
````

**Processing Implementation:**

```ruby
class TemplateProcessor
  def process(template_path, destination, variables)
    # Read template
    template_content = File.read(template_path)

    # Simple variable replacement (Mustache-style)
    processed = template_content.gsub(/\{\{([^}]+)\}\}/) do |match|
      key_path = $1.strip.split('.')
      fetch_nested_value(variables, key_path) || match
    end

    # Handle conditionals
    processed = process_conditionals(processed, variables)

    # Handle loops
    processed = process_loops(processed, variables)

    # Write processed file
    File.write(destination, processed)
  end

  private

  def fetch_nested_value(hash, keys)
    keys.reduce(hash) do |current, key|
      break nil unless current.is_a?(Hash)
      current[key.to_sym] || current[key.to_s]
    end
  end

  def process_conditionals(content, variables)
    # Handle {{#if condition}} ... {{/if}}
    content.gsub(/\{\{#if\s+([^}]+)\}\}(.*?)\{\{\/if\}\}/m) do
      condition = evaluate_condition($1, variables)
      condition ? $2 : ''
    end
  end

  def process_loops(content, variables)
    # Handle {{#each collection}} ... {{/each}}
    content.gsub(/\{\{#each\s+([^}]+)\}\}(.*?)\{\{\/each\}\}/m) do
      collection_path = $1.strip
      template = $2
      collection = fetch_nested_value(variables, collection_path.split('.'))

      collection.map do |item|
        template.gsub(/\{\{this(?:\.([^}]+))?\}\}/) do
          $1 ? fetch_nested_value(item, $1.split('.')) : item
        end
      end.join
    end
  end
end
```

**Advanced Template Types:**

1. **ERB Templates** (for Ruby logic):

```erb
# .sxn/templates/database.yml.erb
development:
  adapter: postgresql
  database: <%= session_name %>_development
  username: <%= ENV['DB_USER'] || 'postgres' %>
  <% if docker_environment? %>
  host: db
  <% else %>
  host: localhost
  <% end %>
```

2. **Liquid Templates** (safer sandboxed processing):

```liquid
# .sxn/templates/README.liquid
# {{ session.name | upcase }}

{% if session.linear_task %}
Linear Task: {{ session.linear_task }}
{% endif %}

{% for project in session.projects %}
- {{ project | capitalize }}
{% endfor %}
```

**Configuration Example:**

```yaml
templates:
  - source: .sxn/templates/CLAUDE.md
    destination: CLAUDE.md
    engine: mustache # or 'erb', 'liquid'
    process: true
    variables:
      custom_var: "value" # Additional variables

  - source: .sxn/templates/database.yml.erb
    destination: config/database.yml
    engine: erb
    process: true

  - source: .sxn/templates/docker-compose.override.yml
    destination: docker-compose.override.yml
    engine: liquid
    process: true
```

### Language-Specific Defaults

#### Rails Projects

```yaml
rails_defaults:
  copy_files:
    - config/master.key
    - config/credentials/*.key
    - .env
    - .env.development
    - .env.test
  setup_commands:
    - "bundle install"
    - "bin/rails db:create"
    - "bin/rails db:migrate"
    - "bin/rails db:seed" # Optional
```

#### JavaScript/TypeScript Projects

```yaml
javascript_defaults:
  copy_files:
    - .env
    - .env.local
    - .npmrc
  setup_commands:
    - "npm install" # Auto-detects yarn/pnpm
    - "npm run build"
```

### Security Considerations

#### Sensitive File Handling

```ruby
class SecureFileHandler
  SENSITIVE_PATTERNS = [
    /master\.key$/,
    /credentials.*\.key$/,
    /\.env/,
    /secrets\.yml$/,
    /\.npmrc$/  # May contain auth tokens
  ]

  def handle_sensitive_file(source, destination, strategy = :copy)
    validate_permissions(source)
    validate_no_logging(source)

    case strategy
    when :copy
      FileUtils.cp(source, destination, preserve: true)
      File.chmod(0600, destination)  # Restrict permissions
    when :symlink
      File.symlink(File.absolute_path(source), destination)
    end

    audit_security_action(source, destination)
  end
end
```

## Performance Optimizations

### Configuration Caching

Prevent expensive filesystem walks on every command:

```ruby
class ConfigCache
  CACHE_FILE = '.sxn/.cache/config.json'
  CACHE_TTL = 300  # 5 minutes

  def get_config(directory)
    if cache_valid?
      return load_cached_config
    end

    config = discover_config(directory)  # Expensive operation
    save_cache(config)
    config
  end

  private

  def cache_valid?
    return false unless File.exist?(CACHE_FILE)

    cache_mtime = File.mtime(CACHE_FILE)
    config_files = Dir.glob("**/.sxn/config.yml", base: project_root)

    # Invalidate if any config file is newer than cache
    config_files.none? { |f| File.mtime(f) > cache_mtime }
  end
end
```

### Session Metadata Database

Replace filesystem scanning with indexed SQLite:

```ruby
class SessionDatabase
  def initialize(db_path = '.sxn/sessions.db')
    @db = SQLite3::Database.new(db_path)
    create_tables
    create_indexes
  end

  def create_tables
    @db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL,
        status TEXT NOT NULL,
        metadata JSON,
        INDEX idx_status (status),
        INDEX idx_created (created_at),
        INDEX idx_name (name)
      )
    SQL
  end

  def list_sessions(limit: 100)
    # This is O(1) with index vs O(n) filesystem scan
    @db.execute(
      "SELECT * FROM sessions ORDER BY updated_at DESC LIMIT ?",
      limit
    )
  end

  def add_session(session)
    @db.execute(
      "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?)",
      session.id, session.name, session.created_at,
      session.updated_at, session.status, session.metadata.to_json
    )
  end
end
```

### Lazy Git Operations

Defer expensive git operations until needed:

```ruby
class LazyWorktree
  def initialize(project, branch)
    @project = project
    @branch = branch
    @created = false
  end

  def path
    create! unless @created
    @path
  end

  private

  def create!
    # Only create worktree when actually accessed
    @path = Git.create_worktree(@project, @branch)
    @created = true
  end
end
```

### Parallel Rule Execution

Run independent rules concurrently:

```ruby
class ParallelRuleExecutor
  def apply_rules(rules)
    # Group rules by dependency
    independent_rules = rules.select { |r| r.dependencies.empty? }
    dependent_rules = rules - independent_rules

    # Execute independent rules in parallel
    Parallel.map(independent_rules, in_threads: 4) do |rule|
      apply_rule(rule)
    end

    # Then execute dependent rules serially
    dependent_rules.each { |rule| apply_rule(rule) }
  end
end
```

### Language Detection

```ruby
class ProjectDetector
  def detect_type(path)
    # Rails detection
    if File.exist?(File.join(path, 'Gemfile'))
      gemfile = File.read(File.join(path, 'Gemfile'))
      return :rails if gemfile.include?('rails')
      return :ruby
    end

    # JavaScript/TypeScript detection
    if File.exist?(File.join(path, 'package.json'))
      package = JSON.parse(File.read(File.join(path, 'package.json')))
      return :typescript if File.exist?(File.join(path, 'tsconfig.json'))
      return :nextjs if package.dig('dependencies', 'next')
      return :react if package.dig('dependencies', 'react')
      return :javascript
    end

    :unknown
  end

  def detect_package_manager(path)
    return :pnpm if File.exist?(File.join(path, 'pnpm-lock.yaml'))
    return :yarn if File.exist?(File.join(path, 'yarn.lock'))
    return :npm if File.exist?(File.join(path, 'package-lock.json'))
    :npm # default
  end
end
```

## Known Limitations & Trade-offs

### Accepted Limitations (v1.0)

These are conscious trade-offs we're making for simplicity:

1. **Single-machine focus**: No distributed session management initially
2. **Local filesystem only**: No network filesystem optimization (NFS/SMB will be slow)
3. **Limited concurrency**: File-based locking, not distributed locks
4. **Git worktree limits**: Performance degrades beyond 50 worktrees per repository
5. **Platform support**: Full support for macOS/Linux only, Windows via WSL2

### Security Boundaries

What we explicitly DON'T protect against:

1. **Malicious local users**: Assumes trusted development environment
2. **Supply chain attacks**: Doesn't validate gem dependencies
3. **Hardware attacks**: No protection against memory dumps
4. **Network attacks**: MCP server runs without TLS locally

### Performance Expectations

Realistic performance targets:

| Operation        | Target (v1.0) | At Scale (100+ sessions) |
| ---------------- | ------------- | ------------------------ |
| Session list     | < 50ms        | < 200ms                  |
| Session create   | < 2s          | < 5s                     |
| Config discovery | < 100ms       | < 100ms (cached)         |
| Worktree create  | < 3s          | < 10s                    |
| Rule application | < 5s          | < 15s                    |

### Scaling Limits

When the tool will struggle:

- **> 100 concurrent sessions**: SQLite contention issues
- **> 50 worktrees per repo**: Git performance degradation
- **> 10 team members**: Lock contention on shared resources
- **> 1GB template files**: Memory usage spikes
- **Network filesystems**: 10x slower operations

## Implementation Phases

### Phase 1: Security-First MVP (Week 1)

**Goal**: Secure foundation with basic functionality

- [ ] Core CLI structure with Thor
- [ ] **Secure command execution** (Process.spawn, no shell)
- [ ] **Path validation** for all file operations
- [ ] **SQLite session database** (not filesystem scanning)
- [ ] Basic session creation with transactional operations
- [ ] Configuration with caching
- [ ] Security-focused unit tests

**Deliverables**:

- Secure `sxn init`, `sxn add`, `sxn list`
- No shell injection vulnerabilities
- 95% test coverage for security-critical code

### Phase 2: Safe Rules System (Week 2)

**Goal**: Implement rules with security controls

- [ ] **Liquid template engine** (sandboxed, no code execution)
- [ ] **Whitelist-based command execution**
- [ ] **Encrypted sensitive file handling**
- [ ] File copying with permission preservation
- [ ] Rule validation and error handling
- [ ] Comprehensive security tests

**Deliverables**:

- Safe rule application system
- No template injection vulnerabilities
- Encrypted credential storage

### Phase 3: Performance & Scalability (Week 3)

**Goal**: Optimize for real-world usage

- [ ] **Configuration caching with file watchers**
- [ ] **Parallel rule execution**
- [ ] **Lazy git operations**
- [ ] Session indexing and search
- [ ] Batch operations support
- [ ] Performance benchmarks

**Deliverables**:

- < 100ms config discovery (cached)
- < 50ms session listing (100 sessions)
- Parallel rule execution

### Phase 4: User Experience (Week 4)

**Goal**: Polish and usability

- [ ] Rich terminal UI with TTY components
- [ ] Clear error messages with recovery suggestions
- [ ] Interactive prompts with validation
- [ ] Shell completion scripts
- [ ] `sxn debug` commands for troubleshooting
- [ ] Comprehensive documentation

**Deliverables**:

- Professional CLI experience
- Shell completions for bash/zsh/fish
- User and troubleshooting guides

### Phase 5: MCP Integration (Week 5)

**Goal**: AI-safe agent access

- [ ] FastMCP server with **sanitized inputs**
- [ ] Rate limiting for MCP requests
- [ ] Audit logging for all MCP operations
- [ ] Read-only mode for AI agents
- [ ] MCP security tests

**Deliverables**:

- Secure MCP server
- AI agent access controls
- Audit trail for AI operations

### Phase 6: Production Hardening (Week 6)

**Goal**: Enterprise-ready features

- [ ] **Transactional operations with rollback**
- [ ] **Distributed locking** for team usage
- [ ] Session backup and restore
- [ ] Health monitoring and alerting
- [ ] Auto-cleanup with safety checks
- [ ] Chaos testing

**Deliverables**:

- Production-ready tool
- < 1 critical bug per month target
- Enterprise deployment guide

## Technical Specifications

### Dependencies

**Core Dependencies**:

- `thor` (~> 1.3) - CLI framework
- `tty-prompt` (~> 0.23) - Interactive prompts
- `tty-table` (~> 0.12) - Table formatting
- `pastel` (~> 0.8) - Terminal colors
- `dry-configurable` (~> 1.0) - Configuration management

**MCP Dependencies**:

- `fastmcp` (~> 0.2) - MCP server framework
- `async` (~> 2.0) - Async operations
- `json-schema` (~> 4.0) - Schema validation

**Development Dependencies**:

- `rspec` (~> 3.12) - Testing framework
- `rubocop` (~> 1.50) - Code linting
- `simplecov` (~> 0.22) - Code coverage
- `faker` (~> 3.2) - Test data generation
- `webmock` (~> 3.19) - HTTP mocking

### Performance Requirements

- Session creation: < 100ms
- Worktree creation: < 2s per repository
- Session listing: < 50ms for 100 sessions
- MCP response time: < 200ms per operation
- Memory usage: < 50MB for typical operations

### Error Handling Strategy

```ruby
module Sxn
  class Error < StandardError; end

  class ConfigurationError < Error; end
  class SessionNotFoundError < Error; end
  class ProjectNotFoundError < Error; end
  class WorktreeError < Error; end
  class GitError < Error; end

  class ErrorHandler
    def self.handle(error, context = {})
      case error
      when GitError
        UI.error "Git operation failed: #{error.message}"
        UI.suggest "Check git status and try again"
      when SessionNotFoundError
        UI.error "Session not found: #{error.message}"
        UI.suggest "Run 'sxn list' to see available sessions"
      else
        UI.error "Unexpected error: #{error.message}"
        UI.debug error.backtrace if verbose?
      end

      exit(error.exit_code || 1)
    end
  end
end
```

## Testing Strategy

### Testing Framework Stack

- **RSpec**: Unit and integration testing
- **Aruba**: CLI acceptance testing
- **Climate Control**: Environment variable testing
- **VCR**: HTTP interaction recording for MCP tests
- **SimpleCov**: Code coverage reporting

### Test Structure

```
spec/
├── unit/                          # Unit tests
│   ├── commands/
│   │   ├── init_spec.rb
│   │   ├── projects_spec.rb
│   │   └── rules_spec.rb
│   ├── core/
│   │   ├── session_manager_spec.rb
│   │   └── rules_engine_spec.rb
│   └── rules/
│       ├── copy_files_rule_spec.rb
│       └── detector_spec.rb
│
├── integration/                   # Integration tests
│   ├── session_lifecycle_spec.rb
│   ├── worktree_creation_spec.rb
│   └── rule_application_spec.rb
│
├── features/                      # Aruba CLI tests
│   ├── init.feature
│   ├── projects.feature
│   ├── sessions.feature
│   ├── rules.feature
│   └── step_definitions/
│       └── sxn_steps.rb
│
├── fixtures/                      # Test fixtures
│   ├── rails_project/
│   │   ├── Gemfile
│   │   ├── config/
│   │   └── .env.example
│   └── js_project/
│       ├── package.json
│       └── .env.example
│
└── support/
    ├── spec_helper.rb
    ├── aruba.rb
    └── helpers/
        ├── git_helper.rb
        └── file_helper.rb
```

### Unit Tests (RSpec)

```ruby
# spec/unit/core/rules_engine_spec.rb
RSpec.describe Sxn::Core::RulesEngine do
  let(:engine) { described_class.new }
  let(:project) { double('project', path: '/tmp/test-project') }

  describe '#apply_rules' do
    context 'with copy_files rule' do
      it 'copies sensitive files with correct permissions' do
        rule = { 'copy_files' => [
          { 'source' => 'config/master.key', 'strategy' => 'copy' }
        ]}

        expect(SecureFileHandler).to receive(:handle_sensitive_file)
          .with('config/master.key', anything, :copy)

        engine.apply_rules(project, rule)
      end
    end
  end
end
```

### Integration Tests

```ruby
# spec/integration/session_lifecycle_spec.rb
RSpec.describe 'Session Lifecycle' do
  include GitHelper
  include FileHelper

  let(:tmp_dir) { Dir.mktmpdir }

  before do
    setup_test_repository(tmp_dir)
    create_test_config(tmp_dir)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it 'creates session with worktrees and applies rules' do
    session_manager = Sxn::Core::SessionManager.new(tmp_dir)

    session = session_manager.create('test-session')
    expect(session).to be_persisted

    worktree = session.add_worktree('test-project', 'feature-branch')
    expect(worktree).to exist

    # Verify rules were applied
    expect(File).to exist(File.join(worktree.path, '.env'))
    expect(File.stat(File.join(worktree.path, 'config/master.key')).mode)
      .to eq(0100600)
  end
end
```

### CLI Acceptance Tests (Aruba)

```gherkin
# spec/features/rules.feature
Feature: Project Rules Management
  As a developer
  I want to manage project setup rules
  So that new worktrees are automatically configured

  Background:
    Given I have a Rails project with sensitive files
    And I have initialized sxn in the project

  Scenario: Apply default Rails rules
    When I run `sxn worktree add atlas-core feature-branch`
    Then the exit status should be 0
    And the file "atlas-one-sessions/current/atlas-core/config/master.key" should exist
    And the file "atlas-one-sessions/current/atlas-core/.env" should exist
    And the output should contain "Applied 3 rules successfully"

  Scenario: Custom rule templates
    Given I have a template file ".sxn/templates/CLAUDE.md"
    When I run `sxn rules add atlas-core template .sxn/templates/CLAUDE.md`
    And I run `sxn worktree add atlas-core`
    Then the file "atlas-one-sessions/current/atlas-core/CLAUDE.md" should exist
    And the file should contain "Session: current"
```

### MCP Tests with VCR

```ruby
# spec/unit/mcp/server_spec.rb
RSpec.describe Sxn::MCP::Server do
  describe 'tool registration' do
    it 'exposes all CLI commands as MCP tools' do
      VCR.use_cassette('mcp_tool_discovery') do
        server = described_class.new
        tools = server.list_tools

        expect(tools).to include(
          have_attributes(name: 'sxn_init'),
          have_attributes(name: 'sxn_projects_add'),
          have_attributes(name: 'sxn_worktree_add')
        )
      end
    end
  end
end
```

### Performance Tests

```ruby
# spec/performance/large_scale_spec.rb
RSpec.describe 'Performance' do
  it 'handles 100 sessions efficiently' do
    time = Benchmark.measure do
      100.times { |i| create_session("session-#{i}") }
    end

    expect(time.real).to be < 5.0  # Should complete in under 5 seconds
  end

  it 'lists sessions quickly with many entries' do
    create_sessions(100)

    time = Benchmark.measure do
      Sxn::Commands::Sessions.new.list
    end

    expect(time.real).to be < 0.05  # 50ms target
  end
end
```

### Test Coverage Requirements

- Overall: 90% minimum
- Core business logic: 95% minimum
- Security-critical code: 100% required
- CLI commands: 85% minimum

### Continuous Integration

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        ruby: ["3.0", "3.1", "3.2"]
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rspec
      - run: bundle exec cucumber
      - run: bundle exec rubocop
```

## Security Considerations

1. **Path Validation**: Sanitize all user-provided paths
2. **Command Injection**: Never pass user input directly to shell commands
3. **File Permissions**: Respect filesystem permissions
4. **Sensitive Data**: Never log sensitive information
5. **MCP Security**: Validate all MCP requests, implement rate limiting

## Migration Strategy

For teams currently using manual worktree management:

1. **Discovery Phase**: Scan existing worktrees and import as sessions
2. **Parallel Operation**: Allow both manual and sxn management initially
3. **Gradual Adoption**: Migrate one project at a time
4. **Training**: Provide interactive tutorials and documentation
5. **Rollback Plan**: Easy export to standard git worktrees

## Success Metrics

- **Adoption**: 80% of team using sxn within 3 months
- **Productivity**: 30% reduction in session setup time
- **Reliability**: < 1 critical bug per month
- **Performance**: All operations under defined thresholds
- **User Satisfaction**: > 4.0/5.0 in team surveys

## Risk Mitigation

### High-Risk Areas

1. **Git Worktree Corruption**

   - Mitigation: Implement robust validation and recovery
   - Fallback: Manual worktree repair documentation

2. **Cross-Platform Compatibility**

   - Mitigation: Extensive testing on macOS/Linux
   - Fallback: Platform-specific implementations

3. **MCP Integration Complexity**

   - Mitigation: Start with simple tool exposure
   - Fallback: CLI-only operation mode

4. **Team Adoption Resistance**
   - Mitigation: Gradual rollout with champions
   - Fallback: Maintain compatibility with manual workflow

## Alternative Approaches Considered

1. **TypeScript Implementation**: Better MCP SDK support but requires Node.js runtime
2. **Go Implementation**: Better performance but less Ruby ecosystem integration
3. **Shell Scripts**: Simpler but limited functionality and poor Windows support
4. **VS Code Extension**: IDE-specific, doesn't work for terminal users

## Minimum Viable Product (MVP)

The absolute minimum for initial release:

1. `sxn init` - Configure sessions folder
2. `sxn projects add/list` - Register projects
3. `sxn add/list` - Create and list sessions
4. `sxn worktree add` - Create worktrees in sessions

This provides immediate value while keeping complexity manageable.

## Future Enhancements (Post-Launch)

1. **Session Templates**: Predefined configurations for common workflows
2. **Team Collaboration**: Shared sessions with locking
3. **IDE Integration**: VS Code and RubyMine extensions
4. **Analytics Dashboard**: Web UI for session metrics
5. **Cloud Sync**: Backup and sync across machines
6. **AI Assistance**: Intelligent session recommendations
7. **Plugin System**: Extensibility for custom workflows

## Global Gem Installation & Distribution

### Gemspec Configuration

```ruby
# sxn.gemspec
Gem::Specification.new do |spec|
  spec.name          = "sxn"
  spec.version       = Sxn::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]
  spec.summary       = "Session management for multi-repository development"
  spec.description   = "Sxn simplifies git worktree management with intelligent project rules"
  spec.homepage      = "https://github.com/yourusername/sxn"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  # Executable
  spec.bindir        = "bin"
  spec.executables   = ["sxn"]

  # Files
  spec.files         = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  # Runtime dependencies
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-table", "~> 0.12"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "dry-configurable", "~> 1.0"
  spec.add_dependency "fastmcp", "~> 0.2"
  spec.add_dependency "zeitwerk", "~> 2.6"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.4"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "aruba", "~> 2.1"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "vcr", "~> 6.2"
  spec.add_development_dependency "webmock", "~> 3.19"
  spec.add_development_dependency "climate_control", "~> 1.2"
end
```

### Installation Methods

#### 1. From RubyGems (Production)

```bash
# Install globally
gem install sxn

# Verify installation
sxn --version
sxn --help
```

#### 2. From Source (Development)

```bash
# Clone repository
git clone https://github.com/yourusername/sxn.git
cd sxn

# Install dependencies
bundle install

# Build gem locally
gem build sxn.gemspec

# Install locally built gem
gem install ./sxn-0.1.0.gem

# Or install directly via bundler
bundle exec rake install
```

#### 3. Via Bundler (Project-specific)

```ruby
# Gemfile
gem 'sxn', '~> 0.1'

# Or from GitHub
gem 'sxn', github: 'yourusername/sxn'
```

### Publishing to RubyGems

#### Pre-release Checklist

```bash
# 1. Run all tests
bundle exec rspec
bundle exec cucumber

# 2. Check code quality
bundle exec rubocop

# 3. Update version
# Edit lib/sxn/version.rb
module Sxn
  VERSION = "0.1.0"
end

# 4. Update CHANGELOG.md
# Document all changes

# 5. Build gem
gem build sxn.gemspec

# 6. Test local installation
gem install ./sxn-0.1.0.gem
sxn --version
```

#### Publishing Process

```bash
# 1. Create RubyGems account (if needed)
# Visit https://rubygems.org/sign_up

# 2. Setup credentials
gem signin

# 3. Push to RubyGems
gem push sxn-0.1.0.gem

# 4. Verify on RubyGems.org
# https://rubygems.org/gems/sxn
```

### Platform Compatibility

#### Supported Platforms

- macOS 11+ (primary development platform)
- Ubuntu 20.04+
- Debian 11+
- RHEL/CentOS 8+
- Windows 10+ with WSL2 (limited support)

#### Ruby Version Support

- Ruby 3.0+ (required)
- Ruby 3.2+ (recommended)
- JRuby 9.4+ (experimental)

### Post-Installation Setup

#### Shell Completion

```bash
# Bash completion
sxn completion bash > /usr/local/etc/bash_completion.d/sxn

# Zsh completion
sxn completion zsh > /usr/local/share/zsh/site-functions/_sxn

# Fish completion
sxn completion fish > ~/.config/fish/completions/sxn.fish
```

#### System Integration

```bash
# Add to PATH (if not automatically added)
echo 'export PATH="$PATH:$(gem environment gemdir)/bin"' >> ~/.bashrc

# Create system-wide config (optional)
sudo sxn init --system /opt/sxn-sessions

# Setup MCP server (for AI integration)
sxn mcp install
```

### Version Management

#### Semantic Versioning

- MAJOR.MINOR.PATCH (e.g., 1.2.3)
- MAJOR: Breaking changes
- MINOR: New features, backward compatible
- PATCH: Bug fixes, backward compatible

#### Release Cycle

- Patch releases: As needed for critical fixes
- Minor releases: Monthly with new features
- Major releases: Annually or for breaking changes

### Troubleshooting Installation

#### Common Issues

```bash
# Permission denied
sudo gem install sxn

# Dependency conflicts
gem install sxn --conservative

# SSL certificate errors
gem install sxn --source http://rubygems.org

# Behind corporate proxy
gem install sxn --http-proxy http://proxy.company.com:8080
```

#### Verification Commands

```bash
# Check installation
which sxn
sxn --version

# Check gem location
gem which sxn

# List installed files
gem contents sxn

# Check dependencies
gem dependency sxn
```

## Documentation Plan

1. **README.md**: Quick start and basic usage
2. **GUIDE.md**: Comprehensive user guide
3. **API.md**: MCP tool documentation
4. **CONTRIBUTING.md**: Development setup and guidelines
5. **CHANGELOG.md**: Version history and migration guides

## Support and Maintenance

1. **Bug Reports**: GitHub issues with templates
2. **Feature Requests**: Discussion forum for proposals
3. **Documentation**: Maintained with each release
4. **Version Policy**: Semantic versioning, 6-month support cycle
5. **Security Updates**: Critical patches within 48 hours

## Conclusion

Sxn aims to simplify multi-repository development through intelligent session management. By starting with a focused MVP and gradually adding features based on user feedback, we can deliver immediate value while building toward a comprehensive solution.

The hybrid Ruby implementation with MCP support provides the best balance of simplicity, performance, and integration with existing tools. The phased approach allows for course correction based on real-world usage patterns.

Success will be measured not by feature count but by developer productivity gains and reduction in context-switching overhead.
