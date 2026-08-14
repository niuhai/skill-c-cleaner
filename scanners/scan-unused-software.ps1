# U scanner: installed software candidates that deserve a manual usage check.
# Read-only: no uninstall command, registry write, or install-directory deletion.

if (-not (Get-Command "Write-ScanResult" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== U: installed software candidates =====" -ForegroundColor Cyan
Write-Host "This is a candidate list, not proof that software is unused." -ForegroundColor Yellow
$uScanWatch = [Diagnostics.Stopwatch]::StartNew()
$fastMode = [bool]$Global:CDriveFastMode

$oldDays = 180
$minimumBytes = 200MB
$largeWithoutDateBytes = 1GB
$cutoff = (Get-Date).AddDays(-$oldDays)

function Convert-EstimatedBytes {
    param($Value)
    try {
        if ($null -eq $Value) { return [int64]0 }
        $kb = [int64]$Value
        if ($kb -le 0) { return [int64]0 }
        return $kb * 1KB
    } catch { return [int64]0 }
}

function Convert-InstallDate {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    foreach ($format in @("yyyyMMdd", "yyyy/M/d", "yyyy/MM/dd", "yyyy-M-d", "yyyy-MM-dd", "yyyy.M.d", "yyyy.MM.dd")) {
        try { return [datetime]::ParseExact($Value.Trim(), $format, [Globalization.CultureInfo]::InvariantCulture) } catch {}
    }
    return $null
}

function Test-SystemSoftwareEntry {
    param($Entry)
    if ([int]$Entry.SystemComponent -eq 1) { return $true }
    if ($Entry.ReleaseType -in @("Security Update", "Update", "Hotfix")) { return $true }
    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.ParentKeyName)) { return $true }
    $name = [string]$Entry.DisplayName
    return $name -match '(?i)(Windows Update|Update for|Security Update|Visual C\+\+|\.NET|ASP\.NET|WebView2|Edge Update|Runtime|Redistributable|KB\d+)'
}

$rawEntries = @(Get-UninstallRegistryEntries)
$folderSizesMeasured = 0
$folderSizesSkippedFast = 0
$folderSizesSkippedNonC = 0
$folderSizesSkippedRecent = 0

$records = @(
    $rawEntries |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.DisplayName) -and
            -not (Test-SystemSoftwareEntry $_)
        } |
        ForEach-Object {
            $bytes = Convert-EstimatedBytes $_.EstimatedSize
            $date = Convert-InstallDate ([string]$_.InstallDate)
            $installFolder = Resolve-UninstallInstallFolder -Entry $_ -NoExistenceCheck:$fastMode -InstallLocationOnly:$fastMode
            $sizeSource = if ($bytes -gt 0) { "registry-estimate" } else { "unreported" }
            if ($bytes -le 0 -and $installFolder) {
                $isCInstall = $false
                try { $isCInstall = ([IO.Path]::GetPathRoot($installFolder) -eq "C:\") } catch {}
                $worthMeasuring = (-not $date) -or ($date -lt $cutoff)
                if ($fastMode) {
                    $folderSizesSkippedFast++
                } elseif (-not $isCInstall) {
                    $folderSizesSkippedNonC++
                } elseif (-not $worthMeasuring) {
                    $folderSizesSkippedRecent++
                } else {
                    $folder = Get-FolderSizeFast $installFolder
                    $folderSizesMeasured++
                    if ($folder.Found) {
                        $bytes = [int64]$folder.Size
                        $sizeSource = "measured-$($folder.Status)"
                    }
                }
            }
            [pscustomobject]@{
                Name = ([string]$_.DisplayName).Trim()
                Publisher = ([string]$_.Publisher).Trim()
                Bytes = $bytes
                SizeSource = $sizeSource
                InstallDate = $date
                InstallFolder = $installFolder
                RegistryPath = [string]$_.PSPath
                RegistryEntry = $_
            }
        } |
        Group-Object { "$($_.Name)|$($_.Publisher)" } |
        ForEach-Object { $_.Group | Sort-Object Bytes -Descending | Select-Object -First 1 }
)

$candidates = @(
    $records |
        Where-Object {
            $isOld = $_.InstallDate -and $_.InstallDate -lt $cutoff
            $isLarge = $_.Bytes -ge $minimumBytes
            $isLargeWithoutDate = (-not $_.InstallDate) -and $_.Bytes -ge $largeWithoutDateBytes
            $isLarge -and ($isOld -or $isLargeWithoutDate)
        } |
        ForEach-Object {
            $isOld = $_.InstallDate -and $_.InstallDate -lt $cutoff
            $resolvedFolder = $_.InstallFolder
            if ($fastMode -and -not $resolvedFolder) {
                $resolvedFolder = Resolve-UninstallInstallFolder -Entry $_.RegistryEntry -TrustDisplayIconPath
            }
            $reason = if ($isOld) {
                "install date is older than $oldDays days"
            } else {
                "large entry with no install date"
            }
            [pscustomobject]@{
                Name = $_.Name
                Publisher = $_.Publisher
                Bytes = $_.Bytes
                SizeSource = $_.SizeSource
                InstallDate = $_.InstallDate
                InstallFolder = $resolvedFolder
                RegistryPath = $_.RegistryPath
                Reason = $reason
            }
        } |
        Sort-Object Bytes -Descending |
        Select-Object -First 25
)

if ($candidates.Count -eq 0) {
    Write-Host "  No candidate matched the bounded rules." -ForegroundColor Green
} else {
    Write-Host "  Candidates: $($candidates.Count) (max 25 shown)" -ForegroundColor Yellow
    foreach ($app in $candidates) {
        $installText = if ($app.InstallDate) { $app.InstallDate.ToString("yyyy-MM-dd") } else { "unknown" }
        $publisherText = if ($app.Publisher) { $app.Publisher } else { "unknown publisher" }
        $pathText = if ($app.InstallFolder) { $app.InstallFolder } else { $app.RegistryPath }
        $driveText = if ($app.InstallFolder -match '^(?<drive>[A-Za-z]):') { $Matches['drive'].ToUpperInvariant() } else { "unknown" }
        $note = "Publisher=$publisherText; install_date=$installText; size_source=$($app.SizeSource); install_drive=$driveText; evidence=$($app.Reason); last-use time is not reliable in uninstall registry"
        Write-InventoryResult -Category "U-unused-software" -Name $app.Name -Size $app.Bytes `
            -Path $pathText -Kind "software-candidate" `
            -Evidence "$note; manual confirmation required; uninstalling may free the install footprint, not necessarily C drive space"
    }
}

Write-Host "  Store apps under WindowsApps may require an administrator read-only scan." -ForegroundColor DarkGray
$uScanWatch.Stop()
if ($null -eq $Global:CDriveScannerMetadata) { $Global:CDriveScannerMetadata = @{} }
$Global:CDriveScannerMetadata["U"] = @{
    elapsed_seconds = [math]::Round($uScanWatch.Elapsed.TotalSeconds, 3)
    mode = if ($fastMode) { "registry-fast" } else { "c-drive-measured" }
    registry_entries = $rawEntries.Count
    normalized_records = $records.Count
    candidates = $candidates.Count
    folder_sizes_measured = $folderSizesMeasured
    folder_sizes_skipped_fast = $folderSizesSkippedFast
    folder_sizes_skipped_non_c = $folderSizesSkippedNonC
    folder_sizes_skipped_recent = $folderSizesSkippedRecent
    accounting = "inventory-only"
}
Write-Host ""
