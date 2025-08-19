# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-01-20

### Added
- Complete session management system for multi-repository development
- Git worktree integration with intelligent project rules
- Secure automation with template engine (Liquid-based)
- SQLite-based session database for persistent state
- Configuration management with hierarchical settings
- Rules engine for project-specific automation
- Project detector for automatic project type identification
- MCP (Model Context Protocol) server integration
- Comprehensive security layer with path validation and command execution controls
- Template processing with security sandboxing
- Progress bars and interactive CLI prompts
- Full test suite with 2,324 tests and 87.75% branch coverage

### Changed
- Improved performance test thresholds for CI environments
- Replaced thread-based stress tests with sequential operations to prevent hanging
- Relaxed memory leak test thresholds for CI compatibility
- Updated Ruby version requirement to 3.2.0+

### Fixed
- Ruby 3.2 compatibility issues with hash inspection format
- Performance test timing issues in CI environments
- Template security caching test reliability
- RuboCop compliance with appropriate metric relaxations

### Security
- Implemented comprehensive path traversal protection
- Added secure command execution with whitelisting
- Template sandboxing to prevent code injection
- Sensitive file handling with encryption support

## [0.1.0] - 2025-01-19

### Added
- Initial placeholder release
- Basic gem structure

[0.2.0]: https://github.com/idl3/sxn/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/idl3/sxn/releases/tag/v0.1.0