#!/usr/bin/env pwsh
<#
.SYNOPSIS
会话初始化检查：验证开发环境健康状态
.DESCRIPTION
检查Python、Node、Git等工具链，验证项目依赖，评估资源可用性
.NOTES
环境变量：$FACTORY_PROJECT_DIR
输出格式：JSON状态报告
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR
$checkResult = @{
    status = "ready"
    timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    checks = @{}
    issues = @()
    recommendations = @()
}

# ==================== 版本配置 ====================

# 推荐版本
$RECOMMENDED_PYTHON_VERSION = "3.12.0"
$RECOMMENDED_NODE_VERSION = "22.22.0"

# 读取项目版本配置
function Get-ProjectConfigVersion {
    param([string]$Type)

    $version = $null

    switch ($Type) {
        "python" {
            # 检查 .python-version
            $pythonVersionFile = Join-Path $projectDir ".python-version"
            if (Test-Path $pythonVersionFile) {
                $version = (Get-Content $pythonVersionFile -First 1).Trim()
            }
            # 检查 pyproject.toml
            elseif (Test-Path (Join-Path $projectDir "pyproject.toml")) {
                $pyproject = Get-Content (Join-Path $projectDir "pyproject.toml") -Raw
                if ($pyproject -match 'requires-python\s*=\s*["\']?([0-9.]+)') {
                    $version = $matches[1]
                }
            }
            # 检查 runtime.txt (Python on some platforms)
            elseif (Test-Path (Join-Path $projectDir "runtime.txt")) {
                $runtime = Get-Content (Join-Path $projectDir "runtime.txt") -First 1
                if ($runtime -match 'python-([0-9.]+)') {
                    $version = $matches[1]
                }
            }
        }
        "node" {
            # 检查 .nvmrc
            $nvmrcFile = Join-Path $projectDir ".nvmrc"
            if (Test-Path $nvmrcFile) {
                $version = (Get-Content $nvmrcFile -First 1).Trim()
            }
            # 检查 .node-version
            $nodeVersionFile = Join-Path $projectDir ".node-version"
            elseif (Test-Path $nodeVersionFile) {
                $version = (Get-Content $nodeVersionFile -First 1).Trim()
            }
            # 检查 package.json engines
            elseif (Test-Path (Join-Path $projectDir "package.json")) {
                $packageJson = Get-Content (Join-Path $projectDir "package.json") -Raw | ConvertFrom-Json
                if ($packageJson.PSObject.Properties['engines'] -and $packageJson.engines.PSObject.Properties['node']) {
                    $version = $packageJson.engines.node -replace '[>=~^]', ''
                }
            }
        }
    }

    return $version
}

# 获取目标版本（项目配置优先）
$targetPythonVersion = Get-ProjectConfigVersion -Type "python"
if (-not $targetPythonVersion) {
    $targetPythonVersion = $RECOMMENDED_PYTHON_VERSION
}

$targetNodeVersion = Get-ProjectConfigVersion -Type "node"
if (-not $targetNodeVersion) {
    $targetNodeVersion = $RECOMMENDED_NODE_VERSION
}

# 版本比较函数
function Compare-Version {
    param([string]$Version1, [string]$Version2)

    try {
        # 提取主版本号
        $v1 = [version]($Version1 -replace '[^0-9.]', '')
        $v2 = [version]($Version2 -replace '[^0-9.]', '')

        if ($v1 -lt $v2) { return -1 }
        elseif ($v1 -gt $v2) { return 1 }
        else { return 0 }
    }
    catch {
        # 无法解析版本，返回未知
        return -999
    }
}

# ==================== 环境检查 ====================

# 1. 磁盘空间检查
function Test-DiskSpace {
    $drive = Get-PSDrive -Name ([System.IO.Directory]::GetDirectoryRoot($projectDir).TrimEnd(':'))
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    $checkResult.checks.disk_space = @{
        freeGB = $freeGB
        status = if ($freeGB -lt 5) { "warning" } else { "ok" }
    }

    if ($freeGB -lt 5) {
        $checkResult.issues += "磁盘空间不足：剩余 $freeGB GB"
        $checkResult.recommendations += "清理磁盘或释放至少 5GB 空间"
    }
}

