# scan-virtual-memory.ps1 - virtual memory assessment
# Read-only. Never changes registry, system properties, or pagefile files.

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "`n===== Virtual memory assessment =====" -ForegroundColor Cyan
$vmScanWatch = [Diagnostics.Stopwatch]::StartNew()

function Format-BytesGB {
    param([double]$Bytes)
    return [math]::Round($Bytes / 1GB, 2)
}

function Normalize-PagefilePath {
    param([string]$Path)
    if (-not $Path) { return "" }
    $prefix = '\??\'
    if ($Path.StartsWith($prefix)) { return $Path.Substring($prefix.Length) }
    return $Path
}

function Get-PagefileConfiguration {
    $entries = @()
    try {
        $key = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -ErrorAction Stop
        foreach ($line in @($key.PagingFiles)) {
            if (-not $line) { continue }
            $parts = @($line -split '\s+') | Where-Object { $_ -ne "" }
            if ($parts.Count -lt 3) { continue }

            $path = Normalize-PagefilePath ([string]$parts[0])
            $initialMB = 0L
            $maximumMB = 0L
            [void][long]::TryParse($parts[1], [ref]$initialMB)
            [void][long]::TryParse($parts[2], [ref]$maximumMB)
            $driveMatch = [regex]::Match($path, '^(?<drive>[A-Za-z]):')
            $actualBytes = 0L
            $actualReadable = $false

            try {
                $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if ($item -and -not $item.PSIsContainer) {
                    $actualBytes = [long]$item.Length
                    $actualReadable = $true
                }
            } catch {
                # pagefile.sys is commonly protected; registry data is still useful.
            }

            $entries += [PSCustomObject]@{
                Path = $path
                Drive = if ($driveMatch.Success) { $driveMatch.Groups['drive'].Value.ToUpperInvariant() } else { "" }
                InitialMB = $initialMB
                MaximumMB = $maximumMB
                SystemManaged = ($initialMB -eq 0 -and $maximumMB -eq 0)
                ActualBytes = $actualBytes
                ActualReadable = $actualReadable
            }
        }
    } catch {
        # Permission-limited sessions may not expose the registry value.
    }
    return @($entries)
}

function Get-PagefileUsageInfo {
    $items = @()
    try {
        $items = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
    } catch {
        try { $items = @(Get-WmiObject -Class Win32_PageFileUsage -ErrorAction Stop) } catch { $items = @() }
    }
    return @($items)
}

function Get-PhysicalMemoryBytes {
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($computer.TotalPhysicalMemory) { return [long]$computer.TotalPhysicalMemory }
    } catch {}
    try {
        $computer = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        if ($computer.TotalPhysicalMemory) { return [long]$computer.TotalPhysicalMemory }
    } catch {}
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
        $computerInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
        if ($computerInfo.TotalPhysicalMemory) { return [long]$computerInfo.TotalPhysicalMemory }
    } catch {}
    return 0L
}

function Get-CrashDumpMode {
    try {
        $value = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -ErrorAction Stop
        return $value.CrashDumpEnabled
    } catch {
        return $null
    }
}

