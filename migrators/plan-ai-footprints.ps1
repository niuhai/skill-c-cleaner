# plan-ai-footprints.ps1 - read-only migration planning from an AF report

param(
    [string]$ReportPath = "",
    [string]$DestinationRoot = "D:\AI-Data",
    [int]$MinimumSizeMB = 100,
    [ValidateSet("console", "json")]
    [string]$OutputFormat = "console"
)

$skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

function Get-LatestAFReport {
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $skillRoot 'reports') -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 30)) {
        try {
            $report = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($report.scanner_metadata.AF) { return [pscustomobject]@{ Path=$file.FullName; Report=$report } }
        } catch { }
    }
    return $null
}

$loaded = $null
if ($ReportPath) {
    if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "Report not found: $ReportPath" }
    $loaded = [pscustomobject]@{ Path=(Resolve-Path -LiteralPath $ReportPath).Path; Report=(Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
} else {
    $loaded = Get-LatestAFReport
}
if (-not $loaded -or -not $loaded.Report.scanner_metadata.AF) {
    throw 'No AI-footprint report found. Run: .\analyze.ps1 -Categories AF -OutputFormat json'
}

$plans = [System.Collections.ArrayList]::new()
$seen = @{}
foreach ($app in @($loaded.Report.scanner_metadata.AF.apps)) {
    foreach ($root in @($app.roots)) {
        if ([string]$root.drive -ne 'C:\' -or [string]$root.status -ne 'ok' -or [int64]$root.bytes -lt ($MinimumSizeMB * 1MB)) { continue }
        $method = [string]$root.relocation
        if (-not $method -or $method -eq 'vendor-only') { continue }
        $source = [string]$root.path
        $key = $source.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $safeAppId = ([string]$app.id -replace '[^a-zA-Z0-9._-]', '-')
        $safeRootId = ([string]$root.id -replace '[^a-zA-Z0-9._-]', '-')
        $destination = Join-Path $DestinationRoot (Join-Path $safeAppId $safeRootId)
        $support = 'manual-review'
        $steps = @()
        switch ($method) {
            'official-env' {
                $support = 'official'
                $steps = @(
                    "Inspect managed content first: $([string]$root.inspectCommand)",
                    'Close every process that can write this path.',
                    "Copy and verify the source at '$source' to '$destination'; keep the source as rollback until the application succeeds.",
                    "Set the user environment variable $([string]$root.migrationKey) to '$destination', start a new shell, and verify with the vendor command.",
                    'Only after verification, remove the original through a separately confirmed cleanup action.'
                )
            }
            'windows-apps-settings' {
                $support = 'platform-supported-if-offered'
                $steps = @('Use Windows Settings > Apps > Installed apps > Move when the package exposes that option.', 'Do not move or delete WindowsApps manually.')
            }
            'supported-installer' {
                $support = 'vendor-installer'
                $steps = @('Use the vendor uninstaller/installer to choose a non-C location.', 'Do not drag or delete the installation directory.')
            }
            'junction-cautious' {
                $steps = @('No vendor-supported relocation was detected.', 'Classify state versus cache inside this root first.', 'If a junction is still chosen: close the app, copy, byte-count verify, retain a rollback copy, create the junction, relaunch, and rescan C without following the link.')
            }
            'cli-or-junction-cautious' {
                $steps = @('Check whether this application version supports a user-data or extensions directory option.', 'Prefer the supported CLI/configuration path; use a junction only after the cautious copy/verify/rollback workflow.')
            }
            default {
                $steps = @('Use the application or library configuration to select a non-C cache/model location.', 'Copy and verify before deleting the old source.')
            }
        }
        [void]$plans.Add([pscustomobject]@{
            appId=[string]$app.id; appName=[string]$app.name; rootId=[string]$root.id
            source=$source; destination=$destination; bytes=[int64]$root.bytes
            method=$method; support=$support; migrationKey=[string]$root.migrationKey
            inspectCommand=[string]$root.inspectCommand; cleanupCommand=[string]$root.cleanupCommand; steps=$steps
        })
    }
}

$ordered = @($plans | Sort-Object bytes -Descending)
$scannerCandidateBytes = [int64]$loaded.Report.scanner_metadata.AF.migration_candidate_bytes
$displayedCandidateBytes = [int64](($ordered | Where-Object { $_.method -ne 'windows-apps-settings' } | Measure-Object bytes -Sum).Sum)
$platformAdvisoryBytes = [int64](($ordered | Where-Object { $_.method -eq 'windows-apps-settings' } | Measure-Object bytes -Sum).Sum)
$result = [pscustomobject]@{
    schema=1; generatedAt=(Get-Date).ToString('o'); sourceReport=$loaded.Path
    destinationRoot=$DestinationRoot; candidateBytes=$scannerCandidateBytes; displayedCandidateBytes=$displayedCandidateBytes
    platformAdvisoryBytes=$platformAdvisoryBytes
    warning='Read-only plan. candidateBytes uses the AF accounting total; displayed plans honor MinimumSizeMB. WindowsApps is advisory-only. Sizes can overlap cleanup candidates; do not add them together. No move, deletion, junction, or environment change was performed.'
    plans=$ordered
}

if ($OutputFormat -eq 'json') {
    $result | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host '===== AI footprint migration plan (read-only) =====' -ForegroundColor Cyan
Write-Host "Source report: $($loaded.Path)" -ForegroundColor DarkGray
Write-Host ("AF candidates: {0:N2} GB; displayed above threshold: {1:N2} GB across {2} roots" -f ($result.candidateBytes/1GB), ($result.displayedCandidateBytes/1GB), $ordered.Count) -ForegroundColor Yellow
if ($platformAdvisoryBytes -gt 0) { Write-Host ("WindowsApps advisory-only footprint: {0:N2} GB" -f ($platformAdvisoryBytes/1GB)) -ForegroundColor DarkGray }
Write-Host 'Nothing was moved or deleted. Cleanup and migration sizes can overlap.' -ForegroundColor DarkGray
foreach ($plan in $ordered) {
    Write-Host ("`n{0} / {1}: {2:N2} GB [{3}; {4}]" -f $plan.appName, $plan.rootId, ($plan.bytes/1GB), $plan.method, $plan.support) -ForegroundColor White
    Write-Host "  $($plan.source) -> $($plan.destination)" -ForegroundColor DarkGray
    foreach ($step in @($plan.steps)) { Write-Host "  - $step" -ForegroundColor DarkGray }
}
Write-Host ''
