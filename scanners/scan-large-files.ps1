﻿﻿﻿﻿﻿# scan-large-files.ps1 - F类：大文件TOP N + 用户文件夹排行
# 只读扫描，不修改任何文件

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

$UserProfile = $env:USERPROFILE

Write-Host "===== F类：C盘大文件 TOP 20 =====" -ForegroundColor Cyan
Write-Host "(扫描中，可能需1-3分钟...)" -ForegroundColor DarkGray

$topN = 20
$excludeDirs = @(
    "C:\Windows\*",
    "C:\`$Recycle.Bin\*",
    "C:\System Volume Information\*",
    "C:\ProgramData\Microsoft\*",
    "C:\ProgramData\Huorong\*",
    "C:\ProgramData\SF\*",
    "C:\ProgramData\Sangfor\*",
    "C:\ProgramData\NAC\*",
    "C:\ProgramData\SecurityCore\*",
    "C:\ProgramData\SecurityEv\*",
    "C:\ProgramData\KvEdr\*",
    "C:\Users\*\NTUSER.*",
    "C:\Users\*\ntuser.*",
    "C:\Users\*\AppData\Local\Microsoft\*",
    "C:\Program Files\WindowsApps\*"
)

try {
    $largeFiles = Get-ChildItem -Path C:\ -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object {
            $path = $_.FullName
            $excluded = $false
            foreach ($ex in $excludeDirs) { if ($path -like $ex) { $excluded = $true; break } }
            -not $excluded
        } |
        Sort-Object Length -Descending |
        Select-Object -First $topN

    Write-Host ""
    Write-Host "排名  大小       路径" -ForegroundColor White
    Write-Host "----  --------   ----" -ForegroundColor White
    $rank = 0
    foreach ($file in $largeFiles) {
        $rank++
        $sizeStr = if ($file.Length -ge 1GB) {
            "$([math]::Round($file.Length/1GB,2)) GB"
        } elseif ($file.Length -ge 1MB) {
            "$([math]::Round($file.Length/1MB,1)) MB"
        } else {
            "$([math]::Round($file.Length/1KB,1)) KB"
        }
        Write-Host ("#{0,2}" -f $rank) -NoNewline -ForegroundColor Yellow
        Write-Host "  $sizeStr" -NoNewline -ForegroundColor Green
        Write-Host "  $($file.FullName)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "扫描出错: 可能需要管理员权限" -ForegroundColor Red
}

Write-Host ""
Write-Host "===== 用户文件夹子目录大小 TOP 15 =====" -ForegroundColor Cyan
Write-Host "(扫描中...)" -ForegroundColor DarkGray

try {
    $userFolders = Get-ChildItem "$UserProfile" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('NTUSER.DAT','ntuser.dat.LOG1','ntuser.dat.LOG2','ntuser.ini') } |
        ForEach-Object {
            $r = Get-FolderSizeFast $_.FullName
            [PSCustomObject]@{ Folder = $_.Name; Size = $r.Size; Path = $_.FullName }
        } |
        Sort-Object Size -Descending |
        Select-Object -First 15

    Write-Host ""
    foreach ($f in $userFolders) {
        $sizeStr = if ($f.Size -ge 1GB) {
            "$([math]::Round($f.Size/1GB,2)) GB"
        } elseif ($f.Size -ge 1MB) {
            "$([math]::Round($f.Size/1MB,1)) MB"
        } else {
            "$([math]::Round($f.Size/1KB,1)) KB"
        }
        Write-Host "  $sizeStr  ~\$($f.Folder)" -ForegroundColor Green
    }
} catch {
    Write-Host "扫描出错" -ForegroundColor Red
}

Write-Host ""
