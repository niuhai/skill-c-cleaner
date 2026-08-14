# clean-deep.ps1 - Layer 2 深度清理（需逐项确认）
# 包含: Windows更新缓存 + WinSxS + 还原点 + 休眠
# 每项列出大小后需用户显式确认 (Y/N)
# 不自动执行任何操作！

$skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not $skillRoot -or -not (Test-Path (Join-Path $skillRoot "_common.ps1"))) {
    throw "Skill root could not be resolved from the script location."
}
. (Join-Path $skillRoot "_common.ps1")

$LogFile = "C:\cleanup_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

Write-Host "===== 深度清理 — 逐项确认模式 =====" -ForegroundColor Cyan
Write-Host "以下每项操作前都会要求你确认。输入 Y 执行 / N 跳过。" -ForegroundColor Yellow
Write-Host "所有操作记录到: $LogFile" -ForegroundColor Yellow
Write-Host ""
Start-Transcript -Path $LogFile -Append

$totalFreed = 0

# 1. Windows 更新缓存
Write-Host "──────────────────────────────────────" -ForegroundColor Cyan
Write-Host "[1/4] Windows 更新缓存" -ForegroundColor Yellow
$updatePath = "C:\Windows\SoftwareDistribution\Download"
if (Test-Path $updatePath) {
    $ur = Get-FolderSizeFast $updatePath
    $updateSize = if ($ur.Found) { $ur.Size } else { 0 }
    $updateMB = [math]::Round($updateSize / 1MB, 2)
    Write-Host "  路径: $updatePath" -ForegroundColor DarkGray
    Write-Host "  大小: ${updateMB} MB" -ForegroundColor DarkGray
    Write-Host "  说明: 已下载安装成功的更新包残留" -ForegroundColor DarkGray
    $confirm = Read-Host "  是否清理? (Y/N)"
    if ($confirm -eq 'Y') {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        Remove-Directory -Path $updatePath -AllowedRoots @($updatePath) -ShowProgress
        $null = New-Item -ItemType Directory -Path $updatePath -Force -ErrorAction SilentlyContinue
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Write-Host "  ✅ 已清理" -ForegroundColor Green
        $totalFreed += [long]$updateSize
    } else { Write-Host "  跳过" -ForegroundColor DarkGray }
} else { Write-Host "  路径不存在" -ForegroundColor DarkGray }

Write-Host ""

# 2. WinSxS 组件清理
Write-Host "──────────────────────────────────────" -ForegroundColor Cyan
Write-Host "[2/4] WinSxS 组件存储清理" -ForegroundColor Yellow
try {
    $dismOutput = Dism /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
    $dismText = $dismOutput -join "`n"
    $reclaimMatch = [regex]::Match($dismText, 'Size of Reclaimable Packages\s*:\s*([\d.]+)\s*(GB|MB)')
    if ($reclaimMatch.Success) {
        Write-Host "  可清理空间: $($reclaimMatch.Value)" -ForegroundColor Green
        $confirm = Read-Host "  是否执行 Dism 清理? (Y/N)"
        if ($confirm -eq 'Y') {
            Dism /Online /Cleanup-Image /StartComponentCleanup
            Write-Host "  ✅ 组件清理完成" -ForegroundColor Green
        } else { Write-Host "  跳过" -ForegroundColor DarkGray }
    } else {
        Write-Host "  当前无需清理" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  WinSxS分析失败: 需管理员权限" -ForegroundColor Red
}

Write-Host ""

# 3. 系统还原点
Write-Host "──────────────────────────────────────" -ForegroundColor Cyan
Write-Host "[3/4] 系统还原点" -ForegroundColor Yellow
try {
    vssadmin list shadows 2>$null
    Write-Host "  ⚠️ 删除所有还原点会失去系统回滚能力" -ForegroundColor Red
    Write-Host "  建议: 只限制存储上限而非全部删除" -ForegroundColor Yellow
    $confirm = Read-Host "  是否限制还原点空间上限为5GB? (Y/N)"
    if ($confirm -eq 'Y') {
        vssadmin resize shadowstorage /on=C: /for=C: /maxsize=5GB
        Write-Host "  ✅ 已限制为5GB" -ForegroundColor Green
    } else { Write-Host "  跳过" -ForegroundColor DarkGray }
} catch {
    Write-Host "  无法访问还原点: 需管理员权限" -ForegroundColor Red
}

Write-Host ""

# 4. 休眠文件
Write-Host "──────────────────────────────────────" -ForegroundColor Cyan
Write-Host "[4/4] 休眠文件 hiberfil.sys" -ForegroundColor Yellow
if (Test-Path "C:\hiberfil.sys") {
    $hiberSize = (Get-Item "C:\hiberfil.sys" -Force).Length
    $hiberGB = [math]::Round($hiberSize / 1GB, 2)
    Write-Host "  当前大小: ${hiberGB} GB" -ForegroundColor Yellow
    Write-Host "  说明: 关闭休眠后文件自动删除。如果只用睡眠(合盖)不用休眠可关闭" -ForegroundColor DarkGray
    $confirm = Read-Host "  是否关闭休眠? (Y/N)"
    if ($confirm -eq 'Y') {
        powercfg.exe /hibernate off
        Write-Host "  ✅ 休眠已关闭，hiberfil.sys 将被删除" -ForegroundColor Green
        $totalFreed += [long]$hiberSize
    } else { Write-Host "  跳过" -ForegroundColor DarkGray }
} else {
    Write-Host "  休眠未开启" -ForegroundColor DarkGray
}

Write-Host ""
$totalMB = [math]::Round($totalFreed / 1MB, 2)
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "本次释放空间: ${totalMB} MB" -ForegroundColor Green
Write-Host "日志已保存: $LogFile"
Write-Host "============================================" -ForegroundColor Cyan
Stop-Transcript
