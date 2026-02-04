#!/usr/bin/env pwsh
<#
.SYNOPSIS
自动格式化Hook：使用uv(python)和pnpm(前端)进行代码格式化
.DESCRIPTION
支持uv/black/ruff for Python, pnpm/prettier/eslint for JS/TS
.NOTES
入口点：PostToolUse (Edit|Write)
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR
$changesDetected = $false

# 进入项目目录
Push-Location $projectDir

# 检测工具可用性
$useUv = Get-Command uv -ErrorAction SilentlyContinue
$usePnpm = Get-Command pnpm -ErrorAction SilentlyContinue
$usePython = Get-Command python -ErrorAction SilentlyContinue

# Python文件格式化
$pythonFiles = @(".py", ".pyx", ".pyi")
$hasPythonFiles = $false

foreach ($ext in $pythonFiles) {
    if (Get-ChildItem -Path $projectDir -Filter "*$ext" -Recurse -ErrorAction SilentlyContinue) {
        $hasPythonFiles = $true
        break
    }
}

if ($hasPythonFiles) {
    Write-Host "🐍 Python 文件格式化..." -ForegroundColor Cyan

    # 优先使用 uv + ruff（更快）
    if ($useUv) {
        Write-Host "  使用 uv + ruff..." -ForegroundColor Gray
        try {
            # uv run ruff format（替代black）
            $null = uv run ruff format . 2>&1
            # uv run ruff check --fix
            $null = uv run ruff check --fix . 2>&1
            Write-Host "  ✅ uv + ruff 格式化完成" -ForegroundColor Green
            $changesDetected = $true
        }
        catch {
            Write-Host "  ⚠️  uv + ruff 运行失败，尝试 fallback..." -ForegroundColor Yellow
            $useUv = $false
        }
    }

    # Fallback：使用 python + black/ruff
    if (-not $useUv -and $usePython) {
        Write-Host "  使用 python + black..." -ForegroundColor Gray
        try {
            # Black 格式化
            $null = python -m black --quiet . 2>&1
            Write-Host "  ✅ black 格式化完成" -ForegroundColor Green
            $changesDetected = $true
        }
        catch {
            Write-Host "  ℹ️  未安装 black，跳过" -ForegroundColor Gray
        }

        # Ruff lint fix
        try {
            $null = python -m ruff check --fix . 2>&1
            Write-Host "  ✅ ruff check --fix 完成" -ForegroundColor Green
            $changesDetected = $true
        }
        catch {
            Write-Host "  ℹ️  未安装 ruff，跳过" -ForegroundColor Gray
        }
    }

    # 类型检查（可选，不阻塞）
    try {
        if ($useUv) {
            $null = uv run mypy . 2>&1 | Out-Null
        }
        elseif ($usePython) {
            $null = python -m mypy . 2>&1 | Out-Null
        }
    }
    catch {
        # mycp 检查失败不影响格式化
    }
}

# 前端文件格式化
$frontendFiles = @(".js", ".jsx", ".ts", ".tsx", ".vue", ".svelte", ".json")
$hasFrontendFiles = $false

foreach ($ext in $frontendFiles) {
    if (Get-ChildItem -Path $projectDir -Filter "*$ext" -Recurse -ErrorAction SilentlyContinue) {
        $hasFrontendFiles = $true
        break
    }
}

if ($hasFrontendFiles) {
    Write-Host "📦 前端文件格式化..." -ForegroundColor Cyan

    # 使用 pnpm + prettier
    if ($usePnpm -or Test-Path (Join-Path $projectDir "pnpm-lock.yaml")) {
        Write-Host "  使用 pnpm + prettier..." -ForegroundColor Gray
        try {
            $null = pnpm prettier --write "**/*.{js,jsx,ts,tsx,vue,json}" 2>&1
            Write-Host "  ✅ pnpm prettier 格式化完成" -ForegroundColor Green
            $changesDetected = $true
        }
        catch {
            Write-Host "  ℹ️  pnpm prettier 运行失败，尝试 npx..." -ForegroundColor Yellow
        }
    }
    else {
        # Fallback: npx prettier
        Write-Host "  使用 npx prettier..." -ForegroundColor Gray
        try {
            $null = npx prettier --write "**/*.{js,jsx,ts,tsx,vue,json}" 2>&1
            Write-Host "  ✅ prettier 格式化完成" -ForegroundColor Green
            $changesDetected = $true
        }
        catch {
            Write-Host "  ℹ️  prettier 未安装，跳过" -ForegroundColor Gray
        }
    }

    # ESLint修复（可选）
    if (Test-Path (Join-Path $projectDir "node_modules" ".bin" "eslint") -or $usePnpm) {
        try {
            Write-Host "  运行 ESLint 修复..." -ForegroundColor Gray
            if ($usePnpm) {
                $null = pnpm eslint --fix "**/*.{js,jsx,ts,tsx}" 2>&1 | Out-Null
            }
            else {
                $null = npx eslint --fix "**/*.{js,jsx,ts,tsx}" 2>&1 | Out-Null
            }
            Write-Host "  ✅ ESLint 修复完成" -ForegroundColor Green
        }
        catch {
            Write-Host "  ℹ️  ESLint 修复跳过" -ForegroundColor Gray
        }
    }
}

# Markdown文件
$markdownFiles = Get-ChildItem -Path $projectDir -Filter "*.md" -Recurse -ErrorAction SilentlyContinue
if ($markdownFiles) {
    Write-Host "📄 Markdown 文件格式化..." -ForegroundColor Cyan
    try {
        $null = pnpm prettier --write "**/*.md" 2>&1
        Write-Host "  ✅ Markdown 格式化完成" -ForegroundColor Green
        $changesDetected = $true
    }
    catch {
        # 跳过Markdown格式化
    }
}

# Git暂存变更
if ($changesDetected) {
    Push-Location $projectDir
    $null = git add -u . 2>&1
    Pop-Location
    Write-Host "📝 变更已暂存到 Git" -ForegroundColor Green
}

Pop-Location

Write-Host "✨ 自动格式化完成" -ForegroundColor Green

exit 0
