# Sxn

[![CI](https://github.com/idl3/sxn/actions/workflows/ci.yml/badge.svg)](https://github.com/idl3/sxn/actions/workflows/ci.yml)
[![Ruby Version](https://img.shields.io/badge/ruby-3.2%2B-red)](https://www.ruby-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE.txt)

Sxn is a powerful session management tool for multi-repository development. It helps developers manage complex development environments with multiple git repositories, providing isolated workspaces, automatic project setup, and intelligent session management.

## Features

- **Session Management**: Create isolated development sessions with their own git worktrees
- **Multi-Repository Support**: Work with multiple repositories in a single session
- **Automatic Project Setup**: Apply project-specific rules and templates automatically
- **Git Worktree Integration**: Leverage git worktrees for efficient branch management
- **Template Engine**: Generate project-specific files using Liquid templates
- **Security First**: Path validation and command sanitization for safe operations
- **Thread-Safe**: Concurrent operations with proper synchronization

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sxn'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install sxn
```

## Quick Start

### Initialize Sxn in your workspace

```bash
sxn init
```

### Create a new session

```bash
sxn add feature-xyz --description "Working on feature XYZ"
```

### Switch to a session

```bash
sxn use feature-xyz
```

### Add a project worktree to current session

```bash
sxn worktree add my-project --branch feature-xyz
```

### List sessions

```bash
sxn list
```

## Usage

### Session Management

Sessions are isolated workspaces that contain git worktrees for your projects:

```bash
# Create a new session
sxn add my-feature

# Switch to a session
sxn use my-feature

# List all sessions
sxn list

# Show current session
sxn current

# Remove a session
sxn sessions remove my-feature
```

### Project Management

Register and manage projects that can be added to sessions:

```bash
# Add a project
sxn projects add my-app ~/projects/my-app

# List projects
sxn projects list

# Remove a project
sxn projects remove my-app
```

### Worktree Management

Add project worktrees to your current session:

```bash
# Add a worktree for a project
sxn worktree add my-app --branch feature-branch

# List worktrees in current session
sxn worktree list

# Remove a worktree
sxn worktree remove my-app
```

### Rules and Templates

Define project-specific setup rules:

```bash
# List available rules
sxn rules list

# Apply rules to a project
sxn rules apply my-app
```

## Configuration

Sxn stores its configuration in `.sxn/config.yml` in your workspace:

```yaml
sessions_folder: .sxn-sessions
settings:
  auto_cleanup: true
  max_sessions: 10
  default_branch: main
```

## Project Rules

Create `.sxn-rules.yml` in your project root to define automatic setup:

```yaml
rules:
  - type: template
    template: rails/database.yml
    destination: config/database.yml

  - type: copy_files
    source: .env.example
    destination: .env

  - type: setup_commands
    commands:
      - bundle install
      - yarn install
      - rails db:setup
```

## Templates

Sxn includes templates for common project types:

- **Rails**: CLAUDE.md, database.yml, session-info.md
- **JavaScript**: README.md, session-info.md
- **Common**: .gitignore, session-info.md

Templates use Liquid syntax and have access to session, project, and environment variables.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

### Running Tests

```bash
# Run all tests in parallel (recommended for speed)
bundle exec parallel_rspec spec/

# Run all tests sequentially
bundle exec rspec

# Run only unit tests
bundle exec rspec spec/unit

# Run with coverage
ENABLE_SIMPLECOV=true bundle exec parallel_rspec spec/
```

### Type Checking

```bash
# Install RBS dependencies
rbs collection install

# Run Steep type checker
steep check
```

### Linting

```bash
# Run RuboCop
bundle exec rubocop
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yourusername/sxn.

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Author's Note

This is a personal project that leverages Claude Code as the primary and active developer. As we continue to refine the development process and iron out any kinks, you can expect builds to gradually become more stable. Your patience and feedback are greatly appreciated as we evolve this tool together.
