# Validate that a combined F,MX report reused full-pass aggregates.

param([Parameter(Mandatory=$true)][string]$ReportPath)

$failures = [System.Collections.ArrayList]::new()
$assertionCount = 0
function Assert-Reuse {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:assertionCount++
    if (-not $Condition) { [void]$failures.Add("$Name$(if($Detail){": $Detail"})") }
}

Assert-Reuse 'report exists' (Test-Path -LiteralPath $ReportPath -PathType Leaf) $ReportPath
if (Test-Path -LiteralPath $ReportPath -PathType Leaf) {
    $report = Get-Content -LiteralPath $ReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $f = $report.scanner_metadata.F
    $mx = $report.scanner_metadata.MX
    Assert-Reuse 'F metadata exists' ($null -ne $f)
    Assert-Reuse 'MX metadata exists' ($null -ne $mx)
    Assert-Reuse 'F seeded exact aggregate measurements' ([int]$f.measurement_cache_seeded -gt 0) ([string]$f.measurement_cache_seeded)
    Assert-Reuse 'F seeded every configured aggregate' ([int]$f.measurement_cache_seeded -eq [int]$f.aggregate_targets) "$($f.measurement_cache_seeded)/$($f.aggregate_targets)"
    Assert-Reuse 'MX reused measurements before its batch' ([int]$mx.cache_hits_before_batch -gt 0) ([string]$mx.cache_hits_before_batch)
    Assert-Reuse 'MX measured each root from cache or batch' (([int]$mx.cache_hits_before_batch + [int]$mx.batch_seeded) -eq [int]$mx.root_directories) "$($mx.cache_hits_before_batch)+$($mx.batch_seeded)/$($mx.root_directories)"
    $failedStages = @($report.telemetry | Where-Object { $_.Category -in @('F','MX') -and $_.Status -ne 'completed' })
    Assert-Reuse 'F and MX telemetry completed' ($failedStages.Count -eq 0) (($failedStages.Category) -join ',')
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    exit 1
}
Write-Host "F-to-MX reuse validation: all $assertionCount checks passed for $ReportPath" -ForegroundColor Cyan
