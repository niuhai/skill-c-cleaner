﻿﻿﻿﻿﻿# scan-security-software.ps1 - H类：安全/管控软件数据检测
# 只读扫描，绝不触碰这些文件！ — 完全签名驱动

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "===== H类：安全软件与管控数据 =====" -ForegroundColor Cyan
Write-Host "注意: 本扫描仅作信息展示，不会修改或删除任何安全软件文件！" -ForegroundColor Yellow
Write-Host ""

Invoke-SignatureScan -Category "security" -CategoryLabel "H"

$totalMB = ($Global:CDriveScanResults | Where-Object { $_.Category -eq "H" } | Measure-Object SizeMB -Sum).Sum
if ($totalMB -gt 0) {
    Write-Host ""
    Write-Host "  安全/管控软件 总占用估计: $([math]::Round($totalMB,2)) MB" -ForegroundColor Yellow
    Write-Host "  这些大多数不能删除，但了解它们的存在能帮你理解C盘空间去向" -ForegroundColor Yellow
}

Write-Host ""
