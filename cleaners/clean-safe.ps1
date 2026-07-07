# clean-safe.ps1 - Layer 3 安全自动清理
# 仅清理明确可安全删除的类别: 临时文件, 缓存, 缩略图
# 不涉及系统级操作, 不会造成任何副作用
# 默认 WhatIf 模式

param([switch]$ReallyDelete)

$skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $skillRoot -or -not (Test-Path (Join-Path $skillRoot "_common.ps1"))) {
    $skillRoot = "C:\.trae\skills\c-drive-cleaner"
}
. (Join-Path $skillRoot "_common.ps1")

# 日志文件放到 skill 的 reports 目录下，避免污染 C 盘根目录
$reportsDir = Join-Path $skillRoot "reports"
if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
$LogFile = Join-Path $reportsDir "cleanup_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

if (-not $ReallyDelete) {
    Write-Host "===== 安全清理 - WhatIf 预览模式 =====" -ForegroundColor Cyan
    Write-Host "下面显示的都会在真正执行时被永久删除（不经过回收站）。" -ForegroundColor Yellow
    Write-Host "添加 -ReallyDelete 参数才真正执行。建议以管理员身份运行以获得最佳效果。" -ForegroundColor Yellow
    Write-Host ""
    $WhatIf = $true
} else {
    # 管理员权限检测
    if (-not (Test-Admin)) {
        Write-Host "===== 需要管理员权限 =====" -ForegroundColor Red
        Write-Host "系统目录需要管理员权限才能清理。" -ForegroundColor Yellow
        Write-Host "请关闭此窗口，右键 PowerShell -> 以管理员身份运行，然后重试。" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "===== 安全清理 - 执行中 =====" -ForegroundColor Cyan
    Write-Host "日志: $LogFile" -ForegroundColor Yellow
    Write-Host "注意: 文件将被永久删除（不经过回收站），删除后无法恢复。" -ForegroundColor Red
    $WhatIf = $false
}

function Safe-Clean {
    param([string]$Path, [string]$Description)
    $exists = Test-Path $Path -ErrorAction SilentlyContinue
    if (-not $exists) {
        Write-Host "$Description - 路径不存在或无权访问, 跳过" -ForegroundColor DarkGray
        return 0
    }
    $r = Get-FolderSizeFast $Path
    if (-not $r.Found -or $r.Size -eq 0) {
        Write-Host "$Description - 空目录, 跳过" -ForegroundColor DarkGray
        return 0
    }
    $sizeMB = [math]::Round($r.Size / 1MB, 2)
    $sizeStr = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB/1024,2)) GB" } else { "$sizeMB MB" }
    Write-Host "$Description : $sizeStr" -ForegroundColor Green
    Write-Host "  路径: $Path" -ForegroundColor DarkGray
    if (-not $WhatIf) {
        $ok = Remove-Directory -Path $Path -ShowProgress
        if ($ok) { return $r.Size } else { return 0 }
    }
    return $r.Size
}

$totalFreed = 0L

$totalFreed += Safe-Clean -Path "C:\Windows\Temp" -Description "[1/7] Windows 临时文件夹"
$totalFreed += Safe-Clean -Path "$env:LOCALAPPDATA\Temp" -Description "[2/7] 用户临时文件夹"

$doPath = "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization"
$totalFreed += Safe-Clean -Path $doPath -Description "[5/7] 传递优化文件"

$totalFreed += Safe-Clean -Path "C:\ProgramData\Microsoft\Windows\WER" -Description "[6/7] Windows 错误报告"

# 3. 缩略图缓存
$thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
if (Test-Path $thumbPath) {
    $thumbFiles = Get-ChildItem $thumbPath -Filter "*.db" -ErrorAction SilentlyContinue
    $thumbSize = ($thumbFiles | Measure-Object Length -Sum).Sum
    $thumbMB = [math]::Round($thumbSize / 1MB, 2)
    Write-Host "[3/7] 缩略图缓存: ${thumbMB} MB" -ForegroundColor Green
    if (-not $WhatIf -and $thumbFiles) {
        Write-Host "  删除中..." -NoNewline -ForegroundColor DarkGray
        $thumbFiles | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-Host " 完成" -ForegroundColor Green
    }
    $totalFreed += [long]$thumbSize
}

# 4. 回收站
try {
    $rb = Get-ChildItem "C:\`$Recycle.Bin" -Recurse -Force -ErrorAction SilentlyContinue
    $rbSize = ($rb | Where-Object { -not $_.PSIsContainer } | Measure-Object Length -Sum).Sum
    $rbMB = [math]::Round($rbSize / 1MB, 2)
    Write-Host "[4/7] 回收站: ${rbMB} MB" -ForegroundColor Green
    if (-not $WhatIf) {
        Write-Host "  清空回收站..." -NoNewline -ForegroundColor DarkGray
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Host " 完成" -ForegroundColor Green
    }
    $totalFreed += [long]$rbSize
} catch { Write-Host "[4/7] 回收站: 无法访问" -ForegroundColor DarkGray }

# 7. Windows更新缓存
Write-Host "[7/7] Windows更新缓存 (跳过 - 需要停止wuauserv服务, 请用clean-deep.ps1)" -ForegroundColor Yellow

$totalMB = [math]::Round($totalFreed / 1MB, 2)
$totalGB = [math]::Round($totalFreed / 1GB, 2)
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host "可释放空间: $totalMB MB ($totalGB GB) (预览模式)" -ForegroundColor Yellow
    Write-Host "请确认无误后, 加 -ReallyDelete 参数再次运行" -ForegroundColor Yellow
} else {
    Write-Host "已释放: $totalMB MB ($totalGB GB)" -ForegroundColor Green
    $space = Get-DriveSpace
    if ($space) {
        Write-Host "C盘当前: $($space.UsedGB) GB / $($space.TotalGB) GB (剩余 $($space.FreeGB) GB, $($space.UsedPercent)%)" -ForegroundColor Cyan
    }
    Write-Host "日志已保存: $LogFile"
}
Write-Host "============================================" -ForegroundColor Cyan
