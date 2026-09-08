# MX scanner: bounded inventory for space that is not a direct cleanup finding.
# Read-only: root directories, root files, loose user files, and permission gaps.

if (-not (Get-Command "Write-InventoryResult" -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")
}

Write-Host "===== MX: miscellaneous C drive inventory =====" -ForegroundColor Cyan
Write-Host "This explains space; it is not a disk-defragmentation or delete list." -ForegroundColor DarkGray

$mxWatch = [Diagnostics.Stopwatch]::StartNew()
$rootDirs = @(Get-ChildItem -LiteralPath "C:\" -Force -Directory -ErrorAction SilentlyContinue)
$plan = Invoke-PathMeasurementPlan -Paths @($rootDirs.FullName) -Parallelism 4
$rootRows = @()
foreach ($dir in $rootDirs) {
    $size = Get-FolderSizeFast $dir.FullName
    if ($size.Found) {
        $rootRows += [pscustomobject]@{ Name = $dir.Name; Path = $dir.FullName; Bytes = [int64]$size.Size; Access = $size.Status; Evidence = $size.Evidence }
    } else {
        $rootRows += [pscustomobject]@{ Name = $dir.Name; Path = $dir.FullName; Bytes = [int64]0; Access = "inaccessible" }
    }
}

Write-Host "[1/3] C root directories" -ForegroundColor White
foreach ($row in ($rootRows | Sort-Object Bytes -Descending | Select-Object -First 20)) {
    $evidence = if ($row.Access -eq "ok") { "robocopy /L /XJ read-only size" } else { "low confidence: $($row.Evidence)" }
    Write-InventoryResult -Category "MX-root-directory" -Name $row.Name -Size $row.Bytes `
        -Path $row.Path -Kind "top-level-directory" -Evidence $evidence -Access $row.Access
}

Write-Host "[2/3] C root files" -ForegroundColor White
$rootFiles = @(Get-ChildItem -LiteralPath "C:\" -Force -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending)
foreach ($file in ($rootFiles | Select-Object -First 20)) {
    $evidence = "root file; last write $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
    Write-InventoryResult -Category "MX-root-file" -Name $file.Name -Size ([int64]$file.Length) `
        -Path $file.FullName -Kind "root-file" -Evidence $evidence
}

Write-Host "[3/3] loose files in selected user folders" -ForegroundColor White
$looseRoots = @(
    @{ Path = "$env:USERPROFILE\Desktop"; Name = "Desktop" },
    @{ Path = "$env:USERPROFILE\Documents"; Name = "Documents" },
    @{ Path = "$env:USERPROFILE\Downloads"; Name = "Downloads" },
    @{ Path = "$env:USERPROFILE\WPS Cloud Files"; Name = "WPS Cloud Files" }
)
$looseFiles = @()
foreach ($root in $looseRoots) {
    if (-not (Test-Path -LiteralPath $root.Path -PathType Container -ErrorAction SilentlyContinue)) { continue }
    $looseFiles += @(Get-ChildItem -LiteralPath $root.Path -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
        $extension = if ($_.Extension) { $_.Extension.ToLowerInvariant() } else { "[no extension]" }
        [pscustomobject]@{ Root = $root.Name; Name = $_.Name; Path = $_.FullName; Length = [int64]$_.Length; Extension = $extension; LastWriteTime = $_.LastWriteTime }
    })
}

foreach ($file in ($looseFiles | Sort-Object Length -Descending | Select-Object -First 20)) {
    $evidence = "$($file.Root) loose file; type $($file.Extension); last write $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
    Write-InventoryResult -Category "MX-loose-file" -Name $file.Name -Size $file.Length `
        -Path $file.Path -Kind "loose-user-file" -Evidence $evidence
}

if ($looseFiles.Count -gt 0) {
    Write-Host "  loose files by extension:" -ForegroundColor DarkGray
    $groups = $looseFiles | Group-Object Extension | Sort-Object Count -Descending | Select-Object -First 12
    foreach ($group in $groups) {
        $bytes = [int64](($group.Group | Measure-Object -Property Length -Sum).Sum)
        Write-Host "    $($group.Name): $($group.Count) files / $([math]::Round($bytes / 1MB, 2)) MB" -ForegroundColor DarkGray
    }
}

$protectedPaths = @("C:\Program Files\WindowsApps", "C:\System Volume Information")
foreach ($path in $protectedPaths) {
    if (-not (Test-Path -LiteralPath $path -ErrorAction SilentlyContinue)) { continue }
    $probe = Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $probe) {
        Write-InventoryResult -Category "MX-permission-gap" -Name "protected directory" -Size 0 `
            -Path $path -Kind "permission-gap" -Evidence "administrator permission may be required" -Access "inaccessible"
    }
}

$mxWatch.Stop()
if ($null -eq $Global:CDriveScannerMetadata) { $Global:CDriveScannerMetadata = @{} }
$Global:CDriveScannerMetadata['MX'] = [pscustomobject]@{
    schema=1; elapsed_seconds=[math]::Round($mxWatch.Elapsed.TotalSeconds,3)
    root_directories=$rootDirs.Count; batch_requested=$plan.Requested; cache_hits_before_batch=$plan.CachedBefore
    batch_seeded=$plan.Seeded; batch_seconds=$plan.Seconds
    accounting='inventory only; root totals may be partial and are never summed as cleanup capacity'
}

Write-Host "MX findings are inventory only and are excluded from cleanup totals." -ForegroundColor Yellow
Write-Host ""
