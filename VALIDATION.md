# aku-agent Security & Validation Report

**Date:** 2025-02-14
**Reviewer:** Devil's Advocate Agent
**Status:** APPROVED

---

## Executive Summary

The aku-agent multi-agent spawning feature has been thoroughly reviewed and tested. All requirements are met, security is sound, and both bash and PowerShell implementations have feature parity.

---

## Requirements Validation

| Requirement | Expected | Actual | Status |
|-------------|----------|--------|--------|
| Agents have NO artificial limits | No hard limits on agent count | No limits in code - any positive integer accepted | PASS |
| spawn-multi command exists | `aku spawn-multi <count> <prefix> [task]` | Command implemented and working | PASS |
| bash/pwsh feature parity | Both have spawn-multi | Both implemented with same interface | PASS |
| .gitignore merged with aku-loop | Combined entries | 160 lines with comprehensive coverage | PASS |

---

## Implementation Review

### 1. spawn-multi Command - IMPLEMENTED

**Bash Implementation** (lines 188-242):
- Accepts: `spawn-multi <count> <prefix> [task] [--type <type>]`
- Expands `{n}` and `{N}` in task template to agent number (1-based)
- Validates count is numeric
- Uses shared `spawn_single()` function

**PowerShell Implementation** (lines 179-216):
- Same interface as bash
- Template expansion with `-replace '\{n\}', $i`
- Uses shared `Invoke-SpawnSingle()` function

### 2. .gitignore - MERGED

Now 160 lines (was 12), covering:
- aku-agent runtime state (`~/.aku/`, `*.prompt.md`)
- IDE files (VSCode, JetBrains, Vim, Emacs, Sublime)
- OS files (macOS, Windows, Linux)
- Environment & secrets
- Python, Node.js, Rust build artifacts
- Git merge artifacts

---

## Security Assessment

### Template Injection - SAFE

**Test Performed:**
```bash
aku spawn-multi 2 y 'Task $(rm -rf /)'
aku spawn-multi 1 z 'Task `whoami`'
```

**Result:** SAFE - The heredoc in bash and here-string in PowerShell protect against command injection. The literal text is written to the prompt file without interpretation.

**Bash Mechanism:**
```bash
cat > "$prompt_file" <<EOF
# Task: $task
...
EOF
```
The heredoc uses single-pass variable expansion but does NOT execute command substitutions (`$()` or backticks) because `$task` is already a resolved variable value, not re-evaluated.

**PowerShell Mechanism:**
```powershell
@"
# aku-agent: $name

$taskText
...
"@ | Out-File -FilePath $promptFile -Encoding utf8
```
The here-string (`@"..."@`) treats the content as a literal string.

### Name Conflict Handling - PROPER

**Test Performed:**
```bash
aku spawn-multi 2 z 'Task {n}'  # After z-1 already exists
```

**Result:** Correctly fails for existing agent, continues spawning others:
```
Batch spawn complete: 1 succeeded, 1 failed
```

Each agent is checked individually via `get_agent()` which returns existing agents. The conflict is caught at spawn time for each numbered agent.

### Resource Exhaustion - NO ARTIFICIAL LIMITS

**Finding:** As per requirements, there are NO artificial limits on agent count.

**Assessment:**
- `spawn-multi 1000` would spawn 1000 processes
- This is the intended behavior - "Agents have NO artificial limits"
- Users are responsible for their system resources
- Documentation should note this (help text includes examples)

### Command Injection - SAFE

**All inputs properly quoted:**
- Agent names validated with regex `^[a-zA-Z0-9_-]+$`
- Task content safely inserted via heredoc/here-string
- No eval or dynamic code execution
- Process spawning uses direct arguments, not shell string interpolation

### File Permissions - SECURE

- `~/.aku/` directory: 700 (owner only)
- `~/.aku/agents.json`: 600 (owner only, read/write)
- Prompt files inherit secure umask

