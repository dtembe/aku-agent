#!/usr/bin/env bash
#
# aku-agent.sh - Simple wrapper to spawn and manage independent Claude Code CLI processes
#
# Usage: aku <command> [options]
#
# Commands:
#   spawn <name> [task]   - Spawn new agent
#   list                  - List running agents
#   attach <name>         - Attach to agent output
#   stop <name>           - Stop agent
#   clean                 - Remove stopped agents
#   logs <name>           - View log file
#
# @author: Dan Tembe
# @created: 2025-02-14
# @last_modified: 2025-02-14

set -euo pipefail

# Check for jq dependency
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install with: apt install jq / brew install jq" >&2
    exit 1
fi

# Check for claude CLI dependency
if ! command -v claude &> /dev/null; then
    echo "Error: claude CLI is required but not found in PATH." >&2
    echo "Install from: https://claude.ai/code" >&2
    exit 1
fi

# Config
AKU_DIR="${AKU_DIR:-$HOME/.aku}"
AKU_AGENTS_FILE="$AKU_DIR/agents.json"
AKU_LOGS_DIR="$AKU_DIR/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Output helpers
info()  { echo -e "${CYAN}ℹ${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }

# Initialize
init() {
    mkdir -p "$AKU_DIR" "$AKU_LOGS_DIR"
    chmod 700 "$AKU_DIR" "$AKU_LOGS_DIR"
    [[ -f "$AKU_AGENTS_FILE" ]] || echo '{"agents":[]}' > "$AKU_AGENTS_FILE"
    chmod 600 "$AKU_AGENTS_FILE"
}

# Get agent by name (exact match only, returns null if not found)
get_agent() {
    local name="$1"
    local match=$(jq -r --arg n "$name" '.agents[] | select(.name == $n)' "$AKU_AGENTS_FILE" 2>/dev/null)
    if [[ -n "$match" ]]; then
        echo "$match"
    fi
}

# List all agents (compact JSON for line-by-line parsing)
list_agents() {
    cat "$AKU_AGENTS_FILE" | jq -c '.agents[]'
}

# Save agent to registry
save_agent() {
    local name="$1" pid="$2" log="$3" prompt="$4" status="$5"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local agent=$(cat <<EOF
{"name":"$name","pid":$pid,"log":"$log","prompt":"$prompt","status":"$status","started":"$timestamp"}
EOF
)

    local tmp=$(mktemp)
    jq ".agents += [$agent]" "$AKU_AGENTS_FILE" > "$tmp" && mv "$tmp" "$AKU_AGENTS_FILE"
}

# Update agent status
update_status() {
    local name="$1" status="$2"
    local tmp=$(mktemp)
    jq --arg n "$name" --arg s "$status" '.agents |= map(if .name == $n then .status = $s else . end)' "$AKU_AGENTS_FILE" > "$tmp" && mv "$tmp" "$AKU_AGENTS_FILE"
}

# Remove agent from registry
remove_agent() {
    local name="$1"
    local tmp=$(mktemp)
    jq --arg n "$name" '.agents = [.agents[] | select(.name != $n)]' "$AKU_AGENTS_FILE" > "$tmp" && mv "$tmp" "$AKU_AGENTS_FILE"
}

# Check if process is running
is_running() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

# SPAWN command
cmd_spawn() {
    local name="${1:-}"
    local task="${2:-No task specified}"

    if [[ -z "$name" ]]; then
        err "Usage: aku spawn <name> [task]"
        exit 1
    fi

    # Validate agent name (alphanumeric, dash, underscore only)
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        err "Invalid agent name '$name'. Use alphanumeric, dash, or underscore only."
        exit 1
    fi

    # Check for duplicate name
    if [[ -n $(get_agent "$name") ]]; then
        err "Agent '$name' already exists"
        exit 1
    fi

    local log_file="$AKU_LOGS_DIR/${name}.log"
    local prompt_file="$AKU_DIR/${name}.prompt.md"

    # Create prompt
    cat > "$prompt_file" <<EOF
# Task: $task

You are an independent Claude Code agent named '$name'.
Work directory: $(pwd)

Complete the task above. When done, summarize what you accomplished.
EOF

    info "Spawning agent: ${BOLD}$name${NC}"

    # Spawn claude process in background
    claude -p --dangerously-skip-permissions < "$prompt_file" > "$log_file" 2>&1 &
    local pid=$!

    # Save to registry
    save_agent "$name" "$pid" "$log_file" "$prompt_file" "running"

    ok "Agent spawned"
    echo ""
    echo "  Name:    $name"
    echo "  PID:     $pid"
    echo "  Log:     $log_file"
    echo "  Prompt:  $prompt_file"
    echo ""
    echo "  Monitor: aku attach $name"
    echo "  Stop:    aku stop $name"
}

# LIST command
cmd_list() {
    init

    echo ""
    echo -e "${BOLD}  NAME           PID      STATUS    LOG${NC}"
    echo "  ─────────────────────────────────────────────────"

    local found=0
    while IFS= read -r agent; do
        [[ -z "$agent" ]] && continue
        found=1

        local name=$(echo "$agent" | jq -r '.name')
        local pid=$(echo "$agent" | jq -r '.pid')
        local status=$(echo "$agent" | jq -r '.status')

        # Check if actually running
        if is_running "$pid"; then
            status="${GREEN}running${NC}"
        else
            status="${RED}stopped${NC}"
            [[ $(echo "$agent" | jq -r '.status') == "running" ]] && update_status "$name" "stopped"
        fi

        printf "  %-14s %-8s %-9b %s\n" "$name" "$pid" "$status" "$AKU_LOGS_DIR/${name}.log"
    done < <(list_agents)

    [[ $found -eq 0 ]] && echo "  (no agents)"
    echo ""
}

# ATTACH command
cmd_attach() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        err "Usage: aku attach <name>"
        exit 1
    fi

    local agent=$(get_agent "$name")
    if [[ -z "$agent" ]]; then
        err "Agent not found: $name"
        exit 1
    fi

    local log=$(echo "$agent" | jq -r '.log')
    local pid=$(echo "$agent" | jq -r '.pid')

    if ! is_running "$pid"; then
        warn "Agent is not running. Showing last log output:"
        cat "$log"
        exit 0
    fi

    info "Attached to $name (Ctrl+C to detach)"
    tail -f "$log"
}