# 2. Python环境检查
function Test-PythonEnvironment {
    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    }

    if ($pythonCmd) {
        try {
            $versionOutput = & $pythonCmd --version 2>&1

            # 提取版本号（去除 "Python " 前缀）
            $version = ($versionOutput -replace 'Python ', '').Trim()

            # 提取数字版本
            $numericVersion = $version -replace '[^0-9.]', ''

            # 版本检查
            $versionCompare = Compare-Version $numericVersion $targetPythonVersion

            $status = "ok"
            if ($versionCompare -lt 0) {
                $status = "outdated"
                $checkResult.recommendations += "Python版本过旧（当前:v$version，目标:v$targetPythonVersion），建议升级"
            }
            elseif ($versionCompare -gt 0) {
                $status = "newer"
            }

            $checkResult.checks.python = @{
                path = $pythonCmd.Source
                version = "v$version"
                target = "v$targetPythonVersion"
                status = $status
            }

            Write-Host "  ✓ Python: v$version (目标: v$targetPythonVersion)" -ForegroundColor Gray

            # 检查常用包
            $packages = @("pytest", "black", "ruff", "mypy")
            foreach ($pkg in $packages) {
                $installed = & $pythonCmd -c "import $pkg" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $checkResult.checks."python_$pkg" = "installed"
                }
            }

            if (-not $checkResult.checks.ContainsKey("python_pytest")) {
                $checkResult.recommendations += "安装 pytest: python -m pip install pytest"
                $checkResult.status = "warning"
            }
        }
        catch {
            $checkResult.checks.python = @{
                status = "error"
                error = $_.Exception.Message
            }
            $checkResult.issues += "Python环境配置错误"
        }
    }
    else {
        $checkResult.checks.python = @{
            status = "not_found"
            target = "v$targetPythonVersion"
        }
        $checkResult.issues += "未找到Python环境"
        $checkResult.recommendations += "安装 Python v$targetPythonVersion 或更高版本"
        $checkResult.status = "warning"
    }
}

# uv包管理器检查（Python）
function Test-UvEnvironment {
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue

    if ($uvCmd) {
        try {
            $version = & uv --version 2>&1
            $checkResult.checks.uv = @{
                path = $uvCmd.Source
                version = $version
                status = "ok"
            }

            # 检查uv cache
            $cachePath = Join-Path $env:USERPROFILE ".cache", "uv"
            if (Test-Path $cachePath) {
                $checkResult.checks.uv_cache = "available"
            }

            Write-Host "  ✓ 检测到 uv（推荐的超快Python包管理器）" -ForegroundColor Green
        }
        catch {
            $checkResult.checks.uv = @{
                status = "error"
                error = $_.Exception.Message
            }
        }
    }
    else {
        $checkResult.checks.uv = @{ status = "not_found" }
        $checkResult.recommendations += "推荐安装 uv（超快的Python包管理器）：pip install uv"
        $checkResult.status = "info"
    }
}

# 3. Node.js环境检查
function Test-NodeEnvironment {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    $pnpmCmd = Get-Command pnpm -ErrorAction SilentlyContinue

    if ($nodeCmd) {
        try {
            $versionOutput = & node --version 2>&1
            $version = $versionOutput -replace 'v', ''

            # 提取数字版本
            $numericVersion = $version -replace '[^0-9.]', ''

            # 版本检查
            $versionCompare = Compare-Version $numericVersion $targetNodeVersion

            $status = "ok"
            if ($versionCompare -lt 0) {
                $status = "outdated"
                $checkResult.recommendations += "Node.js版本过旧（当前:v$version，目标:v$targetNodeVersion），建议升级"
            }
            elseif ($versionCompare -gt 0) {
                $status = "newer"
            }

            $checkResult.checks.node = @{
                path = $nodeCmd.Source
                version = "v$version"
                target = "v$targetNodeVersion"
                status = $status
            }

            Write-Host "  ✓ Node.js: v$version (目标: v$targetNodeVersion)" -ForegroundColor Gray
        }
        catch {
            $checkResult.checks.node = @{ status = "error" }
        }
    }
    else {
        $checkResult.checks.node = @{
            status = "not_found"
            target = "v$targetNodeVersion"
        }
        $checkResult.recommendations += "安装 Node.js v$targetNodeVersion 或更高版本"
        $checkResult.status = "warning"
    }

    # 优先检查pnpm
    if ($pnpmCmd) {
        try {
            $version = & pnpm --version 2>&1
            $checkResult.checks.pnpm = @{
                path = $pnpmCmd.Source
                version = $version
                status = "preferred"
            }
            Write-Host "  ✓ pnpm: v$version (推荐)" -ForegroundColor Green
        }
        catch {
            $checkResult.checks.pnpm = @{ status = "error" }
        }
    }
    else {
        $checkResult.checks.pnpm = @{ status = "not_found" }
        $checkResult.recommendations += "推荐安装 pnpm（快速的前端包管理器）：npm install -g pnpm"
        if ($checkResult.status -ne "warning") {
            $checkResult.status = "info"
        }
    }

    if ($npmCmd) {
        try {
            $version = & npm --version 2>&1
            $checkResult.checks.npm = @{
                path = $npmCmd.Source
                version = $version
                status = "fallback"
            }
        }
        catch {
            $checkResult.checks.npm = @{ status = "error" }
        }
    }
    else {
        $checkResult.checks.npm = @{ status = "not_found" }
    }
}

