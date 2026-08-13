# scan-space-accounting.ps1 - SA class: opt-in NTFS allocated-size accounting

if (-not (Get-Command "Write-InventoryResult" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}
$scannerRoot = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $scannerRoot
$rows = @(& (Join-Path $skillRoot "measure-space.ps1") -PassThru)
foreach ($row in $rows) {
    $evidence = "logical=$([math]::Round($row.entryLogicalBytes/1GB,3)) GB; allocated=$([math]::Round($row.allocatedBytes/1GB,3)) GB; status=$($row.status); hardlinkDuplicates=$($row.hardlinkDuplicates); sparseOrCompressed=$($row.sparseOrCompressedFiles)"
    Write-InventoryResult -Category "SA-allocated-space" -Name $row.name -Size $row.allocatedBytes `
        -Path $row.path -Kind "allocated-space" -Evidence $evidence -Access $row.status
}
