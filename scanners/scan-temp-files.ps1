﻿﻿﻿﻿﻿# scan-temp-files.ps1 - B类：临时文件与缓存扫描
# 只读扫描，不修改任何文件 — 完全签名驱动

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "===== B类：临时文件与缓存 =====" -ForegroundColor Cyan

Invoke-SignatureScan -Category "system" -CategoryLabel "B"

Write-Host ""
