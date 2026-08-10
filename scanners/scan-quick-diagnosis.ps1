param(
    [string]$OutputFormat = "console"
)

$SkillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not (Test-Path (Join-Path $SkillRoot "_common.ps1"))) {
    throw "Skill root could not be resolved from the script location."
}
. (Join-Path $SkillRoot "_common.ps1")

Write-Host ""
Write-Host "⚡ Quick Diagnosis (15-30s)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$result = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    phase = "quick_diagnosis"
    duration预估 = "15-30 seconds"
    token_cost预估 = "~500 tokens (input ~200 + output ~300)"
    data = @{}
}

Write-Host "`n[1/5] C Drive Space Overview..." -ForegroundColor DarkGray
$space = Get-DriveSpace
if ($space) {
    $result.data['drive'] = @{
        total_gb = [math]::Round($space.TotalGB, 1)
        used_gb = [math]::Round($space.UsedGB, 1)
        free_gb = [math]::Round($space.FreeGB, 1)
        used_percent = $space.UsedPercent
    }
    
    $color = if ($space.UsedPercent -gt 90) { "Red" } elseif ($space.UsedPercent -gt 80) { "Yellow" } else { "Green" }
    Write-Host "  Capacity: $($space.TotalGB) GB | Used: $($space.UsedGB) GB ($($space.UsedPercent)%) | Free: $($space.FreeGB) GB" -ForegroundColor White
    
    $healthScore = [math]::Max(0, [math]::Min(100, 100 - ($space.UsedPercent - 50) * 2))
    Write-Host "  Health Score: $healthScore/100" -ForegroundColor $color
} else {
    $result.data['drive'] = $null
}

Write-Host "[2/5] Temp Files Check..." -ForegroundColor DarkGray
$tempSize = 0
$tempPaths = @(
    @{ path = "$env:TEMP"; name = "User Temp" },
    @{ path = "$env:SystemRoot\Temp"; name = "Windows Temp" },
    @{ path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; name = "Thumbnail Cache" },
    @{ path = "C:\`$Recycle.Bin"; name = "Recycle Bin" }
)

$tempDetails = @()
foreach ($tp in $tempPaths) {
    if (Test-Path $tp.path) {
        $size = Get-FolderSizeFast $tp.path
        if ($size -gt 0) {
            $sizeMB = [math]::Round($size / 1MB, 1)
            $tempSize += $size
            $tempDetails += @{ name = $tp.name; size_mb = $sizeMB }
        }
    }
}
$result.data['temp_files'] = @{
    total_mb = [math]::Round($tempSize / 1MB, 1)
    details = $tempDetails
}
Write-Host "  Total Temp: $([math]::Round($tempSize / 1MB, 1)) MB"

Write-Host "[3/5] Top User Folders..." -ForegroundColor DarkGray
$userFolders = @(
    @{ path = "$env:USERPROFILE\Desktop"; name = "Desktop" },
    @{ path = "$env:USERPROFILE\Documents"; name = "Documents" },
    @{ path = "$env:USERPROFILE\Downloads"; name = "Downloads" },
    @{ path = "$env:USERPROFILE\AppData\Local"; name = "AppData Local" },
    @{ path = "$env:USERPROFILE\AppData\Roaming"; name = "AppData Roaming" }
)

$topFolders = @()
foreach ($uf in $userFolders) {
    if (Test-Path $uf.path) {
        $size = Get-FolderSizeFast $uf.path
        if ($size -gt 100MB) {
            $sizeGB = [math]::Round($size / 1GB, 2)
            $topFolders += @{ name = $uf.name; size_gb = $sizeGB; path = $uf.path }
        }
    }
}
$topFolders = $topFolders | Sort-Object { $_.size_gb } -Descending | Select-Object -First 5
$result.data['top_folders'] = $topFolders

Write-Host "  Top 5 folders:"
foreach ($tf in $topFolders) {
    $bar = "█" * [math]::Min(20, [math]::Floor($tf.size_gb)) + "░" * [math]::Max(0, 20 - [math]::Floor($tf.size_gb))
    Write-Host "    $($tf.name): $($tf.size_gb) GB [$bar]" -ForegroundColor DarkGray
}

Write-Host "[4/5] Special Software Detection..." -ForegroundColor DarkGray
$specialItems = @()

$dockerPath = "$env:LOCALAPPDATA\Docker"
if (Test-Path $dockerPath) {
    $dockerSize = Get-FolderSizeFast $dockerPath
    if ($dockerSize -gt 100MB) {
        $specialItems += @{ name = "Docker Desktop"; size_gb = [math]::Round($dockerSize / 1GB, 1); category = "G" }
    }
}

$wslPath = "$env:LOCALAPPDATA\Packages"
if (Test-Path $wslPath) {
    $wslDistros = Get-ChildItem $wslPath -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match "Canonical|Ubuntu|Debian|SUSE" }
    foreach ($distro in $wslDistros) {
        $vhdx = Join-Path $distro.FullName "LocalState\ext4.vhdx"
        if (Test-Path $vhdx) {
            $wslSize = (Get-Item $vhdx).Length / 1GB
            if ($wslSize -gt 0.5) {
                $specialItems += @{ name = "WSL2 ($($distro.Name))"; size_gb = [math]::Round($wslSize, 1); category = "G" }
            }
        }
    }
}

