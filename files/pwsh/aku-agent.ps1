#!/usr/bin/env pwsh
#
# aku-agent.ps1 - Simple wrapper to spawn and manage independent Claude Code CLI processes
#
# Usage: aku <command> [options]
#
# @author: Dan Tembe
# @created: 2025-02-14
# @last_modified: 2025-02-14

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command = "help",

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Arguments
)

# Config
$Env:AKU_DIR = if ($Env:AKU_DIR) { $Env:AKU_DIR } else { "$HOME\.aku" }
$AgentsFile = "$Env:AKU_DIR\agents.json"
$LogsDir = "$Env:AKU_DIR\logs"
$PromptsDir = "$Env:AKU_DIR\prompts"

# Colors
function Write-Info($msg) { Write-Host "ℹ $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "⚠ $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "✗ $msg" -ForegroundColor Red }

# Initialize
function Init {
    if (-not (Test-Path $Env:AKU_DIR)) { New-Item -ItemType Directory -Path $Env:AKU_DIR -Force | Out-Null }
    if (-not (Test-Path $LogsDir)) { New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null }
    if (-not (Test-Path $PromptsDir)) { New-Item -ItemType Directory -Path $PromptsDir -Force | Out-Null }
    if (-not (Test-Path $AgentsFile)) { '{"agents":[]}' | Out-File -FilePath $AgentsFile -Encoding utf8 }

    # Secure permissions
    $acl = Get-Acl $Env:AKU_DIR
    $acl.SetAccessRuleProtection($true, $false)
    $userAccess = [System.Security.AccessControl.FileSystemAccessRule]::new(
        [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
        "FullControl",
        "Allow"
    )
    $acl.SetAccessRule($userAccess)
    Set-Acl -Path $Env:AKU_DIR -AclObject $acl
}

# Get agents
function Get-Agents {
    return Get-Content $AgentsFile | ConvertFrom-Json
}

# Save agent
function Save-Agent($name, $pid, $log, $prompt, $status) {
    $agents = Get-Agents
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    $newAgent = @{
        name = $name
        pid = $pid
        log = $log
        prompt = $prompt
        status = $status
        started = $timestamp
    }
    $agents.agents += $newAgent
    $agents | ConvertTo-Json -Depth 10 | Out-File -FilePath $AgentsFile -Encoding utf8
}

# Update status
function Update-Status($name, $status) {
    $agents = Get-Agents
    foreach ($agent in $agents.agents) {
        if ($agent.name -eq $name) {
            $agent.status = $status
        }
    }
    $agents | ConvertTo-Json -Depth 10 | Out-File -FilePath $AgentsFile -Encoding utf8
}

# Remove agent
function Remove-Agent($name) {
    $agents = Get-Agents
    $agents.agents = @($agents.agents | Where-Object { $_.name -ne $name })
    $agents | ConvertTo-Json -Depth 10 | Out-File -FilePath $AgentsFile -Encoding utf8
}

# Check if process running
function Test-Running($pid) {
    try { Get-Process -Id $pid -ErrorAction Stop | Out-Null; return $true }
    catch { return $false }
}

# SPAWN command
function Invoke-Spawn {
    param($name, $task)

    if (-not $name) {
        Write-Err "Usage: aku spawn <name> [task]"
        exit 1
    }

    # Validate agent name (alphanumeric, dash, underscore only)
    if ($name -notmatch '^[a-zA-Z0-9_-]+$') {
        Write-Err "Invalid agent name '$name'. Use alphanumeric, dash, or underscore only."
        exit 1
    }

    # Check for claude CLI
    if (-not (Get-Command "claude" -ErrorAction SilentlyContinue)) {
        Write-Err "Error: claude CLI is required but not found in PATH."
        Write-Err "Install from: https://claude.ai/code"
        exit 1
    }

    # Check duplicate
    $agents = Get-Agents
    if ($agents.agents | Where-Object { $_.name -eq $name }) {
        Write-Err "Agent '$name' already exists"
        exit 1
    }

    $logFile = "$LogsDir\$name.log"
    $promptFile = "$PromptsDir\$name.prompt.md"
    $taskText = if ($task) { $task } else { "No task specified. Wait for instructions or define your own purpose based on the context." }

    # Create prompt
    @"
# aku-agent: $name

You are an autonomous agent named '$name'.

$taskText

Available commands:
- Check the current directory to understand the project
- Ask for clarification on what you should work on
- Explore the codebase to find areas needing attention
"@ | Out-File -FilePath $promptFile -Encoding utf8

    Write-Info "Spawning agent: $name"

    # Spawn claude process using cmd redirect
    $cmdLine = "claude -p --dangerously-skip-permissions < `"$promptFile`" > `"$logFile`" 2>&1"

    # Use Start-Process with cmd to handle redirects
    $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processStartInfo.FileName = "cmd.exe"
    $processStartInfo.Arguments = "/c `"$cmdLine`""
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $process = [System.Diagnostics.Process]::Start($processStartInfo)

    Save-Agent -name $name -pid $process.Id -log $logFile -prompt $promptFile -status "running"

    Write-OK "Agent spawned"
    Write-Host ""
    Write-Host "  Name:    $name"
    Write-Host "  PID:     $($process.Id)"
    Write-Host "  Log:     $logFile"
    Write-Host "  Prompt:  $promptFile"
    Write-Host ""
    Write-Host "  Monitor: aku attach $name"
    Write-Host "  Stop:    aku stop $name"
}

# LIST command
function Invoke-List {
    Init
    $agents = Get-Agents

    Write-Host ""
    Write-Host "  NAME           PID      STATUS    LOG" -ForegroundColor White
    Write-Host "  ─────────────────────────────────────────────────"

    if ($agents.agents.Count -eq 0) {
        Write-Host "  (no agents)"
    } else {
        foreach ($agent in $agents.agents) {
            $status = $agent.status
            if (Test-Running $agent.pid) {
                $status = "running"
                Write-Host "  $($agent.name.PadRight(14)) $($agent.pid.ToString().PadRight(8)) " -NoNewline
                Write-Host "$status" -ForegroundColor Green -NoNewline
                Write-Host "    $LogsDir\$($agent.name).log"
            } else {
                $status = "stopped"
                if ($agent.status -eq "running") { Update-Status $agent.name "stopped" }
                Write-Host "  $($agent.name.PadRight(14)) $($agent.pid.ToString().PadRight(8)) " -NoNewline
                Write-Host "$status" -ForegroundColor Red -NoNewline
                Write-Host "    $LogsDir\$($agent.name).log"
            }
        }
    }
    Write-Host ""
}

# ATTACH command
function Invoke-Attach {
    param($name)

    if (-not $name) {
        Write-Err "Usage: aku attach <name>"
        exit 1
    }

    $agents = Get-Agents
    $agent = $agents.agents | Where-Object { $_.name -eq $name -or $_.name.Contains($name) } | Select-Object -First 1

    if (-not $agent) {
        Write-Err "Agent not found: $name"
        exit 1
    }

    if (-not (Test-Running $agent.pid)) {
        Write-Warn "Agent is not running. Showing last log output:"
        Get-Content $agent.log
        exit 0
    }

    Write-Info "Attached to $($agent.name) (Ctrl+C to detach)"
    Get-Content $agent.log -Wait
}

# STOP command
function Invoke-Stop {
    param($name)

    if (-not $name) {
        Write-Err "Usage: aku stop <name>"
        Write-Host "  Use 'aku stop --all' to stop all agents"
        exit 1
    }

    if ($name -eq "--all") {
        Write-Info "Stopping all agents..."
        $agents = Get-Agents
        foreach ($agent in $agents.agents) {
            if (Test-Running $agent.pid) {
                try {
                    Stop-Process -Id $agent.pid -Force
                    Update-Status $agent.name "stopped"
                    Write-OK "Stopped $($agent.name)"
                } catch {
                    Write-Warn "Could not stop $($agent.name)"
                }
            }
        }
        return
    }

    $agents = Get-Agents
    $agent = $agents.agents | Where-Object { $_.name -eq $name -or $_.name.Contains($name) } | Select-Object -First 1

    if (-not $agent) {
        Write-Err "Agent not found: $name"
        exit 1
    }

    if (-not (Test-Running $agent.pid)) {
        Write-Warn "Agent already stopped"
        Update-Status $agent.name "stopped"
        exit 0
    }

    try {
        Stop-Process -Id $agent.pid -Force
        Update-Status $agent.name "stopped"
        Write-OK "Stopped $($agent.name)"
    } catch {
        Write-Err "Failed to stop $($agent.name)"
    }
}

# CLEAN command
function Invoke-Clean {
    Write-Info "Cleaning up stopped agents..."
    $agents = Get-Agents
    $count = 0

    $toRemove = @()
    foreach ($agent in $agents.agents) {
        if ($agent.status -eq "stopped" -or -not (Test-Running $agent.pid)) {
            $toRemove += $agent.name
            Remove-Item "$PromptsDir\$($agent.name).prompt.md" -ErrorAction SilentlyContinue
            $count++
        }
    }

    foreach ($name in $toRemove) {
        Remove-Agent $name
    }

    Write-OK "Removed $count stopped agent(s)"
}

# LOGS command
function Invoke-Logs {
    param($name)

    if (-not $name) {
        Write-Err "Usage: aku logs <name>"
        exit 1
    }

    $agents = Get-Agents
    $agent = $agents.agents | Where-Object { $_.name -eq $name -or $_.name.Contains($name) } | Select-Object -First 1

    if (-not $agent) {
        Write-Err "Agent not found: $name"
        exit 1
    }

    $pager = if ($Env:PAGER) { $Env:PAGER } else { "less" }
    & $pager $agent.log
}

# Help
function Show-Help {
    @'
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

'@
}

# Main
Init

switch ($Command) {
    { $_ -in "spawn", "run", "new" } { Invoke-Spawn $Arguments[0] ($Arguments | Select-Object -Skip 1) -join " " }
    { $_ -in "list", "ls", "ps" } { Invoke-List }
    { $_ -in "attach", "watch" } { Invoke-Attach $Arguments[0] }
    { $_ -in "stop", "kill" } { Invoke-Stop $Arguments[0] }
    { $_ -in "clean", "cleanup" } { Invoke-Clean }
    { $_ -in "logs", "log" } { Invoke-Logs $Arguments[0] }
    { $_ -in "help", "--help", "-h" } { Show-Help }
    default { Write-Err "Unknown command: $Command"; Show-Help; exit 1 }
}
