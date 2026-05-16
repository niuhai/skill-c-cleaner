﻿﻿﻿﻿﻿# scan-duplicate-runtimes.ps1 - J类：重复运行时检测
# 只读扫描 — 通用模式匹配，自动发现Electron/CEF应用

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "===== J类：重复运行时(Electron/CEF)检测 =====" -ForegroundColor Cyan

$scanRoots = @(
    @{ Path = "$env:LOCALAPPDATA"; Label = "LocalAppData" },
    @{ Path = "$env:APPDATA"; Label = "AppData\Roaming" },
    @{ Path = "${env:ProgramFiles(x86)}"; Label = "Program Files (x86)" },
    @{ Path = "$env:ProgramFiles"; Label = "Program Files" }
)

$electronApps = [System.Collections.ArrayList]::new()
$cefIndicators = @("libcef.dll", "chrome_elf.dll", "v8_context_snapshot.bin")
$pakPattern = "*.pak"

foreach ($root in $scanRoots) {
    if (-not (Test-Path $root.Path)) { continue }
    $dirs = Get-ChildItem $root.Path -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        $hasCef = $false
        foreach ($indicator in $cefIndicators) {
            if (Get-ChildItem $dir.FullName -Recurse -Filter $indicator -File -ErrorAction SilentlyContinue |
                Select-Object -First 1) {
                $hasCef = $true
                break
            }
        }
        if (-not $hasCef) { continue }
        $pakFiles = Get-ChildItem $dir.FullName -Recurse -Filter $pakPattern -File -ErrorAction SilentlyContinue
        if ($pakFiles.Count -ge 3) {
            $r = Get-FolderSizeFast $dir.FullName
            [void]$electronApps.Add([PSCustomObject]@{
                Name = $dir.Name
                Path = $dir.FullName
                Size = $r.Size
                PakCount = $pakFiles.Count
            })
        }
    }
}

if ($electronApps.Count -eq 0) {
    Write-Host "  ○ 未发现Electron/CEF应用" -ForegroundColor DarkGray
} else {
    $totalSize = ($electronApps | Measure-Object Size -Sum).Sum
    $totalGB = [math]::Round($totalSize / 1GB, 2)
    $avgSize = [math]::Round(($electronApps | Measure-Object Size -Average).Average / 1MB, 0)
    $wasteEstimate = [math]::Round(($electronApps.Count - 1) * $avgSize / 1024, 2)

    Write-Host "  发现 $($electronApps.Count) 个Electron/CEF应用，总占用 $totalGB GB" -ForegroundColor Yellow
    Write-Host "  每个应用自带一份Chromium运行时(~${avgSize}MB)，估计重复浪费 ~${wasteEstimate} GB" -ForegroundColor Yellow
    Write-Host ""

    $sorted = $electronApps | Sort-Object Size -Descending
    foreach ($app in $sorted) {
        $sizeStr = if ($app.Size -ge 1GB) { "$([math]::Round($app.Size/1GB,2)) GB" } else { "$([math]::Round($app.Size/1MB,1)) MB" }
        Write-ScanResult -Category "J" -Name "$($app.Name) (Electron)" -Size $app.Size `
            -Risk "cautious" -Path $app.Path `
            -Advice "如非必须，考虑用网页版替代以节省运行时重复" `
            -Note "$($app.PakCount)个.pak文件"
    }
}

Write-Host ""
