# scan-duplicate-runtimes.ps1 - J class: Electron/CEF runtime inventory
# Read-only. Application footprints and runtime-shaped bytes are inventory only.

if (-not (Get-Command "Initialize-NativeFileScanner" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== J: Electron/CEF runtime inventory =====" -ForegroundColor Cyan
Write-Host "Single-pass native scan; application footprints are not counted as cleanup capacity." -ForegroundColor DarkGray

try {
    Initialize-NativeFileScanner
} catch {
    Write-Host "  Native scanner unavailable: $($_.Exception.Message)" -ForegroundColor Red
    return
}

$scanRoots = @(
    $env:LOCALAPPDATA,
    $env:APPDATA,
    ${env:ProgramFiles(x86)},
    $env:ProgramFiles
) | Where-Object {
    $_ -and (Test-Path -LiteralPath $_ -PathType Container -ErrorAction SilentlyContinue)
} | Select-Object -Unique

$exclusions = @(
    "C:\Program Files\WindowsApps",
    "C:\Program Files (x86)\WindowsApps"
)
$expandContainers = @(
    "Microsoft",
    "Google",
    "Tencent"
)

$scan = [CleanSight.NativeFileScanner]::ScanRuntimeApps(
    [string[]]$scanRoots,
    [string[]]$exclusions,
    [string[]]$expandContainers,
    4
)
$apps = @($scan.Apps | Sort-Object TotalBytes -Descending)

function Get-AppIdentity {
    param([object]$App)
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
    accounting = "inventory-only"
}

Write-Host ("  Runtime scan completed in {0:N1}s across {1:N0} files." -f $scan.ElapsedSeconds, $scan.EnumeratedFiles) -ForegroundColor DarkGray
Write-Host ""
