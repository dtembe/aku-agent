# aku-agent

<img src="artifacts/aku-bw-icon.png" alt="aku-agent" width="64">

**Multi-Process Claude Code Runner**

A simple wrapper to spawn and manage multiple independent Claude Code CLI processes. No complex orchestration—just spawn, track, and manage.

## What It Does

```bash
# Spawn independent Claude Code processes
aku spawn frontend "Build the React dashboard"
aku spawn backend "Build the FastAPI endpoints"
aku spawn tester "Write integration tests"

# See what's running
aku list

# Attach to see output
aku attach frontend

# Stop when done
aku stop frontend
```

Each agent runs as a completely separate OS process with its own isolated context.

**No Limits:** Agents have full autonomy to execute commands, modify files, install packages, and manage your development environment.

## Installation

```bash
# Linux/Mac
cp files/bash/aku-agent.sh /usr/local/bin/aku
chmod +x /usr/local/bin/aku

# Or add to PATH
export PATH="$HOME/aku-agent/files/bash:$PATH"
```

## Commands

| Command | Description |
|---------|-------------|
| `aku spawn <name> [task]` | Spawn new agent with optional task |
| `aku spawn-multi <count> <prefix> [task]` | Spawn multiple numbered agents |
| `aku list` | List all agents (running and stopped) |
| `aku attach <name>` | Attach to agent's live output |
| `aku stop <name>` | Stop a running agent |
| `aku stop --all` | Stop all agents |
| `aku clean` | Remove stopped agents from registry |
| `aku logs <name>` | View full log file |

## Agent Types

When spawning agents, you can specify the type via the `--type` flag:

| Type | Description |
|------|-------------|
| `default` | Standard Claude Code agent with full capabilities |
| `software-developer` | Specialized for coding tasks with enhanced development tools |

```bash
# Spawn with explicit type
aku spawn agent1 --type software-developer "Build the API"

# Multi-spawn with type
aku spawn-multi 3 worker --type software-developer "Process module {n}"
```

## Examples

### Single Agent Spawning

```bash
# Spawn multiple agents for parallel work
aku spawn frontend "Implement the login page UI"
aku spawn backend "Create the authentication API"
aku spawn docs "Update API documentation"

# Monitor their progress
aku list
aku attach frontend

# Stop one agent
aku stop frontend

# Clean up when done
aku clean
```

### Multi-Agent Spawning

```bash
# Spawn 5 numbered workers with a common task template
aku spawn-multi 5 worker "Process module {n}"
# Creates: worker-1, worker-2, worker-3, worker-4, worker-5
# Tasks: "Process module 1", "Process module 2", etc.

# Spawn developers for parallel feature work
aku spawn-multi 3 dev "Build feature {n} from the spec"
# Creates: dev-1, dev-2, dev-3

# Multi-spawn with agent type
aku spawn-multi 3 reviewer --type software-developer "Review module {n}"
```

### Agent Type Selection

```bash
# Default agent (general purpose)
aku spawn helper --type default "Analyze the codebase structure"

# Software developer (coding focused)
aku spawn builder --type software-developer "Implement the user authentication"
```

## aku-agent vs aku-loop

| Feature | aku-agent | aku-loop |
|---------|-----------|----------|
| Architecture | Spawns separate CLI processes | Runs subagents within one session |
| Context | Each process is isolated | Subagents share context |
| Best for | Independent parallel tasks | Coordinated team work |
| Persistence | Agents survive terminal close | Session-bound |
| Agent types | default, software-developer | Team-based roles |

## Directory Structure

```
aku-agent/
├── artifacts/
│   └── aku-bw-icon.png        # Logo
├── files/
│   ├── bash/
│   │   ├── aku-agent.sh       # Linux/Mac script
│   │   └── AGENTS.md          # Agent template
│   └── pwsh/
│       ├── aku-agent.ps1      # Windows script
│       └── AGENTS.md          # Agent template
├── CLAUDE.md                  # Developer guide
└── README.md                  # This file

~/.aku/                        # Runtime (auto-created)
├── agents.json                # Agent registry
├── logs/                      # Agent output
└── *.prompt.md                # Agent prompts
```

## How It Works

Each `aku spawn` creates a new background process:

```bash
claude -p --dangerously-skip-permissions < prompt.md > log.txt &
```

We track the PID and manage the process through a simple JSON registry. That's it.

Multi-spawning simply loops this process, creating numbered agent names and substituting `{n}` in task templates.

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `AKU_DIR` | `~/.aku` | Base directory for state and logs |

## Requirements

- `claude` CLI in PATH
- `jq` for JSON parsing (bash version only)

## Safety

**Uses `--dangerously-skip-permissions`** – run in isolated development environments only. Each agent has full autonomy to execute commands and modify files.

## License

MIT
