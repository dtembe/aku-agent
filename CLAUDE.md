# CLAUDE.md

This file provides guidance to Claude Code when working with the aku-agent project.

## Project Overview

aku-agent is a **simple wrapper** to spawn and manage independent Claude Code CLI processes. It's intentionally minimal - just spawn, track, and manage.

## Key Concept

Unlike aku-loop (which runs subagents within one Claude session), aku-agent spawns completely separate `claude` CLI processes. Each agent is its own OS process.

## Project Structure

```
aku-agent/
├── README.md
├── CLAUDE.md
├── files/
│   ├── bash/
│   │   └── aku-agent.sh      # Linux/Mac
│   └── pwsh/
│       └── aku-agent.ps1     # Windows
└── ~/.aku/                   # Runtime (auto-created)
    ├── agents.json           # Simple registry {name, pid, log, status}
    └── logs/                 # Agent output
```

## Commands

```bash
aku spawn <name> [task]   # Spawn new agent
aku list                  # List running agents
aku attach <name>         # Attach to output
aku stop <name>           # Stop agent
aku clean                 # Remove stopped agents
```

## Implementation Notes

### Spawning (bash)
```bash
claude -p --dangerously-skip-permissions < prompt.md > log.txt &
```

### Spawning (pwsh)
```powershell
Start-Process -FilePath "claude" -ArgumentList "-p", "--dangerously-skip-permissions" ...
```

### State File Format
```json
{
  "agents": [
    {
      "name": "frontend",
      "pid": 12345,
      "log": "/home/user/.aku/logs/frontend.log",
      "prompt": "/home/user/.aku/frontend.prompt.md",
      "status": "running",
      "started": "2025-02-14T21:00:00Z"
    }
  ]
}
```

## Dependencies

- `jq` for JSON parsing (bash version)
- `claude` CLI must be in PATH

## Safety

Uses `--dangerously-skip-permissions` - run in isolated dev environments only.

## Keep It Simple

This project is intentionally minimal. Don't add:
- Task queues
- Complex orchestration
- Inter-agent communication
- Distributed features

If you need those, use aku-loop instead.
