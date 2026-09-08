# Structural and behavioral validation for vendor-managed storage discovery.

param([string]$ReportPath = '')

$skillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $skillRoot '_common.ps1')
$configPath = Join-Path $skillRoot 'extensions\managed-storage.json'
$failures = [System.Collections.ArrayList]::new()
$assertionCount = 0

function Assert-MS {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:assertionCount++
    if (-not $Condition) { [void]$failures.Add("$Name$(if($Detail){": $Detail"})") }
}

try { $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "Managed-storage JSON parse failed: $($_.Exception.Message)" }

Assert-MS 'schema is supported' ([int]$config.schema -eq 1)
$sources = @($config.sources)
$ids = @($sources | ForEach-Object { [string]$_.id })
Assert-MS 'source ids are non-empty and unique' ((@($ids | Where-Object { -not $_ }).Count -eq 0) -and (@($ids | Select-Object -Unique).Count -eq $ids.Count))
foreach ($source in $sources) {
    $label = [string]$source.id
    Assert-MS "$label remains cautious" ([string]$source.risk -eq 'cautious') ([string]$source.risk)
    Assert-MS "$label uses a vendor workflow" ([string]$source.action -in @('vendor-ui','vendor-cli','vendor-review')) ([string]$source.action)
    Assert-MS "$label has a reporting threshold" ([double]$source.minimumMB -ge 0)
    Assert-MS "$label has no drive-root target" ((Expand-EnvPath ([string]$source.path)).TrimEnd('\') -notmatch '^[A-Za-z]:$') ([string]$source.path)
    Assert-MS "$label has application-specific processes" (@(ConvertTo-NonEmptyStringList -Values @($source.processes) | Where-Object { $_.ToLowerInvariant() -in @('node','python','java','dotnet') }).Count -eq 0)
    foreach ($url in @($source.officialDocs)) { Assert-MS "$label official reference is HTTPS" ([string]$url -match '^https://') ([string]$url) }
}
Assert-MS 'WPS cache is UI-managed' (@($sources | Where-Object { $_.id -eq 'wps-cloud-cache' -and $_.action -eq 'vendor-ui' }).Count -eq 1)
Assert-MS 'ESP-IDF archives are CLI-managed' (@($sources | Where-Object { $_.id -eq 'esp-idf-dist' -and $_.action -eq 'vendor-cli' }).Count -eq 1)

$fixtureRoot = Join-Path $env:TEMP ("CleanSight-managed-storage-test-" + [guid]::NewGuid().ToString('N'))
$fixturePath = Join-Path $fixtureRoot 'cache'
$fixtureConfig = Join-Path $fixtureRoot 'managed-storage.json'
try {
    [void](New-Item -ItemType Directory -Path $fixturePath -Force)
    [IO.File]::WriteAllBytes((Join-Path $fixturePath 'fixture.bin'), ([byte[]]::new(4096)))
    $fixture = [pscustomobject]@{ schema=1; sources=@([pscustomobject]@{
        id='fixture'; name='fixture managed store'; path=$fixturePath; kind='fixture'; risk='cautious'; action='vendor-review'
        processes=@(); minimumMB=0; advice='fixture'; migration='fixture'; note='fixture'; officialDocs=@('https://example.invalid/fixture')
    }) }
    $fixture | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fixtureConfig -Encoding UTF8
    $Global:CDriveManagedStorageConfigPath = $fixtureConfig
    $Global:CDriveScanResults = [System.Collections.ArrayList]::new()
    $Global:CDriveInventory = [System.Collections.ArrayList]::new()
    $Global:CDriveScannerMetadata = @{}
    $Global:CDriveMeasurementCache = @{}
    $Global:CDriveMeasurementCacheHits = 0
    $Global:CDriveMeasurementCacheMisses = 0
    $null = & (Join-Path $skillRoot 'scanners\scan-managed-storage.ps1') *>&1
    $rows = @($Global:CDriveScanResults)
    Assert-MS 'fixture produces one cautious report row' ($rows.Count -eq 1 -and [string]$rows[0].Risk -eq 'cautious') "$($rows.Count) rows"
    Assert-MS 'fixture is measured without deletion' ([int64]$rows[0].Measurements[0].Bytes -eq 4096 -and (Test-Path -LiteralPath (Join-Path $fixturePath 'fixture.bin')))
    Assert-MS 'scanner exposes no direct cleaner' ($Global:CDriveScannerMetadata.MS.directCleanerAvailable -eq $false)
} finally {
    $Global:CDriveManagedStorageConfigPath = $null
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    if ($resolvedFixture.StartsWith($resolvedTemp + '\CleanSight-managed-storage-test-', [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedFixture)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($ReportPath) {
    Assert-MS 'requested MS report exists' (Test-Path -LiteralPath $ReportPath -PathType Leaf) $ReportPath
    if (Test-Path -LiteralPath $ReportPath -PathType Leaf) {
        $report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $metadata = $report.scanner_metadata.MS
        $reportSources = @($metadata.sources)
        Assert-MS 'report includes MS metadata' ($null -ne $metadata)
        Assert-MS 'report keeps direct cleaner disabled' ($metadata.directCleanerAvailable -eq $false)
        Assert-MS 'report source bytes are positive' ([int64](($reportSources | Measure-Object bytes -Sum).Sum) -gt 0)
        Assert-MS 'report sources use configured vendor actions' (@($reportSources | Where-Object { $_.action -notin @('vendor-ui','vendor-cli','vendor-review') }).Count -eq 0)
        if (Test-Path -Path "$env:USERPROFILE\WPS Cloud Files\.*\cachedata" -PathType Container) {
            Assert-MS 'present WPS cache appears in report' (@($reportSources | Where-Object id -eq 'wps-cloud-cache').Count -gt 0)
        }
        $idfRoot = Get-EffectiveEnvironmentValue -Name 'IDF_TOOLS_PATH'
        if (-not $idfRoot) { $idfRoot = Join-Path $env:USERPROFILE '.espressif' }
        if (Test-Path -LiteralPath (Join-Path $idfRoot 'dist') -PathType Container) {
            Assert-MS 'present ESP-IDF dist appears in report' (@($reportSources | Where-Object id -eq 'esp-idf-dist').Count -gt 0)
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    exit 1
}
Write-Host "Managed-storage validation: all $assertionCount checks passed for $($sources.Count) sources." -ForegroundColor Cyan
