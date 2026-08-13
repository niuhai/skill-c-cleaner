# measure-space.ps1 - bounded NTFS allocated-size accounting
# Read-only. Reports entry logical, unique logical, and allocated bytes.

param(
    [string]$Paths = "",
    [int]$MaxFiles = 200000,
    [int]$MaxSeconds = 90,
    [ValidateSet("console", "json")]
    [string]$OutputFormat = "console",
    [switch]$PassThru
)

$skillRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $skillRoot "_common.ps1")

$targets = @()
if ($Paths) {
    foreach ($path in @($Paths -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $targets += [pscustomobject]@{ id=$path; name=(Split-Path -Leaf $path); path=$path; maxFiles=$MaxFiles; maxSeconds=$MaxSeconds }
    }
} else {
    $configPath = Join-Path $skillRoot "extensions\space-accounting.json"
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $targets = @($config.targets)
}

$rows = @()
Write-Host "===== NTFS allocated-size accounting =====" -ForegroundColor Cyan
Write-Host "Allocated bytes are deduplicated by NTFS file identity; bounded or partial rows are not exact." -ForegroundColor DarkGray

foreach ($target in $targets) {
    $configuredPath = Expand-EnvPath ([string]$target.path)
    $resolvedPaths = if ($configuredPath -match '[*?]') {
        @(Get-ChildItem -Path $configuredPath -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
    } else { @($configuredPath) }
    if ($resolvedPaths.Count -eq 0) { $resolvedPaths = @($configuredPath) }
    $targetMaxFiles = if ($target.maxFiles) { [int]$target.maxFiles } else { $MaxFiles }
    $targetMaxSeconds = if ($target.maxSeconds) { [int]$target.maxSeconds } else { $MaxSeconds }
    $resolvedIndex = 0
    foreach ($path in @($resolvedPaths | Select-Object -Unique)) {
        $resolvedIndex++
        $measurement = Get-NtfsPathMeasurement -Path $path -MaxFiles $targetMaxFiles -MaxSeconds $targetMaxSeconds
        $row = [pscustomobject]@{
            id = if ($resolvedPaths.Count -gt 1) { "$($target.id)-$resolvedIndex" } else { [string]$target.id }
            name = if ($resolvedPaths.Count -gt 1) { "$($target.name) #$resolvedIndex" } else { [string]$target.name }
            configuredPath = $configuredPath
            path = $path
            status = $measurement.Status
            entryLogicalBytes = [int64]$measurement.EntryLogicalBytes
            uniqueLogicalBytes = [int64]$measurement.UniqueLogicalBytes
            allocatedBytes = [int64]$measurement.AllocatedBytes
            fileCount = [int]$measurement.FileCount
            uniqueFileCount = [int]$measurement.UniqueFileCount
            hardlinkDuplicates = [int]$measurement.HardlinkDuplicates
            sparseOrCompressedFiles = [int]$measurement.SparseOrCompressedFiles
            errors = [int]$measurement.Errors
            elapsedSeconds = [double]$measurement.ElapsedSeconds
        }
        $rows += $row

        if ($OutputFormat -eq "console") {
            $logicalGB = [math]::Round($row.entryLogicalBytes / 1GB, 3)
            $allocatedGB = [math]::Round($row.allocatedBytes / 1GB, 3)
            $differenceGB = [math]::Round(($row.entryLogicalBytes - $row.allocatedBytes) / 1GB, 3)
            Write-Host "  $($row.name): logical $logicalGB GB; allocated $allocatedGB GB; difference $differenceGB GB [$($row.status)]" -ForegroundColor $(if ($row.status -eq "ok") { "Green" } else { "Yellow" })
            Write-Host "     $path | files $($row.fileCount), hard-link duplicates $($row.hardlinkDuplicates), sparse/compressed $($row.sparseOrCompressedFiles)" -ForegroundColor DarkGray
        }
    }
}

if ($OutputFormat -eq "json") { $rows | ConvertTo-Json -Depth 6 }
if ($PassThru) { return $rows }
