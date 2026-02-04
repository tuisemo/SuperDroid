#!/usr/bin/env pwsh
<#
.SYNOPSIS
子任务验证器：验证子droid完成情况
.DESCRIPTION
检查子任务输出、结果完整性，生成子任务报告
.NOTES
入口点：SubagentStop
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR

# 读取标准输入
$inputData = Get-Content -Raw | ConvertFrom-Json

# 获取子任务信息
$subagentName = ""
$taskDescription = ""
$result = ""
$status = ""

if ($inputData.PSObject.Properties['subagent_name']) {
    $subagentName = $inputData.subagent_name
}
elseif ($inputData.PSObject.Properties['droid']) {
    $subagentName = $inputData.droid
}

if ($inputData.PSObject.Properties['task_description']) {
    $taskDescription = $inputData.task_description
}
elseif ($inputData.PSObject.Properties['prompt']) {
    $taskDescription = $inputData.prompt
}

if ($inputData.PSObject.Properties['result']) {
    $result = $inputData.result
}
elseif ($inputData.PSObject.Properties['response']) {
    $result = $inputData.response
}

if ($inputData.PSObject.Properties['status']) {
    $status = $inputData.status
}

# 创建验证报告
$validationReport = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    subagent = $subagentName
    task = $taskDescription
    status = if ($status) { $status } else { "unknown" }
    validation = @{}
}

# 检查任务执行状态
$validationReport.validation.completed = ($result.Length -gt 0)

# 检查是否包含错误
$hasError = $result -match "error|错误|failed|失败|exception|异常"
$validationReport.validation.has_error = $hasError

# 检查结果质量（长度、结构）
$validationReport.validation.result_length = $result.Length
$validationReport.validation.has_structure = $result -match "\n[\s]*[-*+#]|```|\[.*\]"

# 生成评估
$validationReport.validation.score = 0
$validationReport.validation.score += $(if ($validationReport.validation.completed) { 30 } else { 0 })
$validationReport.validation.score += $(if (-not $validationReport.validation.has_error) { 30 } else { 0 })
$validationReport.validation.score += $(if ($validationReport.validation.has_structure) { 20 } else { 0 })
$validationReport.validation.score += $(if ($result.Length -gt 100) { 20 } else { $result.Length / 5 })
$validationReport.validation.score = [math]::Min($validationReport.validation.score, 100)

# 保存验证报告
$logDir = Join-Path $projectDir ".factory", "logs", "subtasks"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logFile = Join-Path $logDir "subtask_validation_$(Get-Date -Format 'yyyy-MM-dd').json"
$reportJson = $validationReport | ConvertTo-Json -Compress
Add-Content -Path $logFile -Value $reportJson

# 更新统计
$statsFile = Join-Path $logDir "subtask_stats.json"
$stats = @{}

if (Test-Path $statsFile) {
    $stats = Get-Content -Path $statsFile -Raw | ConvertFrom-Json -AsHashtable
}

$agentKey = if ($subagentName) { $subagentName } else { "unknown" }
if (-not $stats.ContainsKey($agentKey)) {
    $stats[$agentKey] = @{
        total = 0
        completed = 0
        failed = 0
        avg_score = 0
    }
}

$stats[$agentKey].total += 1
if ($validationReport.validation.completed) { $stats[$agentKey].completed += 1 }
if ($hasError) { $stats[$agentKey].failed += 1 }

# 计算平均分（简化版）
$stats[$agentKey].avg_score = ($validationReport.validation.score + ($stats[$agentKey].avg_score * ($stats[$agentKey].total - 1))) / $stats[$agentKey].total

$stats | ConvertTo-Json -Depth 10 | Set-Content -Path $statsFile -Encoding UTF8

# 显示简短状态
if ($subagentName) {
    $score = $validationReport.validation.score
    $icon = switch ($score) {
        { $_ -ge 80 } { "✓" }
        { $_ -ge 50 } { "≈" }
        default { "✗" }
    }
    $color = switch ($score) {
        { $_ -ge 80 } { "Green" }
        { $_ -ge 50 } { "Yellow" }
        default { "Red" }
    }

    Write-Host "$icon [${subagentName}] 评分: $([math]::Round($score))%" -ForegroundColor $color

    if ($hasError) {
        Write-Host "  ⚠️  子任务包含错误信息" -ForegroundColor Yellow
    }
}

exit 0
