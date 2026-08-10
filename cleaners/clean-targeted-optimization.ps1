# clean-targeted-optimization.ps1 - targeted cleanup
# Preview by default. Deletion requires -ReallyDelete.

param(
    [ValidateSet("safe", "cautious", "all")]
    [string]$RiskLevel = "safe",
    [string]$Targets = "",
    [switch]$ReallyDelete,
    [switch]$WhatIf
)

$cleanerRoot = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $cleanerRoot
if (-not (Test-Path (Join-Path $skillRoot "_common.ps1"))) {
    throw "Skill root could not be resolved from the script location."
}
. (Join-Path $skillRoot "_common.ps1")

$configPath = Join-Path $skillRoot "extensions\targeted-optimization.json"
if (-not (Test-Path $configPath)) { throw "Targeted optimization config not found: $configPath" }
$config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$preview = $WhatIf -or -not $ReallyDelete
$selected = if ($Targets) { @($Targets -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @() }

function Resolve-TargetMatches {
    param([string]$Root, [string]$Pattern)
    $candidate = Join-Path $Root $Pattern
    if ($Pattern -match '[*?]') {
        return @(Get-ChildItem -Path $candidate -Force -ErrorAction SilentlyContinue)
    }
    if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) {
        return @(Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue)
    }
    return @()
}

function Get-TargetBytes {
    param([System.IO.FileSystemInfo]$Item)
    if (-not $Item) { return [int64]0 }
    if (-not $Item.PSIsContainer) { return [int64]$Item.Length }
    $m = Get-ChildItem -LiteralPath $Item.FullName -Force -File -Recurse -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    if ($m.Sum) { return [int64]$m.Sum }
    return [int64]0
}

function Test-WithinRoot {
    param([string]$Root, [string]$Path)
    try {
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        $pathFull = [IO.Path]::GetFullPath($Path)
        return $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Test-TargetProcessRunning {
    param($Target)
    $names = @($Target.processes | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if ($names.Count -eq 0) { return $false }
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $names -contains $_.ProcessName.ToLowerInvariant()
    } | Select-Object -First 1
    if ($running) {
        Write-Host "Target skipped: process still running ($($running.ProcessName), PID $($running.Id))" -ForegroundColor Yellow
        return $true
    }
    return $false
}

Write-Host "===== Targeted optimization cleanup =====" -ForegroundColor Cyan
if ($preview) {
    Write-Host "Preview mode: no files will be deleted. Add -ReallyDelete to execute." -ForegroundColor Yellow
} else {
    Write-Host "Execution mode: matched paths will be permanently deleted." -ForegroundColor Red
}

$totalBytes = [int64]0
$matchedCount = 0
$deletedCount = 0

foreach ($target in @($config.targets)) {
    if ($selected.Count -gt 0 -and $target.id -notin $selected -and $target.name -notin $selected) { continue }
    if ($RiskLevel -eq "safe" -and $target.risk -ne "safe") { continue }
    if ($RiskLevel -eq "cautious" -and $target.risk -eq "forbidden") { continue }

    $root = Expand-EnvPath $target.root
    if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }
    if (-not $preview -and (Test-TargetProcessRunning $target)) { continue }

    $seen = @{}
    foreach ($pattern in @($target.paths)) {
        foreach ($item in @(Resolve-TargetMatches -Root $root -Pattern $pattern)) {
            if (-not $item) { continue }
            if (-not (Test-WithinRoot -Root $root -Path $item.FullName)) { continue }
            $key = $item.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true

            $bytes = Get-TargetBytes $item
            if ($bytes -le 0) { continue }
            $matchedCount++
            $totalBytes += $bytes
            $size = if ($bytes -ge 1GB) { "$([math]::Round($bytes / 1GB, 2)) GB" } else { "$([math]::Round($bytes / 1MB, 0)) MB" }
            Write-Host "  [$($target.risk)] $($target.name) / $($item.Name): $size" -ForegroundColor $(if ($target.risk -eq "safe") { "Green" } else { "Yellow" })
            Write-Host "     Path: $($item.FullName)" -ForegroundColor DarkGray
            Write-Host "     Note: $($target.note)" -ForegroundColor DarkGray

            if (-not $preview) {
                try {
                    if ($item.PSIsContainer) {
                        $ok = Remove-Directory -Path $item.FullName -ShowProgress
                    } else {
                        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                        $ok = -not (Test-Path -LiteralPath $item.FullName -ErrorAction SilentlyContinue)
                    }
                    if ($ok) { $deletedCount++ }
                } catch {
                    Write-Host "     Cleanup failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}

$total = if ($totalBytes -ge 1GB) { "$([math]::Round($totalBytes / 1GB, 2)) GB" } else { "$([math]::Round($totalBytes / 1MB, 0)) MB" }
Write-Host ""
if ($preview) {
    Write-Host "Preview total: $total across $matchedCount item(s)." -ForegroundColor Yellow
} else {
    Write-Host "Processed: $deletedCount/$matchedCount item(s); matched total: $total." -ForegroundColor Green
}
