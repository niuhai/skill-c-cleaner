# scan-targeted-optimization.ps1 - targeted read-only scan

$scannerRoot = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $scannerRoot
if (-not (Test-Path (Join-Path $skillRoot "_common.ps1"))) { $skillRoot = "C:\.trae\skills\c-drive-cleaner" }
if (-not (Get-Command "Write-ScanResult" -ErrorAction SilentlyContinue)) {
    . (Join-Path $skillRoot "_common.ps1")
}

$configPath = Join-Path $skillRoot "extensions\targeted-optimization.json"
if (-not (Test-Path $configPath)) {
    Write-Host "Targeted optimization config not found." -ForegroundColor Yellow
    return
}

try {
    $config = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Host "Targeted optimization config parse failed: $($_.Exception.Message)" -ForegroundColor Red
    return
}

function Resolve-TargetMatches {
    param([string]$Root, [string]$Pattern)
    $candidate = Join-Path $Root $Pattern
    if ($Pattern -match '[*?]') {
        return @(Get-ChildItem -Path $candidate -Force -ErrorAction SilentlyContinue)
    }
    if (Test-Path -LiteralPath $candidate -ErrorAction SilentlyContinue) {
        return @(Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue)
    }
    return @()
}

function Convert-NativeTargetMeasurement {
    param([string]$Path, [object]$Native)
    if (-not $Native.Exists) {
        return [pscustomobject]@{ Path=$Path; Bytes=[int64]0; Status="missing"; Evidence="Win32 batch measurement; path missing or not enumerable" }
    }
    if ($Native.ReparsePoint) {
        return [pscustomobject]@{ Path=$Path; Bytes=[int64]0; Status="partial"; Evidence="Win32 batch measurement; reparse-point path was not followed" }
    }
    $status = if (-not $Native.RootAccessible) { "inaccessible" } elseif ($Native.SkippedDirectories -gt 0) { "partial" } else { "ok" }
    return [pscustomobject]@{
        Path = $Path
        Bytes = [int64]$Native.Bytes
        Status = $status
        Evidence = "Win32 batch measurement; skipped_directories=$($Native.SkippedDirectories); elapsed_seconds=$($Native.ElapsedSeconds)"
    }
}

function Test-WithinRoot {
    param([string]$Root, [string]$Path)
    try {
        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        $pathFull = [IO.Path]::GetFullPath($Path)
        return $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

$targetMatches = [Collections.ArrayList]::new()
foreach ($target in @($config.targets)) {
    $root = Expand-EnvPath $target.root
    if (-not (Test-Path -LiteralPath $root -ErrorAction SilentlyContinue)) { continue }

    $seen = @{}
    foreach ($pattern in @($target.paths)) {
        foreach ($item in @(Resolve-TargetMatches -Root $root -Pattern $pattern)) {
            if (-not $item) { continue }
            if (-not (Test-WithinRoot -Root $root -Path $item.FullName)) { continue }
            $key = $item.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            [void]$targetMatches.Add([pscustomobject]@{ Target=$target; Item=$item })
        }
    }
}

Write-Host "===== Targeted optimization scan =====" -ForegroundColor Cyan
if ($targetMatches.Count -gt 0) {
    $paths = [string[]]@($targetMatches | ForEach-Object { $_.Item.FullName })
    $nativeMeasurements = $null
    try {
        Initialize-NativeFileScanner
        $nativeMeasurements = [CleanSight.NativeFileScanner]::MeasurePaths($paths, 4)
    } catch {
        Write-Host "  Native batch measurement unavailable; using compatibility fallback." -ForegroundColor DarkGray
    }
    for ($index = 0; $index -lt $targetMatches.Count; $index++) {
        $match = $targetMatches[$index]
        $target = $match.Target
        $item = $match.Item
        $measurement = if ($null -ne $nativeMeasurements) {
            Convert-NativeTargetMeasurement -Path $item.FullName -Native $nativeMeasurements[$index]
        } else {
            Get-PathLogicalMeasurement -Path $item.FullName
        }
        if (-not $measurement -or $measurement.Bytes -le 0) { continue }
        $bytes = [int64]$measurement.Bytes

        $preserveText = @($target.preserve) -join ', '
        $preserve = if ($target.preserve -and @($target.preserve).Count -gt 0) {
            ("Keep: {0}" -f $preserveText)
        } else { "" }
        $advice = if ($target.risk -eq "safe") { "Clean after closing the app" } else { "Confirm after closing related processes" }
        Write-ScanResult -Category "O" -Name "$($target.name) / $($item.Name)" `
            -Size $bytes -Risk $target.risk -Path $item.FullName `
            -Advice $advice -Migration "" -Note "$($target.note) $preserve" -Source "Targeted" `
            -Measurements @($measurement)
    }
}
Write-Host ""
