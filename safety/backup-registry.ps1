# backup-registry.ps1 - 操作前注册表备份
# 在执行环境变量修改/配置变更前备份相关注册表项

param([string]$BackupDir = "")

$skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $skillRoot "_common.ps1")
if (-not $BackupDir) { $BackupDir = Get-CleanSightArtifactPath "snapshots\registry_backups" }

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "===== 注册表备份工具 =====" -ForegroundColor Cyan

# 关键注册表路径 (环境变量 + 应用配置)
$keyPaths = @(
    "HKCU\Environment",
    "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders",
    "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
)

$backups = @()

foreach ($key in $keyPaths) {
    $regFile = "$BackupDir\$(($key -replace '[\\:]', '_'))_$timestamp.reg"
    try {
        reg export $key $regFile /y 2>$null
        if (Test-Path $regFile) {
            $backups += $regFile
            Write-Host "  ✅ $key -> $(Split-Path $regFile -Leaf)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ⚠️ $key 备份失败: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "备份完成: $($backups.Count) 个注册表文件" -ForegroundColor Green
Write-Host "位置: $BackupDir"
Write-Host ""
Write-Host "恢复方法 (管理员PowerShell):" -ForegroundColor DarkGray
foreach ($bf in $backups) {
    Write-Host "  reg import $bf" -ForegroundColor DarkGray
}
