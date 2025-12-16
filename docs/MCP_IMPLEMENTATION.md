# SXN MCP Server & Claude Code Plugin Implementation Plan

## Overview

Build an MCP (Model Context Protocol) server for sxn that enables Claude Code to manage development sessions, worktrees, templates, and rules. Then enhance with a Claude Code plugin for richer UX.

## Architecture

### Phase 1: MCP Server (`sxn-mcp`)
A standalone MCP server using the official Ruby SDK that exposes sxn operations as tools, resources, and prompts.

### Phase 2: Claude Code Plugin
A plugin that bundles the MCP server with slash commands, hooks, and skills for enhanced Claude Code integration.

---

## Phase 1: MCP Server Implementation

### Dependencies

Add to `sxn.gemspec`:
```ruby
spec.add_dependency "mcp", "~> 0.4"  # Official Anthropic/Shopify Ruby SDK
```

Note: `async` (~2.0) and `json-schema` (~4.0) already present in gemspec.

### File Structure

```
lib/sxn/
├── mcp/
│   ├── server.rb                 # Main MCP server class
│   ├── tools/
│   │   ├── base_tool.rb          # Shared tool functionality + error mapping
│   │   ├── sessions.rb           # Session CRUD tools
│   │   ├── worktrees.rb          # Worktree management tools
│   │   ├── projects.rb           # Project management tools
│   │   ├── templates.rb          # Template tools
│   │   └── rules.rb              # Rules tools
│   ├── resources/
│   │   └── session_resources.rb  # Read-only context resources
│   └── prompts/
│       └── workflow_prompts.rb   # User-initiated workflow prompts
├── mcp.rb                        # Module loader
bin/
└── sxn-mcp                       # Executable for MCP server
```

### MCP Tools

#### Session Tools
| Tool | Description |
|------|-------------|
| `sxn_sessions_list` | List sessions with optional status filter |
| `sxn_sessions_create` | Create session with auto-detection, optional template |
| `sxn_sessions_get` | Get detailed session info |
| `sxn_sessions_delete` | Delete session (with force option) |
| `sxn_sessions_archive` | Archive a session |
| `sxn_sessions_activate` | Activate an archived session |
| `sxn_sessions_swap` | Switch session + return navigation info (hybrid cd approach) |

#### Worktree Tools
| Tool | Description |
|------|-------------|
| `sxn_worktrees_list` | List worktrees in session |
| `sxn_worktrees_add` | Add worktree with auto rule application |
| `sxn_worktrees_remove` | Remove worktree from session |

#### Project Tools
| Tool | Description |
|------|-------------|
| `sxn_projects_list` | List registered projects |
| `sxn_projects_add` | Register new project (auto-detect type) |
| `sxn_projects_get` | Get project details |

#### Template Tools
| Tool | Description |
|------|-------------|
| `sxn_templates_list` | List available templates |
| `sxn_templates_apply` | Apply template to session |

#### Rules Tools
| Tool | Description |
|------|-------------|
| `sxn_rules_list` | List rules for project |
| `sxn_rules_apply` | Apply rules to worktree |

### MCP Resources (Read-only Context)

| URI | Description |
|-----|-------------|
| `sxn://session/current` | Current session info + worktrees |
| `sxn://sessions` | All sessions summary |
| `sxn://projects` | Registered projects |

### MCP Prompts (User-initiated Workflows)

| Prompt | Description |
|--------|-------------|
| `new-session` | Guided session creation workflow |
| `multi-repo-setup` | Set up multi-repo development environment |

### Session Swap: Hybrid Directory Approach

The `sxn_sessions_swap` tool implements the hybrid approach:

```ruby
# Returns structured response with navigation strategy
{
  session: { name: "feature-xyz", path: "/path/to/session" },
  worktrees: [{ project: "api", path: "/path/to/session/api" }],
  navigation: {
    strategy: "bash_cd" | "new_instance",
    bash_command: "cd /path/to/session",  # If within allowed dirs
    shell_command: "claude --cwd /path/to/session",  # If new instance needed
    reason: "Session is child of current directory" | "Session outside working directory"
  }
}
```

