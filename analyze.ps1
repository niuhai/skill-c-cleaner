param(
    [string]$Categories = "all",
    [string]$OutputFormat = "console",
    [string]$Template = "v6-ai-decision",
    [string]$OutputRoot = "",
    [switch]$Fast,
    [switch]$RecordGrowth
)

$SkillRoot = Split-Path -Parent $PSCommandPath
if (-not $SkillRoot) { $SkillRoot = $PSScriptRoot }
if (-not $SkillRoot) { throw "Skill root could not be resolved from the script location." }
. (Join-Path $SkillRoot "_common.ps1")

if ($OutputRoot) { $Global:CDriveArtifactRoot = $OutputRoot }

$VERSION = "7.4.0"
$BRAND = "CleanSight"
$Global:CDriveScanResults = [System.Collections.ArrayList]::new()
$Global:CDriveInventory = [System.Collections.ArrayList]::new()
$Global:CDriveScannerMetadata = @{}
$Global:CDriveScanTelemetry = [System.Collections.ArrayList]::new()
$Global:CDriveMeasurementCache = @{}
$Global:CDriveMeasurementCacheHits = 0
$Global:CDriveMeasurementCacheMisses = 0
$Global:CDriveMeasurementCacheEnabled = $true
$Global:CDriveUninstallRegistryEntries = $null
$Global:CDriveFastMode = [bool]$Fast
$Global:CDriveNativePathTotals = @()
$Global:CDriveNativePathTotalsMetadata = $null
$Global:CDriveRecordGrowth = [bool]$RecordGrowth

function Get-AnalyzerMeasurementPlanPaths {
    param([object[]]$SelectedCategories)
    $codes = @($SelectedCategories | ForEach-Object { [string]$_.Code })
    $signatureMap = @{
        A=@("system"); B=@("system"); C=@("dev_tools"); D=@("browsers")
        E=@("ides","media","office","ai_tools","cloud_storage")
        G=@("virtualization","games"); H=@("security"); K=@("input_methods"); L=@("im_apps")
    }
    $signatureCategories = [System.Collections.ArrayList]::new()
    foreach ($code in $codes) {
        foreach ($category in @($signatureMap[$code])) {
            if ($category -and $category -notin $signatureCategories) { [void]$signatureCategories.Add($category) }
        }
    }

    $paths = [System.Collections.ArrayList]::new()
    if ($signatureCategories.Count -gt 0) {
        foreach ($path in @(Get-SignatureMeasurementPlanPaths -Categories @($signatureCategories))) { [void]$paths.Add($path) }
    }

    if ($codes -contains "I") {
        $versionSpecs = @(
            @{ Root="${env:ProgramFiles(x86)}\Microsoft\EdgeCore"; Pattern='^\d+\.\d+\.\d+\.\d+$'; Minimum=2 },
            @{ Root="$env:ProgramFiles\WPS Office"; Pattern='^\d+\.\d+\.\d+\.\d+'; Minimum=2 },
            @{ Root="$env:ProgramFiles\Microsoft Visual Studio"; Pattern='^20\d+$'; Minimum=2 },
            @{ Root="$env:LOCALAPPDATA\Programs\Python"; Pattern='^Python\d+'; Minimum=2 },
            @{ Root="$env:LOCALAPPDATA\Volta\tools\image\node"; Pattern='.*'; Minimum=4 }
        )
        foreach ($spec in $versionSpecs) {
            $versions = @(Get-ChildItem -LiteralPath $spec.Root -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $spec.Pattern })
            if ($versions.Count -ge $spec.Minimum) {
                foreach ($version in $versions) { [void]$paths.Add($version.FullName) }
            }
        }
    }

    if ($codes -contains "WU") {
        foreach ($path in @(
            'C:\$WinREAgent','C:\$WINDOWS.~BT','C:\$Windows.~WS',
            'C:\Windows\SoftwareDistribution\Download',
            'C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache',
            'C:\Windows\Logs\CBS','C:\Windows\Logs\DISM'
        )) { [void]$paths.Add($path) }
    }
    if ($codes -contains "AF") {
        # AF measures every declared AI root and its nested components in one
        # traversal, then seeds the shared cache. Do not pre-scan those child
        # paths independently in the global planner.
        $aiRoots = @(Resolve-AIFootprintConfiguredRoots | Where-Object {
            try { [IO.Path]::GetPathRoot($_.Path) -eq 'C:\' } catch { $false }
        })
        return @($paths | Where-Object {
            $candidate = [string]$_
            @($aiRoots | Where-Object { Test-PathAtOrBelow -Path $candidate -Root $_.Path }).Count -eq 0
        })
    }
    return @($paths)
}

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
    Write-Host "  Artifacts: $(Get-CleanSightArtifactRoot)" -ForegroundColor DarkGray
    Write-Host ""
}

