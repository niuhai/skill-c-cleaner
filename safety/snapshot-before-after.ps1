# snapshot-before-after.ps1 - 清理/迁移前后快照对比
# 记录操作前后的C盘空间和各主要目录大小

param(
    [string]$Label = "manual",
    [string]$Mode = "before"  # before / after
)

$skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $skillRoot "_common.ps1")
$SnapshotDir = Initialize-CleanSightArtifactDirectory (Get-CleanSightArtifactPath "snapshots")
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$snapshotFile = "$SnapshotDir\$($Label)_${Mode}_$timestamp.json"

Write-Host "===== 快照工具: $Mode =====" -ForegroundColor Cyan

$snapshot = @{
    Timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Mode = $Mode
    Label = $Label
    C_Drive = @{}
    Key_Paths = @{}
}

# C盘总览
$drive = Get-PSDrive C
$snapshot.C_Drive = @{
    TotalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    UsedGB = [math]::Round($drive.Used / 1GB, 2)
    FreeGB = [math]::Round($drive.Free / 1GB, 2)
    UsedPercent = [math]::Round($drive.Used / ($drive.Used + $drive.Free) * 100, 1)
}

# 关键路径大小
$keyPaths = @(
    @{Name="Windows Temp"; Path="C:\Windows\Temp"},
    @{Name="User Temp"; Path="$env:LOCALAPPDATA\Temp"},
    @{Name="Edge (x86)"; Path=${env:ProgramFiles(x86)} + "\Microsoft\EdgeCore"},
    @{Name="ProgramData"; Path=$env:ProgramData},
    @{Name="Recycle Bin"; Path="C:\`$Recycle.Bin"},
    @{Name="WinSxS"; Path="C:\Windows\WinSxS"},
    @{Name="SoftwareDistribution"; Path="C:\Windows\SoftwareDistribution"},
    @{Name="User AppData"; Path="$env:USERPROFILE\AppData"}
)

foreach ($kp in $keyPaths) {
    if (Test-Path $kp.Path) {
        $items = Get-ChildItem $kp.Path -Recurse -Force -ErrorAction SilentlyContinue
        $size = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object Length -Sum).Sum
        $snapshot.Key_Paths[$kp.Name] = @{
            Path = $kp.Path
            SizeMB = [math]::Round($size / 1MB, 2)
            ItemCount = @($items).Count
        }
    } else {
        $snapshot.Key_Paths[$kp.Name] = @{ Path = $kp.Path; SizeMB = 0; ItemCount = 0; Missing = $true }
    }
}

# 保存快照
$snapshot | ConvertTo-Json -Depth 4 | Out-File $snapshotFile -Encoding UTF8

Write-Host "快照已保存: $snapshotFile" -ForegroundColor Green
Write-Host "C盘: $($snapshot.C_Drive.UsedGB)/$($snapshot.C_Drive.TotalGB) GB ($($snapshot.C_Drive.UsedPercent)%)" -ForegroundColor Yellow

# 如果是 after 模式，尝试找 before 快照对比
if ($Mode -eq "after") {
    $beforeFile = Get-ChildItem $SnapshotDir -Filter "$($Label)_before_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($beforeFile) {
        $before = Get-Content $beforeFile.FullName | ConvertFrom-Json
        $diffFree = $snapshot.C_Drive.FreeGB - $before.C_Drive.FreeGB
        Write-Host ""
        Write-Host "===== 对比结果 =====" -ForegroundColor Cyan
        Write-Host "操作前空闲: $($before.C_Drive.FreeGB) GB" -ForegroundColor DarkGray
        Write-Host "操作后空闲: $($snapshot.C_Drive.FreeGB) GB" -ForegroundColor Green
        if ($diffFree -gt 0) {
            Write-Host "✅ 释放空间: +$([math]::Round($diffFree,2)) GB" -ForegroundColor Green
        } elseif ($diffFree -lt 0) {
            Write-Host "⚠️ 空间减少: $([math]::Round($diffFree,2)) GB" -ForegroundColor Red
        } else {
            Write-Host "  空间无变化" -ForegroundColor DarkGray
        }
    }
}