Claude Code will:
1. Try `cd` via Bash tool if session is within allowed directories
2. If outside, suggest user run `claude --cwd <path>` for new instance

### Server Implementation

```ruby
# lib/sxn/mcp/server.rb
module Sxn
  module MCP
    class Server
      def initialize(workspace_path: nil)
        @workspace_path = workspace_path || ENV['SXN_WORKSPACE'] || discover_workspace
        @config_manager = Sxn::Core::ConfigManager.new(@workspace_path)
        @server = build_mcp_server
      end

      def run_stdio
        transport = ::MCP::Server::Transports::StdioTransport.new(@server)
        transport.open
      end

      private

      def build_mcp_server
        ::MCP::Server.new(
          name: "sxn",
          version: Sxn::VERSION,
          tools: registered_tools,
          resources: registered_resources,
          prompts: registered_prompts,
          server_context: build_context
        )
      end

      def build_context
        {
          config_manager: @config_manager,
          session_manager: Sxn::Core::SessionManager.new(@config_manager),
          project_manager: Sxn::Core::ProjectManager.new(@config_manager),
          worktree_manager: Sxn::Core::WorktreeManager.new(@config_manager),
          template_manager: Sxn::Core::TemplateManager.new(@config_manager),
          rules_manager: Sxn::Core::RulesManager.new(@config_manager),
          workspace_path: @workspace_path
        }
      end
    end
  end
end
```

### Error Mapping

Map sxn errors to MCP protocol errors:

```ruby
# lib/sxn/mcp/tools/base_tool.rb
module Sxn::MCP::Tools
  module ErrorMapping
    SXN_TO_MCP = {
      Sxn::SessionNotFoundError => ::MCP::Tool::ExecutionError,
      Sxn::ProjectNotFoundError => ::MCP::Tool::ExecutionError,
      Sxn::MCPValidationError => ::MCP::InvalidArgumentError,
      Sxn::ValidationError => ::MCP::InvalidArgumentError
    }

    def self.wrap
      yield
    rescue Sxn::Error => e
      mcp_error = SXN_TO_MCP[e.class] || ::MCP::Tool::ExecutionError
      raise mcp_error, e.message
    end
  end
end
```

### Installation & Configuration

**CLI Installation:**
```bash
claude mcp add --transport stdio sxn -- sxn-mcp
```

**Project `.mcp.json`:**
```json
{
  "mcpServers": {
    "sxn": {
      "command": "sxn-mcp",
      "args": [],
      "env": {
        "SXN_WORKSPACE": "${PWD}"
      }
    }
  }
}
```

---

## Phase 2: Claude Code Plugin

### Plugin Structure

```
sxn-claude-plugin/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── commands/
│   ├── start.md                 # /sxn:start - create session
│   ├── use.md                   # /sxn:use - switch session
│   ├── status.md                # /sxn:status - current session info
│   └── worktree.md              # /sxn:worktree - add worktree
├── agents/
│   └── session-setup.md         # Subagent for guided setup
├── skills/
│   └── session-management.md    # Auto-activate for session tasks
├── hooks/
│   └── hooks.json               # Auto-detect sxn workspaces
└── .mcp.json                    # MCP server config
```

### Plugin Manifest

```json
{
  "name": "sxn",
  "version": "0.1.0",
  "description": "Session management for multi-repository development",
  "author": "Ernest",
  "repository": "https://github.com/ernest/sxn"
}
```

### Slash Commands

**`/sxn:start` (commands/start.md):**
```markdown
Create a new sxn development session.

Arguments: $ARGUMENTS

Use the sxn MCP server to:
1. If no name provided, suggest a name based on context
2. Create session with sxn_sessions_create
3. Optionally apply template if specified
4. Add worktrees for requested projects
5. Navigate to session directory
```

**`/sxn:use` (commands/use.md):**
```markdown
Switch to an existing sxn session.

Arguments: $ARGUMENTS

1. Call sxn_sessions_swap with the session name
2. Follow navigation strategy (bash cd or suggest new instance)
3. Show session status after switch
```

### Hooks

