﻿﻿﻿﻿﻿# scan-multi-version.ps1 - I类：多版本软件共存检测
# 只读扫描 — 通用模式匹配，不硬编码具体软件

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

$ProgramFiles = $env:ProgramFiles
$ProgramFiles86 = ${env:ProgramFiles(x86)}
$LocalAppData = $env:LOCALAPPDATA

Write-Host "===== I类：多版本软件共存检测 =====" -ForegroundColor Cyan

function Detect-MultiVersion {
    param([string]$BasePath, [string]$AppName, [string]$Pattern)
    if (-not (Test-Path $BasePath)) { return }
    $versions = Get-ChildItem $BasePath -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $Pattern } |
        Sort-Object Name -Descending
    if ($versions.Count -gt 1) {
        $newest = $versions[0].Name
        $oldOnes = ($versions[1..$versions.Count] | ForEach-Object { $_.Name }) -join ", "
        $totalSize = 0L
        foreach ($v in $versions) {
            $r = Get-FolderSizeFast $v.FullName
            $totalSize += $r.Size
        }
        Write-ScanResult -Category "I" -Name "$AppName ($($versions.Count)个版本共存)" -Size $totalSize `
            -Risk "cautious" -Path $BasePath `
            -Advice "旧版本可卸载 | 最新: $newest | 旧版: $oldOnes"
    }
}

Detect-MultiVersion "$ProgramFiles86\Microsoft\EdgeCore" "Microsoft Edge" '^\d+\.\d+\.\d+\.\d+$'
Detect-MultiVersion "$ProgramFiles\WPS Office" "WPS Office" '^\d+\.\d+\.\d+\.\d+'
Detect-MultiVersion "$ProgramFiles\Microsoft Visual Studio" "Visual Studio" '^20\d+$'
Detect-MultiVersion "$LocalAppData\Programs\Python" "Python" '^Python\d+'

$voltaVersions = "$LocalAppData\Volta\tools\image\node"
if (Test-Path $voltaVersions) {
    $nodeVers = Get-ChildItem $voltaVersions -Directory -ErrorAction SilentlyContinue
    if ($nodeVers.Count -gt 3) {
        $totalSize = 0L
        foreach ($v in $nodeVers) { $r = Get-FolderSizeFast $v.FullName; $totalSize += $r.Size }
        Write-ScanResult -Category "I" -Name "Node.js(Volta): $($nodeVers.Count)个版本" -Size $totalSize `
            -Risk "cautious" -Path $voltaVersions -Advice "不常用的版本可用volta uninstall移除"
    }
}

Write-Host ""
Write-Host "  通用扫描: Program Files 中同厂商多版本" -ForegroundColor DarkGray
$commonDirs = @($ProgramFiles, $ProgramFiles86)
foreach ($baseDir in $commonDirs) {
    if (-not (Test-Path $baseDir)) { continue }
    $vendors = Get-ChildItem $baseDir -Directory -ErrorAction SilentlyContinue
    foreach ($vendor in $vendors) {
        $subDirs = Get-ChildItem $vendor.FullName -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+' } |
            Measure-Object
        if ($subDirs.Count -gt 1) {
            Write-Host "  ⚠️ $($vendor.Name) 下有 $($subDirs.Count) 个版本子目录" -ForegroundColor Yellow
            Write-Host "     路径: $($vendor.FullName)" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