$devTools = @(
    @{ name = "npm"; path = "$env:APPDATA\npm-cache"; check_file = "_cacache" },
    @{ name = "pip"; path = "$env:LOCALAPPDATA\pip"; check_file = "cache" },
    @{ name = "yarn"; path = "$env:LOCALAPPDATA\Yarn"; check_file = "Cache" },
    @{ name = "nuget"; path = "$env:USERPROFILE\.nuget"; check_file = "packages" },
    @{ name = "cargo"; path = "$env:USERPROFILE\.cargo"; check_file = "registry" }
)

$devCaches = @()
foreach ($dt in $devTools) {
    if (Test-Path $dt.path) {
        $checkPath = Join-Path $dt.path $dt.check_file
        if (Test-Path $checkPath) {
            $size = Get-FolderSizeFast $dt.path
            if ($size -gt 50MB) {
                $sizeMB = [math]::Round($size / 1MB, 0)
                $devCaches += @{ name = $dt.name; size_mb = $sizeMB; category = "C" }
                $specialItems += @{ name = "$($dt.name) cache"; size_gb = [math]::Round($size / 1GB, 2); category = "C" }
            }
        }
    }
}
$result.data['dev_caches'] = $devCaches
$result.data['special_items'] = $specialItems

if ($specialItems.Count -gt 0) {
    Write-Host "  Found $($specialItems.Count) special items:"
    foreach ($si in $specialItems | Sort-Object { $_.size_gb } -Descending) {
        Write-Host "    • $($si.name): $($si.size_gb) GB [Category $($si.category)]" -ForegroundColor Yellow
    }
} else {
    Write-Host "  No large special items detected" -ForegroundColor DarkGreen
}

Write-Host "[5/5] User Type Detection..." -ForegroundColor DarkGray
$userType = "normal_user"
$typeEvidence = @()

$nodeExists = Test-Path "$env:APPDATA\npm"
$pythonExists = Test-Path "$env:LOCALAPPDATA\Programs\Python"
$dockerExists = $specialItems | Where-Object { $_.name -match "Docker|WSL" }
$vscodeExists = Test-Path "$env:USERPROFILE\.vscode"

if ($nodeExists -or $pythonExists -or $dockerExists) {
    $userType = "developer"
    if ($nodeExists) { $typeEvidence += "Node.js detected" }
    if ($pythonExists) { $typeEvidence += "Python detected" }
    if ($dockerExists) { $typeEvidence += "Docker/WSL detected" }
}

$result.data['user_type'] = $userType
$result.data['type_evidence'] = $typeEvidence

$stopwatch.Stop()
$result.duration_actual = "$([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s"
result.token_used估算 = "500 (approx)"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Quick Diagnosis Complete ($($result.duration_actual))" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($OutputFormat -eq "json") {
    $result | ConvertToJson -Depth 5
} elseif ($OutputFormat -eq "markdown") {
    "# Quick Diagnosis Report`n`n"
    "| Item | Value |"
    "|------|------|"
    "| Timestamp | $($result.timestamp) |"
    "| Phase | $($result.phase) |"
    "| Duration | $($result.duration_actual) |"
    "| Token Cost | $($result.token_cost预估) |"
    "| User Type | $($result.userType) |"
    "`n## Drive Status`n"
    "- **Total**: $($result.data.drive.total_gb) GB"
    "- **Used**: $($result.data.drive.used_gb) GB ($($result.data.drive.used_percent)%)"
    "- **Free**: $($result.data.drive.free_gb) GB"
    "`n## Key Findings`n"
    "- **Temp Files**: $($result.data.temp_files.total_mb) MB"
    "- **Special Items**: $($result.data.special_items.Count) items"
    "- **Dev Caches**: $($result.data.dev_caches.Count) types"
} else {
    Write-Host "`n📊 DIAGNOSIS SUMMARY" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "User Type: " -NoNewline -ForegroundColor Gray
    switch ($result.userType) {
        "developer" { Write-Host "👨‍💻 Developer" -ForegroundColor Green }
        default { Write-Host "👤 Normal User" -ForegroundColor Blue }
    }
    if ($typeEvidence.Count -gt 0) {
        Write-Host "Evidence: ($($typeEvidence -join ', '))" -ForegroundColor DarkGray
    }
    
    Write-Host "`n🔴 TOP CONCERNS:" -ForegroundColor Yellow
    $allConcerns = @()
    $allConcerns += $specialItems | ForEach-Object { "$($_.name): $($_.size_gb)GB" }
    $allConcerns += "Temp files: $($result.data.temp_files.total_mb)MB"
    
    $sortedConcerns = $allConcerns | Sort-Object { if ($_ -match '(\d+\.?\d*)\s*GB') { [double]$Matches[1] } else { 0 } } -Descending
    
    foreach ($concern in $sortedConcerns | Select-Object -First 5) {
        Write-Host "  ⚠️  $concern" -ForegroundColor Yellow
    }

    return $result
}