function Get-DriveSnapshot {
    $snapshots = @()
    $partitionByDrive = @{}
    $diskByNumber = @{}
    $storageWatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        foreach ($association in @(Get-CimInstance -ClassName Win32_LogicalDiskToPartition -ErrorAction Stop)) {
            $driveId = [string]$association.Dependent.DeviceID
            $partitionId = [string]$association.Antecedent.DeviceID
            $diskMatch = [regex]::Match($partitionId, '(?i)^Disk #(?<disk>\d+),')
            if ($driveId -match '^[A-Za-z]:$' -and $diskMatch.Success) {
                $partitionByDrive[$driveId.Substring(0, 1).ToUpperInvariant()] = [pscustomobject]@{
                    DiskNumber = [int]$diskMatch.Groups['disk'].Value
                }
            }
        }
    } catch {}
    try {
        foreach ($disk in @(Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop)) {
            $diskByNumber[[int]$disk.Index] = $disk
        }
    } catch {}
    $storageWatch.Stop()
    $script:VMStorageProbeSeconds = [math]::Round($storageWatch.Elapsed.TotalSeconds, 3)

    try {
        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            if (-not $drive.IsReady -or $drive.DriveType -ne [System.IO.DriveType]::Fixed) { continue }
            $freePercent = 0
            if ($drive.TotalSize -gt 0) {
                $freePercent = [math]::Round(($drive.AvailableFreeSpace / $drive.TotalSize) * 100, 1)
            }

            $diskNumber = $null
            $mediaType = "Unknown"
            $busType = "Unknown"
            try {
                $driveLetter = $drive.Name.Substring(0, 1).ToUpperInvariant()
                $partition = $partitionByDrive[$driveLetter]
                if (-not $partition) { throw "partition metadata unavailable" }
                $diskNumber = $partition.DiskNumber
                $disk = $diskByNumber[[int]$diskNumber]
                if (-not $disk) { throw "disk metadata unavailable" }
                if ($disk.MediaType) { $mediaType = [string]$disk.MediaType }
                if ([string]$disk.Model -match '(?i)NVMe') { $busType = "NVMe" }
                elseif ($disk.InterfaceType) { $busType = [string]$disk.InterfaceType }
            } catch {}

            $snapshots += [PSCustomObject]@{
                Drive = $drive.Name.Substring(0, 1).ToUpperInvariant()
                TotalBytes = [long]$drive.TotalSize
                FreeBytes = [long]$drive.AvailableFreeSpace
                TotalGB = Format-BytesGB $drive.TotalSize
                FreeGB = Format-BytesGB $drive.AvailableFreeSpace
                FreePercent = $freePercent
                DiskNumber = $diskNumber
                MediaType = $mediaType
                BusType = $busType
            }
        }
    } catch {}
    return @($snapshots)
}

$isAdmin = $false
try { $isAdmin = Test-Admin } catch {}
if (-not $isAdmin) {
    Write-Host "  WARNING: non-admin session; usage and disk metadata may be incomplete" -ForegroundColor Yellow
}

$driveSnapshots = @(Get-DriveSnapshot)
$driveC = $driveSnapshots | Where-Object { $_.Drive -eq "C" } | Select-Object -First 1
if (-not $driveC) {
    Write-Host "  ERROR: C drive information unavailable" -ForegroundColor Red
    return
}

$freePercent = $driveC.FreePercent
$freeGB = $driveC.FreeGB
$totalGB = $driveC.TotalGB
$ramBytes = Get-PhysicalMemoryBytes
$ramGB = if ($ramBytes -gt 0) { Format-BytesGB $ramBytes } else { $null }
$crashDumpMode = Get-CrashDumpMode
$pagefiles = @(Get-PagefileConfiguration)
$usageItems = @(Get-PagefileUsageInfo)
$recommendations = @()
$suitableDrives = @()

Write-Host "`n  [System state]" -ForegroundColor White
$freeColor = if ($freePercent -lt 20) { "Red" } elseif ($freePercent -lt 30) { "Yellow" } else { "Green" }
Write-Host "  C free: $freeGB GB / $totalGB GB ($freePercent%)" -ForegroundColor $freeColor
if ($ramGB) { Write-Host "  Physical memory: $ramGB GB" -ForegroundColor DarkGray }
else { Write-Host "  Physical memory: unavailable" -ForegroundColor DarkGray }
if ($null -ne $crashDumpMode) { Write-Host "  Crash dump mode: $crashDumpMode" -ForegroundColor DarkGray }

if ($pagefiles.Count -gt 0) {
    Write-Host "`n  [PagingFiles registry configuration]" -ForegroundColor White
    foreach ($pf in $pagefiles) {
        $sizeText = if ($pf.SystemManaged) { "system managed" } else { "$($pf.InitialMB)-$($pf.MaximumMB) MB" }
        $actualText = if ($pf.ActualReadable) { "; actual file $((Format-BytesGB $pf.ActualBytes)) GB" } else { "; actual size unavailable" }
        $color = if ($pf.Drive -eq "C") { "Yellow" } else { "Green" }
        Write-Host "  $($pf.Path): $sizeText$actualText" -ForegroundColor $color
    }
} else {
    Write-Host "`n  [PagingFiles registry configuration]" -ForegroundColor White
    Write-Host "  WARNING: PagingFiles could not be read; do not infer that no pagefile exists" -ForegroundColor Yellow
}

