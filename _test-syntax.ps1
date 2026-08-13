$root = $PSScriptRoot
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.ps1" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\reports\\' })

$allOk = $true
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    try {
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        )
        if ($parseErrors.Count -gt 0) {
            Write-Host "  [FAIL] $($file.FullName)" -ForegroundColor Red
            $parseErrors | ForEach-Object { Write-Host "    $($_.Message)" -ForegroundColor Red }
            $allOk = $false
        } else {
            Write-Host "  [OK]   $($file.FullName)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [FAIL] $($file.FullName): $($_.Exception.Message)" -ForegroundColor Red
        $allOk = $false
    }
}

if (-not $allOk) {
    Write-Host "`nSome syntax checks failed." -ForegroundColor Red
    exit 1
}

Write-Host "`nAll $($files.Count) PowerShell syntax checks passed." -ForegroundColor Green
