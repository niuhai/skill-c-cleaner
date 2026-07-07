# 每日C盘空间监控 (只报告，不自动清理)

$threshold = 90  # 超过90%报警

# 动态获取 skill 根目录（兼容不同安装位置）
$SkillRoot = "C:\.trae\skills\c-drive-cleaner"
if ($PSCommandPath) {
    $dir = Split-Path -Parent $PSCommandPath
    $parent = Split-Path -Parent $dir
    if (Test-Path (Join-Path $parent "_common.ps1")) { $SkillRoot = $parent }
}

$drive = Get-PSDrive C
$usedPercent = [math]::Round($drive.Used / ($drive.Used + $drive.Free) * 100, 1)
$freeGB = [math]::Round($drive.Free / 1GB, 2)
$usedGB = [math]::Round($drive.Used / 1GB, 2)
$totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)

$report = @"
=== C盘空间日报 $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===
总容量: ${totalGB} GB | 已用: ${usedGB} GB | 可用: ${freeGB} GB
使用率: ${usedPercent}%
"@

$logDir = "C:\cleanup_snapshots\daily"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$report | Out-File "$logDir\$(Get-Date -Format 'yyyyMMdd').txt" -Append -Encoding UTF8

if ($usedPercent -ge $threshold) {
    Write-Host "⚠️ 告警: C盘使用率 ${usedPercent}% 超过阈值 ${threshold}%!" -ForegroundColor Red
    Write-Host "可用空间仅 ${freeGB} GB，建议尽快清理" -ForegroundColor Red
    Write-Host "运行扫描: powershell -File '$SkillRoot\analyze.ps1'" -ForegroundColor Yellow
}

# 清理超过30天的日志
Get-ChildItem $logDir -Filter "*.txt" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force
