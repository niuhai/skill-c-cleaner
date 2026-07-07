$root = "c:\.trae\skills\c-drive-cleaner"
$files = @(
    "$root\_common.ps1",
    "$root\cleaners\clean-safe.ps1",
    "$root\cleaners\clean-apps.ps1",
    "$root\cleaners\clean-deep.ps1",
    "$root\cleaners\clean-dev-caches.ps1"
)
$allOk = $true
foreach ($f in $files) {
    $tokens = $null
    $parseErrors = $null
    try {
        [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors) {
            Write-Host "  [FAIL] $f" -ForegroundColor Red
            $parseErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            $allOk = $false
        } else {
            Write-Host "  [OK]   $f" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [FAIL] $f : $_" -ForegroundColor Red
        $allOk = $false
    }
}
if ($allOk) {
    Write-Host "`nAll syntax checks passed!" -ForegroundColor Green
} else {
    Write-Host "`nSome checks failed!" -ForegroundColor Red
}
