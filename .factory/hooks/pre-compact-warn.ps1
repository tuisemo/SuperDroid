#!/usr/bin/env pwsh
<#
.SYNOPSIS
压缩前预警：在context压缩前提醒用户保存重要信息
.DESCRIPTION
在执行compact操作前，提示用户重要的上下文信息即将被压缩
建议用户保存关键决策、待办事项等
.NOTES
入口点：PreCompact
阻断能力：否（仅提示）
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host "⚠️  即将执行 Context 压缩操作" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Yellow

Write-Host "当前会话的详细对话历史将被压缩以释放空间。" -ForegroundColor White
Write-Host "以下信息建议立即保存（如尚未保存）：" -ForegroundColor White
Write-Host ""
Write-Host "  📋 待办事项/任务清单" -ForegroundColor Cyan
Write-Host "  💡 重要技术决策及原因" -ForegroundColor Cyan
Write-Host "  🔧 关键代码变更说明" -ForegroundColor Cyan
Write-Host "  📊 性能测试结果或指标" -ForegroundColor Cyan
Write-Host "  ❓ 未解决的疑问或阻塞点" -ForegroundColor Cyan
Write-Host ""

# 检查是否有未提交的待办事项
$todoFile = Join-Path $projectDir ".factory", "todos", "current.md"
if (Test-Path $todoFile) {
    $todoContent = Get-Content $todoFile -Raw
    $incompleteTodos = ($todoContent | Select-String "^- \[ \]" -AllMatches).Matches.Count
    if ($incompleteTodos -gt 0) {
        Write-Host "⚠️  检测到 $incompleteTodos 个未完成的待办事项" -ForegroundColor Yellow
        Write-Host "   建议执行 '/todos' 或保存到项目看板`n" -ForegroundColor Gray
    }
}

# 记录压缩事件
$logDir = Join-Path $projectDir ".factory", "logs", "compact"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logEntry = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    event = "pre_compact_warning"
} | ConvertTo-Json -Compress

Add-Content -Path (Join-Path $logDir "compact-events.jsonl") -Value $logEntry

Write-Host "💡 提示：系统将自动保留关键决策到 .factory/decisions/" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor Gray

exit 0
