# track-regeneration.ps1 - cleanup-session checkpoints for cache regeneration
# Start records a before-action baseline. Check records immediate/5m/1h/24h state.

param(
    [ValidateSet("start", "check")]
    [string]$Mode = "check",
    [string]$Paths = "",
    [string]$SessionId = "",
    [string]$Label = "manual cleanup",
    [int]$MaxFiles = 200000,
    [int]$MaxSeconds = 60
)

$skillRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $skillRoot "_common.ps1")
$sessionDir = Join-Path $skillRoot "reports\cleanup-sessions"
if (-not (Test-Path -LiteralPath $sessionDir)) { New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null }

function Get-RegenMeasurement {
    param([string]$Path)
    $logical = Get-PathLogicalMeasurement -Path $Path
    $allocated = Get-NtfsPathMeasurement -Path $Path -MaxFiles $MaxFiles -MaxSeconds $MaxSeconds
    return [pscustomobject]@{
        path = $Path
        logicalStatus = $logical.Status
        logicalBytes = [int64]$logical.Bytes
        allocatedStatus = $allocated.Status
        allocatedBytes = [int64]$allocated.AllocatedBytes
        fileCount = [int]$allocated.FileCount
    }
}

function Get-CheckpointStage {
    param([double]$Minutes)
    if ($Minutes -lt 5) { return "immediate" }
    if ($Minutes -lt 60) { return "five-minute-plus" }
    if ($Minutes -lt 1440) { return "one-hour-plus" }
    return "twenty-four-hour-plus"
}

if ($Mode -eq "start") {
    $resolved = @($Paths -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { Expand-EnvPath $_ })
    if ($resolved.Count -eq 0) { throw "-Paths is required for Mode=start" }
    if (-not $SessionId) { $SessionId = Get-Date -Format "yyyyMMdd-HHmmss" }
    $drive = New-Object IO.DriveInfo("C:\")
    $baseline = @($resolved | ForEach-Object { Get-RegenMeasurement $_ })
    $session = [pscustomobject]@{
        schema = 1
        sessionId = $SessionId
        label = $Label
        createdAt = (Get-Date).ToString("o")
        baseline = [pscustomobject]@{ driveFreeBytes=[int64]$drive.AvailableFreeSpace; targets=$baseline }
        checkpoints = @()
    }
    $path = Join-Path $sessionDir "cleanup-$SessionId.json"
    $session | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $path -Encoding UTF8
    Write-Host "Regeneration baseline recorded: $path" -ForegroundColor Green
    return
}

if (-not $SessionId) {
    $latest = Get-ChildItem -LiteralPath $sessionDir -Filter "cleanup-*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "No cleanup session found. Run Mode=start first." }
    $sessionPath = $latest.FullName
} else {
    $sessionPath = Join-Path $sessionDir "cleanup-$SessionId.json"
}
if (-not (Test-Path -LiteralPath $sessionPath)) { throw "Cleanup session not found: $sessionPath" }
$session = Get-Content -LiteralPath $sessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$created = [datetime]$session.createdAt
$now = Get-Date
$minutes = ($now - $created).TotalMinutes
$drive = New-Object IO.DriveInfo("C:\")
$pathsToCheck = @($session.baseline.targets | ForEach-Object { $_.path })
$current = @($pathsToCheck | ForEach-Object { Get-RegenMeasurement $_ })
$referenceTargets = if (@($session.checkpoints).Count -gt 0) { @($session.checkpoints[0].targets) } else { @($session.baseline.targets) }
$hasPostCleanupReference = @($session.checkpoints).Count -gt 0
$checkpointTargets = @()
foreach ($row in $current) {
    $baselineRow = @($session.baseline.targets | Where-Object { $_.path -eq $row.path }) | Select-Object -First 1
    $referenceRow = @($referenceTargets | Where-Object { $_.path -eq $row.path }) | Select-Object -First 1
    $checkpointTargets += [pscustomobject]@{
        path=$row.path; logicalStatus=$row.logicalStatus; logicalBytes=$row.logicalBytes
        allocatedStatus=$row.allocatedStatus; allocatedBytes=$row.allocatedBytes; fileCount=$row.fileCount
        deltaFromBaselineBytes=([int64]$row.allocatedBytes - [int64]$baselineRow.allocatedBytes)
        regeneratedFromImmediateBytes=if ($hasPostCleanupReference) { [int64]$row.allocatedBytes - [int64]$referenceRow.allocatedBytes } else { $null }
    }
}
$checkpoint = [pscustomobject]@{
    timestamp = $now.ToString("o")
    elapsedMinutes = [math]::Round($minutes,2)
    stage = Get-CheckpointStage $minutes
    driveFreeBytes = [int64]$drive.AvailableFreeSpace
    driveFreeDeltaBytes = [int64]$drive.AvailableFreeSpace - [int64]$session.baseline.driveFreeBytes
    targets = $checkpointTargets
}
$checkpoints = @($session.checkpoints) + @($checkpoint)
$session.checkpoints = $checkpoints
$session | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $sessionPath -Encoding UTF8

Write-Host "===== Regeneration checkpoint: $($checkpoint.stage) =====" -ForegroundColor Cyan
Write-Host "Drive free delta from baseline: $([math]::Round($checkpoint.driveFreeDeltaBytes/1GB,3)) GB" -ForegroundColor White
foreach ($row in $checkpointTargets) {
    if ($hasPostCleanupReference) {
        $delta = [int64]$row.regeneratedFromImmediateBytes
        $label = "regenerated from immediate"
    } else {
        $delta = [int64]$row.deltaFromBaselineBytes
        $label = "change from pre-cleanup baseline"
    }
    Write-Host "  $($row.path): allocated $([math]::Round($row.allocatedBytes/1GB,3)) GB; $label $([math]::Round($delta/1GB,3)) GB [$($row.allocatedStatus)]" -ForegroundColor $(if ($delta -gt 100MB) { "Yellow" } else { "DarkGray" })
}
Write-Host "Checkpoint recorded: $sessionPath" -ForegroundColor Green
