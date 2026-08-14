# scan-duplicate-runtimes.ps1 - J class: Electron/CEF runtime inventory
# Read-only. Application footprints and runtime-shaped bytes are inventory only.

if (-not (Get-Command "Initialize-NativeFileScanner" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== J: Electron/CEF runtime inventory =====" -ForegroundColor Cyan
$fastMode = [bool]$Global:CDriveFastMode
$scanMode = if ($fastMode) { "focused-fast" } else { "broad-deep" }
Write-Host "Native scan ($scanMode); application footprints are not counted as cleanup capacity." -ForegroundColor DarkGray

try {
    Initialize-NativeFileScanner
} catch {
    Write-Host "  Native scanner unavailable: $($_.Exception.Message)" -ForegroundColor Red
    return
}

$exclusions = @(
    "C:\Program Files\WindowsApps",
    "C:\Program Files (x86)\WindowsApps"
)
$expandContainers = @(
    "Microsoft",
    "Google",
    "Tencent"
)

$scanRoots = @()
$exactCandidates = @()
$candidateSources = [ordered]@{
    registry = 0
    configured = 0
    containers = 0
}

if ($fastMode) {
    $candidateSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $candidateLabels = @{}
    $broadRoots = @(
        "C:\",
        $env:SystemRoot,
        (Join-Path $env:SystemRoot "System32"),
        (Join-Path $env:SystemRoot "SysWOW64"),
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:LOCALAPPDATA,
        $env:APPDATA,
        $env:USERPROFILE
    ) | Where-Object { $_ } | ForEach-Object {
        try { [IO.Path]::GetFullPath($_).TrimEnd('\') } catch { $_.TrimEnd('\') }
    }
    $excludedCandidateTrees = @(
        $env:SystemRoot,
        (Join-Path $env:ProgramData "Package Cache"),
        (Join-Path $env:LOCALAPPDATA "Package Cache")
    ) | Where-Object { $_ } | ForEach-Object {
        try { [IO.Path]::GetFullPath($_).TrimEnd('\') } catch { $_.TrimEnd('\') }
    }

    function Add-RuntimeCandidate {
        param([string]$Path, [string]$Source, [string]$Label = "")
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        $expanded = [Environment]::ExpandEnvironmentVariables($Path).Trim().Trim('"')
        try { $expanded = [IO.Path]::GetFullPath($expanded).TrimEnd('\') } catch { $expanded = $expanded.TrimEnd('\') }
        if ([IO.Path]::GetPathRoot($expanded) -ne "C:\") { return }
        if ($broadRoots -contains $expanded) { return }
        foreach ($excludedTree in $excludedCandidateTrees) {
            if ($expanded -eq $excludedTree -or $expanded.StartsWith($excludedTree + "\", [StringComparison]::OrdinalIgnoreCase)) { return }
        }
        if ($candidateSet.Add($expanded)) { $candidateSources[$Source]++ }
        if ($Label) { $candidateLabels[$expanded] = $Label }
    }

    foreach ($entry in @(Get-UninstallRegistryEntries)) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.DisplayName)) { continue }
        Add-RuntimeCandidate -Path (Resolve-UninstallInstallFolder -Entry $entry -NoExistenceCheck -InstallLocationOnly) -Source "registry" -Label ([string]$entry.DisplayName).Trim()
    }

    $runtimeConfigPath = Join-Path (Get-SkillRoot) "extensions\runtime-inventory.json"
    if (Test-Path -LiteralPath $runtimeConfigPath -PathType Leaf -ErrorAction SilentlyContinue) {
        try {
            $runtimeConfig = Get-Content -LiteralPath $runtimeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($path in @($runtimeConfig.exact_paths)) {
                Add-RuntimeCandidate -Path ([string]$path) -Source "configured"
            }
            foreach ($container in @($runtimeConfig.candidate_containers)) {
                $containerPath = [Environment]::ExpandEnvironmentVariables([string]$container)
                if (-not (Test-Path -LiteralPath $containerPath -PathType Container -ErrorAction SilentlyContinue)) { continue }
                foreach ($child in @(Get-ChildItem -LiteralPath $containerPath -Directory -Force -ErrorAction SilentlyContinue)) {
                    Add-RuntimeCandidate -Path $child.FullName -Source "containers"
                }
            }
        } catch {
            Write-Host "  Runtime inventory config could not be read: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    $allCandidates = @($candidateSet)
    $exactCandidates = @(
        foreach ($candidate in $allCandidates) {
            $hasParent = $false
            foreach ($other in $allCandidates) {
                if ($candidate -eq $other) { continue }
                if ($candidate.StartsWith($other.TrimEnd('\') + "\", [StringComparison]::OrdinalIgnoreCase)) {
                    $hasParent = $true
                    break
                }
            }
            if (-not $hasParent) { $candidate }
        }
    )
    $candidateSources["deduplicated"] = $allCandidates.Count - $exactCandidates.Count
    Write-Host "  Fast coverage: uninstall install roots + configured runtime roots; use full J for broad AppData discovery." -ForegroundColor DarkGray
} else {
    $candidateLabels = @{}
    $scanRoots = @(
        $env:LOCALAPPDATA,
        $env:APPDATA,
        ${env:ProgramFiles(x86)},
        $env:ProgramFiles
    ) | Where-Object {
        $_ -and (Test-Path -LiteralPath $_ -PathType Container -ErrorAction SilentlyContinue)
    } | Select-Object -Unique
}

$scan = [CleanSight.NativeFileScanner]::ScanRuntimeApps(
    [string[]]$scanRoots,
    [string[]]$exclusions,
    [string[]]$expandContainers,
    [string[]]$exactCandidates,
    4
)
$apps = @($scan.Apps | Sort-Object TotalBytes -Descending)

function Get-AppIdentity {
    param([object]$App)
    if ($candidateLabels.ContainsKey($App.Path)) { return [string]$candidateLabels[$App.Path] }
    $packageJson = Join-Path $App.Path "package.json"
    if (Test-Path -LiteralPath $packageJson -PathType Leaf -ErrorAction SilentlyContinue) {
        try {
            $package = Get-Content -LiteralPath $packageJson -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($package.productName) { return [string]$package.productName }
            if ($package.name) { return [string]$package.name }
        } catch { }
    }
    if ($App.ExecutableNames -and @($App.ExecutableNames).Count -gt 0) {
        return (@($App.ExecutableNames) -join ", ")
    }
    return ""
}

if ($apps.Count -eq 0) {
    Write-Host "  No Electron/CEF application roots detected." -ForegroundColor DarkGray
} else {
    $totalBytes = [int64](($apps | Measure-Object TotalBytes -Sum).Sum)
    $runtimeBytes = [int64](($apps | Measure-Object RuntimeBytes -Sum).Sum)
    Write-Host ("  Detected {0} application roots; footprint {1:N2} GB; runtime-shaped files {2:N2} GB." -f $apps.Count, ($totalBytes / 1GB), ($runtimeBytes / 1GB)) -ForegroundColor Yellow
    Write-Host "  Runtime-shaped bytes are not automatically reclaimable; uninstalling an unused app is the supported action." -ForegroundColor DarkGray
    Write-Host ""

    foreach ($app in $apps) {
        $identity = Get-AppIdentity -App $app
        $displayName = if ($identity) { "$($app.DirectoryName) ($identity)" } else { $app.DirectoryName }
        $runtimePercent = if ($app.TotalBytes -gt 0) {
            [math]::Round($app.RuntimeBytes / $app.TotalBytes * 100, 0)
        } else { 0 }
        $sizeText = if ($app.TotalBytes -ge 1GB) {
            "$([math]::Round($app.TotalBytes/1GB,2)) GB"
        } else {
            "$([math]::Round($app.TotalBytes/1MB,1)) MB"
        }
        Write-Host "  ${displayName}: $sizeText" -ForegroundColor DarkCyan
        Write-Host "     Path: $($app.Path)" -ForegroundColor DarkGray
        Write-Host "     Evidence: runtime-shaped ${runtimePercent}% ($([math]::Round($app.RuntimeBytes/1MB,1)) MB); $($app.PakCount) .pak files" -ForegroundColor DarkGray

        [void]$Global:CDriveInventory.Add(@{
            Category = "J"
            Name = "$displayName (Electron/CEF)"
            SizeMB = [math]::Round([int64]$app.TotalBytes / 1MB, 2)
            SizeBytes = [int64]$app.TotalBytes
            Path = $app.Path
            Kind = "installed-electron-app"
            Evidence = "runtime-shaped ${runtimePercent}%; $($app.PakCount) .pak files; use supported uninstall only after confirming the app is unused"
            Access = if ($app.SkippedDirectories -gt 0) { "partial" } else { "ok" }
        })
    }
}

if ($null -eq $Global:CDriveScannerMetadata) { $Global:CDriveScannerMetadata = @{} }
$Global:CDriveScannerMetadata["J"] = @{
    engine = "Win32 FindFirstFileExW"
    elapsed_seconds = [math]::Round($scan.ElapsedSeconds, 3)
    candidates = [int64]$scan.CandidateDirectories
    files = [int64]$scan.EnumeratedFiles
    skipped_directories = [int64]$scan.SkippedDirectories
    findings = $apps.Count
    expanded_containers = @($expandContainers)
    mode = $scanMode
    coverage = if ($fastMode) { "focused install/runtime roots; broad AppData discovery deferred to full J" } else { "broad immediate application roots" }
    candidate_sources = $candidateSources
    accounting = "inventory-only"
}

Write-Host ("  Runtime scan completed in {0:N1}s across {1:N0} files." -f $scan.ElapsedSeconds, $scan.EnumeratedFiles) -ForegroundColor DarkGray
Write-Host ""
