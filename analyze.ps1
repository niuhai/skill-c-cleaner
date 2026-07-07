param(
    [string]$Categories = "all",
    [string]$OutputFormat = "console",
    [string]$Template = "v6-ai-decision"
)

$SkillRoot = Split-Path -Parent $PSCommandPath
if (-not $SkillRoot) { $SkillRoot = "C:\.trae\skills\c-drive-cleaner" }
. (Join-Path $SkillRoot "_common.ps1")

$VERSION = "6.1.2"
$BRAND = "CleanSight"
$Global:CDriveScanResults = [System.Collections.ArrayList]::new()

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  $BRAND v$VERSION - AI Disk Health Advisor" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$space = Get-DriveSpace
$healthScore = 50
if ($space) {
    $barLen = 30
    $usedBlocks = [math]::Round($space.UsedPercent / 100 * $barLen)
    $freeBlocks = $barLen - $usedBlocks
    $bar = "#" * $usedBlocks + "-" * $freeBlocks
    $barColor = if ($space.UsedPercent -gt 90) { "Red" } elseif ($space.UsedPercent -gt 80) { "Yellow" } else { "Green" }
    Write-Host "  C: [$bar] $($space.UsedPercent)%" -ForegroundColor $barColor
    Write-Host "  Used: $($space.UsedGB) GB / Total: $($space.TotalGB) GB / Free: $($space.FreeGB) GB" -ForegroundColor White
    $healthScore = [math]::Max(0, [math]::Min(100, 100 - ($space.UsedPercent - 50) * 2))
    $scoreColor = if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" }
    Write-Host "  Health Score: $healthScore/100" -ForegroundColor $scoreColor
    Write-Host ""
}

$allCats = @(
    @{ Code = "A"; Script = "scan-system-hidden.ps1" }
    @{ Code = "B"; Script = "scan-temp-files.ps1" }
    @{ Code = "C"; Script = "scan-dev-caches.ps1" }
    @{ Code = "D"; Script = "scan-browsers.ps1" }
    @{ Code = "E"; Script = "scan-app-data.ps1" }
    @{ Code = "F"; Script = "scan-large-files.ps1" }
    @{ Code = "G"; Script = "scan-special-sources.ps1" }
    @{ Code = "H"; Script = "scan-security-software.ps1" }
    @{ Code = "I"; Script = "scan-multi-version.ps1" }
    @{ Code = "J"; Script = "scan-duplicate-runtimes.ps1" }
    @{ Code = "K"; Script = "scan-ime-data.ps1" }
    @{ Code = "L"; Script = "scan-im-apps.ps1" }
    @{ Code = "VM"; Script = "scan-virtual-memory.ps1" }
    @{ Code = "SI"; Script = "scan-search-index.ps1" }
)

$selectedCats = if ($Categories -eq "all") { $allCats } else {
    $codes = $Categories -split "," | ForEach-Object { $_.Trim().ToUpper() }
    $allCats | Where-Object { $_.Code -in $codes }
}

$totalCats = @($selectedCats).Count
$catIdx = 0
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($cat in $selectedCats) {
    $catIdx++
    $scriptPath = Join-Path $SkillRoot "scanners\$($cat.Script)"
    if (Test-Path $scriptPath) {
        Write-Host "[$catIdx/$totalCats] " -NoNewline -ForegroundColor DarkGray
        . $scriptPath
    } else {
        Write-Host "  WARN: scanner not found: $($cat.Script)" -ForegroundColor Red
    }
}

$stopwatch.Stop()
$scanDuration = "$([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scan Complete (took $scanDuration)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$results = $Global:CDriveScanResults
$totalCleanable = 0; $totalCautious = 0; $totalForbidden = 0; $totalAll = 0
if ($results -and $results.Count -gt 0) {
    $safeItems = @($results | Where-Object { $_.Risk -eq "safe" })
    $cautItems = @($results | Where-Object { $_.Risk -eq "cautious" })
    $forbItems = @($results | Where-Object { $_.Risk -eq "forbidden" })
    if ($safeItems.Count -gt 0) { $totalCleanable = [math]::Round(($safeItems | ForEach-Object { $_.SizeMB } | Measure-Object -Sum).Sum, 2) }
    if ($cautItems.Count -gt 0) { $totalCautious = [math]::Round(($cautItems | ForEach-Object { $_.SizeMB } | Measure-Object -Sum).Sum, 2) }
    if ($forbItems.Count -gt 0) { $totalForbidden = [math]::Round(($forbItems | ForEach-Object { $_.SizeMB } | Measure-Object -Sum).Sum, 2) }
    $totalAll = [math]::Round(($results | ForEach-Object { $_.SizeMB } | Measure-Object -Sum).Sum, 2)
}

