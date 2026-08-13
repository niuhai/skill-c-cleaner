# scan-growth.ps1 - GR class: recurring growth and baseline delta
# This scanner is read-only unless track-growth.ps1 receives -Record.

$scannerRoot = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $scannerRoot
if ($Global:CDriveFastMode) {
    & (Join-Path $skillRoot "track-growth.ps1") -Mode compare -UseCachedSnapshot
} else {
    & (Join-Path $skillRoot "track-growth.ps1") -Mode compare -Record:$Global:CDriveRecordGrowth
}
