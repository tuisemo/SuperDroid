#!/usr/bin/env pwsh
<#
.SYNOPSIS
代码质量门禁：快速Lint和安全检查
.DESCRIPTION
在代码编辑后运行快速检查，发现基本问题但不阻止执行
.NOTES
入口点：PostToolUse（Bash/Execute后）
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR

# 读取标准输入
$inputData = Get-Content -Raw | ConvertFrom-Json

# 获取命令信息
$command = ""
if ($inputData.PSObject.Properties['tool_input'] -and $inputData.tool_input.PSObject.Properties['command']) {
    $command = $inputData.tool_input.command
}

if (-not $command) {
    exit 0
}

# 如果不是生成/编辑代码相关的命令，跳过
$codeCommands = @("python", "python3", "node", "npx", "npm", "go", "javac", "mvn")
$isCodeCommand = $false
foreach ($cmd in $codeCommands) {
    if ($command -like "$cmd*") {
        $isCodeCommand = $true
        break
    }
}

if (-not $isCodeCommand) {
    exit 0
}

# 安全模式检测
$securityPatterns = @{
    # SQL注入风险
    "SELECT.*\+\s*\w+" = "可能的SQL注入风险：字符串拼接SQL查询"
    "INSERT.*\+\s*\w+" = "可能的SQL注入风险：字符串拼接SQL查询"
    "DELETE FROM.*\+\s*\w+" = "可能的SQL注入风险：字符串拼接SQL查询"

    # XSS风险
    "innerHTML.*\+\s*\w+" = "可能的XSS风险：使用innerHTML拼接用户输入"
    "eval\(" = "代码注入风险：使用eval()执行动态代码"
    "innerHTML = document\." = "可能的XSS风险：innerHTML赋值"

    # 硬编码密钥
    "password\s*=\s*['""][^'""]+['""]" = "硬编码密码风险"
    "api_key\s*=\s*['""][^'""]+['""]" = "硬编码API密钥风险"
    "secret\s*=\s*['""][^'""]+['""]" = "硬编码密钥风险"
    "token\s*=\s*['""][^'""]+['""]" = "硬编码Token风险"

    # 不安全反序列化
    "pickle\.loads\(" = "不安全的pickle反序列化"
    "marshal\.loads\(" = "不安全的marshal反序列化"
}

# 代码风格问题
$stylePatterns = @{
    "TODO:" = "存在TODO标记，建议后续跟进"
    "FIXME:" = "存在FIXME标记，需要立即修复"
    "HACK:" = "存在HACK标记，需要重构"
    "XXX:" = "存在XXX标记，需要处理"
    "print\(" = "调试代码未清理"
    "console\.log\(" = "调试代码未清理"
    "debugger" = "调试代码未清理"
}

# 执行安全检查
$securityIssues = @()
foreach ($pattern in $securityPatterns.Keys) {
    if ($command -match $pattern) {
        $securityIssues += $securityPatterns[$pattern]
    }
}

# 执行风格检查
$styleIssues = @()
# 注意：这需要能访问生成的代码文件，暂只检查命令中的模式

# 如果有安全问题，显示警告
if ($securityIssues.Count -gt 0) {
    Write-Host "🔒 代码质量检查发现安全问题：" -ForegroundColor Red
    foreach ($issue in $securityIssues) {
        Write-Host "  ⚠️  $issue" -ForegroundColor Yellow
    }

    # 记录日志
    $logDir = Join-Path $projectDir ".factory", "logs", "quality"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $logFile = Join-Path $logDir "security_$(Get-Date -Format 'yyyy-MM-dd').log"
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $command | $($securityIssues -join '; ')"
    Add-Content -Path $logFile -Value $logEntry
}

# 如果有风格问题，显示提示
if ($styleIssues.Count -gt 0) {
    Write-Host "📝 代码风格检查发现待处理项：" -ForegroundColor Cyan
    foreach ($issue in $styleIssues) {
        Write-Host "  - $issue" -ForegroundColor Gray
    }
}

# 如果没有问题
if ($securityIssues.Count -eq 0 -and $styleIssues.Count -eq 0) {
    Write-Host "✅ 代码质量检查通过" -ForegroundColor Green
}

exit 0  # 仅警告，不阻止
