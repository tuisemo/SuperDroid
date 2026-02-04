#!/usr/bin/env pwsh
<#
.SYNOPSIS
命令验证器：检测危险命令并拦截
.DESCRIPTION
在用户提交提示前分析命令，识别危险模式并根据规则决定是否拦截
.NOTES
入口点：UserPromptSubmit
阻断能力：支持（返回退出码2表示拦截）
#>

param(
    [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
    [string]$InputJson
)

$ErrorActionPreference = "Continue"

# 读取标准输入
$inputData = $InputJson | ConvertFrom-Json

# 危险命令模式
$dangerousPatterns = @{
    # 文件删除
    "rm -rf" = "高风险：递归删除整个目录"
    "rm -Rf" = "高风险：递归删除整个目录"
    "Remove-Item -Recurse -Force" = "高风险：递归删除整个目录"
    "del /s /q" = "高风险：递归删除文件"

    # Git危险操作
    "git reset --hard" = "风险：硬重置，未提交的更改将丢失"
    "git push --force" = "风险：强制推送可能覆盖远程历史"
    "git push -f" = "风险：强制推送可能覆盖远程历史"
    "git clean -fdx" = "风险：删除所有未跟踪文件"

    # 数据库危险操作
    "DROP DATABASE" = "极高危：删除整个数据库"
    "DROP TABLE" = "高危：删除数据表"
    "DELETE FROM.*WHERE 1=1" = "高危：删除所有数据"
    "TRUNCATE TABLE" = "高危：清空数据表"

    # 生产环境操作
    "production.*rm" = "风险：生产环境删除操作"
    "prod.*delete" = "风险：生产环境删除操作"

    # 系统关键目录
    "/etc/.*rm" = "风险：删除系统配置"
    "C:\\Windows\\.*delete" = "风险：删除系统文件"
    "\.env" = "风险：编辑环境变量文件"
    "secrets" = "风险：访问敏感信息文件"
}

# 需要警告但不拦截的模式
$warningPatterns = @{
    "pip install.*git\+" = "注意：从Git仓库安装，请确保来源可信"
    "npm install.*--unsafe-perm" = "注意：使用不安全权限安装"
    "curl.*bash" = "注意：直接执行下载的脚本，请验证URL"
    "wget.*bash" = "注意：直接执行下载的脚本，请验证URL"
    "chmod 777" = "注意：设置完全开放权限可能存在安全风险"
    "sudo.*rm" = "注意：使用sudo删除文件"
}

# 提取命令内容
function Get-CommandFromInput {
    param([object]$Data)

    $command = ""

    # 从不同可能的字段提取
    if ($Data.PSObject.Properties['command']) {
        $command = $Data.command
    }
    elseif ($Data.PSObject.Properties['tool_input']) {
        if ($Data.tool_input.PSObject.Properties['command']) {
            $command = $Data.tool_input.command
        }
    }
    elseif ($Data.PSObject.Properties['prompt']) {
        $command = $Data.prompt
    }

    return $command
}

$commandText = Get-CommandFromInput -Data $inputData

# 检查危险模式
foreach ($pattern in $dangerousPatterns.Keys) {
    if ($commandText -match $pattern) {
        $message = $dangerousPatterns[$pattern]
        Write-Host "🚫 命令拦截：$message" -ForegroundColor Red
        Write-Host "命令内容：$commandText" -ForegroundColor DarkRed
        Write-Host "`n此操作已被拦截。如果您确定要执行，请：" -ForegroundColor Yellow
        Write-Host "  1. 理解操作的潜在风险" -ForegroundColor Yellow
        Write-Host "  2. 手动在终端中执行（绕过AI辅助）" -ForegroundColor Yellow
        Write-Host "  3. 考虑是否真的需要执行此操作" -ForegroundColor Yellow

        # 记录拦截日志
        $logDir = Join-Path $env:FACTORY_PROJECT_DIR ".factory", "logs", "commands"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $logFile = Join-Path $logDir "blocked_$(Get-Date -Format 'yyyy-MM-dd').log"
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | BLOCKED | Pattern: $pattern | Message: $message | Command: $($commandText -replace '\r?\n', ' ')"
        Add-Content -Path $logFile -Value $logEntry

        # 返回退出码2表示拦截
        exit 2
    }
}

# 检查警告模式
foreach ($pattern in $warningPatterns.Keys) {
    if ($commandText -match $pattern) {
        $message = $warningPatterns[$pattern]
        Write-Host "⚠️  命令警告：$message" -ForegroundColor Yellow
        Write-Host "命令内容：$commandText" -ForegroundColor Cyan

        # 记录警告日志
        $logDir = Join-Path $env:FACTORY_PROJECT_DIR ".factory", "logs", "commands"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }

        $logFile = Join-Path $logDir "warning_$(Get-Date -Format 'yyyy-MM-dd').log"
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | WARNING | Pattern: $pattern | Message: $message | Command: $($commandText -replace '\r?\n', ' ')"
        Add-Content -Path $logFile -Value $logEntry

        # 警告但不拦截
        exit 0
    }
}

# 记录正常命令
$logDir = Join-Path $env:FACTORY_PROJECT_DIR ".factory", "logs", "commands"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logFile = Join-Path $logDir "audit_$(Get-Date -Format 'yyyy-MM-dd').log"
$logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | ALLOWED | Command: $($commandText -replace '\r?\n', ' ')"
Add-Content -Path $logFile -Value $logEntry

exit 0
