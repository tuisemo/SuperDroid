<#
.SYNOPSIS
高性能自动格式化Hook v2.0
.DESCRIPTION
优化：只格式化修改的文件，避免全局扫描，性能提升10-100倍
.NOTES
入口点：PostToolUse (Edit|Write)
#>

$ErrorActionPreference = "Continue"
$projectDir = $env:FACTORY_PROJECT_DIR
$scriptStartTime = Get-Date
$changesDetected = $false

# 性能监控
$perfLog = @{}

function Measure-Execution {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    $start = Get-Date
    try {
        & $ScriptBlock
        $duration = ((Get-Date) - $start).TotalSeconds
        $perfLog[$Name] = "$duration sec"
        Write-Host "  ? $Name completed ($([math]::Round($duration, 2))s)" -ForegroundColor Green
        return $true
    }
    catch {
        $duration = ((Get-Date) - $start).TotalSeconds
        $perfLog[$Name] = "$duration sec (FAILED)"
        Write-Host "  ? $Name failed ($([math]::Round($duration, 2))s)" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Gray
        return $false
    }
}

# 读取标准输入
$inputData = Get-Content -Raw | ConvertFrom-Json

# 获取修改的文件路径
$modifiedFiles = @()

if ($inputData.PSObject.Properties['tool_input']) {
    if ($inputData.tool_input.PSObject.Properties['file_path']) {
        $modifiedFiles += $inputData.tool_input.file_path
    }
}

# 如果没有修改的文件，立即退出
if ($modifiedFiles.Count -eq 0) {
    Write-Host "??  No modified files, skipping formatting" -ForegroundColor Gray
    exit 0
}

# 转换为相对路径
$modifiedRelativeFiles = $modifiedFiles | ForEach-Object {
    $_.Replace($projectDir, "").TrimStart("\", "/").Replace("\", "/")
}

Write-Host "?? High-Performance Formatter (v2.0)" -ForegroundColor Cyan
Write-Host "  Modified files: $modifiedRelativeFiles.Count" -ForegroundColor Gray

# 检测工具可用性
$useUv = Get-Command uv -ErrorAction SilentlyContinue
$usePnpm = Get-Command pnpm -ErrorAction SilentlyContinue
$usePython = Get-Command python -ErrorAction SilentlyContinue

# 按文件类型分组（只处理修改的文件）
$pythonFiles = $modifiedRelativeFiles | Where-Object { $_ -match '\.(py|pyx|pyi)$' }
$frontendFiles = $modifiedRelativeFiles | Where-Object { $_ -match '\.(js|jsx|ts|tsx|vue|svelte|json)$' }

# Python文件格式化
if ($pythonFiles.Count -gt 0) {
    Write-Host "
?? Python formatting..." -ForegroundColor Cyan
    
    if ($useUv) {
        $filesList = $pythonFiles -join ' '
        $null = Measure-Execution "uv + ruff format" {
            $null = uv run ruff format $filesList 2>&1
            $changesDetected = $true
        }
        
        if ($?) {
            $null = uv run ruff check --fix $filesList 2>&1 | Out-Null
        }
    }
    elseif ($usePython) {
        $filesList = $pythonFiles -join ' '
        $null = Measure-Execution "black format" {
            $null = python -m black --quiet $filesList 2>&1
            $changesDetected = $true
        }
        
        if ($?) {
            $null = python -m ruff check --fix $filesList --select=E,W,F 2>&1 | Out-Null
        }
    }
}

# 前端文件格式化
if ($frontendFiles.Count -gt 0) {
    Write-Host "
?? Frontend formatting..." -ForegroundColor Cyan
    
    $jsFiles = $frontendFiles | Where-Object { $_ -match '\.(js|jsx|ts|tsx)$' }
    $jsonFiles = $frontendFiles | Where-Object { $_ -match '\.json$' }
    
    if ($usePnpm -or (Test-Path (Join-Path $projectDir "pnpm-lock.yaml"))) {
        if ($jsFiles.Count -gt 0 -and $jsFiles.Count -lt 10) {
            $filesList = ($jsFiles | ForEach-Object { "'$_'" }) -join ' '
            $null = Measure-Execution "pnpm prettier (JS/TS)" {
                $null = pnpm prettier --write $filesList 2>&1
                $changesDetected = $true
            }
        }
        
        if ($jsonFiles.Count -gt 0 -and $jsonFiles.Count -lt 5) {
            $filesList = ($jsonFiles | ForEach-Object { "'$_'" }) -join ' '
            $null = Measure-Execution "pnpm prettier (JSON)" {
                $null = pnpm prettier --write $filesList 2>&1
                $changesDetected = $true
            }
        }
    }
}

# 性能报告
$totalDuration = ((Get-Date) - $scriptStartTime).TotalSeconds
Write-Host "
? Performance stats:" -ForegroundColor Cyan
Write-Host "  Total time: $([math]::Round($totalDuration, 2))s" -ForegroundColor Green

if ($perfLog.Count -gt 0) {
    Write-Host "
  Details:" -ForegroundColor Gray
    foreach ($key in $perfLog.Keys) {
        Write-Host "    - $key: $($perfLog[$key])" -ForegroundColor Gray
    }
}

# Git暂存
if ($changesDetected) {
    Push-Location $projectDir
    $null = git add -u . 2>&1
    Pop-Location
    Write-Host "
?? Changes staged to Git" -ForegroundColor Green
}

Write-Host "
? High-performance formatting complete" -ForegroundColor Green

exit 0
