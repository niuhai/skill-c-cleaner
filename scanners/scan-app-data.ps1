﻿﻿﻿﻿﻿# scan-app-data.ps1 - E类：应用数据与日志扫描
# 只读扫描，不修改任何文件 — 签名驱动 + IDE/媒体/办公/AI工具

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "===== E类：应用数据与日志 =====" -ForegroundColor Cyan

$sysLogs = @(
    @{Name="setupact.log"; Path="C:\Windows\setupact.log"},
    @{Name="DumpStack.log"; Path="C:\DumpStack.log"},
    @{Name="iis.log"; Path="C:\Windows\iis.log"},
    @{Name="comsetup.log"; Path="C:\Windows\comsetup.log"},
    @{Name="DPINST.LOG"; Path="C:\Windows\DPINST.LOG"}
)
$totalLogSize = 0L
foreach ($log in $sysLogs) {
    if (Test-Path $log.Path) {
        $totalLogSize += (Get-Item $log.Path).Length
    }
}
if ($totalLogSize -gt 0) {
    Write-ScanResult -Category "E" -Name "系统日志文件" -Size $totalLogSize `
        -Risk "safe" -Path "C:\Windows\*.log" -Advice "一般用户可删除 | 调试用途"
}

Invoke-SignatureScan -Category "ides" -CategoryLabel "E"
Invoke-SignatureScan -Category "media" -CategoryLabel "E"
Invoke-SignatureScan -Category "office" -CategoryLabel "E"
Invoke-SignatureScan -Category "ai_tools" -CategoryLabel "E"
Invoke-SignatureScan -Category "cloud_storage" -CategoryLabel "E"

Write-Host ""
