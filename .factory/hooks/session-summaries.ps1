#!/usr/bin/env pwsh
<#
.SYNOPSIS
会话总结器：生成会话摘要和下一步建议
.DESCRIPTION
分析会话活动，提取关键成果，生成可执行建议
.NOTES
入口点：Stop
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR

# 获取会话信息（从环境变量或预设上下文）
$sessionStartTime = if ($env:FACTORY_SESSION_START) { $env:FACTORY_SESSION_START } else { (Get-Date).AddMinutes(-30) }
$sessionDuration = (Get-Date) - $sessionStartTime

# 读取变更日志
$changeLogFile = Join-Path $projectDir ".factory", "logs", "changes", "session_$(Get-Date -Format 'yyyy-MM-dd').jsonl"
$changes = @()

if (Test-Path $changeLogFile) {
    # 仅读取最近的变更（当前会话）
    $recentChanges = Get-Content $changeLogFile | Where-Object {
        $entry = $_ | ConvertFrom-Json
        [DateTime]$entry.timestamp -gt $sessionStartTime
    }
    $changes = $recentChanges
}

# 读取失败日志（如果有）
$failureLogFile = Join-Path $projectDir ".factory", "logs", "failures", "failure.log"
$failures = @()

if (Test-Path $failureLogFile) {
    $failures = Get-Content $failureLogFile | Where-Object {
        $_ -match (Get-Date -Format "yyyy-MM-dd")
    }
}

# 读取Git状态
Push-Location $projectDir
$gitStatus = git status --short 2>&1
$gitDiffStat = git diff --stat 2>&1
Pop-Location

# 生成会话摘要
$summary = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    duration = "$($sessionDuration.Hours)h $($sessionDuration.Minutes)m"
    changes = @{
        total = $changes.Count
        by_type = @{}
    }
    failures = $failures.Count
    git_status = @{
        has_changes = ($gitStatus.Length -gt 0)
        modified_files = ($gitStatus -split "`n").Count
    }
    key_achievements = @()
    challenges = @()
    next_actions = @()
}

# 统计变更类型
foreach ($changeStr in $changes) {
    try {
        $change = $changeStr | ConvertFrom-Json
        $changeType = $change.change_type

        if (-not $summary.changes.by_type.ContainsKey($changeType)) {
            $summary.changes.by_type[$changeType] = 0
        }
        $summary.changes.by_type[$changeType] += 1
    }
    catch {
        # 忽略解析错误
    }
}

# 提取关键成就
if ($summary.changes.total -gt 10) {
    $summary.key_achievements += "完成 $([math]::Round($summary.changes.total)) 次操作"
}

if ($summary.changes.by_type.ContainsKey('MODIFY')) {
    $summary.key_achievements += "修改代码文件 $($summary.changes.by_type['MODIFY']) 次"
}

if ($summary.changes.by_type.ContainsKey('CREATE')) {
    $summary.key_achievements += "创建新文件 $($summary.changes.by_type['CREATE']) 个"
}

if ($summary.failures -eq 0 -and $summary.changes.total -gt 0) {
    $summary.key_achievements += "无错误执行"
}

# 生成挑战
if ($summary.failures -gt 0) {
    $summary.challenges += "遇到 $($(summary.failures)) 次失败，可能需要优化"
}

if ($summary.git_status.modified_files -gt 5 -and $summary.git_status.has_changes) {
    $summary.challenges += "多个修改未提交，建议定期提交"
}

# 生成下一步建议
if ($summary.git_status.has_changes) {
    $summary.next_actions += "考虑执行 git commit 提交变更"
}

if ($summary.changes.total -gt 50) {
    $summary.next_actions += "变更较多，建议休息并回顾处理内容"
}

if ($summary.failures -gt 3) {
    $summary.next_actions += "检查常见错误模式并更新 lessons.md"
}

if ($summary.changes.total -eq 0) {
    $summary.next_actions += "开始新的开发任务或研究工作"
}

# 保存摘要
$logDir = Join-Path $projectDir ".factory", "logs", "sessions"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$summaryFile = Join-Path $logDir "summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$summary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryFile -Encoding UTF8

# 显示摘要
Write-Host "`n━━━ 📊 会话摘要 ━━━" -ForegroundColor Cyan
Write-Host "时长：$($summary.duration)" -ForegroundColor Gray
Write-Host "操作：$($summary.changes.total) 次" -ForegroundColor Gray
Write-Host "失败：$($summary.failures) 次" -ForegroundColor $(if ($summary.failures -eq 0) { 'Green' } else { 'Yellow' })

Write-Host "`n关键成就：`n" -ForegroundColor Green
foreach ($achievement in $summary.key_achievements) {
    Write-Host "  ✓ $achievement" -ForegroundColor Green
}

if ($summary.challenges.Count -gt 0) {
    Write-Host "`n遇到的挑战：`n" -ForegroundColor Yellow
    foreach ($challenge in $summary.challenges) {
        Write-Host "  - $challenge" -ForegroundColor Yellow
    }
}

if ($summary.next_actions.Count -gt 0) {
    Write-Host "`n建议的下一步：`n" -ForegroundColor Cyan
    foreach ($action in $summary.next_actions) {
        Write-Host "  $action" -ForegroundColor Cyan
    }
}

Write-Host "`n━━━━━━━━━━━━━━━━━`n" -ForegroundColor Gray

# 更新全局统计
$globalStatsFile = Join-Path $projectDir ".factory", "logs", "global_stats.json"
$globalStats = @{}

if (Test-Path $globalStatsFile) {
    $globalStats = Get-Content -Path $globalStatsFile -Raw | ConvertFrom-Json -AsHashtable
}

$dateKey = (Get-Date -Format 'yyyy-MM-dd')
if (-not $globalStats.ContainsKey($dateKey)) {
    $globalStats[$dateKey] = @{
        total_changes = 0
        total_failures = 0
        session_count = 0
    }
}

$globalStats[$dateKey].total_changes += $summary.changes.total
$globalStats[$dateKey].total_failures += $summary.failures
$globalStats[$dateKey].session_count += 1

$globalStats | ConvertTo-Json -Depth 10 | Set-Content -Path $globalStatsFile -Encoding UTF8

exit 0
