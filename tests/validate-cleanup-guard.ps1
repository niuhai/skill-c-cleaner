# Read-only assertions for the centralized cleanup safety gate.
$skillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $skillRoot "_common.ps1")

$testRoot = Join-Path $env:LOCALAPPDATA ("Temp\CleanSightGuardTest-" + [guid]::NewGuid().ToString("N"))
$allowedRoot = Join-Path $testRoot "allowed"
$outsideRoot = Join-Path $testRoot "outside"
$junctionPath = Join-Path $allowedRoot "redirected"
$testFile = Join-Path $allowedRoot "cache.tmp"
$failures = [System.Collections.ArrayList]::new()

function Assert-Gate {
    param([string]$Name, [bool]$Expected, [object]$Actual)
    if ([bool]$Actual.Safe -ne $Expected) {
        [void]$failures.Add("$Name expected Safe=$Expected, got Safe=$($Actual.Safe): $($Actual.Reason)")
    } else {
        Write-Host "[PASS] $Name - $($Actual.Reason)" -ForegroundColor Green
    }
}

try {
    [void](New-Item -ItemType Directory -Path $allowedRoot -Force)
    [void](New-Item -ItemType Directory -Path $outsideRoot -Force)
    Set-Content -LiteralPath $testFile -Value "guard fixture" -Encoding ASCII
    [void](New-Item -ItemType Junction -Path $junctionPath -Target $outsideRoot -Force)

    Assert-Gate "drive root rejected" $false (Test-CleanupTargetSafety -Path "C:\" -AllowedRoots @("C:\") -TargetType Directory)
    Assert-Gate "relative path rejected" $false (Test-CleanupTargetSafety -Path ".\relative" -AllowedRoots @($allowedRoot))
    Assert-Gate "allowed directory accepted" $true (Test-CleanupTargetSafety -Path $allowedRoot -AllowedRoots @($allowedRoot) -TargetType Directory)
    Assert-Gate "allowed file accepted" $true (Test-CleanupTargetSafety -Path $testFile -AllowedRoots @($allowedRoot) -TargetType File)
    Assert-Gate "outside allowed root rejected" $false (Test-CleanupTargetSafety -Path $outsideRoot -AllowedRoots @($allowedRoot) -TargetType Directory)
    Assert-Gate "junction rejected" $false (Test-CleanupTargetSafety -Path $junctionPath -AllowedRoots @($allowedRoot) -TargetType Directory)
    $rootDeleteResult = Remove-Directory -Path "C:\" -AllowedRoots @("C:\")
    if ($rootDeleteResult) { [void]$failures.Add("Remove-Directory unexpectedly accepted the drive root") }
    else { Write-Host "[PASS] Remove-Directory wrapper fails closed for drive root" -ForegroundColor Green }
    if (Test-Path -LiteralPath "D:\") {
        Assert-Gate "cross-volume path rejected" $false (Test-CleanupTargetSafety -Path "D:\" -AllowedRoots @("D:\") -TargetType Directory)
    }
} finally {
    if (Test-Path -LiteralPath $junctionPath -ErrorAction SilentlyContinue) {
        & cmd.exe /c "rmdir `"$junctionPath`"" 2>$null
    }
    if ((Test-Path -LiteralPath $testRoot -ErrorAction SilentlyContinue) -and
        $testRoot.StartsWith((Join-Path $env:LOCALAPPDATA "Temp\CleanSightGuardTest-"), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    exit 1
}
Write-Host "Cleanup safety gate: all assertions passed." -ForegroundColor Cyan
