#!/usr/bin/env pwsh
<#
.SYNOPSIS
增强文件保护：防止编辑敏感文件
.DESCRIPTION
保护敏感配置、密钥文件、生产环境配置等，支持智能白名单
.NOTES
入口点：PreToolUse
阻断能力：支持（返回退出码2表示拦截文件编辑）
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
    }
    elseif ($inputData.tool_input.PSObject.Properties['path']) {
        $filePath = $inputData.tool_input.path
    }
}

if (-not $filePath) {
    exit 0  # 无文件路径，允许执行
}

# 转换为绝对路径
if (-not [System.IO.Path]::IsPathRooted($filePath)) {
    $filePath = Join-Path $projectDir $filePath
}

$filePath = $filePath -replace "/", "\"

# 敏感文件模式（正则表达式）
$sensitivePatterns = @(
    # 环境变量和密钥
    "\.env$",
    "\.env\.",
    "\.env\.local$",
    "\.env\.local\.",
    "\.secrets?$",
    "\.key$",
    "\.pem$",
    "\.p12$",
    "\.pfx$",
    "\.crt$",
    "secret(s)?.(yaml|yml|json|toml|ini)$",
    "private(.*).(yaml|yml|json|toml)$",
    "credentials\.(yaml|yml|json|toml)$",
    "auth\.(yaml|yml|json|toml)$",

    # SSH和证书
    "[\\/]id_rsa$",
    "[\\/]id_ed25519$",
    "[\\/]authorized_keys$",
    "[\\/]known_hosts$",
    "\.(key|crt|cert|p12|pfx)$",

    # Git和版本控制
    "\.git",
    "\.git\\",
    "\.gitlock$",
    "HEAD$",

    # 锁定文件标记（通过.git/lock）
    "\.lock$",

    # 生产配置
    "production\.(yaml|yml|json|toml|ini|conf)$",
    "prod\.(yaml|yml|json|toml|ini|conf)$",
    "deploy(ment)?-config\.(yaml|yml|json)$",

    # 数据库备份
    "\.(sql|sqlite|db|mdb)$",
    "backup(s)?.(sql|json)$",

    # 构建产物（某些情况下需要保护）
    "dist\\",
    "build\\",

    # 编译结果
    "node_modules\\.+\.js$",
    "\.pyc$",
    "\.pyo$",
    "\.so$",
    "\.dll$",
    "\.exe$",
)

# 白名单路径（这些路径即使包含敏感模式也允许编辑）
$whitelistPaths = @(
    # 示例配置
    "examples\\",
    "samples\\",
    "templates\\",
    "docs\\",
    "\.factory\\",

    # 测试环境配置
    "\.env\.test$",
    "\.env\.dev$",
    "\.env\.development$",
)

# 检查白名单
function Test-Whitelisted {
    param([string]$Path)

    foreach ($pattern in $whitelistPaths) {
        if ($Path -match [regex]::Escape($pattern)) {
            return $true
        }
    }
    return $false
}

# 检查敏感模式
function Test-SensitiveFile {
    param([string]$Path)

    foreach ($pattern in $sensitivePatterns) {
        if ($Path -match $pattern) {
            return @{
                matched = $true
                pattern = $pattern
            }
        }
    }
    return @{ matched = $false }
}

# 首先检查白名单
if (Test-Whitelisted -Path $filePath) {
    Write-Host "✓ 文件通过白名单检查" -ForegroundColor Green
    exit 0
}

# 检查敏感模式
$sensitiveCheck = Test-SensitiveFile -Path $filePath

if ($sensitiveCheck.matched) {
    $message = "🚫 文件保护拦截：敏感文件编辑被阻止"
    Write-Host $message -ForegroundColor Red
    Write-Host "文件路径：$filePath" -ForegroundColor DarkRed
    Write-Host "匹配模式：$($sensitiveCheck.pattern)" -ForegroundColor DarkYellow
    Write-Host "`n此文件包含敏感信息，为保护系统安全，不允许AI工具直接编辑。" -ForegroundColor Yellow
    Write-Host "如果您确定需要编辑此文件，请：" -ForegroundColor Yellow
    Write-Host "  1. 手动使用文本编辑器编辑" -ForegroundColor Yellow
    Write-Host "  2. 确保文件不会泄露敏感信息" -ForegroundColor Yellow
    Write-Host "  3. 将文件路径添加到白名单（如需重复编辑）" -ForegroundColor Yellow

    # 记录拦截日志
    $logDir = Join-Path $projectDir ".factory", "logs", "security"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $logFile = Join-Path $logDir "file-protection_$(Get-Date -Format 'yyyy-MM-dd').log"
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | BLOCKED | Path: $filePath | Pattern: $($sensitiveCheck.pattern)"
    Add-Content -Path $logFile -Value $logEntry

    # 返回退出码2表示拦截
    exit 2
}

# 通过检查
Write-Host "✓ 文件保护检查通过" -ForegroundColor Green
exit 0
