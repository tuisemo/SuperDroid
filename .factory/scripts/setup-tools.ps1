#!/usr/bin/env pwsh
<#
.SYNOPSIS
开发环境初始化脚本 - 安装和配置 uv、pnpm、Node.js 22.22.0、Python 3.12.0 等工具

.DESCRIPTION
自动化设置现代化的 Python 和前端开发环境，确保版本一致性：
- Node.js: 22.22.0 LTS
- Python: 3.12.0
- pnpm: 最新稳定版
- uv: 最新稳定版

.PARAMETER Force
强制重新安装/升级所有工具

.PARAMETER PythonOnly
仅设置 Python 工具链

.PARAMETER FrontendOnly
仅设置前端工具链

.PARAMETER NonInteractive
非交互模式（用于自动化/CI）

.EXAMPLE
.\setup-tools.ps1                    # 交互式安装
.\setup-tools.ps1 -Force              # 强制升级
.\setup-tools.ps1 -NonInteractive     # 自动化模式
.\setup-tools.ps1 -PythonOnly         # 仅 Python
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$PythonOnly,
    [switch]$FrontendOnly,
    [switch]$NonInteractive,
    [string]$NodeVersion = "22.22.0",
    [string]$PythonVersion = "3.12.0"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# 颜色定义（兼容不同 PowerShell 版本）
$Colors = @{
    Cyan = "Cyan"
    Green = "Green"
    Yellow = "Yellow"
    Red = "Red"
    Gray = "Gray"
    White = "White"
}

# 项目目录
$script:ProjectDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# 版本要求（从 .factory/.droid.yaml 读取或默认值）
$script:RequiredNodeVersion = $NodeVersion
$script:RequiredPythonVersion = $PythonVersion

function Write-Header {
    param([string]$Title)
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Cyan
    Write-Host " $Title" -ForegroundColor $Colors.Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host " ✓ $Message" -ForegroundColor $Colors.Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host " ⚠ $Message" -ForegroundColor $Colors.Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host " ✗ $Message" -ForegroundColor $Colors.Red
}

function Write-Info {
    param([string]$Message)
    Write-Host " ℹ $Message" -ForegroundColor $Colors.Gray
}

# 版本比较函数
function Compare-Version {
    param(
        [string]$Current,
        [string]$Required
    )
    
    try {
        $currentV = [version]($Current -replace '[^0-9.]', '')
        $requiredV = [version]($Required -replace '[^0-9.]', '')
        
        if ($currentV -lt $requiredV) { return -1 }
        elseif ($currentV -gt $requiredV) { return 1 }
        else { return 0 }
    }
    catch {
        return -999  # 无法比较
    }
}

# 检查当前 Node.js 版本
function Test-NodeVersion {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) { return $null }
    
    try {
        $version = & node --version 2>$null
        return $version -replace '^v', ''
    }
    catch {
        return $null
    }
}

# 检查当前 Python 版本
function Test-PythonVersion {
    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $pythonCmd) { $pythonCmd = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $pythonCmd) { return $null }
    
    try {
        $version = & $pythonCmd --version 2>&1
        if ($version -match 'Python\s+(\d+\.\d+\.\d+)') {
            return $matches[1]
        }
        return $null
    }
    catch {
        return $null
    }
}

# 安装/升级 Node.js 到指定版本
function Install-NodeJs {
    Write-Header "Node.js 安装/升级"
    
    $currentVersion = Test-NodeVersion
    $versionCompare = if ($currentVersion) { Compare-Version $currentVersion $script:RequiredNodeVersion } else { -1 }
    
    if ($currentVersion -and $versionCompare -ge 0 -and -not $Force) {
        Write-Success "Node.js 已满足要求 (当前: v$currentVersion, 要求: v$script:RequiredNodeVersion)"
        return $true
    }
    
    if ($currentVersion -and $versionCompare -lt 0) {
        Write-Warning "Node.js 版本过低 (当前: v$currentVersion, 要求: v$script:RequiredNodeVersion)"
    }
    
    # 检查 nvm-windows
    $nvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
    
    if ($nvmCmd) {
        Write-Info "使用 nvm-windows 安装 Node.js v$script:RequiredNodeVersion..."
        try {
            & nvm install $script:RequiredNodeVersion
            & nvm use $script:RequiredNodeVersion
            Write-Success "Node.js v$script:RequiredNodeVersion 安装完成"
            
            # 创建 .nvmrc
            $script:RequiredNodeVersion | Out-File -FilePath (Join-Path $script:ProjectDir ".nvmrc") -Encoding UTF8 -NoNewline
            Write-Info "已创建 .nvmrc 文件"
            return $true
        }
        catch {
            Write-Error "nvm 安装失败: $_"
            return $false
        }
    }
    else {
        Write-Warning "未检测到 nvm-windows，建议安装以管理 Node.js 版本"
        Write-Info "下载地址: https://github.com/coreybutler/nvm-windows/releases"
        Write-Info "安装后重新运行此脚本"
        
        # 提供手动安装指导
        Write-Host "`n手动安装步骤:" -ForegroundColor $Colors.Cyan
        Write-Host "1. 下载并安装 nvm-windows" -ForegroundColor $Colors.White
        Write-Host "2. 重新打开 PowerShell" -ForegroundColor $Colors.White
        Write-Host "3. 运行: nvm install $script:RequiredNodeVersion" -ForegroundColor $Colors.White
        Write-Host "4. 运行: nvm use $script:RequiredNodeVersion" -ForegroundColor $Colors.White
        
        return $false
    }
}

