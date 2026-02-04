#!/usr/bin/env pwsh
<#
.SYNOPSIS
变更跟踪器：记录所有文件变更和操作
.DESCRIPTION
跟踪文件操作，生成变更摘要，影响分析
.NOTES
入口点：PostToolUse
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR

# 确保日志目录存在
$logDir = Join-Path $projectDir ".factory", "logs", "changes"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# 读取标准输入
$inputData = Get-Content -Raw | ConvertFrom-Json

# 获取工具类型和详细信息
$toolName = ""
$toolOutput = ""
$filePath = ""

if ($inputData.PSObject.Properties['tool_name']) {
    $toolName = $inputData.tool_name
}

if ($inputData.PSObject.Properties['content']) {
    $toolOutput = $inputData.content
}

if ($inputData.PSObject.Properties['tool_input']) {
    if ($inputData.tool_input.PSObject.Properties['file_path']) {
        $filePath = $inputData.tool_input.file_path
    }
}

# 获取git状态
Push-Location $projectDir
$gitStatus = git status --porcelain 2>&1
$gitDiffShort = git diff --shortstat 2>&1
Pop-Location

# 当前时间戳
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# 生成变更条目
$changeEntry = @{
    timestamp = $timestamp
    tool = $toolName
    file = $filePath
    git_status_lines = ($gitStatus -split "`n" | Measure-Object).Count
    git_shortstat = $gitDiffShort.Trim()
}

# 如果是编辑操作，提取更多信息
if ($toolName -eq "Edit" -or $toolName -eq "Write" -or $toolName -eq "Read") {
    if ($filePath) {
        # 转换为相对路径
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

# 如果是执行命令
if ($toolName -eq "Bash" -or $toolName -eq "Execute") {
    if ($inputData.tool_input.PSObject.Properties['command']) {
        $changeEntry.command = $inputData.tool_input.command
        $changeEntry.change_type = "EXECUTE"
    }
}

# 转换为JSON并记录日志
$logEntry = $changeEntry | ConvertTo-Json -Compress

# 会话日志文件（每天一个）
$logFile = Join-Path $logDir "session_$(Get-Date -Format 'yyyy-MM-dd').jsonl"
Add-Content -Path $logFile -Value $logEntry

# 分类变更
$categoryLog = Join-Path $logDir "by_category.json"
$categories = @{}

if (Test-Path $categoryLog) {
    $categories = Get-Content $categoryLog | ConvertFrom-Json -AsHashtable
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

# 实时摘要显示
switch ($toolName) {
    { $_ -in @("Edit", "Write", "Create") } {
        Write-Host "📝 变更记录：$($changeEntry.change_type) $($changeEntry.file)" -ForegroundColor Cyan
    }
    { $_ -in @("Bash", "Execute") } {
        Write-Host "⚡ 命令执行：$(($changeEntry.command -split ' ')[0])" -ForegroundColor Gray
    }
    default {
        Write-Host "🔧 工具使用：$toolName" -ForegroundColor DarkGray
    }
}

# 每50个变更生成一次摘要
$allChanges = Get-Content $logFile | Measure-Object -Line
if ($allChanges.Lines % 50 -eq 0) {
    $summaryFile = Join-Path $logDir "summary_$(Get-Date -Format 'yyyy-MM-dd').md"
    $summary = @"
# 变更摘要 $(Get-Date -Format 'yyyy-MM-dd')

## 统计信息
- 总变更数：$($allChanges.Lines)
- Git状态变更：$($changeEntry.git_status_lines) 个文件

## 分类统计
$($categories.Keys | ForEach-Object {
    $cat = $categories[$_]
    "- **$($_)**: $($cat.count) 次"
    } -join "`n")

## 最近变更
| 时间 | 类型 | 文件/命令 |
|------|------|-----------|
$((Get-Content $logFile -Tail 10 | ForEach-Object {
    $entry = $_ | ConvertFrom-Json
    "| $($entry.timestamp) | $($entry.change_type) | $($entry.file ?? $entry.command) |"
    }) -join "`n")
"@

    $summary | Out-File -FilePath $summaryFile -Encoding UTF8

    Write-Host "📊 已生成变更摘要：$summaryFile" -ForegroundColor Green
}

exit 0