$allCats = @(
    @{ Code = "AF"; Script = "scan-ai-footprints.ps1" }
    @{ Code = "A"; Script = "scan-system-hidden.ps1" }
    @{ Code = "B"; Script = "scan-temp-files.ps1" }
    @{ Code = "C"; Script = "scan-dev-caches.ps1" }
    @{ Code = "D"; Script = "scan-browsers.ps1" }
    @{ Code = "E"; Script = "scan-app-data.ps1" }
    @{ Code = "MS"; Script = "scan-managed-storage.ps1" }
    @{ Code = "F"; Script = "scan-large-files.ps1" }
    @{ Code = "G"; Script = "scan-special-sources.ps1" }
    @{ Code = "H"; Script = "scan-security-software.ps1" }
    @{ Code = "I"; Script = "scan-multi-version.ps1" }
    @{ Code = "J"; Script = "scan-duplicate-runtimes.ps1" }
    @{ Code = "K"; Script = "scan-ime-data.ps1" }
    @{ Code = "L"; Script = "scan-im-apps.ps1" }
    @{ Code = "VM"; Script = "scan-virtual-memory.ps1" }
    @{ Code = "SI"; Script = "scan-search-index.ps1" }
    @{ Code = "O"; Script = "scan-targeted-optimization.ps1" }
    @{ Code = "GR"; Script = "scan-growth.ps1" }
    @{ Code = "U"; Script = "scan-unused-software.ps1" }
    @{ Code = "MX"; Script = "scan-misc-space.ps1" }
    @{ Code = "WU"; Script = "scan-windows-update-residue.ps1" }
    @{ Code = "AD"; Script = "scan-admin-deep-accounting.ps1" }
    @{ Code = "SA"; Script = "scan-space-accounting.ps1" }
)

$selectedCats = if ($Fast -and $Categories -eq "all") {
    # Fast is the default evidence set for iteration-loop. F is opt-in because
    # a full C:\ recursive scan can take several minutes or hit ACLs.
    $allCats | Where-Object { $_.Code -notin @("F", "H", "MX", "AD", "SA") }
} elseif ($Categories -eq "all") { $allCats } else {
    $codes = $Categories -split "," | ForEach-Object { $_.Trim().ToUpper() }
    $allCats | Where-Object { $_.Code -in $codes }
}

$totalCats = @($selectedCats).Count
$catIdx = 0
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$planStatus = "completed"
$planError = ""
$planWatch = [Diagnostics.Stopwatch]::StartNew()
try {
    $planPaths = @(Get-AnalyzerMeasurementPlanPaths -SelectedCategories @($selectedCats))
    $planResult = Invoke-PathMeasurementPlan -Paths $planPaths -Parallelism 4
    $Global:CDriveScannerMetadata["PLAN"] = $planResult
    Write-Host ("  Measurement plan: {0} unique paths, {1} cache entries seeded in {2:N1}s" -f $planResult.Unique, $planResult.Seeded, $planResult.Seconds) -ForegroundColor DarkCyan
} catch {
    $planStatus = "failed"
    $planError = $_.Exception.Message
    $Global:CDriveScannerMetadata["PLAN"] = [pscustomobject]@{ Status="failed"; Error=$planError }
    Write-Host "  Measurement planner unavailable; scanners will measure on demand: $planError" -ForegroundColor Yellow
} finally {
    $planWatch.Stop()
    [void]$Global:CDriveScanTelemetry.Add([pscustomobject]@{
        Category="PLAN"; Script="global-measurement-plan"; Seconds=[math]::Round($planWatch.Elapsed.TotalSeconds,3)
        FindingsAdded=0; InventoryAdded=0; Status=$planStatus; Error=$planError
    })
}

