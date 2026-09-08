# clean-ai-footprints.ps1 - execute only explicit AF component policies
# Preview is the default. Deletion requires -ReallyDelete.

param(
    [ValidateSet('safe', 'cautious', 'all')]
    [string]$RiskLevel = 'safe',
    [string]$Apps = '',
    [switch]$ReallyDelete,
    [switch]$WhatIf
)

$skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $skillRoot '_common.ps1')
$config = Get-AIFootprintConfig
if (-not $config) { throw 'AI footprint config is unavailable.' }

$preview = $WhatIf -or -not $ReallyDelete
$selectedApps = if ($Apps) { @($Apps -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }) } else { @() }
$runningNames = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName.ToLowerInvariant() } | Select-Object -Unique)
$candidates = [System.Collections.ArrayList]::new()
$seen = @{}
$reportedUnsafeRoots = @{}
Initialize-NativeFileScanner

function Resolve-AFRootPaths {
    param($Root)
    $path = Expand-EnvPath ([string]$Root.path)
    $environmentValue = Get-EffectiveEnvironmentValue -Name ([string]$Root.pathEnv)
    if ($environmentValue) { $path = $environmentValue }
    if ($path -match '[*?]') { return @(Get-Item -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object FullName) }
    if (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) { return @((Get-Item -LiteralPath $path -Force).FullName) }
    return @()
}

function Resolve-AFComponentItems {
    param([string]$RootPath, [string]$RelativePath)
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '(^|[\\/])\.\.([\\/]|$)') { return @() }
    $candidate = Join-Path $RootPath $RelativePath
    if ($RelativePath -match '[*?]') { return @(Get-Item -Path $candidate -Force -ErrorAction SilentlyContinue) }
    return @(Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue)
}

