# scan-windows-update-residue.ps1 - WU class: Windows update/recovery residue
# Read-only. Never removes recovery or servicing data directly.

if (-not (Get-Command "Write-InventoryResult" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== WU: Windows update and recovery residue =====" -ForegroundColor Cyan
$pendingSignals = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
)
$pendingReboot = $false
if (Test-Path -LiteralPath $pendingSignals[0] -ErrorAction SilentlyContinue) { $pendingReboot = $true }
if (Test-Path -LiteralPath $pendingSignals[1] -ErrorAction SilentlyContinue) { $pendingReboot = $true }
try {
    $pendingRename = (Get-ItemProperty -LiteralPath $pendingSignals[2] -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    if ($pendingRename) { $pendingReboot = $true }
} catch {}

Write-Host "  Pending reboot signal: $pendingReboot" -ForegroundColor $(if ($pendingReboot) { "Yellow" } else { "DarkGray" })
$targets = @(
    @{ Name='$WinREAgent'; Path='C:\$WinREAgent'; Kind="recovery-update"; Note="Windows recovery/update working directory; keep while an update or restart is pending" },
    @{ Name='$WINDOWS.~BT'; Path='C:\$WINDOWS.~BT'; Kind="feature-update"; Note="feature-upgrade files; prefer Windows Storage cleanup after update completion" },
    @{ Name='$Windows.~WS'; Path='C:\$Windows.~WS'; Kind="feature-update"; Note="feature-upgrade setup files; do not delete during an active upgrade" },
    @{ Name="SoftwareDistribution Download"; Path="C:\Windows\SoftwareDistribution\Download"; Kind="update-download"; Note="Windows Update download cache; use Windows cleanup/repair workflow, not direct deletion by default" },
    @{ Name="Delivery Optimization Cache"; Path="C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache"; Kind="delivery-cache"; Note="delivery cache; Windows Storage cleanup is preferred" },
    @{ Name="CBS logs"; Path="C:\Windows\Logs\CBS"; Kind="servicing-log"; Note="servicing diagnostics; preserve recent logs when update repair is in progress" },
    @{ Name="DISM logs"; Path="C:\Windows\Logs\DISM"; Kind="servicing-log"; Note="DISM diagnostics; usually small and useful for repair" }
)

foreach ($target in $targets) {
    $m = Get-PathLogicalMeasurement -Path $target.Path
    if ($m.Status -eq "missing") { continue }
    $evidence = "$($target.Note); pendingReboot=$pendingReboot; measurement=$($m.Status)"
    Write-InventoryResult -Category "WU-update-residue" -Name $target.Name -Size $m.Bytes `
        -Path $target.Path -Kind $target.Kind -Evidence $evidence -Access $m.Status
}
Write-Host "  WU results are inventory only; do not delete recovery/update folders while servicing is active." -ForegroundColor Yellow
Write-Host ""