foreach ($cat in $selectedCats) {
    $catIdx++
    $scriptPath = Join-Path $SkillRoot "scanners\$($cat.Script)"
    if (Test-Path $scriptPath) {
        Write-Host "[$catIdx/$totalCats] " -NoNewline -ForegroundColor DarkGray
        $categoryWatch = [Diagnostics.Stopwatch]::StartNew()
        $findingCountBefore = $Global:CDriveScanResults.Count
        $inventoryCountBefore = $Global:CDriveInventory.Count
        $categoryStatus = "completed"
        $categoryError = ""
        try {
            . $scriptPath
        } catch {
            $categoryStatus = "failed"
            $categoryError = $_.Exception.Message
            Write-Host "  Scanner failed: $categoryError" -ForegroundColor Red
        } finally {
            $categoryWatch.Stop()
            [void]$Global:CDriveScanTelemetry.Add([pscustomobject]@{
                Category = $cat.Code
                Script = $cat.Script
                Seconds = [math]::Round($categoryWatch.Elapsed.TotalSeconds, 3)
                FindingsAdded = $Global:CDriveScanResults.Count - $findingCountBefore
                InventoryAdded = $Global:CDriveInventory.Count - $inventoryCountBefore
                Status = $categoryStatus
                Error = $categoryError
            })
        }
    } else {
        Write-Host "  WARN: scanner not found: $($cat.Script)" -ForegroundColor Red
    }
}

$stopwatch.Stop()
$scanDuration = "$([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s"

