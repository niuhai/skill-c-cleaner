﻿﻿﻿﻿﻿# scan-ime-data.ps1 - K类：输入法数据扫描
# 只读扫描，不修改任何文件 — 完全签名驱动

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "===== K类：输入法数据 =====" -ForegroundColor Cyan

Invoke-SignatureScan -Category "input_methods" -CategoryLabel "K"

Write-Host ""