if ($usageItems.Count -gt 0) {
    Write-Host "`n  [Pagefile usage]" -ForegroundColor White
    foreach ($usage in $usageItems) {
        Write-Host "  $($usage.Name): allocated $($usage.AllocatedBaseSize) MB; current $($usage.CurrentUsage) MB; peak $($usage.PeakUsage) MB" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Pagefile usage: unavailable" -ForegroundColor DarkGray
}

$cPagefiles = @($pagefiles | Where-Object { $_.Drive -eq "C" })
$offCPagefiles = @($pagefiles | Where-Object { $_.Drive -and $_.Drive -ne "C" })
$cActualBytes = [long](($cPagefiles | Measure-Object ActualBytes -Sum).Sum)
$cConfiguredMaxMB = [long](($cPagefiles | Measure-Object MaximumMB -Sum).Sum)
$cConfiguredInitialMB = [long](($cPagefiles | Measure-Object InitialMB -Sum).Sum)
$allConfiguredMaxMB = [long](($pagefiles | Measure-Object MaximumMB -Sum).Sum)
$cPagefileKnown = ($cPagefiles.Count -gt 0)

Write-Host "`n  [Assessment]" -ForegroundColor White
if ($cPagefileKnown) {
    $cReclaimGB = if ($cActualBytes -gt 0) { Format-BytesGB $cActualBytes } elseif ($cConfiguredInitialMB -gt 0) { [math]::Round($cConfiguredInitialMB / 1024, 2) } else { 0 }
    $cMaxGB = [math]::Round($cConfiguredMaxMB / 1024, 2)
    $assessment = if ($freePercent -lt 20) { "critical" } elseif ($freePercent -lt 30) { "warning" } else { "normal" }

    if ($offCPagefiles.Count -gt 0) {
        Write-Host "  Layout: C pagefile plus non-C pagefile (hybrid)" -ForegroundColor Green
        Write-Host "  C reclaim estimate: about $cReclaimGB GB actual file size" -ForegroundColor Yellow
        Write-Host "  Result: migration mainly frees C space; it is not automatically a performance upgrade" -ForegroundColor DarkGray
        $recommendations += @{
            Priority = if ($assessment -eq "critical") { "high" } else { "medium" }
            Action = "Keep the non-C primary pagefile; review the C pagefile before removing it"
            Detail = "The current configuration is already hybrid. Keep a C pagefile when complete crash dumps are required; otherwise any change must be confirmed and tested after reboot."
            SpaceRelease = $cReclaimGB
            PerformanceGain = "mainly C space; performance depends on physical disk layout"
        }
    } else {
        Write-Host "  Layout: pagefile only on C, or no non-C pagefile detected" -ForegroundColor Yellow
        Write-Host "  C configuration: initial $cConfiguredInitialMB MB; maximum $cConfiguredMaxMB MB" -ForegroundColor Yellow
        $recommendations += @{
            Priority = if ($assessment -eq "critical") { "high" } else { "medium" }
            Action = "Evaluate moving the primary pagefile to a spacious non-C drive"
            Detail = "Check free space, physical disk identity, media type, and crash-dump requirements before changing settings."
            SpaceRelease = $cReclaimGB
            PerformanceGain = "space benefit is clear; performance benefit requires a separate physical disk"
        }
    }
    if ($cMaxGB -gt 0) { Write-Host "  C maximum setting: $cMaxGB GB; this is not current disk usage" -ForegroundColor DarkGray }
    if ($offCPagefiles.Count -gt 0) {
        $offCMaxGB = [math]::Round((($offCPagefiles | Measure-Object MaximumMB -Sum).Sum) / 1024, 2)
        Write-Host "  Non-C maximum setting: $offCMaxGB GB; use this when evaluating another target drive" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  C pagefile configuration was not detected" -ForegroundColor Yellow
    $recommendations += @{
        Priority = "info"
        Action = "Confirm the pagefile source before changing anything"
        Detail = "The file may be on another drive, or the current session may lack permission to read the configuration."
        SpaceRelease = 0
        PerformanceGain = "unknown"
    }
}

$cDiskNumber = $driveC.DiskNumber
foreach ($drive in $driveSnapshots | Where-Object { $_.Drive -ne "C" -and $_.FreeGB -ge 32 }) {
    $maxRequiredGB = if ($allConfiguredMaxMB -gt 0) { [math]::Round($allConfiguredMaxMB / 1024, 2) } else { 32 }
    $hasHeadroom = $drive.FreeGB -ge ($maxRequiredGB + 8)
    $sameDisk = ($null -ne $cDiskNumber -and $null -ne $drive.DiskNumber -and $cDiskNumber -eq $drive.DiskNumber)
    $recommendation = if (-not $hasHeadroom) { "not enough headroom for current maximum" } elseif ($sameDisk) { "can free C space; speedup not guaranteed" } else { "candidate target; measure performance" }
    $suitableDrives += [PSCustomObject]@{
        Drive = $drive.Drive
        FreeGB = $drive.FreeGB
        MediaType = $drive.MediaType
        BusType = $drive.BusType
        DiskNumber = $drive.DiskNumber
        SamePhysicalDiskAsC = $sameDisk
        EnoughHeadroomForCurrentMax = $hasHeadroom
        Recommendation = $recommendation
    }
}

if ($suitableDrives.Count -gt 0) {
    Write-Host "`n  [Non-C candidates]" -ForegroundColor White
    foreach ($candidate in $suitableDrives) {
        $color = if ($candidate.EnoughHeadroomForCurrentMax) { "Green" } else { "Yellow" }
        Write-Host "  $($candidate.Drive): free $($candidate.FreeGB) GB; media $($candidate.MediaType); $($candidate.Recommendation)" -ForegroundColor $color
    }
} else {
    Write-Host "`n  [Non-C candidates]" -ForegroundColor White
    Write-Host "  No candidate drive met the space threshold" -ForegroundColor Yellow
}

Write-Host "`n  [Safety boundaries]" -ForegroundColor White
Write-Host "  - Never delete, truncate, or move pagefile.sys directly" -ForegroundColor DarkGray
Write-Host "  - Do not treat maximum configuration as current disk usage" -ForegroundColor DarkGray
Write-Host "  - Keep a C pagefile when crash-dump requirements are not confirmed" -ForegroundColor DarkGray
Write-Host "  - A different drive letter on the same physical disk does not guarantee an I/O gain" -ForegroundColor DarkGray

$globalVMResult = [PSCustomObject]@{
    Assessment = if ($cPagefileKnown) { if ($freePercent -lt 20) { "critical" } elseif ($freePercent -lt 30) { "warning" } else { "normal" } } else { "unknown" }
    OnC = $cPagefileKnown
    TotalSize = $cActualBytes
    ConfiguredCInitialMB = $cConfiguredInitialMB
    ConfiguredCMaximumMB = $cConfiguredMaxMB
    FreePercent = $freePercent
    PhysicalMemoryBytes = $ramBytes
    Pagefiles = $pagefiles
    Usage = $usageItems
    Recommendations = $recommendations
    SuitableDrives = $suitableDrives
    DetectionSource = if ($pagefiles.Count -gt 0) { "HKLM PagingFiles + file metadata" } else { "permission-limited" }
}

$Global:VMAssessResult = $globalVMResult
$vmScanWatch.Stop()
if ($null -eq $Global:CDriveScannerMetadata) { $Global:CDriveScannerMetadata = @{} }
$Global:CDriveScannerMetadata["VM"] = @{
    elapsed_seconds = [math]::Round($vmScanWatch.Elapsed.TotalSeconds, 3)
    storage_probe = "bulk Win32_LogicalDiskToPartition + Win32_DiskDrive"
    storage_probe_seconds = [double]$script:VMStorageProbeSeconds
    fixed_drives = $driveSnapshots.Count
    pagefiles = $pagefiles.Count
    accounting = "assessment-only"
}
Write-Host ""
