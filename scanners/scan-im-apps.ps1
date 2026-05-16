﻿﻿﻿﻿﻿# scan-im-apps.ps1 - L类：即时通讯工具数据扫描
# 只读扫描，不修改任何文件 — 完全签名驱动

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "===== L类：即时通讯工具数据 =====" -ForegroundColor Cyan

Invoke-SignatureScan -Category "im_apps" -CategoryLabel "L"

Write-Host ""
