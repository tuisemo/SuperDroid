#!/usr/bin/env pwsh
<#
.SYNOPSIS
会话清理器：会话结束时清理资源
.DESCRIPTION
归档日志、清理临时文件、更新索引
.NOTES
入口点：SessionEnd
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR
$logDir = Join-Path $projectDir ".factory", "logs"

# 参数
$retentionDays = 30  # 保留日志的天数
$compressOlderThan = 7  # 压缩超过7天的日志

# 1. 压缩旧日志
function Compress-OldLogs {
    param(
        [string]$Directory,
        [int]$Days
    )

    if (-not (Test-Path $Directory)) {
        return
    }

    Write-Host "🗂️  压缩旧日志..." -ForegroundColor Cyan

    $cutoffDate = (Get-Date).AddDays(-$Days)
    $filesToCompress = Get-ChildItem -Path $Directory -File -Recurse |
        Where-Object { $_.LastWriteTime -lt $cutoffDate -and $_.Extension -notmatch '\.(gz|zip|7z)$' }

    foreach ($file in $filesToCompress) {
        $compressedPath = "$($file.FullName).gz"
        if (-not (Test-Path $compressedPath)) {
            try {
                Compress-Archive -Path $file.FullName -DestinationPath "$($file.FullName).zip" -CompressionLevel Optimal -Force
                Remove-Item -Path $file.FullName -Force
                Write-Host "  压缩：$($file.Name)" -ForegroundColor Gray
            }
            catch {
                Write-Host "  压缩失败：$($file.Name)" -ForegroundColor Red
            }
        }
    }
}

# 2. 删除过期日志
function Remove-ExpiredLogs {
    param(
        [string]$Directory,
        [int]$Days
    )

    if (-not (Test-Path $Directory)) {
        return
    }

    Write-Host "🧹 清理过期日志（保留${Days}天）..." -ForegroundColor Cyan

    $cutoffDate = (Get-Date).AddDays(-$Days)
    $filesToRemove = Get-ChildItem -Path $Directory -File -Recurse |
        Where-Object { $_.LastWriteTime -lt $cutoffDate }

    $removedCount = 0
    foreach ($file in $filesToRemove) {
        try {
            Remove-Item -Path $file.FullName -Force
            $removedCount++
        }
        catch {
            Write-Host "  删除失败：$($file.Name)" -ForegroundColor Red
        }
    }

    Write-Host "  已删除 $removedCount 个过期日志文件" -ForegroundColor Green
}

# 3. 清理临时文件
function Clear-TempFiles {
    $tempDir = Join-Path $projectDir ".factory", "temp"

    if (-not (Test-Path $tempDir)) {
        return
    }

    Write-Host "🗑️  清理临时文件..." -ForegroundColor Cyan

    $tempFiles = Get-ChildItem -Path $tempDir -File -Recurse
    $removedCount = 0

    foreach ($file in $tempFiles) {
        try {
            Remove-Item -Path $file.FullName -Force
            $removedCount++
        }
        catch {
            # 忽略删除错误
        }
    }

    if ($removedCount -gt 0) {
        Write-Host "  已清理 $removedCount 个临时文件" -ForegroundColor Green
    }
}

# 4. 生成索引
function Update-LogIndex {
    $indexFile = Join-Path $logDir "index.json"
    $index = @{}

    # 扫描所有日志目录
    @("changes", "failures", "subtasks", "sessions", "commands", "quality", "notifications") | ForEach-Object {
        $categoryDir = Join-Path $logDir $_

        if (Test-Path $categoryDir) {
            $files = Get-ChildItem -Path $categoryDir -File | Sort-Object LastWriteTime -Descending
            $index[$_] = @{
                count = $files.Count
                latest = if ($files.Count -gt 0) { $files[0].LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
            }
        }
    }

    $index.last_updated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $index | ConvertTo-Json -Depth 10 | Set-Content -Path $indexFile -Encoding UTF8

    Write-Host "📋 日志索引已更新" -ForegroundColor Green
}

# 5. 生成清理报告
$cleanupReport = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    actions = @()
    summary = @{}
}

try {
    # 执行清理
    # Compress-OldLogs -Directory $logDir -Days $compressOlderThan
    # Remove-ExpiredLogs -Directory $logDir -Days $retentionDays
    Clear-TempFiles
    Update-LogIndex

    $cleanupReport.summary.status = "completed"
    $cleanupReport.actions += "临时文件已清理"
    $cleanupReport.actions += "日志索引已更新"

    Write-Host "`n✅ 会话清理完成" -ForegroundColor Green
}
catch {
    $cleanupReport.summary.status = "partial"
    $cleanupReport.summary.error = $_.Exception.Message
    Write-Host "`n⚠️  会话清理部分完成" -ForegroundColor Yellow
}

# 保存清理报告
$reportFile = Join-Path $logDir "cleanup_report_$(Get-Date -Format 'yyyy-MM-dd').json"
$cleanupReport | ConvertTo-Json -Depth 10 | Set-Content -Path $reportFile -Encoding UTF8

# 显示会话结束时间
Write-Host "`n━━━━━ 🏁 会话结束 $(Get-Date -Format 'HH:mm:ss') ━━━━━`n" -ForegroundColor DarkCyan

exit 0