# 安装/升级 pnpm
function Install-Pnpm {
    Write-Header "pnpm 安装/升级"
    
    $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
    
    if ($pnpmCmd -and -not $Force) {
        $version = & pnpm --version
        Write-Success "pnpm 已安装 (v$version)"
        return $true
    }
    
    Write-Info "安装 pnpm..."
    
    try {
        # 使用官方安装脚本
        Invoke-WebRequest -Uri "https://get.pnpm.io/install.ps1" -UseBasicParsing | Invoke-Expression
        
        # 刷新环境变量
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
        if ($pnpmCmd) {
            $version = & pnpm --version
            Write-Success "pnpm v$version 安装成功"
            return $true
        }
        else {
            Write-Warning "pnpm 安装可能成功，请重新打开 PowerShell 后验证"
            return $false
        }
    }
    catch {
        Write-Error "pnpm 安装失败: $_"
        return $false
    }
}

# 安装/升级 Python 到指定版本
function Install-Python {
    Write-Header "Python 安装/升级"
    
    $currentVersion = Test-PythonVersion
    $versionCompare = if ($currentVersion) { Compare-Version $currentVersion $script:RequiredPythonVersion } else { -1 }
    
    if ($currentVersion -and $versionCompare -ge 0 -and -not $Force) {
        Write-Success "Python 已满足要求 (当前: v$currentVersion, 要求: v$script:RequiredPythonVersion)"
        return $true
    }
    
    if ($currentVersion -and $versionCompare -lt 0) {
        Write-Warning "Python 版本过低 (当前: v$currentVersion, 要求: v$script:RequiredPythonVersion)"
    }
    
    # 检查 pyenv-win
    $pyenvCmd = Get-Command pyenv -ErrorAction SilentlyContinue
    
    if ($pyenvCmd) {
        Write-Info "使用 pyenv-win 安装 Python $script:RequiredPythonVersion..."
        try {
            & pyenv install $script:RequiredPythonVersion
            & pyenv global $script:RequiredPythonVersion
            Write-Success "Python $script:RequiredPythonVersion 安装完成"
            
            # 创建 .python-version
            $script:RequiredPythonVersion | Out-File -FilePath (Join-Path $script:ProjectDir ".python-version") -Encoding UTF8 -NoNewline
            Write-Info "已创建 .python-version 文件"
            return $true
        }
        catch {
            Write-Error "pyenv 安装失败: $_"
            return $false
        }
    }
    else {
        Write-Warning "未检测到 pyenv-win，建议安装以管理 Python 版本"
        Write-Info "安装命令: pip install pyenv-win --target %USERPROFILE%\.pyenv"
        
        # 提供手动安装指导
        Write-Host "`n手动安装步骤:" -ForegroundColor $Colors.Cyan
        Write-Host "1. 安装 pyenv-win: pip install pyenv-win" -ForegroundColor $Colors.White
        Write-Host "2. 重新打开 PowerShell" -ForegroundColor $Colors.White
        Write-Host "3. 运行: pyenv install $script:RequiredPythonVersion" -ForegroundColor $Colors.White
        Write-Host "4. 运行: pyenv global $script:RequiredPythonVersion" -ForegroundColor $Colors.White
        
        return $false
    }
}

