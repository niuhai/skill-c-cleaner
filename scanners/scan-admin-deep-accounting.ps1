# scan-admin-deep-accounting.ps1 - AD: elevated, read-only system space accounting
# Never turns protected Windows stores into automatic cleanup findings.

if (-not (Get-Command "Write-InventoryResult" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== AD: Administrator deep space accounting =====" -ForegroundColor Cyan
$isAdmin = Test-Admin
$reserveKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager'
$reserve = Get-ItemProperty -LiteralPath $reserveKey -ErrorAction SilentlyContinue
if ($reserve) {
    $reserveEstimate = [math]::Max(0L, [int64]$reserve.BaseHardReserveSize + [int64]$reserve.HardReserveAdjustment)
    $reserveState = if ([int]$reserve.ShippedWithReserves -eq 1 -and [int]$reserve.PassedPolicy -eq 1) { "enabled-policy" } else { "disabled-or-not-qualified" }
    Write-InventoryResult -Category "AD-reserved-storage" -Name "Reserved Storage policy baseline" -Size $reserveEstimate `
        -Path $reserveKey -Kind "protected-system-accounting" `
        -Evidence "state=$reserveState; registry baseline/adjustment is an estimate, not current physical usage" -Access "ok"
}

if (-not $isAdmin) {
    Write-InventoryResult -Category "AD-admin-required" -Name "Administrator-only accounting not executed" -Size 0 `
        -Path "C:\Windows; C:\Program Files\WindowsApps; System Restore" -Kind "permission-gap" `
        -Evidence "Re-run PowerShell as Administrator with -Categories AD to inspect VSS, component store, WindowsApps, Installer and DriverStore read-only." -Access "inaccessible"
    $Global:CDriveScannerMetadata["AD"] = [pscustomobject]@{ Admin=$false; Status="admin-required"; MeasuredPaths=0; AppxPackages=0 }
    Write-Host "  Administrator rights are required for the remaining deep accounting probes." -ForegroundColor Yellow
    Write-Host ""
} else {
$staticTargets = @(
    [pscustomobject]@{ Name="Windows Installer cache"; Path="C:\Windows\Installer"; Kind="protected-installer-store"; Note="Inventory only. MSI/MSP files are required for repair, update, and uninstall." },
    [pscustomobject]@{ Name="DriverStore FileRepository"; Path="C:\Windows\System32\DriverStore\FileRepository"; Kind="protected-driver-store"; Note="Inventory only. Remove obsolete drivers through pnputil or Device Manager, never by deleting files." }
)

$packages = @()
try {
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
        $_.InstallLocation -and $_.InstallLocation.StartsWith('C:\', [StringComparison]::OrdinalIgnoreCase)
    } | Group-Object InstallLocation | ForEach-Object { $_.Group | Select-Object -First 1 })
} catch {
    Write-InventoryResult -Category "AD-windowsapps" -Name "WindowsApps package inventory unavailable" -Size 0 `
        -Path "C:\Program Files\WindowsApps" -Kind "permission-gap" -Evidence $_.Exception.Message -Access "inaccessible"
}

$measurePaths = [System.Collections.ArrayList]::new()
foreach ($target in $staticTargets) { [void]$measurePaths.Add($target.Path) }
foreach ($package in $packages) { [void]$measurePaths.Add([string]$package.InstallLocation) }
$batch = Invoke-PathMeasurementPlan -Paths @($measurePaths) -Parallelism 4

foreach ($target in $staticTargets) {
    $measurement = Get-PathLogicalMeasurement -Path $target.Path
    if ($measurement.Status -eq "missing") { continue }
    Write-InventoryResult -Category "AD-protected-store" -Name $target.Name -Size $measurement.Bytes `
        -Path $target.Path -Kind $target.Kind -Evidence "$($target.Note) measurement=$($measurement.Status)" -Access $measurement.Status
}

$appxRows = [System.Collections.ArrayList]::new()
foreach ($package in $packages) {
    $measurement = Get-PathLogicalMeasurement -Path ([string]$package.InstallLocation)
    if ($measurement.Status -eq "missing") { continue }
    [void]$appxRows.Add([pscustomobject]@{
        Name=[string]$package.Name; PackageFullName=[string]$package.PackageFullName
        Path=[string]$package.InstallLocation; Bytes=[int64]$measurement.Bytes; Status=[string]$measurement.Status
    })
}
$appxBytes = [int64](($appxRows | Measure-Object Bytes -Sum).Sum)
if ($appxRows.Count -gt 0) {
    Write-InventoryResult -Category "AD-windowsapps" -Name "WindowsApps package roots (logical aggregate)" -Size $appxBytes `
        -Path "C:\Program Files\WindowsApps" -Kind "protected-app-package-store" `
        -Evidence "$($appxRows.Count) unique InstallLocation paths; package sharing/hardlinks can make logical bytes differ from physical allocation; uninstall through Apps/winget only" -Access "ok"
}

$shadowRows = @()
try {
    $cVolume = Get-CimInstance -ClassName Win32_Volume -Filter "DriveLetter='C:'" -ErrorAction Stop | Select-Object -First 1
    $cVolumeId = if ($cVolume) { ([string]$cVolume.DeviceID).TrimEnd('\') } else { "" }
    $allShadowRows = @(Get-CimInstance -ClassName Win32_ShadowStorage -ErrorAction Stop)
    $shadowRows = @($allShadowRows | Where-Object {
        $volumeRef = $_.Volume
        $volumeId = if ($volumeRef -and $volumeRef.PSObject.Properties['DeviceID']) { [string]$volumeRef.DeviceID } else { [string]$volumeRef }
        $cVolumeId -and $volumeId.TrimEnd('\').IndexOf($cVolumeId, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
} catch {}
if ($shadowRows.Count -gt 0) {
    $shadowUsed = [int64](($shadowRows | Measure-Object UsedSpace -Sum).Sum)
    $shadowAllocated = [int64](($shadowRows | Measure-Object AllocatedSpace -Sum).Sum)
    $shadowMax = [int64](($shadowRows | Measure-Object MaxSpace -Sum).Sum)
    Write-InventoryResult -Category "AD-shadow-storage" -Name "VSS / System Restore used space" -Size $shadowUsed `
        -Path "System Volume Information" -Kind "protected-shadow-storage" `
        -Evidence "Win32_ShadowStorage: allocated=$([math]::Round($shadowAllocated/1GB,2)) GB; maximum=$([math]::Round($shadowMax/1GB,2)) GB; manage through System Protection/vssadmin" -Access "ok"
} else {
    Write-InventoryResult -Category "AD-shadow-storage" -Name "VSS / System Restore storage" -Size 0 `
        -Path "System Volume Information" -Kind "protected-shadow-storage" -Evidence "No C: Win32_ShadowStorage instance was returned." -Access "partial"
}

function Convert-DismSizeToBytes {
    param([string]$Text, [string]$Label)
    $match = [regex]::Match($Text, "(?im)^\s*$([regex]::Escape($Label))\s*:\s*([0-9.,]+)\s*(bytes|KB|MB|GB|TB)")
    if (-not $match.Success) { return [int64]0 }
    $number = [double]::Parse(($match.Groups[1].Value -replace ',',''), [Globalization.CultureInfo]::InvariantCulture)
    $factor = switch ($match.Groups[2].Value.ToUpperInvariant()) { "KB" { 1KB } "MB" { 1MB } "GB" { 1GB } "TB" { 1TB } default { 1 } }
    return [int64]($number * $factor)
}

$dismText = ""
try { $dismText = @(& dism.exe /Online /Cleanup-Image /AnalyzeComponentStore /English 2>&1) -join "`n" } catch {}
$componentBytes = if ($dismText) { Convert-DismSizeToBytes -Text $dismText -Label "Actual Size of Component Store" } else { 0L }
if ($componentBytes -gt 0) {
    $sharedBytes = Convert-DismSizeToBytes -Text $dismText -Label "Shared with Windows"
    $backupBytes = Convert-DismSizeToBytes -Text $dismText -Label "Backups and Disabled Features"
    $cacheBytes = Convert-DismSizeToBytes -Text $dismText -Label "Cache and Temporary Data"
    $packagesMatch = [regex]::Match($dismText, '(?im)^\s*Number of Reclaimable Packages\s*:\s*(\d+)')
    $cleanupMatch = [regex]::Match($dismText, '(?im)^\s*Component Store Cleanup Recommended\s*:\s*(Yes|No)')
    Write-InventoryResult -Category "AD-component-store" -Name "WinSxS actual component-store size" -Size $componentBytes `
        -Path "C:\Windows\WinSxS" -Kind "protected-component-store" `
        -Evidence "DISM read-only analysis: shared=$([math]::Round($sharedBytes/1GB,2)) GB; backups/features=$([math]::Round($backupBytes/1GB,2)) GB; cache/temp=$([math]::Round($cacheBytes/1GB,2)) GB; reclaimablePackages=$($packagesMatch.Groups[1].Value); cleanupRecommended=$($cleanupMatch.Groups[1].Value)" -Access "ok"
} else {
    Write-InventoryResult -Category "AD-component-store" -Name "WinSxS DISM accounting unavailable" -Size 0 `
        -Path "C:\Windows\WinSxS" -Kind "permission-gap" -Evidence "DISM /AnalyzeComponentStore did not return a parseable actual-size value." -Access "partial"
}

$Global:CDriveScannerMetadata["AD"] = [pscustomobject]@{
    Admin=$true; Status="completed"; MeasurementBatch=$batch; MeasuredPaths=$measurePaths.Count
    AppxPackages=$appxRows.Count; AppxLogicalBytes=$appxBytes
    TopAppx=@($appxRows | Sort-Object Bytes -Descending | Select-Object -First 20)
    ShadowStorageInstances=$shadowRows.Count; ComponentStoreBytes=$componentBytes
}
Write-Host "  Protected stores remain inventory-only; no cleanup allowance was added." -ForegroundColor Yellow
Write-Host ""
}
