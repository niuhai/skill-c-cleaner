# Validate attribution and accounting invariants in a generated AF JSON report.

param([string]$ReportPath = '')

$skillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $skillRoot '_common.ps1')
$config = Get-AIFootprintConfig
$failures = [System.Collections.ArrayList]::new()
$assertionCount = 0

function Assert-AFReport {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:assertionCount++
    if (-not $Condition) { [void]$failures.Add("$Name$(if($Detail){": $Detail"})") }
}

if (-not $ReportPath) {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $skillRoot 'reports') -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        try {
            $candidate = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($candidate.scanner_metadata.AF) { $ReportPath = $file.FullName; break }
        } catch { }
    }
}
if (-not $ReportPath -or -not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw 'No AF JSON report was found.' }
$report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$af = $report.scanner_metadata.AF
if (-not $af) { throw "Report does not contain AF metadata: $ReportPath" }

$apps = @($af.apps)
Assert-AFReport 'all configured applications have report rows' ($apps.Count -eq @($config.applications).Count) "$($apps.Count) rows"
Assert-AFReport 'physical footprint is positive' ([int64]$af.c_bytes -gt 0)
Assert-AFReport 'safe total is positive' ([int64]$af.safe_clean_bytes -gt 0)
Assert-AFReport 'managed total is positive' ([int64]$af.managed_clean_bytes -gt 0)
Assert-AFReport 'app totals reconcile to physical total' ([int64](($apps | Measure-Object cBytes -Sum).Sum) -eq [int64]$af.c_bytes)
Assert-AFReport 'all discovery candidates remain review-only' (@($af.discovery_candidates | Where-Object { $_.disposition -ne 'review' }).Count -eq 0)
Assert-AFReport 'all external roots retain app attribution' (@($af.external_roots | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.appId) }).Count -eq 0)
Assert-AFReport 'no root remains pending after scan' (@($apps.roots | Where-Object status -eq 'pending').Count -eq 0)

foreach ($configApp in @($config.applications)) {
    $row = @($apps | Where-Object id -eq ([string]$configApp.id) | Select-Object -First 1)
    Assert-AFReport "$($configApp.id) has exactly one report row" ($row.Count -eq 1)
    if ($row.Count -eq 0) { continue }
    $sources = @($row[0].roots | ForEach-Object { [string]$_.source })
    if (@(ConvertTo-NonEmptyStringList -Values @($configApp.registryPatterns)).Count -eq 0) {
        Assert-AFReport "$($configApp.id) cannot claim uninstall roots without patterns" (@($sources | Where-Object { $_ -like 'uninstall-registry:*' }).Count -eq 0)
    }
    if (@(ConvertTo-NonEmptyStringList -Values @($configApp.appxPatterns)).Count -eq 0) {
        Assert-AFReport "$($configApp.id) cannot claim AppX roots without patterns" (@($sources | Where-Object { $_ -like 'appx:*' }).Count -eq 0)
    }
}

$qoder = @($apps | Where-Object id -eq 'qoder' | Select-Object -First 1)
if ($qoder.Count -gt 0) {
    $redirectedQoder = @($qoder[0].roots | Where-Object { $_.id -eq 'roaming' -and $_.status -eq 'redirected' })
    if ($redirectedQoder.Count -gt 0) { Assert-AFReport 'redirected Qoder root contributes zero C bytes' ([int64]$redirectedQoder[0].bytes -eq 0) }
}
$codex = @($apps | Where-Object id -eq 'codex' | Select-Object -First 1)
Assert-AFReport 'current Codex runtime remains preserve-only in report' (@($codex[0].components | Where-Object { $_.id -eq 'current-runtime' -and $_.action -eq 'preserve' -and $_.risk -eq 'forbidden' }).Count -eq 1)

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    exit 1
}
Write-Host "AF report validation: all $assertionCount checks passed for $ReportPath" -ForegroundColor Cyan
