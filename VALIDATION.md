# aku-agent Security & Validation Report

**Date:** 2025-02-14
**Reviewer:** Devil's Advocate Agent
**Status:** ✅ **APPROVED** - All critical issues fixed

---

## Executive Summary

The aku-agent project has been thoroughly reviewed and tested. Initial critical bugs were identified and immediately fixed. All test cases now pass.

---

## Initial Issues Found & Fixed

### 1. JSON Parsing Bug in `list_agents()` - FIXED ✅

**Severity:** CRITICAL
**Location:** `files/bash/aku-agent.sh` line 72

**Problem:** Used `jq -r` which outputs multi-line formatted JSON, breaking line-by-line parsing.

**Fix Applied:**
```bash
# Before
list_agents() {
    cat "$AKU_AGENTS_FILE" | jq -r '.agents[]'
}

# After
list_agents() {
    cat "$AKU_AGENTS_FILE" | jq -c '.agents[]'
}
```

### 2. Missing File Permissions - FIXED ✅

**Severity:** HIGH
**Location:** `files/bash/aku-agent.sh` init() function

**Problem:** No explicit permissions set on sensitive files.

**Fix Applied:**
```bash
init() {
    mkdir -p "$AKU_DIR" "$AKU_LOGS_DIR"
    chmod 700 "$AKU_DIR" "$AKU_LOGS_DIR"      # Added
    [[ -f "$AKU_AGENTS_FILE" ]] || echo '{"agents":[]}' > "$AKU_AGENTS_FILE"
    chmod 600 "$AKU_AGENTS_FILE"               # Added
}
```

### 3. Missing Input Validation - FIXED ✅

**Severity:** MEDIUM
**Location:** `files/bash/aku-agent.sh` cmd_spawn() function

**Problem:** No validation of agent names.

**Fix Applied:**
```bash
# Validate agent name (alphanumeric, dash, underscore only)
if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    err "Invalid agent name '$name'. Use alphanumeric, dash, or underscore only."
    exit 1
fi
```

### 4. Missing Dependency Check - FIXED ✅

**Severity:** LOW
**Location:** `files/bash/aku-agent.sh`

**Problem:** No check for claude CLI before spawn.

**Fix Applied:**
```bash
# Check for claude CLI dependency
if ! command -v claude &> /dev/null; then
    echo "Error: claude CLI is required but not found in PATH." >&2
    echo "Install from: https://claude.ai/code" >&2
    exit 1
fi
```

### 5. Color Code Display Bug - FIXED ✅

**Severity:** LOW
**Location:** `files/bash/aku-agent.sh` cmd_list() function

**Problem:** `printf` didn't interpret escape sequences in status variable.

**Fix Applied:**
```bash
# Changed format specifier from %s to %b
printf "  %-14s %-8s %-9b %s\n" "$name" "$pid" "$status" "$AKU_LOGS_DIR/${name}.log"
```

---

## Security Review

### ✅ Process Spawning - Safe
- Uses `&` for background execution (bash)
- Uses `Start-Process` (pwsh)
- No command injection vectors found
- All inputs properly quoted

### ✅ File Permissions - Secure
- `~/.aku/` directory: 700 (owner only)
- `~/.aku/agents.json`: 600 (owner only, read/write)
- Prompt files inherit secure umask

### ✅ Input Validation - Good
- Agent names validated: alphanumeric, dash, underscore only
- Rejects: spaces, special characters, path traversal attempts
- Task descriptions safely escaped in heredocs

### ✅ Process Management - Safe
- Uses `kill -0` to check if process exists (no signal sent)
- Clean `--all` stop functionality
- Orphan process cleanup via `clean` command

---

## Test Results

| Test Case | Expected | Actual | Status |
|-----------|----------|--------|--------|
| `aku help` | Show usage | Shows usage | ✅ PASS |
| `aku list` (empty) | "(no agents)" | "(no agents)" | ✅ PASS |
| `aku spawn test "task"` | Create agent | Agent created with proper metadata | ✅ PASS |
| `aku list` (with agent) | Show agent with colors | Shows green "running" / red "stopped" | ✅ PASS |
| `aku stop test` | Stop agent | Stops and updates status | ✅ PASS |
| `aku clean` | Remove stopped | Removes stopped agents only | ✅ PASS |
| Duplicate name | Error | "Agent 'xxx' already exists" | ✅ PASS |
| Missing args | Error | "Usage: aku spawn <name> [task]" | ✅ PASS |
| Agent not found | Error | "Agent not found: xxx" | ✅ PASS |
| Invalid agent name | Error | "Invalid agent name..." | ✅ PASS |
| File permissions | 700/600 | Verified with ls -la | ✅ PASS |

---

## Feature Parity: bash vs pwsh

| Feature | bash | pwsh | Status |
|---------|------|------|--------|
| spawn | ✅ | ✅ | ✅ Parity |
| list | ✅ | ✅ | ✅ Parity |
| attach | ✅ | ✅ | ✅ Parity |
| stop | ✅ | ✅ | ✅ Parity |
| stop --all | ✅ | ✅ | ✅ Parity |
| clean | ✅ | ✅ | ✅ Parity |
| logs | ✅ | ✅ | ✅ Parity |
| name validation | ✅ | ✅ | ✅ Parity |
| dep check (jq) | ✅ | N/A | N/A (native JSON) |
| dep check (claude) | ✅ | ✅ | ✅ Parity |
| file permissions | ✅ | ✅ | ✅ Parity |

---

## Security Assessment Summary

| Category | Status | Notes |
|----------|--------|-------|
| Command Injection | ✅ Safe | All inputs properly quoted |
| Path Traversal | ✅ Safe | Name validation prevents `../` |
| File Permissions | ✅ Secure | 700 for dirs, 600 for state |
| Process Orphaning | ✅ Managed | clean command handles cleanup |
| Credential Leakage | ✅ Safe | No credentials stored |
| Special Characters | ✅ Safe | Input validation in place |

---

## Recommendations for Future Enhancements

1. **Log Rotation**: Consider adding log file size limits
2. **Timeout Option**: Add `--timeout` parameter for spawn
3. **Status Icons**: Consider Unicode symbols for running/stopped
4. **Auto-clean**: Add optional auto-cleanup on exit
5. **Parallel Testing**: Add test suite for concurrent operations

---

## Conclusion

**APPROVED** ✅

All critical bugs have been fixed. The aku-agent is safe for use in isolated development environments. The security posture is good with proper file permissions, input validation, and process management.

**Reminder:** This tool uses `--dangerously-skip-permissions` flag for the Claude CLI. Only use in isolated, trusted development environments.

---

## Test Execution Log

```
$ aku help
✅ Shows usage information

$ aku list
✅ Shows "(no agents)" when empty

$ aku spawn test003 "simple task"
✅ Agent spawned
✅ File permissions verified (700/600)

$ aku list
✅ Shows agent with colored status

$ aku stop test003
✅ Stops agent and updates status

$ aku clean
✅ Removes stopped agents from registry

$ aku list
✅ Returns to "(no agents)" state

$ aku spawn "bad name!" "test"
✅ Error: Invalid agent name

$ aku spawn duplicate "test"
✅ Error: Agent already exists

$ aku stop nonexistent
✅ Error: Agent not found

$ aku spawn
✅ Error: Usage message
```

All tests passed successfully.