**`hooks/hooks.json`:**
```json
{
  "hooks": [
    {
      "event": "on_session_start",
      "command": "sxn-detect-workspace",
      "description": "Auto-detect sxn workspace on session start"
    }
  ]
}
```

### Distribution

Plugin can be installed via:
```bash
claude plugin install /path/to/sxn-claude-plugin
# or from npm/registry once published
claude plugin install sxn
```

---

## Implementation Order

### Step 1: MCP Server Core
1. Add `mcp` gem dependency to gemspec
2. Create `lib/sxn/mcp.rb` module loader
3. Implement `lib/sxn/mcp/server.rb`
4. Create `bin/sxn-mcp` executable
5. Implement `lib/sxn/mcp/tools/base_tool.rb` with error mapping

### Step 2: Session Tools
1. `sxn_sessions_list`
2. `sxn_sessions_create`
3. `sxn_sessions_get`
4. `sxn_sessions_delete`
5. `sxn_sessions_archive`
6. `sxn_sessions_activate`
7. `sxn_sessions_swap` (with hybrid cd approach)

### Step 3: Worktree & Project Tools
1. `sxn_worktrees_list`
2. `sxn_worktrees_add`
3. `sxn_worktrees_remove`
4. `sxn_projects_list`
5. `sxn_projects_add`
6. `sxn_projects_get`

### Step 4: Template & Rules Tools
1. `sxn_templates_list`
2. `sxn_templates_apply`
3. `sxn_rules_list`
4. `sxn_rules_apply`

### Step 5: Resources & Prompts
1. `sxn://session/current` resource
2. `sxn://sessions` resource
3. `sxn://projects` resource
4. `new-session` prompt
5. `multi-repo-setup` prompt

### Step 6: Tests
1. Unit tests for each tool
2. Integration tests with mock MCP client
3. Use existing test patterns from `spec/unit/`

### Step 7: Claude Code Plugin
1. Create plugin directory structure
2. Write slash command definitions
3. Implement hooks
4. Create session-management skill
5. Test plugin installation

---

## Critical Files to Modify

| File | Changes |
|------|---------|
| `sxn.gemspec` | Add `mcp` gem dependency |
| `lib/sxn.rb` | Add `require_relative "sxn/mcp"` |
| `lib/sxn/errors.rb` | Already has MCPError classes (use them) |
| `lib/sxn/core/session_manager.rb` | Reference for session operations |
| `lib/sxn/core/worktree_manager.rb` | Reference for worktree operations |
| `lib/sxn/core/project_manager.rb` | Reference for project operations |
| `lib/sxn/core/template_manager.rb` | Reference for template operations |
| `lib/sxn/core/rules_manager.rb` | Reference for rules operations |

## New Files to Create

| File | Purpose |
|------|---------|
| `lib/sxn/mcp.rb` | Module loader |
| `lib/sxn/mcp/server.rb` | Main MCP server |
| `lib/sxn/mcp/tools/*.rb` | Tool implementations |
| `lib/sxn/mcp/resources/*.rb` | Resource implementations |
| `lib/sxn/mcp/prompts/*.rb` | Prompt implementations |
| `bin/sxn-mcp` | Executable |
| `spec/unit/mcp/**/*_spec.rb` | Tests |

---

## Usage Examples

### From Claude Code (after MCP server installed)

```
User: Create a new session for the user-auth feature

Claude: I'll create a new session for you.
[calls sxn_sessions_create with name: "user-auth"]

Session "user-auth" created at /path/to/sxn-sessions/user-auth

Would you like me to add worktrees for specific projects?
```

```
User: Switch to my api-refactor session

Claude: I'll switch to that session.
[calls sxn_sessions_swap with name: "api-refactor"]

Switched to session "api-refactor".
[calls cd /path/to/sxn-sessions/api-refactor via Bash]

Now working in the api-refactor session. This session has worktrees for:
- api-service (branch: api-refactor)
- shared-libs (branch: api-refactor)
```

### With Plugin Slash Commands

```
/sxn:start user-auth --template backend-services
/sxn:use api-refactor
/sxn:status
/sxn:worktree add frontend-app
```
