# scan-system-hidden.ps1 - system hidden files
# Read-only. Never modifies files or system settings.

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== A: system hidden files =====" -ForegroundColor Cyan

$hiberPath = "C:\hiberfil.sys"
if (Test-Path $hiberPath) {
    $hiberSize = (Get-Item $hiberPath -Force).Length
    Write-ScanResult -Category "A" -Name "hiberfil.sys" -Size $hiberSize `
        -Risk "cautious" -Path $hiberPath `
        -Advice "May be removed only by disabling hibernation" -Migration "Not migratable"
} else {
    Write-Host "  Hibernation file: not found" -ForegroundColor DarkGray
}

$pagefilePaths = @("C:\pagefile.sys")
$pagefileConfigured = $false
try {
    $memoryKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -ErrorAction Stop
    foreach ($line in @($memoryKey.PagingFiles)) {
        if (-not $line) { continue }
        $parts = @($line -split '\s+') | Where-Object { $_ -ne "" }
        if ($parts.Count -ge 1) {
            $configuredPath = [string]$parts[0]
            $prefix = '\??\'
            if ($configuredPath.StartsWith($prefix)) { $configuredPath = $configuredPath.Substring($prefix.Length) }
            $pagefilePaths += $configuredPath
            $pagefileConfigured = $true
        }
    }
} catch {}

$pagefileFound = $false
foreach ($pagePath in @($pagefilePaths | Where-Object { $_ } | Select-Object -Unique)) {
    $pageSize = 0L
    $readable = $false
    try {
        $pageItem = Get-Item -LiteralPath $pagePath -Force -ErrorAction Stop
        if ($pageItem -and -not $pageItem.PSIsContainer) {
            $pageSize = [long]$pageItem.Length
            $readable = $true
        }
    } catch {}

    if ($readable) {
        Write-ScanResult -Category "A" -Name "pagefile.sys" -Size $pageSize `
            -Risk "forbidden" -Path $pagePath `
            -Advice "Do not delete directly; change through Virtual memory settings" -Migration "System Properties > Virtual memory"
        $pagefileFound = $true
    } elseif ($pagefileConfigured -and $pagePath -match '^[A-Za-z]:\\pagefile\.sys$') {
        Write-Host "  Pagefile configured: $pagePath (size unavailable)" -ForegroundColor Yellow
        $pagefileFound = $true
    }
}
if (-not $pagefileFound) {
    Write-Host "  Pagefile: no readable file or configuration found" -ForegroundColor DarkGray
}

try {
    $restorePoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    if ($restorePoints) {
        $restoreCount = @($restorePoints).Count
        Write-Host "  Restore points: $restoreCount" -ForegroundColor Yellow
        Write-Host "  Review manually; do not resize shadow storage automatically" -ForegroundColor DarkGray
    } else {
        Write-Host "  Restore points: none or unavailable" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  Restore points: unavailable" -ForegroundColor DarkGray
}

Write-Host "  WinSxS: use DISM analysis; never delete it manually" -ForegroundColor DarkGray
try {
    $dismOutput = Dism /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
    $dismText = $dismOutput -join "`n"
    if ($dismText -match "Component Store Cleanup Recommended\s*:\s*Yes") {
        Write-Host "  WinSxS cleanup is recommended by DISM" -ForegroundColor Yellow
        Write-Host "  Command for explicit review: Dism /Online /Cleanup-Image /StartComponentCleanup" -ForegroundColor DarkGray
    } else {
        Write-Host "  WinSxS: no cleanup recommendation from DISM" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  WinSxS: DISM analysis unavailable" -ForegroundColor DarkGray
}

Invoke-SignatureScan -Category "system" -CategoryLabel "A" -AlreadyScanned @(
    "Windows temp", "User temp", "Thumbnail cache", "Recycle bin", "Windows update cache",
    "Delivery Optimization", "Windows error reports", "Prefetch", "hiberfil.sys", "pagefile.sys"
)

Write-Host ""
