# MS scanner: vendor-managed local storage that must not enter direct cleaners.

if (-not (Get-Command "Get-PathLogicalMeasurement" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== MS: vendor-managed local storage =====" -ForegroundColor Cyan
Write-Host "Reports large caches/archives, but routes cleanup through the owning product UI or CLI." -ForegroundColor DarkGray

$skillRoot = Get-SkillRoot
$configPath = if ($Global:CDriveManagedStorageConfigPath) {
    [string]$Global:CDriveManagedStorageConfigPath
} else {
    Join-Path $skillRoot "extensions\managed-storage.json"
}

try { $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch {
    Write-Host "  Managed-storage config unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
    return
}

$runningNames = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName.ToLowerInvariant() } | Select-Object -Unique)
$sourceRows = [System.Collections.ArrayList]::new()

foreach ($source in @($config.sources)) {
    $configuredPath = Expand-EnvPath ([string]$source.path)
    $environmentRoot = Get-EffectiveEnvironmentValue -Name ([string]$source.pathEnv)
    if ($environmentRoot) {
        $configuredPath = if ([string]$source.relative) {
            Join-Path $environmentRoot ([string]$source.relative)
        } else { $environmentRoot }
    }

    $resolvedPaths = if ($configuredPath -match '[*?]') {
        @(Get-Item -Path $configuredPath -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
    } elseif (Test-Path -LiteralPath $configuredPath -ErrorAction SilentlyContinue) {
        @((Get-Item -LiteralPath $configuredPath -Force).FullName)
    } else { @() }

    $measurements = [System.Collections.ArrayList]::new()
    foreach ($path in @($resolvedPaths | Select-Object -Unique)) {
        $drive = try { [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($path)).ToUpperInvariant() } catch { '' }
        if ($drive -ne 'C:\') { continue }
        $measurement = Get-PathLogicalMeasurement -Path $path
        if ($measurement.Status -eq 'missing') { continue }
        [void]$measurements.Add($measurement)
    }

    $bytes = [int64](($measurements | Measure-Object Bytes -Sum).Sum)
    $minimumBytes = [int64]([double]$source.minimumMB * 1MB)
    if ($bytes -lt $minimumBytes) { continue }

    $processNames = @(ConvertTo-NonEmptyStringList -Values @($source.processes) | ForEach-Object { $_.ToLowerInvariant() })
    $active = @($runningNames | Where-Object { $_ -in $processNames })
    $statuses = @($measurements | ForEach-Object Status | Select-Object -Unique)
    $statusText = if ($statuses.Count) { $statuses -join ',' } else { 'unknown' }
    $activityNote = if ($active.Count) { " Active processes: $($active -join ','); use the vendor workflow only after activity/sync completes." } else { '' }
    $note = "$([string]$source.note) Measurement status: $statusText.$activityNote"

    Write-ScanResult -Category 'MS' -Name ([string]$source.name) -Size $bytes -Risk 'cautious' `
        -Path (($measurements | ForEach-Object Path) -join '; ') -Advice ([string]$source.advice) `
        -Migration ([string]$source.migration) -Note $note -Source "managed-storage:$([string]$source.id)" `
        -Measurements @($measurements)

    [void]$sourceRows.Add([pscustomobject]@{
        id=[string]$source.id; name=[string]$source.name; kind=[string]$source.kind
        action=[string]$source.action; bytes=$bytes; paths=@($measurements | ForEach-Object Path)
        statuses=$statuses; activeProcesses=$active; officialDocs=@($source.officialDocs)
        environmentOverride=[bool]$environmentRoot
    })
}

if ($sourceRows.Count -eq 0) { Write-Host "  No configured vendor-managed store exceeded its reporting threshold." -ForegroundColor DarkGray }
if ($null -eq $Global:CDriveScannerMetadata) { $Global:CDriveScannerMetadata = @{} }
$Global:CDriveScannerMetadata['MS'] = [pscustomobject]@{
    schema=1; config=$configPath; sources=@($sourceRows); directCleanerAvailable=$false
    accounting='C-located logical bytes; vendor-managed findings are cautious and never authorize direct deletion'
}
Write-Host ""
