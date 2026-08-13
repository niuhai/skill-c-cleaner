# track-growth.ps1 - hierarchy-aware C-drive growth tracking
# Read-only by default. Add -Record to persist a compatible baseline.

param(
    [ValidateSet("compare", "snapshot")]
    [string]$Mode = "compare",
    [switch]$Record,
    [switch]$UseCachedSnapshot,
    [string]$HistoryDirectory = ""
)

$skillRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $skillRoot "_common.ps1")
$configPath = Join-Path $skillRoot "extensions\growth-watch.json"
if (-not (Test-Path -LiteralPath $configPath)) { throw "Growth watch config not found: $configPath" }
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

if (-not $HistoryDirectory) { $HistoryDirectory = Join-Path $skillRoot "reports\growth" }
$latestPath = Join-Path $HistoryDirectory "latest.json"
$historyPath = Join-Path $HistoryDirectory "history.jsonl"

function Resolve-GrowthPaths {
    param([string]$Path)
    $expanded = Expand-EnvPath $Path
    if ($expanded -match '[*?]') {
        return @(Get-ChildItem -Path $expanded -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    }
    # Return exact paths even when Test-Path is false: protected root files such
    # as pagefile.sys may still be enumerable by Get-PathLogicalMeasurement.
    return @($expanded)
}

function Measure-GrowthTarget {
    param($Target)
    $nativeRows = @($Global:CDriveNativePathTotals | Where-Object { $_.Id -eq [string]$Target.id })
    if ($nativeRows.Count -gt 0) {
        $nativeBytes = [int64](($nativeRows | Measure-Object -Property Bytes -Sum).Sum)
        $nativeFiles = [int64](($nativeRows | Measure-Object -Property FileCount -Sum).Sum)
        $nativeStatus = if (@($nativeRows | Where-Object Partial).Count -gt 0) { "partial" }
            elseif (@($nativeRows | Where-Object Seen).Count -gt 0) { "ok" }
            else { "missing" }
        return [pscustomobject]@{
            Status = $nativeStatus
            Bytes = $nativeBytes
            FileCount = $nativeFiles
            Evidence = "reused native F scan; no second directory traversal"
            Paths = @($nativeRows.Path | Select-Object -Unique)
        }
    }
    $paths = @(Resolve-GrowthPaths ([string]$Target.path))
    if ($paths.Count -eq 0) {
        return [pscustomobject]@{ Status="missing"; Bytes=[int64]0; FileCount=[int64]0; Evidence="no matching path"; Paths=@() }
    }
    $bytes = [int64]0
    $files = [int64]0
    $statuses = @()
    $evidence = @()
    foreach ($path in $paths) {
        $m = Get-PathLogicalMeasurement -Path $path
        $bytes += [int64]$m.Bytes
        $files += [int64]$m.FileCount
        $statuses += $m.Status
        $evidence += $m.Evidence
    }
    $status = if (@($statuses | Where-Object { $_ -eq "partial" }).Count -gt 0) { "partial" }
        elseif (@($statuses | Where-Object { $_ -eq "inaccessible" }).Count -gt 0) { "partial" }
        else { "ok" }
    return [pscustomobject]@{ Status=$status; Bytes=$bytes; FileCount=$files; Evidence=($evidence -join '; '); Paths=$paths }
}

function Format-GrowthSize {
    param([int64]$Bytes)
    $sign = if ($Bytes -gt 0) { "+" } elseif ($Bytes -lt 0) { "-" } else { "" }
    $absolute = [math]::Abs([double]$Bytes)
    if ($absolute -ge 1GB) { return ("{0}{1:N2} GB" -f $sign, ($absolute / 1GB)) }
    return ("{0}{1:N0} MB" -f $sign, ($absolute / 1MB))
}

$now = Get-Date
$previous = $null
if (Test-Path -LiteralPath $latestPath) {
    try { $previous = Get-Content -LiteralPath $latestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $previous = $null }
}
$schemaCompatible = $previous -and ([int]$previous.schema -eq 2) -and ([int]$previous.measurementVersion -eq [int]$config.measurementVersion)
$currentMeasurementSource = if (@($Global:CDriveNativePathTotals).Count -gt 0) { "native-f-v1" } else { "robocopy-v2" }
$previousMeasurementSource = if ($previous -and $previous.measurementSource) { [string]$previous.measurementSource } else { "robocopy-v2" }
$compatible = $schemaCompatible -and ($previousMeasurementSource -eq $currentMeasurementSource)

if ($UseCachedSnapshot) {
    Write-Host "===== C-drive growth tracking (cached) =====" -ForegroundColor Cyan
    if (-not $schemaCompatible) {
        Write-Host "No compatible growth snapshot is available; run track-growth.ps1 -Record once." -ForegroundColor Yellow
        return
    }
    $snapshotAge = (Get-Date) - [datetime]$previous.timestamp
    Write-Host ("Snapshot age: {0:N1} hours; source: {1}; fast mode does not rescan parent and child trees." -f $snapshotAge.TotalHours, $previousMeasurementSource) -ForegroundColor DarkGray
    Write-Host "These values describe the recorded snapshot, not current reclaimable capacity." -ForegroundColor DarkGray
    Write-Host "`nCoverage roots (recorded, non-overlapping):" -ForegroundColor White
    foreach ($row in @($previous.targets | Where-Object { $_.role -eq "coverage" } | Sort-Object bytes -Descending)) {
        Write-Host ("  {0,-28} {1,12}  [{2}]" -f $row.name, (Format-GrowthSize ([int64]$row.bytes)).TrimStart('+'), $row.status) -ForegroundColor DarkGray
    }
    Write-Host "`nLargest detail paths (recorded, overlapping):" -ForegroundColor White
    foreach ($row in @($previous.targets | Where-Object { $_.role -eq "detail" -and $_.bytes -gt 0 } | Sort-Object bytes -Descending | Select-Object -First 15)) {
        Write-Host ("  {0,-28} {1,12}  parent={2}" -f $row.name, (Format-GrowthSize ([int64]$row.bytes)).TrimStart('+'), $row.parentId) -ForegroundColor DarkGray
    }
    if ($null -eq $Global:CDriveScannerMetadata) { $Global:CDriveScannerMetadata = @{} }
    $Global:CDriveScannerMetadata["GR"] = @{
        mode = "cached"
        snapshot_timestamp = [string]$previous.timestamp
        measurement_source = $previousMeasurementSource
        age_hours = [math]::Round($snapshotAge.TotalHours, 3)
        accounting = "inventory-only"
    }
    return
}

$drive = New-Object System.IO.DriveInfo("C:\")
$currentUsed = [int64]($drive.TotalSize - $drive.AvailableFreeSpace)
$previousUsed = if ($compatible) { [int64]$previous.drive.usedBytes } else { [int64]0 }
$driveDelta = if ($compatible) { $currentUsed - $previousUsed } else { [int64]0 }
$elapsedDays = if ($compatible) { [math]::Max(0.01, ($now - [datetime]$previous.timestamp).TotalDays) } else { 0 }

$rows = @()
foreach ($target in @($config.targets)) {
    $measurement = Measure-GrowthTarget $target
    $old = $null
    if ($compatible) { $old = @($previous.targets | Where-Object { $_.id -eq $target.id }) | Select-Object -First 1 }
    $comparableStatuses = @("ok", "partial", "missing")
    $oldUsable = $old -and ($old.status -eq $measurement.Status) -and ($measurement.Status -in $comparableStatuses)
    $delta = if ($oldUsable) { [int64]$measurement.Bytes - [int64]$old.bytes } else { $null }
    $rate = if ($null -ne $delta -and $elapsedDays -ge 0.5) { [math]::Round(($delta / 1GB) / $elapsedDays, 3) } else { $null }
    $rows += [pscustomobject]@{
        id = [string]$target.id
        name = [string]$target.name
        configuredPath = [string]$target.path
        resolvedPaths = @($measurement.Paths)
        kind = [string]$target.kind
        role = [string]$target.role
        parentId = [string]$target.parentId
        status = $measurement.Status
        evidence = $measurement.Evidence
        bytes = [int64]$measurement.Bytes
        fileCount = [int64]$measurement.FileCount
        deltaBytes = $delta
        growthGBPerDay = $rate
        rateReliable = ($null -ne $rate)
    }
}

$coverageRows = @($rows | Where-Object { $_.role -eq "coverage" })
$coverageComparable = @($coverageRows | Where-Object { $null -ne $_.deltaBytes })
$coverageDelta = if ($coverageComparable.Count -gt 0) { [int64](($coverageComparable | Measure-Object -Property deltaBytes -Sum).Sum) } else { [int64]0 }
$coverageComplete = $compatible -and $coverageComparable.Count -eq $coverageRows.Count
$unexplainedDelta = if ($coverageComplete) { $driveDelta - $coverageDelta } else { $null }
$tolerance = [int64][math]::Max(1GB, [math]::Abs([double]$driveDelta) * 0.35)
$hasPartialCoverage = @($coverageRows | Where-Object { $_.status -eq "partial" }).Count -gt 0
$reconciliationStatus = if (-not $compatible) { "new-baseline-required" }
    elseif (-not $coverageComplete) { "partial-coverage" }
    elseif ([math]::Abs([double]$unexplainedDelta) -le $tolerance -and $hasPartialCoverage) { "consistent-partial" }
    elseif ([math]::Abs([double]$unexplainedDelta) -le $tolerance) { "consistent" }
    else { "measurement-mismatch" }

$snapshot = [pscustomobject]@{
    schema = 2
    measurementVersion = [int]$config.measurementVersion
    measurementSource = $currentMeasurementSource
    timestamp = $now.ToString("o")
    drive = [pscustomobject]@{ totalBytes=[int64]$drive.TotalSize; freeBytes=[int64]$drive.AvailableFreeSpace; usedBytes=$currentUsed }
    reconciliation = [pscustomobject]@{
        status = $reconciliationStatus
        driveDeltaBytes = if ($compatible) { $driveDelta } else { $null }
        coverageDeltaBytes = if ($coverageComplete) { $coverageDelta } else { $null }
        unexplainedDeltaBytes = $unexplainedDelta
        toleranceBytes = $tolerance
        note = "Only role=coverage targets are summed. Detail targets overlap their parents and are never added to totals."
    }
    targets = @($rows | ForEach-Object {
        [pscustomobject]@{
            id=$_.id; name=$_.name; configuredPath=$_.configuredPath; resolvedPaths=$_.resolvedPaths
            kind=$_.kind; role=$_.role; parentId=$_.parentId; status=$_.status; evidence=$_.evidence
            bytes=$_.bytes; fileCount=$_.fileCount
        }
    })
}

Write-Host "===== C-drive hierarchy-aware growth tracking =====" -ForegroundColor Cyan
if (-not $compatible) {
    if ($previous) { Write-Host "Previous baseline is incompatible with $currentMeasurementSource; deltas are intentionally suppressed." -ForegroundColor Yellow }
    else { Write-Host "No previous compatible baseline; this run can establish one." -ForegroundColor Yellow }
} else {
    Write-Host "Drive used delta: $(Format-GrowthSize $driveDelta) over $([math]::Round($elapsedDays,2)) day(s)" -ForegroundColor White
    if ($coverageComplete) {
        $color = if ($reconciliationStatus -eq "consistent") { "Green" } else { "Yellow" }
        Write-Host "Coverage-root delta: $(Format-GrowthSize $coverageDelta); unexplained: $(Format-GrowthSize $unexplainedDelta) [$reconciliationStatus]" -ForegroundColor $color
    } else { Write-Host "Coverage reconciliation is partial; do not trust aggregate attribution." -ForegroundColor Yellow }

    $growth = @($rows | Where-Object { $_.role -eq "detail" -and $null -ne $_.deltaBytes -and $_.deltaBytes -ge 1MB } | Sort-Object deltaBytes -Descending)
    $shrink = @($rows | Where-Object { $_.role -eq "detail" -and $null -ne $_.deltaBytes -and $_.deltaBytes -le -1MB } | Sort-Object deltaBytes)
    Write-Host "Detail growth (never summed with parents):" -ForegroundColor White
    if ($growth.Count -eq 0) { Write-Host "  No detail path grew by at least 1 MB." -ForegroundColor Green }
    foreach ($row in $growth) {
        $rateText = if ($row.rateReliable) { ("{0:N2} GB/day" -f $row.growthGBPerDay) } else { "rate pending" }
        Write-Host "  $(Format-GrowthSize $row.deltaBytes)  $($row.name) ($rateText)" -ForegroundColor Yellow
    }
    if ($shrink.Count -gt 0) {
        Write-Host "Detail shrink:" -ForegroundColor White
        foreach ($row in $shrink) { Write-Host "  $(Format-GrowthSize $row.deltaBytes)  $($row.name)" -ForegroundColor Green }
    }
}

Write-Host "`nCoverage roots (non-overlapping):" -ForegroundColor White
foreach ($row in ($coverageRows | Sort-Object bytes -Descending)) {
    Write-Host ("  {0,-28} {1,12}  [{2}]" -f $row.name, (Format-GrowthSize $row.bytes).TrimStart('+'), $row.status) -ForegroundColor DarkGray
}
Write-Host "`nLargest detail paths (informational, overlapping):" -ForegroundColor White
foreach ($row in ($rows | Where-Object { $_.role -eq "detail" -and $_.bytes -gt 0 } | Sort-Object bytes -Descending | Select-Object -First 20)) {
    Write-Host ("  {0,-28} {1,12}  parent={2}" -f $row.name, (Format-GrowthSize $row.bytes).TrimStart('+'), $row.parentId) -ForegroundColor DarkGray
}

if ($Record) {
    if (-not (Test-Path -LiteralPath $HistoryDirectory)) { New-Item -ItemType Directory -Path $HistoryDirectory -Force | Out-Null }
    $snapshot | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $latestPath -Encoding UTF8
    ($snapshot | ConvertTo-Json -Depth 10 -Compress) | Add-Content -LiteralPath $historyPath -Encoding UTF8
    $cutoff = $now.AddDays(-[int]$config.retentionDays)
    if (Test-Path -LiteralPath $historyPath) {
        $kept = Get-Content -LiteralPath $historyPath -Encoding UTF8 | Where-Object {
            try { ([datetime](($_ | ConvertFrom-Json).timestamp)) -ge $cutoff } catch { $false }
        }
        $kept | Set-Content -LiteralPath $historyPath -Encoding UTF8
    }
    Write-Host "`nCompatible snapshot recorded: $latestPath" -ForegroundColor Green
}