if (-not $results -or $results.Count -eq 0) {
    Write-Host "  No cleanable items found" -ForegroundColor Green
} else {
    $cleanGB = [math]::Round($totalCleanable / 1024, 2)
    $cautGB = [math]::Round($totalCautious / 1024, 2)
    $forbGB = [math]::Round($totalForbidden / 1024, 2)
    $allGB = [math]::Round($totalAll / 1024, 2)
    Write-Host "  Safe to clean:     $cleanGB GB" -ForegroundColor Green
    Write-Host "  Needs confirm:     $cautGB GB" -ForegroundColor Yellow
    Write-Host "  Do NOT delete:     $forbGB GB" -ForegroundColor Red
    Write-Host "  Total scanned:     $allGB GB" -ForegroundColor White
    Write-Host ""
    $byCategory = $results | Group-Object Category | Sort-Object { ($_.Group | ForEach-Object { $_.SizeMB } | Measure-Object -Sum).Sum } -Descending
    Write-Host "  By category:" -ForegroundColor White
    foreach ($grp in $byCategory) {
        $catSize = [math]::Round(($grp.Group | ForEach-Object { $_.SizeMB } | Measure-Object -Sum).Sum, 2)
        $catGB = [math]::Round($catSize / 1024, 2)
        Write-Host "    $($grp.Name): $catGB GB" -ForegroundColor DarkGray
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportId = "CS-${timestamp}-$($healthScore)"
$cb = [char]96 + [char]96 + [char]96

$catNamesCN = @{
    "A"="系统隐藏"; "B"="临时缓存"; "C"="开发缓存"; "D"="浏览器";
    "E"="应用数据"; "F"="大文件"; "G"="特殊占用"; "H"="安全软件";
    "I"="多版本"; "J"="重复运行时"; "K"="输入法"; "L"="即时通讯";
    "VM"="虚拟内存"; "SI"="Search索引"
}

$knownBloat = @{
    "腾讯电脑管家" = "通常是捆绑安装的。如不主动用它杀毒/加速，建议控制面板卸载"
    "360安全卫士"   = "免费杀毒软件但常弹广告。Windows Defender 已足够，建议卸载"
    "360全家桶"     = "浏览器+压缩+安全全家桶，通常是捆绑安装，建议整套卸载"
    "2345全家桶"    = "著名流氓软件家族，通常静默安装，建议用 Geek Uninstaller 深度清理"
    "快压"          = "弹窗广告多，建议用 7-Zip 替代并卸载"
    "好压"          = "广告多，建议用 7-Zip 替代"
    "鲁大师"        = "温度监控但广告多，可用 HWMonitor 替代"
    "小鸟壁纸"      = "弹窗广告+静默安装，必须卸载"
    "Flash中国版"   = "含广告服务，现代浏览器已不需要 Flash，必须卸载"
    "驱动精灵"      = "驱动更新工具，Windows Update 已能自动更新"
    "驱动人生"      = "同驱动精灵，建议卸载"
    "搜狗高速浏览器" = "老旧浏览器内核，建议用 Edge/Chrome 替代"
    "PPS"           = "老旧 P2P 播放器后台占带宽，建议卸载"
    "PPTV"          = "同 PPS，建议卸载"
    "WeGame"        = "腾讯游戏平台，如果不玩游戏可卸载"
}

function BuildReport {
    $reportsDir = Join-Path $SkillRoot "reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
    $mdPath = Join-Path $reportsDir "CleanSight-${reportId}.md"
    $lines = @()
    $lines += "# CleanSight AI 磁盘健康报告"
    $lines += ""
    $lines += "> **报告编号**: $reportId | **生成时间**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | **引擎**: $BRAND v$VERSION"
    $lines += "> **本报告为只读分析，未修改任何文件。所有操作需用户确认后执行。**"
    $lines += "---"
    $lines += "# 一、执行摘要"
    if ($space) {
        $usageLevelCN = if ($space.UsedPercent -gt 90) { "🔴 危急" } elseif ($space.UsedPercent -gt 80) { "⚠️ 偏高" } else { "✅ 正常" }
        $freeLevelCN = if ($space.FreeGB -lt 15) { "🔴 不足" } elseif ($space.FreeGB -lt 30) { "⚠️ 偏低" } else { "✅ 充足" }
        $lines += "| 总容量 | $($space.TotalGB) GB | - |"
        $lines += "| 已用空间 | $($space.UsedGB) GB ($($space.UsedPercent)%) | $usageLevelCN |"
        $lines += "| 可用空间 | $($space.FreeGB) GB | $freeLevelCN |"
        $lines += "| 可安全释放 | $([math]::Round($totalCleanable/1024,2)) GB | ✅ 安全 |"
        $lines += "| 需确认后释放 | $([math]::Round($totalCautious/1024,2)) GB | ⚠️ 需确认 |"
    }
    
    if ($Global:VMAssessResult) {
        $vm = $Global:VMAssessResult
        $vmSizeGB = [math]::Round($vm.TotalSize / 1GB, 2)
        $assessmentCN = switch ($vm.Assessment) {
            "critical" { "🔴 危急 - 建议立即优化" }
            "warning" { "⚠️ 警告 - 建议评估后优化" }
            "normal" { "✅ 正常 - 无需调整" }
            default { "ℹ️ 信息" }
        }
        
        $lines += ""
        $lines += "# 二、虚拟内存评估"
        $lines += ""
        $lines += "## 当前状态"
        $lines += ""
        $lines += "| 指标 | 数值 | 状态 |"
        $lines += "|------|------|------|"
        $freeStatus = if ($vm.FreePercent -lt 30) { '🔴 不足' } else { '✅ 充足' }
        $lines += "| C盘可用空间 | $($vm.FreePercent)% | $freeStatus |"
        $lines += "| 页面文件位置 | $(if ($vm.OnC) { 'C盘' } else { '非系统分区' }) | $(if ($vm.OnC -and $vm.Assessment -ne 'normal') { '⚠️ 可优化' } else { '✅ 良好' }) |"
        $lines += "| 页面文件大小 | $vmSizeGB GB | - |"
        $lines += "| 评估结果 | $assessmentCN |"
        $lines += ""
        
        if ($vm.Recommendations -and $vm.Recommendations.Count -gt 0) {
            $lines += "## 优化建议"
            $lines += ""
            foreach ($rec in $vm.Recommendations) {
                $priorityIcon = switch ($rec.Priority) {
                    "high" { "🔴" }
                    "medium" { "⚠️" }
                    "low" { "✅" }
                    default { "ℹ️" }
                }
                $lines += "- **$priorityIcon $($rec.Action)**"
                $lines += "  - $($rec.Detail)"
                if ($rec.SpaceRelease -gt 0) {
                    $lines += "  - 预期效果: 释放 $($rec.SpaceRelease) GB | 性能收益: $($rec.PerformanceGain)"
                }
                $lines += ""
            }
        }
        
        if ($vm.SuitableDrives -and $vm.SuitableDrives.Count -gt 0 -and $vm.Assessment -ne "normal") {
            $lines += "## 可用迁移目标"
            $lines += ""
            foreach ($drive in $vm.SuitableDrives) {
                $ssdTag = if ($drive.IsSSD) { " ⭐ SSD" } else { "" }
                $lines += "- **驱动器 ${drive.Drive}:** 可用空间 ${drive.FreeGB} GB $ssdTag"
                $lines += "  - $($drive.Recommendation)"
                $lines += ""
            }
        }
        
        if ($vm.Assessment -ne "normal") {
            $lines += "## 实施步骤"
            $lines += ""
            $lines += "1. 按 **Win+R**，输入 **sysdm.cpl**，回车打开系统属性"
            $lines += "2. 切换到「**高级**」选项卡，点击「**性能**」区域的「**设置**」"
            $lines += "3. 切换到「**高级**」选项卡，点击「**虚拟内存**」区域的「**更改**」"
            $lines += "4. 取消勾选「**自动管理所有驱动器的分页文件大小**」"
            $lines += "5. 选择C盘，勾选「**自定义大小**」，设置初始: **4096 MB**，最大: **4096 MB**，点击「**设置**」"
            
            if ($vm.SuitableDrives -and $vm.SuitableDrives.Count -gt 0) {
                $primaryDrive = $vm.SuitableDrives | Where-Object { $_.IsSSD } | Select-Object -First 1
                if (-not $primaryDrive) {
                    $primaryDrive = $vm.SuitableDrives | Select-Object -First 1
                }
                if ($primaryDrive) {
                    $lines += "6. 选择 **${primaryDrive.Drive}:** 盘，勾选「**自定义大小**」，设置初始: **32768 MB**，最大: **65536 MB**，点击「**设置**」"
                }
            }
            $lines += "7. 连续点击「**确定**」，**重启计算机**使更改生效"
            $lines += ""
            $lines += "> ⚠️ **注意:** 保持4GB页面文件在C盘作为备份路径，确保系统兼容性和应急使用。"
        }
    }
    
    $lines | Out-File $mdPath -Encoding UTF8
    Write-Host "  Report generated: $mdPath" -ForegroundColor Green
}

if ($OutputFormat -eq "markdown") { BuildReport }

if ($OutputFormat -eq "json") {
    $reportsDir = Join-Path $SkillRoot "reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
    $jsonPath = Join-Path $reportsDir "CleanSight-${reportId}.json"
    $output = @{ report_id = $reportId; version = $VERSION; timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; scan_duration = $scanDuration }
    $output | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8
    Write-Host "  JSON report generated: $jsonPath" -ForegroundColor Green
}

Write-Host ""