function Get-DeduplicatedFindingRows {
    param([object[]]$Findings)
    $severity = @{ safe=1; cautious=2; dangerous=3; forbidden=4 }
    $sourcePriority = @{ Targeted=4; DB=2; '自定义'=2 }
    $byKey = @{}

    foreach ($finding in @($Findings)) {
        $measurements = @($finding.Measurements)
        if ($measurements.Count -eq 0 -and $finding.Path -and $finding.SizeMB -gt 0) {
            $measurements = @([pscustomobject]@{ Path=$finding.Path; Bytes=[int64]([double]$finding.SizeMB * 1MB) })
        }
        foreach ($measurement in $measurements) {
            $path = [string]$measurement.Path
            $bytes = [int64]$measurement.Bytes
            if (-not $path -or $bytes -le 0) { continue }
            $normalized = ""
            if ([IO.Path]::IsPathRooted($path)) {
                try { $normalized = [IO.Path]::GetFullPath($path).TrimEnd('\') } catch { $normalized = $path.TrimEnd('\') }
            } else {
                $normalized = "virtual:$($finding.Category):$($finding.Name):$path"
            }
            $key = $normalized.ToLowerInvariant()
            $row = [pscustomobject]@{
                Path = $normalized
                Bytes = $bytes
                Risk = [string]$finding.Risk
                Category = [string]$finding.Category
                Name = [string]$finding.Name
                Source = [string]$finding.Source
                OverlapCount = 1
            }
            if (-not $byKey.ContainsKey($key)) {
                $byKey[$key] = $row
                continue
            }
            $current = $byKey[$key]
            $current.OverlapCount++
            if ($bytes -gt $current.Bytes) { $current.Bytes = $bytes }
            $currentSeverity = if ($severity.ContainsKey($current.Risk)) { $severity[$current.Risk] } else { 2 }
            $newSeverity = if ($severity.ContainsKey($row.Risk)) { $severity[$row.Risk] } else { 2 }
            $currentSource = if ($sourcePriority.ContainsKey($current.Source)) { $sourcePriority[$current.Source] } else { 1 }
            $newSource = if ($sourcePriority.ContainsKey($row.Source)) { $sourcePriority[$row.Source] } else { 1 }
            if ($newSeverity -gt $currentSeverity -or ($newSeverity -eq $currentSeverity -and $newSource -gt $currentSource)) {
                $current.Risk = $row.Risk
                $current.Category = $row.Category
                $current.Name = $row.Name
                $current.Source = $row.Source
            }
        }
    }

    $accepted = [System.Collections.ArrayList]::new()
    foreach ($row in @($byKey.Values | Sort-Object { $_.Path.Length })) {
        $parent = $null
        if (-not $row.Path.StartsWith('virtual:', [StringComparison]::OrdinalIgnoreCase)) {
            foreach ($candidate in @($accepted)) {
                if ($candidate.Path.StartsWith('virtual:', [StringComparison]::OrdinalIgnoreCase)) { continue }
                if ($row.Path.StartsWith($candidate.Path.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
                    $parent = $candidate
                    break
                }
            }
        }
        if ($parent) {
            $parent.OverlapCount += $row.OverlapCount
            $parentSeverity = if ($severity.ContainsKey($parent.Risk)) { $severity[$parent.Risk] } else { 2 }
            $childSeverity = if ($severity.ContainsKey($row.Risk)) { $severity[$row.Risk] } else { 2 }
            if ($childSeverity -gt $parentSeverity) { $parent.Risk = $row.Risk }
            continue
        }
        [void]$accepted.Add($row)
    }
    return @($accepted)
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Scan Complete (took $scanDuration)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$results = $Global:CDriveScanResults
$dedupedFindings = @(Get-DeduplicatedFindingRows -Findings @($results))
$totalCleanable = 0; $totalCautious = 0; $totalForbidden = 0; $totalAll = 0
if ($dedupedFindings.Count -gt 0) {
    $safeItems = @($dedupedFindings | Where-Object { $_.Risk -eq "safe" })
    $cautItems = @($dedupedFindings | Where-Object { $_.Risk -eq "cautious" -or $_.Risk -eq "dangerous" })
    $forbItems = @($dedupedFindings | Where-Object { $_.Risk -eq "forbidden" })
    if ($safeItems.Count -gt 0) { $totalCleanable = [math]::Round((($safeItems | Measure-Object Bytes -Sum).Sum / 1MB), 2) }
    if ($cautItems.Count -gt 0) { $totalCautious = [math]::Round((($cautItems | Measure-Object Bytes -Sum).Sum / 1MB), 2) }
    if ($forbItems.Count -gt 0) { $totalForbidden = [math]::Round((($forbItems | Measure-Object Bytes -Sum).Sum / 1MB), 2) }
    $totalAll = [math]::Round((($dedupedFindings | Measure-Object Bytes -Sum).Sum / 1MB), 2)
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
    Write-Host "  Deduplicated paths: $($dedupedFindings.Count) from $($results.Count) findings" -ForegroundColor DarkGray
    $byCategory = $dedupedFindings | Group-Object { $_.Category } | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending
    Write-Host "  By category:" -ForegroundColor White
    foreach ($grp in $byCategory) {
        $catSize = [math]::Round((($grp.Group | Measure-Object Bytes -Sum).Sum / 1MB), 2)
        $catGB = [math]::Round($catSize / 1024, 2)
        Write-Host "    $($grp.Name): $catGB GB" -ForegroundColor DarkGray
    }
}
if ($Global:CDriveInventory -and $Global:CDriveInventory.Count -gt 0) {
    Write-Host "  Inventory only:     $($Global:CDriveInventory.Count) space clues (not added to cleanup totals)" -ForegroundColor DarkCyan
}
if ($Global:CDriveScanTelemetry.Count -gt 0) {
    Write-Host "  Slowest scanner stages:" -ForegroundColor White
    foreach ($stage in @($Global:CDriveScanTelemetry | Sort-Object Seconds -Descending | Select-Object -First 5)) {
        Write-Host ("    {0,-3} {1,7:N1}s  {2}" -f $stage.Category, $stage.Seconds, $stage.Status) -ForegroundColor DarkGray
    }
    Write-Host ("  Measurement cache: {0} hits / {1} misses" -f $Global:CDriveMeasurementCacheHits, $Global:CDriveMeasurementCacheMisses) -ForegroundColor DarkGray
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportId = "CS-${timestamp}-$($healthScore)"
$cb = [char]96 + [char]96 + [char]96

$catNamesCN = @{
    "AF"="AI软件总足迹";
    "A"="系统隐藏"; "B"="临时缓存"; "C"="开发缓存"; "D"="浏览器";
    "E"="应用数据"; "F"="大文件"; "G"="特殊占用"; "H"="安全软件";
    "I"="多版本"; "J"="重复运行时"; "K"="输入法"; "L"="即时通讯";
    "VM"="虚拟内存"; "SI"="Search索引"; "O"="定向优化"; "GR"="增长追踪";
    "U"="不常用软件候选"; "MX"="C盘零碎信息"; "WU"="Windows更新残留";
    "AD"="管理员深度核算"; "SA"="NTFS实际占用"
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

function ConvertTo-MarkdownCell {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $flat = ($Text -replace '\|', '\|') -replace "(\r?\n)+", " "
    return $flat.Trim()
}

function ConvertTo-ChineseNumber {
    param([int]$Number)
    $digits = @('零','一','二','三','四','五','六','七','八','九','十')
    if ($Number -ge 0 -and $Number -le 10) { return $digits[$Number] }
    if ($Number -lt 20) { return ("十" + $digits[$Number - 10]) }
    return [string]$Number
}

function Format-CleanSightSize {
    param([double]$Megabytes)
    if ($Megabytes -ge 1024) { return ("{0:N2} GB" -f ($Megabytes / 1024)) }
    return ("{0:N1} MB" -f $Megabytes)
}

function BuildReport {
    $reportsDir = Initialize-CleanSightArtifactDirectory (Get-CleanSightArtifactPath "reports")
    $mdPath = Join-Path $reportsDir "CleanSight-${reportId}.md"
    $artifactRoot = Get-CleanSightArtifactRoot

    $categoryNames = @{
        AF = "AI软件生命周期"; A = "系统隐藏大文件"; B = "临时文件与缓存"; C = "开发工具缓存"
        D = "浏览器缓存"; E = "应用数据与日志"; MS = "厂商托管存储"; F = "大文件TOP"; G = "特殊占用源"
        H = "安全软件"; I = "多版本共存"; J = "Electron/CEF运行时"; K = "输入法数据"; L = "即时通讯数据"
        VM = "虚拟内存"; SI = "搜索索引"; O = "定向优化"; GR = "增长追踪"; U = "不常用软件候选"
        MX = "C盘零碎信息"; WU = "Windows更新残留"; AD = "管理员深度核算"; SA = "NTFS实际占用"
    }

    # Dedup rows keep only measurement fields, so rebuild Name+Category -> Advice/Note.
    $adviceMap = @{}
    foreach ($finding in @($results)) {
        $key = ("{0}|{1}" -f [string]$finding.Category, [string]$finding.Name).ToLowerInvariant()
        if (-not $adviceMap.ContainsKey($key)) {
            $adviceMap[$key] = [pscustomobject]@{
                Advice = [string]$finding.Advice
                Note = [string]$finding.Note
            }
        }
    }

    $safeRows = @($dedupedFindings | Where-Object { $_.Risk -eq "safe" } | Sort-Object Bytes -Descending)
    $cautRows = @($dedupedFindings | Where-Object { $_.Risk -eq "cautious" -or $_.Risk -eq "dangerous" } | Sort-Object Bytes -Descending)
    $forbRows = @($dedupedFindings | Where-Object { $_.Risk -eq "forbidden" } | Sort-Object Bytes -Descending)

    $lines = @()
    $lines += "# CleanSight AI 磁盘健康报告"
    $lines += ""
    $lines += "> **报告编号**: $reportId | **生成时间**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | **引擎**: $BRAND v$VERSION"
    $lines += "> **本报告为只读分析，未修改任何文件。所有操作需用户确认后执行。**"
    $lines += "---"
    $sectionNo = 1
    $lines += "# $(ConvertTo-ChineseNumber $sectionNo)、执行摘要"
    if ($space) {
        $usageLevelCN = if ($space.UsedPercent -gt 90) { "🔴 危急" } elseif ($space.UsedPercent -gt 80) { "⚠️ 偏高" } else { "✅ 正常" }
        $freeLevelCN = if ($space.FreeGB -lt 15) { "🔴 不足" } elseif ($space.FreeGB -lt 30) { "⚠️ 偏低" } else { "✅ 充足" }
        $lines += "| 指标 | 数值 |"
        $lines += "|------|------|"
        $lines += "| 健康评分 | $healthScore/100（$(if ($healthScore -ge 80) { "✅ 良好" } elseif ($healthScore -ge 60) { "⚠️ 一般" } else { "🔴 偏低" })） |"
        $lines += "| 总容量 | $($space.TotalGB) GB |"
        $lines += "| 已用空间 | $($space.UsedGB) GB（$($space.UsedPercent)%，$usageLevelCN） |"
        $lines += "| 可用空间 | $($space.FreeGB) GB（$freeLevelCN） |"
        $lines += "| ✅ 可安全释放 | $(Format-CleanSightSize $totalCleanable) |"
        $lines += "| ⚠️ 需确认后释放 | $(Format-CleanSightSize $totalCautious) |"
        $lines += "| 🔴 禁止删除 | $(Format-CleanSightSize $totalForbidden) |"
        $lines += "| 扫描合计 | $(Format-CleanSightSize $totalAll) |"
    }
    $lines += ""
    $lines += "> 产物目录: $artifactRoot"
    $lines += ""

    # ---- Tier 分级建议 -----------------------------------------------------
    $sectionNo++
    $lines += "# $(ConvertTo-ChineseNumber $sectionNo)、清理建议（Tier 分级）"
    $lines += ""
    $tiers = @(
        @{ Title = "Tier 1 · 可安全清理 ✅"; Rows = $safeRows; Total = $totalCleanable
           Hint = "纯缓存/临时数据，删除后应用会自动重建；执行前请关闭对应程序。" }
        @{ Title = "Tier 2 · 需确认后清理 ⚠️"; Rows = $cautRows; Total = $totalCautious
           Hint = "需人工确认的低风险项（旧版本、包缓存等），删除后可能重新下载或需要重装。" }
        @{ Title = "Tier 3 · 禁止删除 🔴"; Rows = $forbRows; Total = $totalForbidden
           Hint = "用户数据或系统关键数据，仅作记录，不要删除。" }
    )
    foreach ($tier in $tiers) {
        if ($tier.Rows.Count -eq 0) { continue }
        $lines += "## $($tier.Title) — $(Format-CleanSightSize $tier.Total)"
        $lines += ""
        $lines += "> $($tier.Hint)"
        $lines += ""
        $lines += "| 项目 | 类别 | 大小 | 路径 | 建议 |"
        $lines += "|------|------|-----:|------|------|"
        # 同一项目可能命中多个文件（如 thumbcache_*.db），按项目聚合后再展示。
        $aggregated = @($tier.Rows | Group-Object { ("{0}|{1}" -f [string]$_.Category, [string]$_.Name).ToLowerInvariant() } | ForEach-Object {
            $largest = $_.Group | Sort-Object Bytes -Descending | Select-Object -First 1
            [pscustomobject]@{
                Name = [string]$largest.Name
                Category = [string]$largest.Category
                Bytes = (($_.Group | Measure-Object Bytes -Sum).Sum)
                Path = [string]$largest.Path
                PathCount = $_.Count
            }
        } | Sort-Object Bytes -Descending)
        foreach ($row in @($aggregated | Select-Object -First 60)) {
            $code = [string]$row.Category
            $catName = if ($categoryNames.ContainsKey($code)) { $categoryNames[$code] } else { $code }
            $key = ("{0}|{1}" -f $code, [string]$row.Name).ToLowerInvariant()
            $advice = ""
            if ($adviceMap.ContainsKey($key)) { $advice = $adviceMap[$key].Advice }
            $pathText = [string]$row.Path
            if ($row.PathCount -gt 1) { $pathText = "$pathText（共 $($row.PathCount) 个路径）" }
            $lines += "| $(ConvertTo-MarkdownCell $row.Name) | $code · $(ConvertTo-MarkdownCell $catName) | $(Format-CleanSightSize ($row.Bytes / 1MB)) | $(ConvertTo-MarkdownCell $pathText) | $(ConvertTo-MarkdownCell $advice) |"
        }
        if ($aggregated.Count -gt 60) {
            $lines += "| … | | | 其余 $($aggregated.Count - 60) 项见同目录 JSON 报告 | |"
        }
        $lines += ""
    }

    # ---- 类别汇总 ----------------------------------------------------------
    if ($dedupedFindings.Count -gt 0) {
        $sectionNo++
        $lines += "# $(ConvertTo-ChineseNumber $sectionNo)、扫描明细（按类别）"
        $lines += ""
        $lines += "| 类别 | 条目 | 合计 | 其中可安全清理 |"
        $lines += "|------|-----:|-----:|---------------:|"
        $groups = $dedupedFindings | Group-Object { $_.Category } | Sort-Object { ($_.Group | Measure-Object Bytes -Sum).Sum } -Descending
        foreach ($grp in $groups) {
            $code = [string]$grp.Name
            $catName = if ($categoryNames.ContainsKey($code)) { $categoryNames[$code] } else { $code }
            $sumMB = (($grp.Group | Measure-Object Bytes -Sum).Sum / 1MB)
            $safeMB = 0
            $safeGroup = @($grp.Group | Where-Object { $_.Risk -eq "safe" })
            if ($safeGroup.Count -gt 0) { $safeMB = (($safeGroup | Measure-Object Bytes -Sum).Sum / 1MB) }
            $lines += "| $code · $(ConvertTo-MarkdownCell $catName) | $($grp.Count) | $(Format-CleanSightSize $sumMB) | $(Format-CleanSightSize $safeMB) |"
        }
        $lines += ""
    }

    if ($Global:CDriveInventory -and $Global:CDriveInventory.Count -gt 0) {
        $lines += ""
        $sectionNo++
        $lines += "# $(ConvertTo-ChineseNumber $sectionNo)、C盘零碎空间信息（解释层，不可与清理额度相加）"
        $lines += ""
        $lines += "> 下面是空间解释信息，不是可直接删除额度；目录之间可能与其他扫描类别重叠。"
        $lines += ""
        $lines += "| 类型 | 项目 | 大小 | 路径 | 证据 |"
        $lines += "|------|------|------:|------|------|"
        foreach ($item in @($Global:CDriveInventory | Sort-Object SizeMB -Descending | Select-Object -First 30)) {
            $size = if ($item.SizeMB -ge 1024) { "$([math]::Round($item.SizeMB/1024,2)) GB" } else { "$($item.SizeMB) MB" }
            $lines += "| $($item.Kind) | $($item.Name) | $size | $($item.Path) | $($item.Evidence) |"
        }
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
        $sectionNo++
        $lines += "# $(ConvertTo-ChineseNumber $sectionNo)、虚拟内存评估"
        $lines += ""
        $lines += "## 当前状态"
        $lines += ""
        $lines += "| 指标 | 数值 | 状态 |"
        $lines += "|------|------|------|"
        $vmStatus = if ($vm.FreePercent -lt 30) { '🔴 不足' } else { '✅ 充足' }
        $lines += "| C盘可用空间 | $($vm.FreePercent)% | $vmStatus |"
        if ($vm.OnC) {
            $lines += "| 页面文件位置 | C盘 | $(if ($vm.Assessment -ne 'normal') { '⚠️ 可优化' } else { '✅ 良好' }) |"
            $lines += "| 页面文件大小 | $vmSizeGB GB | - |"
        } else {
            $lines += "| 页面文件位置 | 非系统分区（C 盘无页面文件） | ✅ 良好 |"
            $lines += "| 页面文件大小 | C 盘 0 GB | - |"
        }
        $lines += "| 评估结果 | $assessmentCN |"
        $lines += ""

        if ($vm.Pagefiles -and $vm.Pagefiles.Count -gt 0) {
            $lines += "## 已配置的页面文件"
            $lines += ""
            $lines += "| 路径 | 配置 | 实际占用 |"
            $lines += "|------|------|----------|"
            foreach ($pf in @($vm.Pagefiles)) {
                $sizeText = if ($pf.SystemManaged) { "系统托管" } else { "$($pf.InitialMB)-$($pf.MaximumMB) MB" }
                $actualText = if ($pf.ActualReadable) { "$([math]::Round($pf.ActualBytes/1GB,2)) GB" } else { "不可读（权限）" }
                $lines += "| $(ConvertTo-MarkdownCell $pf.Path) | $sizeText | $actualText |"
            }
            $lines += ""
        }
        
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
            $lines += "| 驱动器 | 可用空间 | 介质 | 说明 |"
            $lines += "|--------|---------:|------|------|"
            foreach ($drive in @($vm.SuitableDrives)) {
                $lines += "| $($drive.Drive): | $($drive.FreeGB) GB | $(ConvertTo-MarkdownCell $drive.MediaType) | $(ConvertTo-MarkdownCell $drive.Recommendation) |"
            }
            $lines += ""
        }
        
        if ($vm.Assessment -ne "normal") {
            if (-not $vm.OnC) {
                $lines += "## 说明"
                $lines += ""
                $lines += "本次未检测到 C 盘页面文件配置，C 盘空间与本项无关。**不要为了释放 C 盘空间而新建 C 盘页面文件**。"
                $lines += "如需调整，请先确认崩溃转储需求，在「系统属性 → 高级 → 性能 → 高级 → 虚拟内存」中查看当前布局；改完重启并复扫验证。"
                $lines += ""
            } elseif ($vm.SuitableDrives -and $vm.SuitableDrives.Count -gt 0) {
                $lines += "## 实施步骤（需你手动确认，脚本不会自动执行）"
                $lines += ""
                $lines += "1. 按 **Win+R**，输入 **sysdm.cpl**，回车打开系统属性"
                $lines += "2. 切换到「**高级**」选项卡，点击「**性能**」区域的「**设置**」"
                $lines += "3. 切换到「**高级**」选项卡，点击「**虚拟内存**」区域的「**更改**」"
                $lines += "4. 取消勾选「**自动管理所有驱动器的分页文件大小**」"
                $lines += "5. 先在候选非 C 盘设置页面文件，再处理 C 盘现有页面文件"
            
                $primaryDrive = $vm.SuitableDrives | Where-Object { $_.EnoughHeadroomForCurrentMax } | Select-Object -First 1
                if (-not $primaryDrive) { $primaryDrive = $vm.SuitableDrives | Select-Object -First 1 }
                if ($primaryDrive) {
                    $lines += "6. 在 **$($primaryDrive.Drive):** 盘（可用 $($primaryDrive.FreeGB) GB）设置页面文件"
                }
                $lines += "7. 仅在已确认不需要完整崩溃转储时，才考虑缩小或移除 C 盘页面文件；否则保留"
                $lines += "8. 连续点击「**确定**」，**重启计算机**使更改生效，并复扫验证"
                $lines += ""
                $lines += "> ⚠️ **注意:** 不要直接删除或移动 pagefile.sys；未确认崩溃转储需求前，保留 C 盘页面文件。"
            } else {
                $lines += "## 说明"
                $lines += ""
                $lines += "当前没有满足空间余量的非 C 候选盘，不建议迁移页面文件；请先释放 C 盘空间或清理其他盘后再评估。"
                $lines += ""
            }
        }
    }
    
    $sectionNo++
    $lines += "# $(ConvertTo-ChineseNumber $sectionNo)、下一步与产物位置"
    $lines += ""
    $lines += "1. 预览（不删除任何文件）："
    $lines += "   - .\cleaners\clean-safe.ps1 -WhatIf"
    $lines += "   - .\cleaners\clean-apps.ps1 -WhatIf -RiskLevel safe"
    $lines += "   - .\cleaners\clean-targeted-optimization.ps1 -WhatIf"
    $lines += "2. 确认无误后再追加 -ReallyDelete 执行（永久删除，不经过回收站）。"
    $lines += "3. 执行后复扫，并用 track-regeneration.ps1 -Mode check -SessionId <id> 检查 5 分钟 / 1 小时 / 24 小时的再生情况。"
    $lines += ""
    $lines += "| 产物 | 位置 |"
    $lines += "|------|------|"
    $lines += "| 报告目录 | $artifactRoot\reports |"
    $lines += "| 增长基线 | $artifactRoot\reports\growth\latest.json |"
    $lines += "| AI 足迹基线 | $artifactRoot\reports\ai-footprints\latest.json |"
    $lines += "| 清理会话 | $artifactRoot\reports\cleanup-sessions |"
    $lines += ""
    $lines += "> 产物默认写入 $artifactRoot；可用 -OutputRoot 参数或 CLEANSIGHT_OUTPUT_DIR 环境变量覆盖。"
    $lines += ""

    $lines | Out-File $mdPath -Encoding UTF8
    Write-Host "  Report generated: $mdPath" -ForegroundColor Green
}

if ($OutputFormat -eq "markdown") { BuildReport }

if ($OutputFormat -eq "json") {
    $reportsDir = Initialize-CleanSightArtifactDirectory (Get-CleanSightArtifactPath "reports")
    $jsonPath = Join-Path $reportsDir "CleanSight-${reportId}.json"
    $output = @{
        report_id = $reportId
        version = $VERSION
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        scan_duration = $scanDuration
        drive = $space
        totals = @{ safe_mb = $totalCleanable; cautious_mb = $totalCautious; forbidden_mb = $totalForbidden; scanned_mb = $totalAll }
        findings = @($results)
        deduplicated_findings = @($dedupedFindings)
        inventory = @($Global:CDriveInventory)
        telemetry = @($Global:CDriveScanTelemetry)
        scanner_metadata = $Global:CDriveScannerMetadata
        measurement_cache = @{ hits=$Global:CDriveMeasurementCacheHits; misses=$Global:CDriveMeasurementCacheMisses }
    }
    $output | ConvertTo-Json -Depth 8 | Out-File $jsonPath -Encoding UTF8
    Write-Host "  JSON report generated: $jsonPath" -ForegroundColor Green
}

Write-Host ""
