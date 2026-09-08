# Read-only structural and regression checks for the AF lifecycle configuration.

param([switch]$VerbosePasses)

$skillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $skillRoot '_common.ps1')
$configPath = Join-Path $skillRoot 'extensions\ai-footprints.json'
$failures = [System.Collections.ArrayList]::new()
$assertionCount = 0

function Assert-AF {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    $script:assertionCount++
    if ($Condition) { if ($VerbosePasses) { Write-Host "[PASS] $Name" -ForegroundColor Green } }
    else { [void]$failures.Add("$Name$(if($Detail){": $Detail"})") }
}

try { $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { throw "AI footprint JSON parse failed: $($_.Exception.Message)" }

Assert-AF 'schema is supported' ([int]$config.schema -eq 1)
Assert-AF 'measurement version is positive' ([int]$config.measurementVersion -gt 0)
$apps = @($config.applications)
Assert-AF 'application list is non-empty' ($apps.Count -gt 0)
$ids = @($apps | ForEach-Object { [string]$_.id })
Assert-AF 'application ids are non-empty and unique' ((@($ids | Where-Object { -not $_ }).Count -eq 0) -and (@($ids | Select-Object -Unique).Count -eq $ids.Count))

# Regression: optional missing/null pattern arrays must not become an empty
# regular expression, because an empty regex matches every installed package.
$missing = [pscustomobject]@{}
$normalizedMissing = @(ConvertTo-NonEmptyStringList -Values @($missing.registryPatterns))
Assert-AF 'missing optional regex list normalizes to zero patterns' ($normalizedMissing.Count -eq 0)
Assert-AF 'missing optional regex list matches nothing' (-not (Test-RegexListMatch -Value 'Unrelated Program' -Patterns @($missing.registryPatterns)))
Assert-AF 'empty regex entries match nothing' (-not (Test-RegexListMatch -Value 'Unrelated Program' -Patterns @('', '   ', $null)))
$emptyMap = @{}
$emptyMappedRoots = if ($emptyMap.ContainsKey('missing')) { @($emptyMap['missing']) } else { @() }
Assert-AF 'missing root-map entry normalizes to zero roots' (@($emptyMappedRoots).Count -eq 0)

$allowedActions = @('safe-clean', 'managed-clean', 'preserve', 'review')
$allowedRisks = @('safe', 'cautious', 'forbidden')
$genericProcessNames = @('node', 'python', 'python3', 'java', 'dotnet')
foreach ($app in $apps) {
    $appId = [string]$app.id
    $roots = @($app.roots)
    $rootIds = @($roots | ForEach-Object { [string]$_.id })
    Assert-AF "$appId root ids are non-empty and unique" ((@($rootIds | Where-Object { -not $_ }).Count -eq 0) -and (@($rootIds | Select-Object -Unique).Count -eq $rootIds.Count))
    foreach ($root in $roots) {
        $expanded = Expand-EnvPath ([string]$root.path)
        Assert-AF "$appId/$($root.id) root path is absolute" ([IO.Path]::IsPathRooted($expanded)) ([string]$root.path)
    }
    foreach ($process in @(ConvertTo-NonEmptyStringList -Values @($app.processes))) {
        Assert-AF "$appId process guard is application-specific" ($process.ToLowerInvariant() -notin $genericProcessNames) $process
    }
    foreach ($propertyName in @('registryPatterns', 'appxPatterns')) {
        foreach ($pattern in @(ConvertTo-NonEmptyStringList -Values @($app.$propertyName))) {
            $valid = $true
            try { [void][regex]::new($pattern) } catch { $valid = $false }
            Assert-AF "$appId $propertyName regex compiles" $valid $pattern
        }
    }
    foreach ($component in @($app.components)) {
        $label = "$appId/$($component.id)"
        Assert-AF "$label references a declared root" ([string]$component.rootId -in $rootIds) ([string]$component.rootId)
        Assert-AF "$label action is explicit" ([string]$component.action -in $allowedActions) ([string]$component.action)
        Assert-AF "$label risk is explicit" ([string]$component.risk -in $allowedRisks) ([string]$component.risk)
        $relative = [string]$component.relative
        Assert-AF "$label is a relative child path" ((-not [IO.Path]::IsPathRooted($relative)) -and $relative -notmatch '(^|[\\/])\.\.([\\/]|$)' -and -not [string]::IsNullOrWhiteSpace($relative)) $relative
        if ([string]$component.action -eq 'safe-clean') {
            Assert-AF "$label safe-clean uses safe risk" ([string]$component.risk -eq 'safe') ([string]$component.risk)
        }
        if ([string]$component.action -eq 'preserve') {
            Assert-AF "$label preserve is forbidden to cleaners" ([string]$component.risk -eq 'forbidden') ([string]$component.risk)
        }
    }
}

$qoder = @($apps | Where-Object id -eq 'qoder' | Select-Object -First 1)
$codex = @($apps | Where-Object id -eq 'codex' | Select-Object -First 1)
Assert-AF 'Qoder workspaceStorage is preserved' (@($qoder.components | Where-Object { $_.id -eq 'workspace-storage' -and $_.action -eq 'preserve' }).Count -eq 1)
Assert-AF 'Qoder History is preserved' (@($qoder.components | Where-Object { $_.id -eq 'history' -and $_.action -eq 'preserve' }).Count -eq 1)
Assert-AF 'current Codex runtime is preserved' (@($codex.components | Where-Object { $_.id -eq 'current-runtime' -and $_.action -eq 'preserve' }).Count -eq 1)

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    exit 1
}
Write-Host "AI footprint validation: all $assertionCount checks passed for $($apps.Count) applications." -ForegroundColor Cyan
