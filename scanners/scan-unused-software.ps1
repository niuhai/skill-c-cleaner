# U scanner: installed software candidates that deserve a manual usage check.
# Read-only: no uninstall command, registry write, or install-directory deletion.

if (-not (Get-Command "Write-ScanResult" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== U: installed software candidates =====" -ForegroundColor Cyan
Write-Host "This is a candidate list, not proof that software is unused." -ForegroundColor Yellow

$oldDays = 180
$minimumBytes = 200MB
$largeWithoutDateBytes = 1GB
$uninstallRoots = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

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
    try {
        if ($Value -match '^\d{8}$') {
            return [datetime]::ParseExact($Value, "yyyyMMdd", [Globalization.CultureInfo]::InvariantCulture)
        }
    } catch {}
    return $null
}

function Resolve-InstallFolder {
    param($Entry)
    $location = [string]$Entry.InstallLocation
    if (-not [string]::IsNullOrWhiteSpace($location)) {
        $location = $location.Trim().Trim('"')
        if (Test-Path -LiteralPath $location -PathType Container -ErrorAction SilentlyContinue) { return $location }
    }

    $icon = [string]$Entry.DisplayIcon
    if (-not [string]::IsNullOrWhiteSpace($icon)) {
        $icon = $icon.Split(',')[0].Trim().Trim('"')
        if (Test-Path -LiteralPath $icon -PathType Leaf -ErrorAction SilentlyContinue) {
            return (Split-Path -Parent $icon)
        }
    }
    return ""
}

function Test-SystemSoftwareEntry {
    param($Entry)
    if ([int]$Entry.SystemComponent -eq 1) { return $true }
    if ($Entry.ReleaseType -in @("Security Update", "Update", "Hotfix")) { return $true }
    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.ParentKeyName)) { return $true }
    $name = [string]$Entry.DisplayName
    return $name -match '(?i)(Windows Update|Update for|Security Update|Visual C\+\+|\.NET|ASP\.NET|WebView2|Edge Update|Runtime|Redistributable|KB\d+)'
}

$rawEntries = @()
foreach ($root in $uninstallRoots) {
    $rawEntries += @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)
}

$records = @(
    $rawEntries |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.DisplayName) -and
            -not (Test-SystemSoftwareEntry $_)
        } |
        ForEach-Object {
            $bytes = Convert-EstimatedBytes $_.EstimatedSize
            $installFolder = Resolve-InstallFolder $_
            if ($bytes -le 0 -and $installFolder) {
                $folder = Get-FolderSizeFast $installFolder
                if ($folder.Found) { $bytes = [int64]$folder.Size }
            }
            $date = Convert-InstallDate ([string]$_.InstallDate)
            [pscustomobject]@{
                Name = ([string]$_.DisplayName).Trim()
                Publisher = ([string]$_.Publisher).Trim()
                Bytes = $bytes
                InstallDate = $date
                InstallFolder = $installFolder
                RegistryPath = [string]$_.PSPath
            }
        } |
        Group-Object { "$($_.Name)|$($_.Publisher)" } |
        ForEach-Object { $_.Group | Sort-Object Bytes -Descending | Select-Object -First 1 }
)

$cutoff = (Get-Date).AddDays(-$oldDays)
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
            $reason = if ($isOld) { "install date is older than $oldDays days" } else { "large entry with no install date" }
            [pscustomobject]@{
                Name = $_.Name
                Publisher = $_.Publisher
                Bytes = $_.Bytes
                InstallDate = $_.InstallDate
                InstallFolder = $_.InstallFolder
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
        $note = "Publisher=$publisherText; install_date=$installText; evidence=$($app.Reason); last-use time is not reliable in uninstall registry"
        Write-InventoryResult -Category "U-unused-software" -Name $app.Name -Size $app.Bytes `
            -Path $pathText -Kind "software-candidate" `
            -Evidence "$note; manual confirmation required; uninstalling may free the install footprint, not necessarily C drive space"
    }
}

Write-Host "  Store apps under WindowsApps may require an administrator read-only scan." -ForegroundColor DarkGray
Write-Host ""