# STOP command
cmd_stop() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        err "Usage: aku stop <name>"
        echo "  Use 'aku stop --all' to stop all agents"
        exit 1
    fi

    if [[ "$name" == "--all" ]]; then
        info "Stopping all agents..."
        while IFS= read -r agent; do
            [[ -z "$agent" ]] && continue
            local n=$(echo "$agent" | jq -r '.name')
            local p=$(echo "$agent" | jq -r '.pid')
            if is_running "$p"; then
                kill "$p" 2>/dev/null && ok "Stopped $n" || warn "Could not stop $n"
                update_status "$n" "stopped"
            fi
        done < <(list_agents)
        return
    fi

    local agent=$(get_agent "$name")
    if [[ -z "$agent" ]]; then
        err "Agent not found: $name"
        exit 1
    fi

    local pid=$(echo "$agent" | jq -r '.pid')
    local name=$(echo "$agent" | jq -r '.name')

    if ! is_running "$pid"; then
        warn "Agent already stopped"
        update_status "$name" "stopped"
        exit 0
    fi

    kill "$pid" && ok "Stopped $name" || err "Failed to stop $name"
    update_status "$name" "stopped"
}

# CLEAN command
cmd_clean() {
    info "Cleaning up stopped agents..."

    local count=0
    while IFS= read -r agent; do
        [[ -z "$agent" ]] && continue
        local name=$(echo "$agent" | jq -r '.name')
        local status=$(echo "$agent" | jq -r '.status')
        local prompt=$(echo "$agent" | jq -r '.prompt')

        if [[ "$status" == "stopped" ]] || ! is_running "$(echo "$agent" | jq -r '.pid')"; then
            remove_agent "$name"
            rm -f "$prompt" 2>/dev/null
            ((count++)) || true
        fi
    done < <(list_agents)

    ok "Removed $count stopped agent(s)"
}

# LOGS command
cmd_logs() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        err "Usage: aku logs <name>"
        exit 1
    fi

    local agent=$(get_agent "$name")
    if [[ -z "$agent" ]]; then
        err "Agent not found: $name"
        exit 1
    fi

    local log=$(echo "$agent" | jq -r '.log')
    ${PAGER:-less} "$log"
}

# Help
show_help() {
    cat << 'EOF'
aku-agent - Multi-Process Claude Code Runner

USAGE:
    aku <command> [arguments]

COMMANDS:
    spawn <name> [task]   Spawn a new independent agent
    list                  List all agents (running and stopped)
    attach <name>         Attach to agent's output stream
    stop <name>           Stop a running agent
    stop --all            Stop all agents
    clean                 Remove stopped agents from registry
    logs <name>           View full log file

EXAMPLES:
    aku spawn frontend "Build React dashboard"
    aku spawn backend "Create API endpoints"
    aku list
    aku attach frontend
    aku stop frontend
    aku clean

ENVIRONMENT:
    AKU_DIR    Base directory (default: ~/.aku)

EOF
}

# Main
main() {
    init

    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        spawn|run|new)  cmd_spawn "$@" ;;
        list|ls|ps)     cmd_list ;;
        attach|watch)   cmd_attach "$@" ;;
        stop|kill)      cmd_stop "$@" ;;
        clean|cleanup)  cmd_clean ;;
        logs|log)       cmd_logs "$@" ;;
        help|--help|-h) show_help ;;
        *)              err "Unknown command: $cmd"; show_help; exit 1 ;;
    esac
}

main "$@"