# 安装 uv
function Install-Uv {
    Write-Header "uv (Python包管理器) 安装"
    
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    
    if ($uvCmd -and -not $Force) {
        $version = & uv --version
        Write-Success "uv 已安装 ($version)"
        return $true
    }
    
    Write-Info "安装 uv..."
    
    try {
        # 方法1: 使用 pipx（推荐）
        $pipxCmd = Get-Command pipx -ErrorAction SilentlyContinue
        if ($pipxCmd) {
            & pipx install uv --force
        }
        else {
            # 方法2: 使用官方安装脚本
            Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -UseBasicParsing | Invoke-Expression
        }
        
        # 刷新环境变量
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
        if ($uvCmd) {
            $version = & uv --version
            Write-Success "uv $version 安装成功"
            return $true
        }
        else {
            Write-Warning "uv 安装可能成功，请重新打开 PowerShell 后验证"
            return $false
        }
    }
    catch {
        Write-Error "uv 安装失败: $_"
        return $false
    }
}

# 安装 Python 开发工具
function Install-PythonTools {
    Write-Header "Python 开发工具安装"
    
    $tools = @(
        @{ Name = "black"; Desc = "代码格式化" }
        @{ Name = "ruff"; Desc = "代码检查（最快）" }
        @{ Name = "mypy"; Desc = "类型检查" }
        @{ Name = "pytest"; Desc = "测试框架" }
        @{ Name = "pytest-cov"; Desc = "覆盖率" }
    )
    
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvCmd) {
        Write-Error "uv 未安装，跳过 Python 工具安装"
        return $false
    }
    
    foreach ($tool in $tools) {
        Write-Info "安装 $($tool.Name) ($($tool.Desc))..."
        try {
            & uv tool install $tool.Name --upgrade 2>$null | Out-Null
            Write-Success "$($tool.Name) 安装完成"
        }
        catch {
            Write-Warning "$($tool.Name) 安装失败: $_"
        }
    }
    
    return $true
}

# 创建项目配置文件
function New-ProjectConfigFiles {
    Write-Header "项目配置文件"
    
    Push-Location $script:ProjectDir
    
    # 创建 .nvmrc
    if (-not (Test-Path ".nvmrc")) {
        $script:RequiredNodeVersion | Out-File -FilePath ".nvmrc" -Encoding UTF8 -NoNewline
        Write-Success "创建 .nvmrc (Node.js v$script:RequiredNodeVersion)"
    }
    
    # 创建 .python-version
    if (-not (Test-Path ".python-version")) {
        $script:RequiredPythonVersion | Out-File -FilePath ".python-version" -Encoding UTF8 -NoNewline
        Write-Success "创建 .python-version (Python $script:RequiredPythonVersion)"
    }
    
    # 创建 pyproject.toml（如果不存在）
    if (-not (Test-Path "pyproject.toml")) {
        $content = @"
[project]
name = "superdroid"
version = "0.1.0"
description = "SuperDroid Project"
requires-python = ">=$($script:RequiredPythonVersion)"
dependencies = []

[project.optional-dependencies]
dev = [
    "black>=24.0.0",
    "ruff>=0.5.0",
    "mypy>=1.10.0",
    "pytest>=8.0.0",
    "pytest-cov>=5.0.0",
]

[tool.ruff]
line-length = 100
target-version = "py312"
select = ["E", "F", "I", "N", "W", "UP"]
exclude = [".git", ".venv", "venv", "__pycache__", "dist", "build"]

[tool.ruff.lint]
ignore = ["E501"]

[tool.black]
line-length = 100
target-version = ["py312"]

[tool.mypy]
python_version = "$($script:RequiredPythonVersion)"
warn_return_any = true
warn_unused_configs = true
disallow_untyped_defs = false

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--cov=. --cov-report=term-missing --cov-report=html"
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
"@
        $content | Out-File -FilePath "pyproject.toml" -Encoding UTF8
        Write-Success "创建 pyproject.toml"
    }
    
    Pop-Location
}

