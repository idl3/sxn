# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.5] - 2025-11-30

### Added
- `sxn enter` command to quickly navigate to current session directory
- `sxn current enter` subcommand as alternative way to enter session
- `--path` option for `sxn current` to output only the session path
- `sxn shell` command to install shell integration (idempotent)
  - Auto-detects shell type (bash/zsh)
  - Installs `sxn-enter` function to shell config
  - Supports `--uninstall` to remove integration
  - Supports `--shell-type` to specify shell explicitly

## [0.2.4] - 2025-11-30

### Added
- Interactive worktree wizard after session creation
  - Prompts to add worktrees with descriptive explanations
  - Supports adding multiple worktrees in sequence
  - Explains branch options including remote tracking syntax
- `--skip-worktree` flag to bypass the wizard when creating sessions
- `--verbose` flag for worktree debugging with detailed git output

### Changed
- Sessions now automatically switch to newly created session (no need to run `sxn use` afterwards)
- Improved project manager to safely handle nil projects configuration

### Fixed
- Fixed test mocks for verbose parameter in worktree operations
- Fixed version spec to support semver pre-release format

## [0.2.3] - 2025-09-16

### Added
- Smart branch defaults: worktrees now use session name as default branch
- Remote branch tracking with `remote:` prefix syntax (e.g., `sxn worktree add project remote:origin/feature`)
- Automatic orphaned worktree recovery and cleanup
- Enhanced error messages with actionable suggestions

### Changed
- Improved worktree creation logic to handle existing/orphaned states
- Better error handling for remote branch operations
- Updated CLI documentation with new branch options

### Fixed
- Orphaned worktree cleanup now works for both existing and missing directories
- Worktree creation properly handles branch conflicts
- Test suite compatibility with new worktree features

## [0.2.1] - 2025-01-20

### Fixed
- Fixed SQLite3 datatype mismatch error when listing sessions
- Fixed `sxn list` showing no sessions even when sessions exist
- Improved type coercion for database parameters
- Enhanced error logging for SQLite3 errors

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

[0.2.4]: https://github.com/idl3/sxn/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/idl3/sxn/compare/v0.2.1...v0.2.3
[0.2.1]: https://github.com/idl3/sxn/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/idl3/sxn/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/idl3/sxn/releases/tag/v0.1.0