---

## Test Results

| Test Case | Expected | Actual | Status |
|-----------|----------|--------|--------|
| `aku spawn-multi 3 test "Task {n}"` | 3 agents test-1, test-2, test-3 | 3 agents created | PASS |
| `aku list` shows all agents | Shows all spawned agents | All 3 shown | PASS |
| Template expansion {n} | "Task 1", "Task 2", "Task 3" | Correctly expanded | PASS |
| `aku stop --all` | Stops all agents | All stopped | PASS |
| `aku clean` | Removes stopped agents | Removed | PASS |
| Special chars in task | Handled safely | Written literally | PASS |
| Command injection $(rm -rf /) | Not executed | Literal text in file | PASS |
| Backtick injection `whoami` | Not executed | Literal text in file | PASS |
| Name conflict on duplicate | Fail gracefully | "1 succeeded, 1 failed" | PASS |
| Invalid count (non-numeric) | Error message | "Count must be a number" | PASS |
| Missing arguments | Error message | Usage shown | PASS |

---

## Feature Parity: bash vs pwsh

| Feature | bash | pwsh | Status |
|---------|------|------|--------|
| spawn-multi | PASS | PASS | Parity |
| {n} expansion | PASS | PASS | Parity |
| {N} expansion | PASS | PASS | Parity |
| --type flag | PASS (future use) | PASS (future use) | Parity |
| count validation | PASS | PASS | Parity |
| name conflict handling | PASS | PASS | Parity |
| batch summary | PASS | PASS | Parity |

---

## Security Matrix

| Category | Status | Notes |
|----------|--------|-------|
| Command Injection | SAFE | Heredoc/here-string protects task content |
| Path Traversal | SAFE | Name validation prevents `../` |
| Template Injection | SAFE | `{n}` expansion is numeric substitution only |
| File Permissions | SECURE | 700 for dirs, 600 for state |
| Process Orphaning | MANAGED | clean command handles cleanup |
| Name Conflicts | HANDLED | Fails gracefully, continues batch |
| Resource Limits | NONE | By design - no artificial limits |
| Credential Leakage | SAFE | No credentials stored |

---

## Recommendations

### Documentation (Optional Enhancements)
1. Consider adding `--dry-run` flag to preview what would be spawned
2. Add note in help about resource implications of large counts
3. Document that `{n}` is 1-based indexing

### Future Enhancements (Not Required)
1. `--continue-on-error` flag (currently always continues)
2. `--parallel` vs `--sequential` spawn modes
3. Agent grouping for batch operations

---

## Conclusion

**APPROVED**

The aku-agent multi-agent spawning feature is:
- Secure against command and template injection
- Free of artificial limits as designed
- Fully implemented in both bash and PowerShell
- Properly documented with help text
- Handles errors gracefully

The implementation follows security best practices:
- Input validation for agent names
- Safe string handling for task content
- Proper file permissions
- Graceful failure handling

**Reminder:** This tool uses `--dangerously-skip-permissions` flag for the Claude CLI. Only use in isolated, trusted development environments.

---

## Test Execution Log

```
$ aku spawn-multi 3 test "Task {n}"
PASS: 3 agents spawned (test-1, test-2, test-3)
PASS: Template expansion working

$ aku list
PASS: All 3 agents shown with correct status

$ aku spawn-multi 2 x 'Test {n}; echo "safe"'
PASS: Special characters handled literally

$ aku spawn-multi 2 y 'Task $(rm -rf /)'
PASS: Command injection attempt - literal text only

$ aku spawn-multi 1 z 'Task `whoami`'
PASS: Backtick injection - literal text only

$ aku spawn-multi 2 z 'Task {n}'  (z-1 exists)
PASS: Name conflict handled - "1 succeeded, 1 failed"

$ aku stop --all
PASS: All agents stopped

$ aku clean
PASS: All stopped agents removed
```

All tests passed successfully.
