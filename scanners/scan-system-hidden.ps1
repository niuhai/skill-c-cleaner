# scan-system-hidden.ps1 - A类：系统隐藏大文件扫描
# 只读扫描，不修改任何文件

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "===== A类：系统隐藏大文件 =====" -ForegroundColor Cyan

$hiberPath = "C:\hiberfil.sys"
if (Test-Path $hiberPath) {
    $hiberSize = (Get-Item $hiberPath -Force).Length
    Write-ScanResult -Category "A" -Name "休眠文件(hiberfil.sys)" -Size $hiberSize `
        -Risk "cautious" -Path $hiberPath `
        -Advice "可关闭休眠释放 | 如只用睡眠可关闭" -Migration "不可迁移"
} else {
    Write-Host "  ○ 休眠文件: 不存在（已关闭）" -ForegroundColor DarkGray
}

$pagefilePaths = @("C:\pagefile.sys")
$pagefileConfigured = $false
try {
    $memoryKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -ErrorAction Stop
    foreach ($line in @($memoryKey.PagingFiles)) {
        if (-not $line) { continue }
        $parts = @($line -split '\s+') | Where-Object { $_ -ne "" }
        if ($parts.Count -ge 1) {
            $configuredPath = [string]$parts[0]
            if ($configuredPath.StartsWith("\??\")) { $configuredPath = $configuredPath.Substring(4) }
            $pagefilePaths += $configuredPath
            $pagefileConfigured = $true
        }
    }
} catch {}

$pagefileFound = $false
$uniquePagefiles = [Collections.Generic.List[string]]::new()
$seenPagefiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($candidate in @($pagefilePaths | Where-Object { $_ })) {
    if ($seenPagefiles.Add([string]$candidate)) { $uniquePagefiles.Add([string]$candidate) }
}
foreach ($pagePath in @($uniquePagefiles)) {
    $pageSize = 0L
    $readable = $false
    try {
        $pageItem = Get-Item -LiteralPath $pagePath -Force -ErrorAction Stop
        if ($pageItem -and -not $pageItem.PSIsContainer) {
            $pageSize = [long]$pageItem.Length
            $readable = $true
        }
    } catch {}

    if ($readable) {
        Write-ScanResult -Category "A" -Name "页面文件(pagefile.sys)" -Size $pageSize `
            -Risk "forbidden" -Path $pagePath `
            -Advice "不建议删除 | 可迁移到其他盘" -Migration "系统设置>虚拟内存"
        $pagefileFound = $true
    } elseif ($pagefileConfigured -and $pagePath -match '^[A-Za-z]:\\pagefile\.sys$') {
        Write-Host "  ⚠️ 页面文件已配置: $pagePath（文件大小因权限无法读取）" -ForegroundColor Yellow
        $pagefileFound = $true
    }
}
if (-not $pagefileFound) {
    Write-Host "  ○ 页面文件: 未检测到可读取文件或配置" -ForegroundColor DarkGray
}

try {
    $rp = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
    if ($rp) {
        $rpCount = @($rp).Count
        Write-Host "  ⚠️ 系统还原点: $rpCount 个" -ForegroundColor Yellow
        Write-Host "     建议: 可清理旧的保留最新 | 迁移: 不可迁移" -ForegroundColor DarkGray
        Write-Host "     操作: vssadmin list shadows | vssadmin resize shadowstorage /on=C: /for=C: /maxsize=5GB" -ForegroundColor DarkGray
    } else {
        Write-Host "  ○ 系统还原点: 无或无法访问" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ○ 系统还原点: 无法查询（需管理员权限）" -ForegroundColor DarkGray
}

Write-Host "  系统还原点和WinSxS: 需 Dism 分析" -ForegroundColor DarkGray
try {
    $dismOutput = Dism /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
    $dismText = $dismOutput -join "`n"
    if ($dismText -match "Component Store Cleanup Recommended\s*:\s*Yes") {
        $reclaimMatch = [regex]::Match($dismText, 'Size of Reclaimable Packages\s*:\s*([\d.]+)\s*(GB|MB)')
        if ($reclaimMatch.Success) {
            Write-Host "  ✅ WinSxS可回收: $($reclaimMatch.Value)" -ForegroundColor Green
            Write-Host "     操作: Dism /Online /Cleanup-Image /StartComponentCleanup" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  ○ WinSxS: 当前无需清理" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  ○ WinSxS: 无法分析（需管理员权限）" -ForegroundColor DarkGray
}

Invoke-SignatureScan -Category "system" -CategoryLabel "A" -AlreadyScanned @("Windows临时文件","用户临时文件","缩略图缓存","回收站","Windows更新缓存","传递优化","Windows错误报告","Prefetch","休眠文件","页面文件")

Write-Host ""
