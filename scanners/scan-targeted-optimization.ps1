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

function Get-TargetMeasurement {
    param([System.IO.FileSystemInfo]$Item)
    if (-not $Item) { return $null }
    if (-not $Item.PSIsContainer) {
        return [pscustomobject]@{ Path=$Item.FullName; Bytes=[int64]$Item.Length; Status="ok"; Evidence="file length" }
    }
    $measurement = Get-PathLogicalMeasurement -Path $Item.FullName
    return [pscustomobject]@{
        Path = $Item.FullName
        Bytes = [int64]$measurement.Bytes
        Status = $measurement.Status
        Evidence = $measurement.Evidence
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

Write-Host "===== Targeted optimization scan =====" -ForegroundColor Cyan
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
            $measurement = Get-TargetMeasurement $item
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
}
Write-Host ""
