﻿﻿﻿﻿﻿# scan-special-sources.ps1 - G类：特殊占用源扫描
# 只读扫描，不修改任何文件 — 签名驱动 + 可疑文件检测

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "===== G类：特殊占用源 =====" -ForegroundColor Cyan

Invoke-SignatureScan -Category "virtualization" -CategoryLabel "G"
Invoke-SignatureScan -Category "games" -CategoryLabel "G"

Write-Host ""
Write-Host "  C盘根目录可疑文件检查" -ForegroundColor Cyan
$suspiciousPatterns = @("C:\*.zip", "C:\*.dmp", "C:\DumpStack*")
$foundAny = $false
foreach ($pattern in $suspiciousPatterns) {
    $matches = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue
    foreach ($m in $matches) {
        if (-not $foundAny) { $foundAny = $true }
        $mMB = [math]::Round($m.Length / 1MB, 2)
        Write-ScanResult -Category "G" -Name "可疑文件: $($m.Name)" -Size $m.Length `
            -Risk "dangerous" -Path $m.FullName -Advice "必须人工确认！右键属性检查来源"
    }
}
if (-not $foundAny) { Write-Host "  ○ 未发现明显可疑文件" -ForegroundColor DarkGray }

Write-Host ""