foreach ($app in @($config.applications)) {
    $appId = ([string]$app.id).ToLowerInvariant()
    $appName = ([string]$app.name).ToLowerInvariant()
    if ($selectedApps.Count -gt 0 -and $appId -notin $selectedApps -and $appName -notin $selectedApps) { continue }

    $eligibleComponents = @($app.components | Where-Object {
        $action = [string]$_.action
        $risk = [string]$_.risk
        $action -in @('safe-clean', 'managed-clean') -and
            ($RiskLevel -ne 'safe' -or $risk -eq 'safe') -and
            ($RiskLevel -ne 'cautious' -or $risk -ne 'forbidden')
    })
    if ($eligibleComponents.Count -eq 0) { continue }
    $usedRootIds = @($eligibleComponents | ForEach-Object { [string]$_.rootId } | Select-Object -Unique)

    $processNames = @($app.processes | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $activeProcesses = @($runningNames | Where-Object { $_ -in $processNames })
    $rootsById = @{}
    foreach ($root in @($app.roots)) {
        $rootId = [string]$root.id
        if ($rootId -notin $usedRootIds) { continue }
        $existingPaths = if ($rootsById.ContainsKey($rootId)) { @($rootsById[$rootId]) } else { @() }
        $resolvedPaths = @()
        foreach ($resolvedPath in @(Resolve-AFRootPaths -Root $root | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
            $inspection = [CleanSight.NativeFileScanner]::InspectPathSafety([string]$resolvedPath)
            $drive = try { [IO.Path]::GetPathRoot([string]$resolvedPath).ToUpperInvariant() } catch { '' }
            if ($drive -ne 'C:\' -or -not $inspection.Exists -or $inspection.ReparsePointInAncestry) {
                $rootKey = ([string]$resolvedPath).ToLowerInvariant()
                if (-not $reportedUnsafeRoots.ContainsKey($rootKey)) {
                    $reportedUnsafeRoots[$rootKey] = $true
                    Write-Host "  Skipped non-C, missing, or redirected AF root: $resolvedPath" -ForegroundColor DarkGray
                }
                continue
            }
            $resolvedPaths += [string]$resolvedPath
        }
        $rootsById[$rootId] = @($existingPaths) + @($resolvedPaths)
    }

    foreach ($component in $eligibleComponents) {
        $risk = [string]$component.risk
        foreach ($rootPath in @($rootsById[[string]$component.rootId] | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
            foreach ($item in @(Resolve-AFComponentItems -RootPath $rootPath -RelativePath ([string]$component.relative))) {
                if (-not $item) { continue }
                $targetType = if ($item.PSIsContainer) { 'Directory' } else { 'File' }
                $gate = Test-CleanupTargetSafety -Path $item.FullName -AllowedRoots @($rootPath) -TargetType $targetType
                if (-not $gate.Safe) {
                    Write-Host "  Skipped unsafe AF target: $($item.FullName) - $($gate.Reason)" -ForegroundColor Yellow
                    continue
                }
                $key = $item.FullName.ToLowerInvariant()
                if ($seen.ContainsKey($key)) { continue }
                $seen[$key] = $true
                [void]$candidates.Add([pscustomobject]@{
                    AppId=[string]$app.id; AppName=[string]$app.name; ActiveProcesses=$activeProcesses
                    ComponentId=[string]$component.id; Kind=[string]$component.kind; Action=[string]$component.action
                    Risk=$risk; Note=[string]$component.note; RootPath=$rootPath; Path=$item.FullName
                    IsDirectory=[bool]$item.PSIsContainer; Bytes=[int64]0; Status='pending'
                })
            }
        }
    }
}

if ($candidates.Count -gt 0) {
    $Global:CDriveMeasurementCache = @{}
    $Global:CDriveMeasurementCacheEnabled = $true
    $Global:CDriveMeasurementCacheHits = 0
    $Global:CDriveMeasurementCacheMisses = 0
    [void](Invoke-PathMeasurementPlan -Paths ([string[]]@($candidates.Path)) -Parallelism 4)
    foreach ($candidate in @($candidates)) {
        $measurement = Get-PathLogicalMeasurement -Path $candidate.Path
        $candidate.Bytes = [int64]$measurement.Bytes
        $candidate.Status = [string]$measurement.Status
    }
}

$actionable = @($candidates | Where-Object { $_.Status -eq 'ok' -and $_.Bytes -gt 0 } | Sort-Object AppName, Path)
$totalBytes = [int64](($actionable | Measure-Object Bytes -Sum).Sum)
Write-Host '===== AI footprint cleanup =====' -ForegroundColor Cyan
if ($preview) { Write-Host 'Preview mode: nothing will be deleted. Add -ReallyDelete to execute.' -ForegroundColor Yellow }
else { Write-Host 'Execution mode: exact configured component paths will be permanently deleted.' -ForegroundColor Red }

foreach ($candidate in $actionable) {
    $activeText = if (@($candidate.ActiveProcesses).Count -gt 0) { "; active=$(@($candidate.ActiveProcesses) -join ',')" } else { '' }
    Write-Host ("  [{0}] {1} / {2}: {3:N2} MB{4}" -f $candidate.Risk, $candidate.AppName, $candidate.Kind, ($candidate.Bytes/1MB), $activeText) -ForegroundColor $(if($candidate.Risk -eq 'safe'){'Green'}else{'Yellow'})
    Write-Host "     $($candidate.Path)" -ForegroundColor DarkGray
}
Write-Host ("Previewed {0} exact paths, {1:N2} GB. Preserved/state roots and whole application directories are excluded." -f $actionable.Count, ($totalBytes/1GB)) -ForegroundColor Cyan
if ($preview -or $actionable.Count -eq 0) { exit 0 }

$sessionId = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionStarted = Get-Date
$driveBefore = New-Object IO.DriveInfo('C:\')
$driveFreeBefore = [int64]$driveBefore.AvailableFreeSpace
$auditRows = [System.Collections.ArrayList]::new()
foreach ($candidate in $actionable) {
    if (@($candidate.ActiveProcesses).Count -gt 0) {
        Write-Host "  Skipped active app $($candidate.AppName): $(@($candidate.ActiveProcesses) -join ', ')" -ForegroundColor Yellow
        continue
    }
    $before = Get-NtfsPathMeasurement -Path $candidate.Path -MaxFiles 300000 -MaxSeconds 90
    $deleted = $false
    try {
        if ($candidate.IsDirectory) { $deleted = Remove-Directory -Path $candidate.Path -AllowedRoots @($candidate.RootPath) -ShowProgress }
        else { $deleted = Remove-SafeFile -Path $candidate.Path -AllowedRoots @($candidate.RootPath) }
    } catch {
        Write-Host "  Cleanup failed: $($candidate.Path) - $($_.Exception.Message)" -ForegroundColor Red
    }
    $after = Get-NtfsPathMeasurement -Path $candidate.Path -MaxFiles 300000 -MaxSeconds 90
    [void]$auditRows.Add([pscustomobject]@{
        appId=$candidate.AppId; componentId=$candidate.ComponentId; path=$candidate.Path; deleted=[bool]$deleted
        before=[pscustomobject]@{ status=$before.Status; logicalBytes=[int64]$before.EntryLogicalBytes; allocatedBytes=[int64]$before.AllocatedBytes; fileCount=[int64]$before.FileCount }
        after=[pscustomobject]@{ status=$after.Status; logicalBytes=[int64]$after.EntryLogicalBytes; allocatedBytes=[int64]$after.AllocatedBytes; fileCount=[int64]$after.FileCount }
    })
}

$driveAfter = New-Object IO.DriveInfo('C:\')
$sessionDir = Join-Path $skillRoot 'reports\cleanup-sessions'
if (-not (Test-Path -LiteralPath $sessionDir)) { New-Item -ItemType Directory -Path $sessionDir -Force | Out-Null }
$session = [pscustomobject]@{
    schema=1; sessionId=$sessionId; label='AI footprint cleanup'; createdAt=$sessionStarted.ToString('o'); completedAt=(Get-Date).ToString('o')
    baseline=[pscustomobject]@{ driveFreeBytes=$driveFreeBefore; targets=@($auditRows | ForEach-Object { [pscustomobject]@{ path=$_.path; logicalStatus=$_.before.status; logicalBytes=$_.before.logicalBytes; allocatedStatus=$_.before.status; allocatedBytes=$_.before.allocatedBytes; fileCount=$_.before.fileCount } }) }
    cleanup=[pscustomobject]@{
        matchedLogicalBytes=$totalBytes
        measuredAllocatedReclaimBytes=[int64](($auditRows | ForEach-Object { [int64]$_.before.allocatedBytes - [int64]$_.after.allocatedBytes } | Measure-Object -Sum).Sum)
        actualDriveFreeDeltaBytes=[int64]$driveAfter.AvailableFreeSpace - $driveFreeBefore
        processed=@($auditRows | Where-Object deleted).Count; matched=$actionable.Count; targets=@($auditRows)
    }
    checkpoints=@([pscustomobject]@{
        timestamp=(Get-Date).ToString('o'); elapsedMinutes=[math]::Round(((Get-Date)-$sessionStarted).TotalMinutes,2); stage='immediate'
        driveFreeBytes=[int64]$driveAfter.AvailableFreeSpace; driveFreeDeltaBytes=[int64]$driveAfter.AvailableFreeSpace - $driveFreeBefore
        targets=@($auditRows | ForEach-Object { [pscustomobject]@{ path=$_.path; logicalStatus=$_.after.status; logicalBytes=$_.after.logicalBytes; allocatedStatus=$_.after.status; allocatedBytes=$_.after.allocatedBytes; fileCount=$_.after.fileCount } })
    })
}
$sessionPath = Join-Path $sessionDir "cleanup-$sessionId.json"
$session | ConvertTo-Json -Depth 12 | Out-File -LiteralPath $sessionPath -Encoding UTF8
Write-Host ("Actual C-drive free-space delta: {0:N3} GB" -f ($session.cleanup.actualDriveFreeDeltaBytes/1GB)) -ForegroundColor Cyan
Write-Host ("Measured allocated-byte reclaim: {0:N3} GB" -f ($session.cleanup.measuredAllocatedReclaimBytes/1GB)) -ForegroundColor Cyan
Write-Host "Cleanup session: $sessionPath" -ForegroundColor Green
Write-Host "Later regeneration check: .\track-regeneration.ps1 -Mode check -SessionId $sessionId" -ForegroundColor DarkGray