# 4. Git环境检查
function Test-GitEnvironment {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue

    if ($gitCmd) {
        try {
            Push-Location $projectDir
            $version = & git --version 2>&1
            $status = & git status --porcelain 2>&1
            Pop-Location

            $checkResult.checks.git = @{
                path = $gitCmd.Source
                version = $version
                hasChanges = ($status.Length -gt 0)
                status = "ok"
            }
        }
        catch {
            $checkResult.checks.git = @{ status = "error" }
        }
    }
    else {
        $checkResult.checks.git = @{ status = "not_found" }
        $checkResult.recommendations += "安装 Git"
        $checkResult.status = "warning"
    }
}

# 5. 项目依赖检查
function Test-ProjectDependencies {
    $requirementsFile = Join-Path $projectDir "requirements.txt"
    $packageJson = Join-Path $projectDir "package.json"

    if (Test-Path $requirementsFile) {
        $checkResult.checks.has_python_requirements = $true
    }

    if (Test-Path $packageJson) {
        $checkResult.checks.has_node_packages = $true
        $nodeModules = Join-Path $projectDir "node_modules"
        if (-not (Test-Path $nodeModules)) {
            $checkResult.recommendations += "运行 npm install 安装依赖"
            $checkResult.status = "warning"
        }
    }
}

# 6. 工具配置检查
function Test-ToolConfig {
    $configs = @(
        ".prettierrc", "prettier.config.js",
        "pyproject.toml", "setup.cfg",
        ".eslintrc.json", ".eslintrc.js"
    )

    $foundConfigs = @()
    foreach ($config in $configs) {
        $configPath = Join-Path $projectDir $config
        if (Test-Path $configPath) {
            $foundConfigs += $config
        }
    }

    $checkResult.checks.tool_configs = $foundConfigs

    if ($foundConfigs.Count -eq 0) {
        $checkResult.recommendations += "添加工具配置文件（.prettierrc, pyproject.toml等）"
    }
}

# 7. 目录结构检查
function Test-DirectoryStructure {
    $expectedDirs = @(".factory", "src", "tests")
    $foundDirs = @()

    foreach ($dir in $expectedDirs) {
        $dirPath = Join-Path $projectDir $dir
        if (Test-Path $dirPath) {
            $foundDirs += $dir
        }
    }

    $checkResult.checks.directory_structure = @{
        expected = $expectedDirs
        found = $foundDirs
        status = if ($foundDirs.Count -ge 2) { "ok" } else { "incomplete" }
    }
}

# 执行所有检查
Test-DiskSpace
Test-UvEnvironment
Test-PythonEnvironment
Test-NodeEnvironment
Test-GitEnvironment
Test-ProjectDependencies
Test-ToolConfig
Test-DirectoryStructure

# 输出结果
$jsonOutput = $checkResult | ConvertTo-Json -Depth 10 -Compress

# 检查是否有严重问题
if ($checkResult.issues.Count -gt 2 -or $checkResult.status -eq "error") {
    $checkResult.status = "warning"
}

if ($checkResult.status -eq "warning") {
    Write-Host "⚠️  环境检查完成，发现一些问题：" -ForegroundColor Yellow
    foreach ($issue in $checkResult.issues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
    if ($checkResult.recommendations.Count -gt 0) {
        Write-Host "`n建议操作：" -ForegroundColor Cyan
        foreach ($rec in $checkResult.recommendations) {
            Write-Host "  - $rec" -ForegroundColor Cyan
        }
    }
}
else {
    Write-Host "✅ 环境检查通过，系统就绪" -ForegroundColor Green
}

# 保存到临时文件供后续使用
$env:FACTORY_ENV_CHECK = $jsonOutput

exit 0
