# iteration-loop.ps1 - bounded loop engineering for C-drive maintenance
# Default mode is diagnosis and preview only. It never deletes files automatically.

param(
    [ValidateSet("diagnose", "preview", "verify")]
    [string]$Mode = "diagnose",
    [switch]$IncludeSlowScan,
    [switch]$RecordGrowth
)

$skillRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $skillRoot "_common.ps1")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stateDir = Initialize-CleanSightArtifactDirectory (Get-CleanSightArtifactPath "reports\iterations")
$statePath = Join-Path $stateDir "iteration-$timestamp.json"

# project-pilot: 8 bounded states. Each state produces an observable artifact.
$states = @(
    "discover",
    "baseline",
    "plan",
    "dispatch",
    "verify",
    "settle",
    "review",
    "next"
)
$events = @()
function Add-Event {
    param([string]$State, [string]$Status, [string]$Detail)
    $script:events += [pscustomobject]@{ timestamp = (Get-Date).ToString("o"); state = $State; status = $Status; detail = $Detail }
    Write-Host ("[{0}] {1}: {2}" -f $State.ToUpperInvariant(), $Status, $Detail) -ForegroundColor DarkGray
}

Add-Event "discover" "start" "Run bounded discovery; the native full-file inventory remains opt-in."
$categories = if ($IncludeSlowScan) { "all" } else { "fast" }
if ($IncludeSlowScan) {
    $analyzeResult = @(& (Join-Path $skillRoot "analyze.ps1") -Categories "all" -OutputFormat "markdown" -RecordGrowth:$RecordGrowth 2>&1)
} else {
    $analyzeResult = @(& (Join-Path $skillRoot "analyze.ps1") -Categories "all" -Fast -OutputFormat "markdown" 2>&1)
}
$analyzeResult | Out-Host
Add-Event "discover" "complete" "Analysis completed for categories: $categories"

Add-Event "baseline" "start" "Reuse the GR result produced by analysis."
if ($RecordGrowth -and -not $IncludeSlowScan) {
    Add-Event "baseline" "refresh" "Record a source-compatible native baseline with one bounded F+GR pass."
    $growthResult = @(& (Join-Path $skillRoot "analyze.ps1") -Categories "F,GR" -OutputFormat "console" -RecordGrowth 2>&1)
    $growthResult | Out-Host
    Add-Event "baseline" "complete" "Native growth baseline refreshed."
} else {
    Add-Event "baseline" "complete" "Growth evidence was already emitted by analysis; duplicate traversal skipped."
}

Add-Event "plan" "complete" "Prioritize measured growth and safe reclaimable cache; do not infer from free space alone."
Add-Event "dispatch" "start" "Generate a non-destructive targeted cleanup preview."
$previewResult = & (Join-Path $skillRoot "cleaners\clean-targeted-optimization.ps1") -RiskLevel safe -WhatIf 2>&1
Add-Event "dispatch" "complete" "Preview generated; deletion requires explicit -ReallyDelete outside this loop."

if ($Mode -eq "verify") {
    Add-Event "verify" "start" "Re-measure after a user-approved cleanup."
    & (Join-Path $skillRoot "analyze.ps1") -Categories "F,GR" -OutputFormat "console" 2>&1 | Out-Host
    $latestCleanup = Get-ChildItem -LiteralPath (Get-CleanSightArtifactPath "reports\cleanup-sessions") -Filter "cleanup-*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestCleanup) {
        $cleanupState = Get-Content -LiteralPath $latestCleanup.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        & (Join-Path $skillRoot "track-regeneration.ps1") -Mode check -SessionId $cleanupState.sessionId 2>&1 | Out-Host
        Add-Event "verify" "complete" "Post-action drive, target, and regeneration measurements completed."
    } else {
        Add-Event "verify" "partial" "Growth was re-measured, but no cleanup session exists for regeneration checks."
    }
} else {
    Add-Event "verify" "deferred" "No cleanup was executed, so post-action verification is deferred."
}

Add-Event "settle" "complete" "Persist iteration state and keep path-level evidence for the next run."
Add-Event "review" "complete" "Review gate: compare drive-free delta with allocated-byte reclaim; confirm regeneration, skipped paths, and permission gaps."
Add-Event "next" "complete" "Next loop should focus on the largest positive delta, not the largest cache label."

$state = [pscustomobject]@{
    schema = 1
    iteration = $timestamp
    mode = $Mode
    categories = $categories
    states = $events
}
$state | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $statePath -Encoding UTF8
Write-Host "`nIteration state recorded: $statePath" -ForegroundColor Green
