<#
.SYNOPSIS
High-Performance Change Tracker v2.0
.DESCRIPTION
Optimized: Removed git commands, reduced operations
.NOTES
Entry point: PostToolUse
Optimized version: v2.0
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR
$scriptStartTime = Get-Date

# Ensure log directory exists
$logDir = Join-Path $projectDir ".factory", "logs", "changes"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Read standard input
$inputData = Get-Content -Raw | ConvertFrom-Json

# Get tool type
$toolName = ""
$filePath = ""

if ($inputData.PSObject.Properties['tool_name']) {
    $toolName = $inputData.tool_name
}

if ($inputData.PSObject.Properties['tool_input']) {
    if ($inputData.tool_input.PSObject.Properties['file_path']) {
        $filePath = $inputData.tool_input.file_path
    }
}

# Current timestamp
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Generate change entry (no git commands)
$changeEntry = @{
    timestamp = $timestamp
    tool = $toolName
    file = $filePath
    change_type = "UNKNOWN"
}

# Extract more info for edit operations
if ($toolName -eq "Edit" -or $toolName -eq "Write" -or $toolName -eq "Read") {
    if ($filePath) {
        # Convert to relative path
        $relativePath = $filePath.Replace($projectDir, "").TrimStart("\")
        $changeEntry.file = $relativePath
        $changeEntry.file_type = [System.IO.Path]::GetExtension($filePath)
        $changeEntry.change_type = switch ($toolName) {
            "Write" { "CREATE" }
            "Edit" { "MODIFY" }
            "Read" { "READ" }
            default { "UNKNOWN" }
        }
    }
}

# If executing command
if ($toolName -eq "Bash" -or $toolName -eq "Execute") {
    if ($inputData.tool_input.PSObject.Properties['command']) {
        $changeEntry.command = $inputData.tool_input.command
        $changeEntry.change_type = "EXECUTE"
    }
}

# Convert to JSON and log
$logEntry = $changeEntry | ConvertTo-Json -Compress

# Session log file (one per day)
$logFile = Join-Path $logDir "session_$(Get-Date -Format 'yyyy-MM-dd').jsonl"
Add-Content -Path $logFile -Value $logEntry

# Categorize changes
$categoryLog = Join-Path $logDir "by_category.json"
$categories = @{}

if (Test-Path $categoryLog) {
    try {
        $categories = Get-Content $categoryLog | ConvertFrom-Json -AsHashtable
    }
    catch {
        $categories = @{}
    }
}

$changeType = $changeEntry.change_type
if (-not $categories.ContainsKey($changeType)) {
    $categories[$changeType] = @{
        count = 0
        files = @()
    }
}

$categories[$changeType].count += 1
if ($changeEntry.file -and $changeEntry.file -notin $categories[$changeType].files) {
    $categories[$changeType].files += $changeEntry.file
}

$categories | ConvertTo-Json -Depth 10 | Out-File -FilePath $categoryLog -Encoding UTF8

# Real-time summary display
switch ($toolName) {
    { $_ -in @("Edit", "Write", "Create") } {
        Write-Host "?? Change recorded ($($changeEntry.change_type)) $($changeEntry.file)" -ForegroundColor Cyan
    }
    { $_ -in @("Bash", "Execute") } {
        $cmdPreview = if ($changeEntry.command) {
            ($changeEntry.command -split ' ')[0]
        } else { "" }
        Write-Host "? Command executed ($cmdPreview)" -ForegroundColor Gray
    }
    default {
        Write-Host "?? Tool used ($toolName)" -ForegroundColor DarkGray
    }
}

exit 0
