# scan-ai-footprints.ps1 - AF class: one-pass AI software footprint accounting
# Read-only unless the analyzer was explicitly invoked with -RecordGrowth.

if (-not (Get-Command "Get-AIFootprintConfig" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== AF: AI software lifecycle footprint =====" -ForegroundColor Cyan
Write-Host "Accounts for installs, runtimes, models, extensions, indexes, state and updater residue; only explicit cache components enter cleanup totals." -ForegroundColor DarkGray

$skillRoot = Get-SkillRoot
$configPath = ""
if ($Global:CDriveAIFootprintConfigPath) { $configPath = [string]$Global:CDriveAIFootprintConfigPath }
if (-not $configPath) { $configPath = Join-Path $skillRoot "extensions\ai-footprints.json" }
$config = Get-AIFootprintConfig -ConfigPath $configPath
if (-not $config) {
    Write-Host "  AI footprint config is unavailable." -ForegroundColor Yellow
    return
}

$minimumDisplayBytes = [int64]([double]$config.minimumDisplayMB * 1MB)
$discoveryMinimumBytes = if ($config.discoveryMinimumMB) { [int64]([double]$config.discoveryMinimumMB * 1MB) } else { [int64](100MB) }
$roots = [System.Collections.ArrayList]::new()
$components = [System.Collections.ArrayList]::new()
$appById = @{}
$rootSequence = 0

function Resolve-UninstallCommandFolder {
    param($Entry)
    $folder = Resolve-UninstallInstallFolder -Entry $Entry
    if ($folder) { return $folder }
    $command = [Environment]::ExpandEnvironmentVariables([string]$Entry.UninstallString).Trim()
    if (-not $command) { return "" }
    $executable = ""
    if ($command -match '^\s*"([^"]+\.exe)"') { $executable = $Matches[1] }
    elseif ($command -match '^\s*([^\s]+\.exe)') { $executable = $Matches[1] }
    if (-not $executable) { return "" }
    $parent = Split-Path -Parent $executable
    if ($parent -and (Test-Path -LiteralPath $parent -PathType Container -ErrorAction SilentlyContinue)) {
        try { return [IO.Path]::GetFullPath($parent).TrimEnd('\') } catch { return $parent.TrimEnd('\') }
    }
    return ""
}

function Resolve-LinkTargetPath {
    param([IO.FileSystemInfo]$Item)
    if (-not $Item -or -not ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return "" }
    $target = @($Item.Target) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace([string]$target)) { return "" }
    if (-not [IO.Path]::IsPathRooted([string]$target)) { $target = Join-Path $Item.Parent.FullName ([string]$target) }
    try { return [IO.Path]::GetFullPath([string]$target).TrimEnd('\') } catch { return [string]$target }
}

function Add-AIFootprintRoot {
    param(
        [string]$AppId, [string]$RootId, [string]$Path, [string]$Kind,
        [string]$Policy, [string]$Relocation, [string]$MigrationKey,
        [string]$InspectCommand, [string]$CleanupCommand, [string]$Source
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    try { $expanded = [IO.Path]::GetFullPath($expanded).TrimEnd('\') } catch { return }
    $key = "$AppId|$($expanded.ToLowerInvariant())"
    if (@($roots | Where-Object { $_.Key -eq $key }).Count -gt 0) { return }
    $item = Get-Item -LiteralPath $expanded -Force -ErrorAction SilentlyContinue
    $drive = try { [IO.Path]::GetPathRoot($expanded).ToUpperInvariant() } catch { "" }
    $isReparse = [bool]($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))
    $linkTarget = Resolve-LinkTargetPath -Item $item
    $script:rootSequence++
    [void]$roots.Add([pscustomobject]@{
        Key=$key; Sequence=$script:rootSequence; AppId=$AppId; RootId=$RootId; Path=$expanded
        Kind=$Kind; Policy=$Policy; Relocation=$Relocation; MigrationKey=$MigrationKey
        InspectCommand=$InspectCommand; CleanupCommand=$CleanupCommand; Source=$Source
        Exists=[bool]$item; Drive=$drive; LinkTarget=$linkTarget; IsReparse=$isReparse
        Included=$false; CoveredBy=""; Status=if($item){"pending"}else{"missing"}
        Bytes=[int64]0; FileCount=[int64]0
    })
}

foreach ($app in @($config.applications)) {
    $appId = [string]$app.id
    $appById[$appId] = $app
    foreach ($root in @($app.roots)) {
        $path = Expand-EnvPath ([string]$root.path)
        $environmentValue = Get-EffectiveEnvironmentValue -Name ([string]$root.pathEnv)
        if ($environmentValue) { $path = $environmentValue }
        if ($path -match '[*?]') {
            foreach ($match in @(Get-Item -Path $path -Force -ErrorAction SilentlyContinue)) {
                Add-AIFootprintRoot -AppId $appId -RootId ([string]$root.id) -Path $match.FullName `
                    -Kind ([string]$root.kind) -Policy ([string]$root.policy) -Relocation ([string]$root.relocation) `
                    -MigrationKey ([string]$root.migrationKey) -InspectCommand ([string]$root.inspectCommand) `
                    -CleanupCommand ([string]$root.cleanupCommand) -Source "configured"
            }
        } else {
            Add-AIFootprintRoot -AppId $appId -RootId ([string]$root.id) -Path $path `
                -Kind ([string]$root.kind) -Policy ([string]$root.policy) -Relocation ([string]$root.relocation) `
                -MigrationKey ([string]$root.migrationKey) -InspectCommand ([string]$root.inspectCommand) `
                -CleanupCommand ([string]$root.cleanupCommand) -Source $(if($environmentValue){"environment"}else{"configured"})
        }
    }
}

$uninstallEntries = @(Get-UninstallRegistryEntries)
foreach ($app in @($config.applications)) {
    # @($null).Count is 1 in PowerShell, and an empty regex matches every
    # string.  Optional discovery fields therefore must be normalized before
    # matching or one app can accidentally claim every installed program.
    $patterns = @(ConvertTo-NonEmptyStringList -Values @($app.registryPatterns))
    if ($patterns.Count -eq 0) { continue }
    $matchedIndex = 0
    foreach ($entry in $uninstallEntries) {
        $name = [string]$entry.DisplayName
        if (-not $name) { continue }
        if (-not (Test-RegexListMatch -Value $name -Patterns $patterns)) { continue }
        $folder = Resolve-UninstallCommandFolder -Entry $entry
        if (-not $folder) { continue }
        $matchedIndex++
        Add-AIFootprintRoot -AppId ([string]$app.id) -RootId "install-registry-$matchedIndex" -Path $folder `
            -Kind "installed-application" -Policy "uninstall-only" -Relocation "supported-installer" `
            -MigrationKey "" -InspectCommand "" -CleanupCommand "" -Source "uninstall-registry:$name"
    }
}

if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
    $packages = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    foreach ($app in @($config.applications)) {
        $patterns = @(ConvertTo-NonEmptyStringList -Values @($app.appxPatterns))
        if ($patterns.Count -eq 0) { continue }
        $matchedIndex = 0
        foreach ($package in $packages) {
            if (-not (Test-RegexListMatch -Value ([string]$package.Name) -Patterns $patterns) -or -not $package.InstallLocation) { continue }
            $matchedIndex++
            Add-AIFootprintRoot -AppId ([string]$app.id) -RootId "install-appx-$matchedIndex" -Path ([string]$package.InstallLocation) `
                -Kind "installed-store-application" -Policy "uninstall-only" -Relocation "windows-apps-settings" `
                -MigrationKey "" -InspectCommand "" -CleanupCommand "" -Source "appx:$($package.PackageFullName)"
        }
    }
}

# A C: junction is an external footprint, not C: physical usage. Ordinary non-C
# install/model roots are retained as evidence but are not traversed.
$candidates = @($roots | Where-Object { $_.Exists -and $_.Drive -eq 'C:\' -and -not $_.IsReparse } | Sort-Object { $_.Path.Length }, Path)
$includedRoots = [System.Collections.ArrayList]::new()
foreach ($root in $candidates) {
    $parent = @($includedRoots | Where-Object { Test-PathAtOrBelow -Path $root.Path -Root $_.Path } | Select-Object -First 1)
    if ($parent.Count -gt 0) {
        $root.CoveredBy = [string]$parent[0].Path
        $root.Status = "covered"
    } else {
        $root.Included = $true
        [void]$includedRoots.Add($root)
    }
}
foreach ($root in @($roots | Where-Object { $_.IsReparse })) { $root.Status = "redirected" }
foreach ($root in @($roots | Where-Object { $_.Exists -and $_.Drive -ne 'C:\' })) { $root.Status = "external" }

function Get-ContainingScanRoot {
    param([string]$Path)
    return @($includedRoots | Where-Object { Test-PathAtOrBelow -Path $Path -Root $_.Path } | Sort-Object { $_.Path.Length } -Descending | Select-Object -First 1)[0]
}

$componentSequence = 0
foreach ($app in @($config.applications)) {
    foreach ($component in @($app.components)) {
        $componentRoots = @($roots | Where-Object { $_.AppId -eq [string]$app.id -and $_.RootId -eq [string]$component.rootId -and $_.Exists -and -not $_.IsReparse })
        foreach ($root in $componentRoots) {
            $candidate = Join-Path $root.Path ([string]$component.relative)
            $matches = if ([string]$component.relative -match '[*?]') {
                @(Get-Item -Path $candidate -Force -ErrorAction SilentlyContinue)
            } else {
                @(Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue)
            }
            foreach ($item in $matches) {
                if (-not $item -or -not (Test-PathAtOrBelow -Path $item.FullName -Root $root.Path)) { continue }
                $scanRoot = Get-ContainingScanRoot -Path $item.FullName
                if (-not $scanRoot) { continue }
                $componentSequence++
                [void]$components.Add([pscustomobject]@{
                    Sequence=$componentSequence; AppId=[string]$app.id; AppName=[string]$app.name
                    Id=[string]$component.id; Path=$item.FullName; RootPath=$root.Path; ScanRootPath=$scanRoot.Path
                    Kind=[string]$component.kind; Action=[string]$component.action; Risk=[string]$component.risk
                    Note=[string]$component.note; Status="pending"; Bytes=[int64]0; FileCount=[int64]0
                })
            }
        }
    }
}

# Deduplicate identical component targets while preserving the more conservative risk.
$riskRank = @{ safe=1; cautious=2; forbidden=3 }
$componentByPath = @{}
foreach ($component in @($components)) {
    $key = $component.Path.ToLowerInvariant()
    if (-not $componentByPath.ContainsKey($key)) { $componentByPath[$key] = $component; continue }
    $current = $componentByPath[$key]
    if ($riskRank[$component.Risk] -gt $riskRank[$current.Risk]) { $componentByPath[$key] = $component }
}
$components = [System.Collections.ArrayList]::new()
foreach ($component in @($componentByPath.Values)) { [void]$components.Add($component) }

$targetMap = @{}
$specs = [System.Collections.ArrayList]::new()
try { Initialize-NativeFileScanner }
catch { Write-Host "  Native scanner initialization failed: $($_.Exception.Message)" -ForegroundColor Yellow }
foreach ($root in @($includedRoots)) {
    $rootTargetId = "root::$($root.Sequence)"
    $aggregateTargets = [System.Collections.ArrayList]::new()
    $rootTarget = New-Object CleanSight.FastPathTotalSpec
    $rootTarget.Id = $rootTargetId
    $rootTarget.Path = $root.Path
    [void]$aggregateTargets.Add($rootTarget)
    $targetMap[$rootTargetId] = [pscustomobject]@{ Type="root"; Value=$root }

    foreach ($component in @($components | Where-Object { $_.ScanRootPath -eq $root.Path })) {
        $componentTargetId = "component::$($component.Sequence)"
        $target = New-Object CleanSight.FastPathTotalSpec
        $target.Id = $componentTargetId
        $target.Path = $component.Path
        [void]$aggregateTargets.Add($target)
        $targetMap[$componentTargetId] = [pscustomobject]@{ Type="component"; Value=$component }
    }

    $spec = New-Object CleanSight.FastFileScanSpec
    $spec.Root = $root.Path
    $spec.ExcludedDirectories = @()
    $spec.PartialDirectories = @()
    $spec.AggregateRoot = $root.Path
    $spec.AggregatePaths = [CleanSight.FastPathTotalSpec[]]@($aggregateTargets)
    [void]$specs.Add($spec)
}

$scan = $null
try {
    if ($specs.Count -gt 0) { $scan = [CleanSight.NativeFileScanner]::ScanLargeFiles([CleanSight.FastFileScanSpec[]]@($specs), 1, 4) }
} catch {
    Write-Host "  One-pass native accounting failed; exact roots will use the compatibility measurement cache: $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($scan) {
    foreach ($total in @($scan.PathTotals)) {
        if (-not $targetMap.ContainsKey([string]$total.Id)) { continue }
        $status = if (-not $total.Seen) { "missing" } elseif ($total.Partial) { "partial" } else { "ok" }
        $measurement = [pscustomobject]@{
            Path=[string]$total.Path; Status=$status; Bytes=[int64]$total.Bytes; FileCount=[int64]$total.FileCount
            Evidence="AI one-pass Win32 aggregation; reparse points not followed"
        }
        $target = $targetMap[[string]$total.Id].Value
        $target.Status = $status
        $target.Bytes = [int64]$total.Bytes
        $target.FileCount = [int64]$total.FileCount
        $Global:CDriveMeasurementCache[(Get-MeasurementCacheKey -Path ([string]$total.Path))] = $measurement
    }
} else {
    foreach ($root in @($includedRoots)) {
        $measurement = Get-PathLogicalMeasurement -Path $root.Path
        $root.Status = $measurement.Status; $root.Bytes = [int64]$measurement.Bytes; $root.FileCount = [int64]$measurement.FileCount
    }
    foreach ($component in @($components)) {
        $measurement = Get-PathLogicalMeasurement -Path $component.Path
        $component.Status = $measurement.Status; $component.Bytes = [int64]$measurement.Bytes; $component.FileCount = [int64]$measurement.FileCount
    }
}

$runningNames = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName.ToLowerInvariant() } | Select-Object -Unique)
$appRows = [System.Collections.ArrayList]::new()
$discoveryCandidates = [System.Collections.ArrayList]::new()
$previous = $null
$historyDirectory = if ($Global:CDriveAIFootprintHistoryDirectory) { [string]$Global:CDriveAIFootprintHistoryDirectory } else { Get-CleanSightArtifactPath "reports\ai-footprints" }
$latestPath = Join-Path $historyDirectory "latest.json"
if (Test-Path -LiteralPath $latestPath -PathType Leaf -ErrorAction SilentlyContinue) {
    try { $previous = Get-Content -LiteralPath $latestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $previous = $null }
}
$previousCompatible = $previous -and [int]$previous.schema -eq 1 -and [int]$previous.measurementVersion -eq [int]$config.measurementVersion

foreach ($app in @($config.applications)) {
    $appRoots = @($roots | Where-Object { $_.AppId -eq [string]$app.id })
    $cRoots = @($appRoots | Where-Object { $_.Included })
    $bytes = [int64](($cRoots | Measure-Object -Property Bytes -Sum).Sum)
    $statuses = @($cRoots | ForEach-Object { $_.Status })
    $status = if ($statuses -contains "partial") { "partial" } elseif ($cRoots.Count -eq 0) { "missing" } else { "ok" }
    $processes = @($app.processes | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $activeNames = @($runningNames | Where-Object { $_ -in $processes })
    $installDrives = @($appRoots | Where-Object { $_.Kind -like 'installed-*' -and $_.Exists } | ForEach-Object { $_.Drive.TrimEnd('\') } | Where-Object { $_ } | Select-Object -Unique)
    $appComponents = @($components | Where-Object { $_.AppId -eq [string]$app.id })
    $safeBytes = [int64](($appComponents | Where-Object { $_.Action -eq 'safe-clean' -and $_.Status -eq 'ok' } | Measure-Object -Property Bytes -Sum).Sum)
    $managedBytes = [int64](($appComponents | Where-Object { $_.Action -eq 'managed-clean' -and $_.Status -eq 'ok' } | Measure-Object -Property Bytes -Sum).Sum)
    $migrationBytes = [int64](($cRoots | Where-Object { $_.Relocation -and $_.Relocation -notin @('vendor-only','windows-apps-settings') } | Measure-Object -Property Bytes -Sum).Sum)

    $delta = $null
    if ($previousCompatible) {
        $oldApp = @($previous.apps | Where-Object { $_.id -eq [string]$app.id } | Select-Object -First 1)
        if ($oldApp.Count -gt 0 -and [string]$oldApp[0].status -eq $status) { $delta = $bytes - [int64]$oldApp[0].cBytes }
    }

    $topChildren = @()
    if ($scan) {
        $topChildren = @($scan.RootChildTotals | Where-Object {
            $childPath = [string]$_.Path
            @($cRoots | Where-Object { Test-PathAtOrBelow -Path $childPath -Root $_.Path }).Count -gt 0
        } | Sort-Object Bytes -Descending | Select-Object -First 5 | ForEach-Object {
            [pscustomobject]@{ name=$_.Name; path=$_.Path; bytes=[int64]$_.Bytes; fileCount=[int64]$_.FileCount }
        })
    }

    # Turn large, still-unclassified children inside a known AI application's
    # mixed-data roots into a review queue.  This is evidence for the next
    # iteration, never an automatic deletion rule.
    foreach ($child in @($topChildren | Where-Object { $_.bytes -ge $discoveryMinimumBytes })) {
        $ownerRoot = @($cRoots | Where-Object { Test-PathAtOrBelow -Path $child.path -Root $_.Path } | Sort-Object { $_.Path.Length } -Descending | Select-Object -First 1)
        if ($ownerRoot.Count -eq 0 -or [string]$ownerRoot[0].Policy -ne 'mixed') { continue }
        $exactPolicies = @($appComponents | Where-Object { $_.Path.TrimEnd('\') -eq ([string]$child.path).TrimEnd('\') })
        if ($exactPolicies.Count -gt 0) { continue }
        $nestedPolicies = @($appComponents | Where-Object { Test-PathAtOrBelow -Path $_.Path -Root ([string]$child.path) })
        # Component policies may intentionally nest (for example User plus
        # User\History). Count their path union via outermost targets so the
        # classified total cannot double-count descendants and hide unknowns.
        $classifiedPolicies = @(Select-TopLevelPathItems -Items @($nestedPolicies | Where-Object status -eq 'ok'))
        $classifiedBytes = [int64](($classifiedPolicies | Measure-Object Bytes -Sum).Sum)
        $unexplainedBytes = [int64][math]::Max(0, [int64]$child.bytes - $classifiedBytes)
        if ($unexplainedBytes -lt $discoveryMinimumBytes) { continue }
        $coverage = if ($nestedPolicies.Count -gt 0) { 'partial' } else { 'unclassified' }
        [void]$discoveryCandidates.Add([pscustomobject]@{
            appId=[string]$app.id; appName=[string]$app.name; path=[string]$child.path
            bytes=$unexplainedBytes; containerBytes=[int64]$child.bytes; classifiedBytes=$classifiedBytes
            fileCount=[int64]$child.fileCount; coverage=$coverage
            rootId=[string]$ownerRoot[0].RootId; rootKind=[string]$ownerRoot[0].Kind
            nestedPolicies=@($nestedPolicies | ForEach-Object { [pscustomobject]@{ id=$_.Id; action=$_.Action; path=$_.Path } })
            disposition='review'; reason='At least discoveryMinimumMB of a mixed AI-data child remains outside exact explicit policies.'
        })
    }

    [void]$appRows.Add([pscustomobject]@{
        id=[string]$app.id; name=[string]$app.name; cBytes=$bytes; status=$status
        active=($activeNames.Count -gt 0); activeProcesses=$activeNames; installDrives=$installDrives
        safeCleanBytes=$safeBytes; managedCleanBytes=$managedBytes; migrationCandidateBytes=$migrationBytes
        deltaBytes=$delta; roots=@($appRoots | ForEach-Object {
            [pscustomobject]@{ id=$_.RootId; path=$_.Path; kind=$_.Kind; policy=$_.Policy; source=$_.Source; drive=$_.Drive; status=$_.Status; bytes=$_.Bytes; linkTarget=$_.LinkTarget; relocation=$_.Relocation; migrationKey=$_.MigrationKey; inspectCommand=$_.InspectCommand; cleanupCommand=$_.CleanupCommand }
        }); components=@($appComponents | ForEach-Object {
            [pscustomobject]@{ id=$_.Id; path=$_.Path; kind=$_.Kind; action=$_.Action; risk=$_.Risk; status=$_.Status; bytes=$_.Bytes; note=$_.Note }
        }); topChildren=$topChildren
    })
}

$totalCBytes = [int64](($includedRoots | Measure-Object -Property Bytes -Sum).Sum)
$uniqueActionComponents = @($components | Where-Object { $_.Status -eq 'ok' -and $_.Bytes -gt 0 -and $_.Action -in @('safe-clean','managed-clean') } | Sort-Object Path -Unique)
$safeTotal = [int64](($uniqueActionComponents | Where-Object Action -eq 'safe-clean' | Measure-Object -Property Bytes -Sum).Sum)
$managedTotal = [int64](($uniqueActionComponents | Where-Object Action -eq 'managed-clean' | Measure-Object -Property Bytes -Sum).Sum)
$migrationTotal = [int64](($includedRoots | Where-Object { $_.Relocation -and $_.Relocation -notin @('vendor-only','windows-apps-settings') } | Measure-Object -Property Bytes -Sum).Sum)

Write-Host ("  C: AI located logical footprint: {0:N2} GB across {1} detected groups." -f ($totalCBytes/1GB), @($appRows | Where-Object cBytes -gt 0).Count) -ForegroundColor Yellow
Write-Host ("  Explicit recurring cleanup: safe {0:N2} GB; managed/confirm {1:N2} GB. Migration candidates: {2:N2} GB." -f ($safeTotal/1GB), ($managedTotal/1GB), ($migrationTotal/1GB)) -ForegroundColor DarkCyan
if ($discoveryCandidates.Count -gt 0) {
    Write-Host ("  Learning queue: {0} large mixed-data paths need classification; none are treated as cleanable." -f $discoveryCandidates.Count) -ForegroundColor Magenta
    foreach ($candidate in @($discoveryCandidates | Sort-Object bytes -Descending | Select-Object -First 5)) {
        Write-Host ("     {0} / {1}: {2:N2} GB unexplained of {3:N2} GB [{4}]" -f $candidate.appName, (Split-Path -Leaf $candidate.path), ($candidate.bytes/1GB), ($candidate.containerBytes/1GB), $candidate.coverage) -ForegroundColor DarkGray
    }
}

foreach ($row in @($appRows | Where-Object { $_.cBytes -ge $minimumDisplayBytes } | Sort-Object cBytes -Descending)) {
    $installText = if ($row.installDrives.Count -gt 0) { $row.installDrives -join ',' } else { "unknown" }
    $activeText = if ($row.active) { "active" } else { "not running" }
    $deltaText = if ($null -ne $row.deltaBytes) { "; delta=$('{0:+0.00;-0.00;0.00}' -f ($row.deltaBytes/1GB)) GB" } else { "" }
    $mismatch = ($row.installDrives | Where-Object { $_ -and $_ -ne 'C:' }).Count -gt 0 -and $row.cBytes -ge 500MB
    $mismatchText = if ($mismatch) { "; app installed off C but user/runtime data remains on C" } else { "" }
    Write-Host ("  {0,-22} {1,7:N2} GB  [{2}; install={3}{4}{5}]" -f $row.name, ($row.cBytes/1GB), $activeText, $installText, $mismatchText, $deltaText) -ForegroundColor $(if($mismatch){"Yellow"}else{"DarkCyan"})
    foreach ($child in @($row.topChildren | Select-Object -First 3)) {
        Write-Host ("     {0,-26} {1,7:N2} GB" -f $child.name, ($child.bytes/1GB)) -ForegroundColor DarkGray
    }
    $evidence = "C-located logical bytes; reparse targets excluded; install_drive=$installText; active=$($row.active); safe_cache=$([math]::Round($row.safeCleanBytes/1GB,2))GB; managed=$([math]::Round($row.managedCleanBytes/1GB,2))GB; migration_candidate=$([math]::Round($row.migrationCandidateBytes/1GB,2))GB$mismatchText$deltaText"
    Write-InventoryResult -Category "AF-ai-footprint" -Name $row.name -Size $row.cBytes -Path (@($row.roots | Where-Object { $_.drive -eq 'C:\' } | ForEach-Object path) -join '; ') `
        -Kind "ai-app-logical-footprint" -Evidence $evidence -Access $row.status
}

foreach ($group in @($uniqueActionComponents | Group-Object { "$($_.AppId)|$($_.Kind)|$($_.Action)|$($_.Risk)" } | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending)) {
    $first = $group.Group[0]
    $bytes = [int64](($group.Group | Measure-Object -Property Bytes -Sum).Sum)
    $risk = if ($first.Action -eq 'safe-clean') { "safe" } else { "cautious" }
    $active = [bool](@($appRows | Where-Object id -eq $first.AppId | Select-Object -First 1).active)
    $notes = @($group.Group | ForEach-Object { if($_.Note){$_.Note}else{$_.Kind} } | Select-Object -Unique)
    $note = $notes -join '; '
    if ($active) { $note = "$note; related process is running, so execution must wait until it exits" }
    $displayPath = if ($group.Count -eq 1) { $first.Path } else { "$($group.Count) exact paths; see JSON measurements" }
    $measurements = @($group.Group | ForEach-Object {
        [pscustomobject]@{ Path=$_.Path; Bytes=$_.Bytes; Status=$_.Status; Evidence="AI one-pass component accounting" }
    })
    Write-ScanResult -Category "AF" -Name "$($first.AppName) / $($first.Kind) ($($group.Count))" -Size $bytes -Risk $risk `
        -Path $displayPath -Advice $(if($risk -eq 'safe'){"Close the app, preview, then clean"}else{"Use the app or dedicated cleaner after confirmation"}) `
        -Migration "" -Note $note -Source "AI-footprint" -Measurements $measurements
}

$snapshot = [pscustomobject]@{
    schema=1; measurementVersion=[int]$config.measurementVersion; timestamp=(Get-Date).ToString('o'); cBytes=$totalCBytes
    apps=@()
}
# Avoid serializing diagnostic-only child lists twice in history; app rows remain
# complete in scanner metadata below.
$snapshot.apps = @($appRows | ForEach-Object { [pscustomobject]@{ id=$_.id; name=$_.name; cBytes=$_.cBytes; status=$_.status } })
if ($Global:CDriveRecordGrowth) {
    if (-not (Test-Path -LiteralPath $historyDirectory)) { New-Item -ItemType Directory -Path $historyDirectory -Force | Out-Null }
    $snapshot | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $latestPath -Encoding UTF8
    ($snapshot | ConvertTo-Json -Depth 6 -Compress) | Add-Content -LiteralPath (Join-Path $historyDirectory 'history.jsonl') -Encoding UTF8
    Write-Host "  AI footprint baseline recorded: $latestPath" -ForegroundColor Green
}

if ($null -eq $Global:CDriveScannerMetadata) { $Global:CDriveScannerMetadata = @{} }
$Global:CDriveScannerMetadata["AF"] = [pscustomobject]@{
    schema=1; engine=if($scan){"one-pass Win32 aggregation"}else{"logical measurement fallback"}
    elapsed_seconds=if($scan){[math]::Round($scan.ElapsedSeconds,3)}else{$null}
    c_bytes=$totalCBytes; logical_c_bytes=$totalCBytes; measurement_basis='logical file lengths on C; reparse targets excluded; allocated bytes verified only during cleanup/SA'
    safe_clean_bytes=$safeTotal; managed_clean_bytes=$managedTotal; migration_candidate_bytes=$migrationTotal
    enumerated_files=if($scan){[int64]$scan.EnumeratedFiles}else{$null}; skipped_directories=if($scan){[int64]$scan.SkippedDirectories}else{$null}
    previous_compatible=[bool]$previousCompatible; snapshot_path=$latestPath; recorded=[bool]$Global:CDriveRecordGrowth
    apps=@($appRows); discovery_candidates=@($discoveryCandidates | Sort-Object bytes -Descending); external_roots=@($roots | Where-Object { $_.Status -in @('external','redirected') } | ForEach-Object {
        [pscustomobject]@{ appId=$_.AppId; path=$_.Path; drive=$_.Drive; status=$_.Status; linkTarget=$_.LinkTarget; kind=$_.Kind; source=$_.Source }
    }); accounting="inventory totals are C-located logical bytes with reparse targets excluded; only explicit components enter cleanup findings; cleanup sessions/SA provide allocated-byte evidence"
}
Write-Host ""
