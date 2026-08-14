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
if (-not (Test-Path (Join-Path $skillRoot "_common.ps1"))) { $skillRoot = "C:\.trae\skills\c-drive-cleaner" }
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
    $m = Get-PathLogicalMeasurement -Path $Item.FullName
    if ($m.Status -eq "ok") { return [int64]$m.Bytes }
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
$sessionId = Get-Date -Format "yyyyMMdd-HHmmss"
$sessionStarted = Get-Date
$driveFreeBefore = [int64]0
if (-not $preview) {
    $beforeDrive = New-Object IO.DriveInfo("C:\")
    $driveFreeBefore = [int64]$beforeDrive.AvailableFreeSpace
}
$auditRows = @()

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
                $beforeActual = Get-NtfsPathMeasurement -Path $item.FullName -MaxFiles 200000 -MaxSeconds 60
                $ok = $false
                try {
                    if ($item.PSIsContainer) {
                        $ok = Remove-Directory -Path $item.FullName -AllowedRoots @($root) -ShowProgress
                    } else {
                        $ok = Remove-SafeFile -Path $item.FullName -AllowedRoots @($root)
                    }
                    if ($ok) { $deletedCount++ }
                } catch {
                    Write-Host "     Cleanup failed: $($_.Exception.Message)" -ForegroundColor Red
                }
                $afterActual = Get-NtfsPathMeasurement -Path $item.FullName -MaxFiles 200000 -MaxSeconds 60
                $auditRows += [pscustomobject]@{
                    targetId = [string]$target.id
                    targetName = [string]$target.name
                    path = $item.FullName
                    deleted = [bool]$ok
                    before = [pscustomobject]@{
                        status=$beforeActual.Status; logicalBytes=[int64]$beforeActual.EntryLogicalBytes
                        allocatedBytes=[int64]$beforeActual.AllocatedBytes; fileCount=[int]$beforeActual.FileCount
                    }
                    after = [pscustomobject]@{
                        status=$afterActual.Status; logicalBytes=[int64]$afterActual.EntryLogicalBytes
                        allocatedBytes=[int64]$afterActual.AllocatedBytes; fileCount=[int]$afterActual.FileCount
                    }
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
    $driveAfter = New-Object IO.DriveInfo("C:\")
    $driveFreeDelta = [int64]$driveAfter.AvailableFreeSpace - $driveFreeBefore
    $allocatedReclaim = [int64](($auditRows | ForEach-Object { [int64]$_.before.allocatedBytes - [int64]$_.after.allocatedBytes } | Measure-Object -Sum).Sum)
    $sessionDir = Join-Path $skillRoot "reports\cleanup-sessions"
    if (-not (Test-Path -LiteralPath $sessionDir)) { New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null }
    $baselineTargets = @($auditRows | ForEach-Object {
        [pscustomobject]@{ path=$_.path; logicalStatus=$_.before.status; logicalBytes=$_.before.logicalBytes; allocatedStatus=$_.before.status; allocatedBytes=$_.before.allocatedBytes; fileCount=$_.before.fileCount }
    })
    $immediateTargets = @($auditRows | ForEach-Object {
        [pscustomobject]@{ path=$_.path; logicalStatus=$_.after.status; logicalBytes=$_.after.logicalBytes; allocatedStatus=$_.after.status; allocatedBytes=$_.after.allocatedBytes; fileCount=$_.after.fileCount }
    })
    $session = [pscustomobject]@{
        schema = 1
        sessionId = $sessionId
        label = "targeted optimization"
        createdAt = $sessionStarted.ToString("o")
        completedAt = (Get-Date).ToString("o")
        baseline = [pscustomobject]@{ driveFreeBytes=$driveFreeBefore; targets=$baselineTargets }
        cleanup = [pscustomobject]@{
            matchedLogicalBytes=$totalBytes; measuredAllocatedReclaimBytes=$allocatedReclaim
            actualDriveFreeDeltaBytes=$driveFreeDelta; processed=$deletedCount; matched=$matchedCount; targets=$auditRows
        }
        checkpoints = @([pscustomobject]@{
            timestamp=(Get-Date).ToString("o"); elapsedMinutes=[math]::Round(((Get-Date)-$sessionStarted).TotalMinutes,2)
            stage="immediate"; driveFreeBytes=[int64]$driveAfter.AvailableFreeSpace; driveFreeDeltaBytes=$driveFreeDelta; targets=$immediateTargets
        })
    }
    $sessionPath = Join-Path $sessionDir "cleanup-$sessionId.json"
    $session | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $sessionPath -Encoding UTF8
    Write-Host "Actual C-drive free-space delta: $([math]::Round($driveFreeDelta/1GB,3)) GB" -ForegroundColor Cyan
    Write-Host "Measured allocated-byte reclaim: $([math]::Round($allocatedReclaim/1GB,3)) GB" -ForegroundColor Cyan
    Write-Host "Cleanup session: $sessionPath" -ForegroundColor Green
    Write-Host "Later regeneration check: .\track-regeneration.ps1 -Mode check -SessionId $sessionId" -ForegroundColor DarkGray
}