# 验证安装
function Test-Installation {
    Write-Header "安装验证"
    
    $results = @()
    
    # Node.js
    $nodeVersion = Test-NodeVersion
    if ($nodeVersion) {
        $compare = Compare-Version $nodeVersion $script:RequiredNodeVersion
        if ($compare -ge 0) {
            Write-Success "Node.js: v$nodeVersion ✓"
            $results += @{ Tool = "Node.js"; Status = "OK"; Version = $nodeVersion }
        }
        else {
            Write-Warning "Node.js: v$nodeVersion (需要 v$script:RequiredNodeVersion)"
            $results += @{ Tool = "Node.js"; Status = "NEED_UPGRADE"; Version = $nodeVersion }
        }
    }
    else {
        Write-Error "Node.js: 未安装"
        $results += @{ Tool = "Node.js"; Status = "MISSING"; Version = "-" }
    }
    
    # pnpm
    $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue
    if ($pnpmCmd) {
        $version = & pnpm --version
        Write-Success "pnpm: v$version ✓"
        $results += @{ Tool = "pnpm"; Status = "OK"; Version = $version }
    }
    else {
        Write-Error "pnpm: 未安装"
        $results += @{ Tool = "pnpm"; Status = "MISSING"; Version = "-" }
    }
    
    # Python
    $pythonVersion = Test-PythonVersion
    if ($pythonVersion) {
        $compare = Compare-Version $pythonVersion $script:RequiredPythonVersion
        if ($compare -ge 0) {
            Write-Success "Python: v$pythonVersion ✓"
            $results += @{ Tool = "Python"; Status = "OK"; Version = $pythonVersion }
        }
        else {
            Write-Warning "Python: v$pythonVersion (需要 v$script:RequiredPythonVersion)"
            $results += @{ Tool = "Python"; Status = "NEED_UPGRADE"; Version = $pythonVersion }
        }
    }
    else {
        Write-Error "Python: 未安装"
        $results += @{ Tool = "Python"; Status = "MISSING"; Version = "-" }
    }
    
    # uv
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($uvCmd) {
        $version = & uv --version
        Write-Success "uv: $version ✓"
        $results += @{ Tool = "uv"; Status = "OK"; Version = $version }
    }
    else {
        Write-Error "uv: 未安装"
        $results += @{ Tool = "uv"; Status = "MISSING"; Version = "-" }
    }
    
    return $results
}

# 主函数
function Main {
    Write-Header "SuperDroid 开发环境初始化"
    Write-Info "目标版本: Node.js v$script:RequiredNodeVersion | Python $script:RequiredPythonVersion"
    Write-Info "项目目录: $script:ProjectDir"
    
    $results = @{
        NodeJs = $false
        Pnpm = $false
        Python = $false
        Uv = $false
        PythonTools = $false
    }
    
    # 前端工具链
    if (-not $PythonOnly) {
        $results.NodeJs = Install-NodeJs
        $results.Pnpm = Install-Pnpm
    }
    
    # Python 工具链
    if (-not $FrontendOnly) {
        $results.Python = Install-Python
        $results.Uv = Install-Uv
        if ($results.Uv) {
            $results.PythonTools = Install-PythonTools
        }
    }
    
    # 创建配置文件
    New-ProjectConfigFiles
    
    # 验证
    $verifyResults = Test-Installation
    
    # 总结
    Write-Header "总结"
    
    $allOk = $true
    foreach ($result in $verifyResults) {
        $icon = switch ($result.Status) {
            "OK" { "✓" }
            "NEED_UPGRADE" { "↑" }
            "MISSING" { "✗" }
            default { "?" }
        }
        $color = switch ($result.Status) {
            "OK" { $Colors.Green }
            "NEED_UPGRADE" { $Colors.Yellow }
            "MISSING" { $Colors.Red }
            default { $Colors.Gray }
        }
        Write-Host " $icon $($result.Tool): $($result.Version)" -ForegroundColor $color
        if ($result.Status -ne "OK") { $allOk = $false }
    }
    
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $Colors.Cyan
    
    if ($allOk) {
        Write-Host " ✨ 全部工具安装完成！" -ForegroundColor $Colors.Green
    }
    else {
        Write-Host " ⚠ 部分工具需要手动安装/升级" -ForegroundColor $Colors.Yellow
        Write-Host " 请查看上方输出了解详细信息" -ForegroundColor $Colors.Gray
        if (-not $NonInteractive) {
            Write-Host "`n按任意键继续..." -ForegroundColor $Colors.Gray
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
    
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`n" -ForegroundColor $Colors.Cyan
    
    Write-Info "常用命令:"
    Write-Host "  pnpm install          # 安装前端依赖" -ForegroundColor $Colors.White
    Write-Host "  uv sync               # 安装 Python 依赖" -ForegroundColor $Colors.White
    Write-Host "  uv run ruff format .  # 格式化代码" -ForegroundColor $Colors.White
    Write-Host "  uv run pytest         # 运行测试" -ForegroundColor $Colors.White
    
    exit $(if ($allOk) { 0 } else { 1 })
}

# 执行主函数
Main
