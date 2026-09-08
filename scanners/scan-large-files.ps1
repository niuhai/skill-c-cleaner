# scan-large-files.ps1 - F class: high-performance C-drive TOP-N inventory
# Source data is read-only. Results are stored only in the in-memory report model.

param(
    [int]$TopN = 20,
    [int]$Parallelism = 4
)

if (-not (Get-Command "Initialize-NativeFileScanner" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

$TopN = [math]::Max(1, [math]::Min($TopN, 100))
$Parallelism = [math]::Max(1, [math]::Min($Parallelism, 8))
$userProfile = [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')

Write-Host "===== F: C drive largest files TOP $TopN =====" -ForegroundColor Cyan
Write-Host "Win32 streaming enumeration; source data is read-only; reparse points are not followed." -ForegroundColor DarkGray

try {
    Initialize-NativeFileScanner
} catch {
    Write-Host "  Native scanner unavailable: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Partition metadata-heavy roots below the first level. This prevents one large
# Users/AppData or Windows tree from serializing an otherwise parallel NVMe scan.
$firstLevelDirectories = @(Get-ChildItem -LiteralPath "C:\" -Force -Directory -ErrorAction SilentlyContinue)
$excludedCoverageRoots = @("C:\System Volume Information")
$reparseRoots = [System.Collections.ArrayList]::new()
$specs = [System.Collections.ArrayList]::new()
$growthPathSpecs = [System.Collections.ArrayList]::new()
$growthConfigPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "extensions\growth-watch.json"
if (Test-Path -LiteralPath $growthConfigPath -PathType Leaf) {
    try {
        $growthConfig = Get-Content -LiteralPath $growthConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($target in @($growthConfig.targets)) {
            $expanded = Expand-EnvPath ([string]$target.path)
            $resolved = if ($expanded -match '[*?]') {
                @(Get-ChildItem -Path $expanded -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
            } else { @($expanded) }
            foreach ($resolvedPath in @($resolved | Select-Object -Unique)) {
                if (-not $resolvedPath) { continue }
                $pathSpec = New-Object CleanSight.FastPathTotalSpec
                $pathSpec.Id = [string]$target.id
                $pathSpec.Path = [string]$resolvedPath
                [void]$growthPathSpecs.Add($pathSpec)
            }
        }
    } catch {
        Write-Host "  Growth aggregation disabled: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

function Add-FileScanSpec {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string[]]$ExcludedDirectories = @(),
        [string[]]$PartialDirectories = @(),
        [string]$AggregateRoot = $userProfile
    )
    $spec = New-Object CleanSight.FastFileScanSpec
    $spec.Root = $Root
    $spec.ExcludedDirectories = @($ExcludedDirectories)
    $spec.PartialDirectories = @($PartialDirectories)
    $spec.AggregateRoot = $AggregateRoot
    $spec.AggregatePaths = [CleanSight.FastPathTotalSpec[]]@($growthPathSpecs)
    [void]$specs.Add($spec)
}

function Get-PartitionChildren {
    param([Parameter(Mandatory)][string]$Root)
    $children = @(Get-ChildItem -LiteralPath $Root -Force -Directory -ErrorAction SilentlyContinue)
    foreach ($child in $children) {
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            [void]$reparseRoots.Add($child.FullName)
        }
    }
    return @($children | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
    })
}

function Add-OneLevelPartition {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string[]]$SkipChildren = @()
    )
    $children = @(Get-PartitionChildren -Root $Root)
    $allChildPaths = @($children.FullName) + @($reparseRoots | Where-Object {
        $_.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -and
        $_.Substring($Root.TrimEnd('\').Length + 1) -notmatch '\\'
    })
    Add-FileScanSpec -Root $Root -ExcludedDirectories $allChildPaths -PartialDirectories $SkipChildren
    foreach ($child in $children) {
        if ($child.FullName -in $SkipChildren) { continue }
        Add-FileScanSpec -Root $child.FullName
    }
}

# Loose C:\ files are scanned separately from every first-level directory.
Add-FileScanSpec -Root "C:\" -ExcludedDirectories @($firstLevelDirectories.FullName) -AggregateRoot ""

foreach ($directory in $firstLevelDirectories) {
    if ($directory.FullName -in $excludedCoverageRoots) { continue }

    if ($directory.FullName -in @("C:\Windows", "C:\ProgramData", "C:\Program Files", "C:\Program Files (x86)")) {
        $skip = if ($directory.FullName.Equals("C:\Windows", [StringComparison]::OrdinalIgnoreCase)) {
            # WinSxS has extensive hard links and is already covered by A/WU/SA.
            @("C:\Windows\WinSxS")
        } else { @() }
        Add-OneLevelPartition -Root $directory.FullName -SkipChildren $skip
        continue
    }

    if (-not $directory.FullName.Equals("C:\Users", [StringComparison]::OrdinalIgnoreCase)) {
        Add-FileScanSpec -Root $directory.FullName
        continue
    }

    # C:\Users root files, then each profile. The active profile is split again,
    # and AppData Local/Roaming/LocalLow are partitioned by application.
    $userDirectories = @(Get-PartitionChildren -Root $directory.FullName)
    Add-FileScanSpec -Root $directory.FullName -ExcludedDirectories @($userDirectories.FullName)
    foreach ($userDirectory in $userDirectories) {
        if (-not $userDirectory.FullName.Equals($userProfile, [StringComparison]::OrdinalIgnoreCase)) {
            Add-FileScanSpec -Root $userDirectory.FullName
            continue
        }

        $profileChildren = @(Get-PartitionChildren -Root $userDirectory.FullName)
        Add-FileScanSpec -Root $userDirectory.FullName -ExcludedDirectories @($profileChildren.FullName)
        foreach ($profileChild in $profileChildren) {
            if (-not $profileChild.FullName.Equals((Join-Path $userProfile "AppData"), [StringComparison]::OrdinalIgnoreCase)) {
                Add-FileScanSpec -Root $profileChild.FullName
                continue
            }

            $appDataChildren = @(Get-PartitionChildren -Root $profileChild.FullName)
            Add-FileScanSpec -Root $profileChild.FullName -ExcludedDirectories @($appDataChildren.FullName)
            foreach ($appDataChild in $appDataChildren) {
                Add-OneLevelPartition -Root $appDataChild.FullName
            }
        }
    }
}

$watch = [Diagnostics.Stopwatch]::StartNew()
$scan = [CleanSight.NativeFileScanner]::ScanLargeFiles(
    [CleanSight.FastFileScanSpec[]]@($specs),
    $TopN,
    $Parallelism
)
$watch.Stop()
$Global:CDriveNativePathTotals = @($scan.PathTotals)
$Global:CDriveNativePathTotalsMetadata = @{
    source = "F"
    timestamp = (Get-Date).ToString("o")
    targets = $growthPathSpecs.Count
    partitions = $specs.Count
    coverage = "visible C drive excluding protected/system-accounting roots and reparse targets"
}

# Reuse exact aggregates from the full C pass in later scanners. This avoids
# rescanning Users/Windows/Program Files when F and MX run together.
$seededMeasurements = 0
foreach ($total in @($scan.PathTotals)) {
    if (-not $total.Path) { continue }
    $status = if (-not $total.Seen) { 'missing' } elseif ($total.Partial) { 'partial' } else { 'ok' }
    $Global:CDriveMeasurementCache[(Get-MeasurementCacheKey -Path ([string]$total.Path))] = [pscustomobject]@{
        Path=[string]$total.Path; Status=$status; Bytes=[int64]$total.Bytes; FileCount=[int64]$total.FileCount
        Evidence="Reused from F full-drive Win32 pass; partial=$([bool]$total.Partial)"
    }
    $seededMeasurements++
}

Write-Host ""
Write-Host "Rank  Size       Path" -ForegroundColor White
Write-Host "----  ---------  ----" -ForegroundColor White
$rank = 0
$sortedFiles = @($scan.TopFiles | Sort-Object Length -Descending)
foreach ($file in $sortedFiles) {
    $rank++
    $sizeStr = if ($file.Length -ge 1GB) {
        "$([math]::Round($file.Length/1GB,2)) GB"
    } elseif ($file.Length -ge 1MB) {
        "$([math]::Round($file.Length/1MB,1)) MB"
    } else {
        "$([math]::Round($file.Length/1KB,1)) KB"
    }
    Write-Host ("#{0,2}  {1,-10} {2}" -f $rank, $sizeStr, $file.Path) -ForegroundColor Green

    $kind = "large-user-file"
    $evidence = "File-level TOP $TopN inventory; review ownership before any action"
    if ($file.Path -match '^[Cc]:\\(pagefile|swapfile|hiberfil)\.sys$') {
        $kind = "system-file"
        $evidence = "System-managed file; never delete or move directly"
    } elseif ($file.Path.StartsWith("C:\Windows\", [StringComparison]::OrdinalIgnoreCase)) {
        $kind = "windows-file"
        $evidence = "Windows-managed file; inventory only"
    } elseif ($file.Path -like "$userProfile\WPS Cloud Files\*\cachedata\*") {
        $kind = "cloud-offline-cache-file"
        $evidence = "WPS local cloud/offline cache; confirm sync and offline availability in WPS before reclaiming"
    } elseif ($file.Path -match '\\(Temp|Cache|CachedData|logs?)\\') {
        $kind = "large-cache-candidate"
        $evidence = "Cache/log-shaped path; close the owning app and verify exact scope before cleanup"
    }
    [void]$Global:CDriveInventory.Add(@{
        Category = "F"
        Name = "Large file #$rank"
        SizeMB = [math]::Round([int64]$file.Length / 1MB, 2)
        SizeBytes = [int64]$file.Length
        Path = $file.Path
        Kind = $kind
        Evidence = $evidence
        Access = "ok"
    })
}

$coverageStatus = if ($scan.SkippedDirectories -gt 0 -or $excludedCoverageRoots.Count -gt 0) { "partial" } else { "ok" }
Write-Host ""
Write-Host ("Completed in {0:N1}s; {1:N0} files, {2:N0} directories, {3:N0} inaccessible directories." -f $scan.ElapsedSeconds, $scan.EnumeratedFiles, $scan.EnumeratedDirectories, $scan.SkippedDirectories) -ForegroundColor DarkGray
Write-Host ("Coverage: {0:N0} partitions; excludes WinSxS, System Volume Information, and {1:N0} reparse-point targets." -f $specs.Count, $reparseRoots.Count) -ForegroundColor DarkGray

Write-Host ""
Write-Host "===== User folder subdirectories TOP 15 =====" -ForegroundColor Cyan
Write-Host "Derived from the same file pass; no second directory-size scan." -ForegroundColor DarkGray
$userRows = @($scan.RootChildTotals | Sort-Object Bytes -Descending | Select-Object -First 15)
foreach ($row in $userRows) {
    $sizeStr = if ($row.Bytes -ge 1GB) {
        "$([math]::Round($row.Bytes/1GB,2)) GB"
    } elseif ($row.Bytes -ge 1MB) {
        "$([math]::Round($row.Bytes/1MB,1)) MB"
    } else {
        "$([math]::Round($row.Bytes/1KB,1)) KB"
    }
    Write-Host "  $sizeStr  ~\$($row.Name)" -ForegroundColor Green
    [void]$Global:CDriveInventory.Add(@{
        Category = "F"
        Name = "User folder: $($row.Name)"
        SizeMB = [math]::Round([int64]$row.Bytes / 1MB, 2)
        SizeBytes = [int64]$row.Bytes
        Path = $row.Path
        Kind = "user-folder-total"
        Evidence = "Derived from the same Win32 pass; may be partial when descendants are inaccessible"
        Access = $coverageStatus
    })
}

if ($null -eq $Global:CDriveScannerMetadata) { $Global:CDriveScannerMetadata = @{} }
$Global:CDriveScannerMetadata["F"] = @{
    engine = "Win32 FindFirstFileExW"
    elapsed_seconds = [math]::Round($scan.ElapsedSeconds, 3)
    wall_seconds = [math]::Round($watch.Elapsed.TotalSeconds, 3)
    files = [int64]$scan.EnumeratedFiles
    directories = [int64]$scan.EnumeratedDirectories
    skipped_directories = [int64]$scan.SkippedDirectories
    excluded_roots = @($excludedCoverageRoots + "C:\Windows\WinSxS")
    reparse_roots_excluded = @($reparseRoots)
    partitions = $specs.Count
    aggregate_targets = $growthPathSpecs.Count
    measurement_cache_seeded = $seededMeasurements
    parallelism = $Parallelism
    coverage = $coverageStatus
}

Write-Host ""
