#!/usr/bin/env pwsh
<#
.SYNOPSIS
预读分析器：在读取文件前提供智能提示，支持大型文件优化
.DESCRIPTION
分析文件大小、类型，提供读取建议，避免加载过大文件
.NOTES
入口点：PreToolUse (匹配 Read)
阻断能力：支持（超大文件建议分批读取）
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR

# 读取标准输入
$inputData = Get-Content -Raw | ConvertFrom-Json

# 获取文件路径
$filePath = ""
if ($inputData.PSObject.Properties['tool_input']) {
    if ($inputData.tool_input.PSObject.Properties['file_path']) {
        $filePath = $inputData.tool_input.file_path
    } elseif ($inputData.tool_input.PSObject.Properties['path']) {
        $filePath = $inputData.tool_input.path
    }
}

if (-not $filePath) {
    exit 0
}

# 转换为绝对路径
if (-not [System.IO.Path]::IsPathRooted($filePath)) {
    $filePath = Join-Path $projectDir $filePath
}

if (-not (Test-Path $filePath)) {
    exit 0
}

$fileInfo = Get-Item $filePath -ErrorAction SilentlyContinue
if (-not $fileInfo) {
    exit 0
}

$fileSize = $fileInfo.Length
$fileSizeMB = [math]::Round($fileSize / 1MB, 2)
$fileSizeKB = [math]::Round($fileSize / 1KB, 2)
$fileExtension = $fileInfo.Extension.ToLower()

# 阈值设置
$LARGE_FILE_THRESHOLD_KB = 500
$VERY_LARGE_THRESHOLD_KB = 2048

# 记录日志
$logDir = Join-Path $projectDir ".factory", "logs", "read-optimizer"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logEntry = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    file_path = $filePath
    file_size_kb = $fileSizeKB
    file_extension = $fileExtension
} | ConvertTo-Json -Compress

Add-Content -Path (Join-Path $logDir "read-analysis.jsonl") -Value $logEntry

# 文件类型建议
$suggestions = @{
    ".log" = @{
        tip = "日志文件建议使用 offset/limit 分批读取"
        threshold_kb = 100
    }
    ".json" = @{
        tip = "JSON文件可考虑使用查询语法获取特定字段"
        threshold_kb = 500
    }
    ".csv" = @{
        tip = "CSV文件建议只读取必要的行/列"
        threshold_kb = 500
    }
    ".xml" = @{
        tip = "XML文件建议使用特定XPath查询"
        threshold_kb = 500
    }
    ".md" = @{
        tip = "文档文件通常可以完整读取"
        threshold_kb = 1024
    }
}

# 检查文件大小
if ($fileSizeKB -gt $VERY_LARGE_THRESHOLD_KB) {
    Write-Host "`n⚠️  超大文件警告" -ForegroundColor Red
    Write-Host "文件大小：$fileSizeKB KB ($([math]::Round($fileSizeKB/1024, 2)) MB)" -ForegroundColor Yellow
    Write-Host "文件路径：$filePath" -ForegroundColor Gray
    Write-Host ""
    Write-Host "💡 强烈建议使用以下方式：" -ForegroundColor Cyan
    Write-Host "   1. 使用 offset 和 limit 分批读取" -ForegroundColor White
    Write-Host "      Read '$filePath' -offset 0 -limit 100" -ForegroundColor DarkGray
    Write-Host "   2. 或使用 Grep 搜索特定内容" -ForegroundColor White
    Write-Host "      Grep 'pattern' '$filePath'" -ForegroundColor DarkGray
    Write-Host ""
    
    if ($fileSizeKB -gt 5120) {
        Write-Host "⚠️  文件超过5MB，建议分批读取以避免内存问题" -ForegroundColor Red
    }
}
elseif ($fileSizeKB -gt $LARGE_FILE_THRESHOLD_KB) {
    Write-Host "⚡ 较大文件：$fileSizeKB KB" -ForegroundColor Yellow
    
    if ($suggestions.ContainsKey($fileExtension)) {
        $suggestion = $suggestions[$fileExtension]
        if ($fileSizeKB -gt $suggestion.threshold_kb) {
            Write-Host "💡 $($suggestion.tip)" -ForegroundColor Cyan
        }
    }
}

exit 0
