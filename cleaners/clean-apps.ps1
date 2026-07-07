# clean-apps.ps1 - 签名驱动应用缓存清理器
# 读取 app-signatures.json 中标记 cleanable 的应用，按 sub_cleanable 精确清理
# 用法: .\clean-apps.ps1 [-RiskLevel safe|cautious|all] [-WhatIf] [-Apps "Trae CN,飞书,微信"]
#        .\clean-apps.ps1 -MigrateFirst -TargetDrive D -RiskLevel safe   # 先迁移再删除
# 示例: .\clean-apps.ps1 -WhatIf                    # 预览所有可清理项
#        .\clean-apps.ps1 -RiskLevel safe              # 只清理安全项
#        .\clean-apps.ps1 -Apps "Trae CN,飞书"         # 只清理指定应用

param(
    [ValidateSet("safe", "cautious", "all")]
    [string]$RiskLevel = "safe",
    [switch]$WhatIf,
    [string]$Apps = "",
    [switch]$MigrateFirst,
    [string]$TargetDrive = ""
)

$skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if (-not (Test-Path (Join-Path $skillRoot "_common.ps1"))) { $skillRoot = "C:\.trae\skills\c-drive-cleaner" }
. (Join-Path $skillRoot "_common.ps1")

$LogFile = Join-Path (Get-SkillRoot) "cleanup_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

if ($WhatIf) {
    Write-Host "===== 应用缓存清理 - WhatIf 预览模式 =====" -ForegroundColor Cyan
    Write-Host "以下为预览，不会删除任何文件。去掉 -WhatIf 参数才真正执行。" -ForegroundColor Yellow
    Write-Host "建议以管理员身份运行以获得最佳效果。" -ForegroundColor DarkGray
} else {
    # 管理员权限检测
    if (-not (Test-Admin)) {
        Write-Host "===== 需要管理员权限 =====" -ForegroundColor Red
        Write-Host "应用缓存目录可能需要管理员权限才能清理。" -ForegroundColor Yellow
        Write-Host "请关闭此窗口，右键 PowerShell -> 以管理员身份运行，然后重试。" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "===== 应用缓存清理 - 执行模式 =====" -ForegroundColor Cyan
    Write-Host "日志: $LogFile" -ForegroundColor Yellow
    Write-Host "注意: 文件将被永久删除（不经过回收站），删除后无法恢复。" -ForegroundColor Red
}

if ($MigrateFirst) {
    if (-not $TargetDrive) {
        $TargetDrive = "D"
        Write-Host "未指定目标盘，默认迁移到 D 盘。用 -TargetDrive E 指定其他盘。" -ForegroundColor DarkGray
    }
    Write-Host "迁移优先模式: 先尝试迁移可迁移项到 $TargetDrive 盘，再删除不可迁移项。" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "风险级别: $RiskLevel | 指定应用: $(if($Apps){$Apps}else{'全部'})" -ForegroundColor White
if ($MigrateFirst) { Write-Host "迁移目标: $TargetDrive 盘 | 模式: 迁移→删除" -ForegroundColor White }
Write-Host ""

# ----- 辅助函数 -----

function Get-AppProcessNames {
    param([string]$AppName)
    $map = @{
        "Chrome"  = @("chrome")
        "Edge"    = @("msedge", "edge", "MicrosoftEdge")
        "Firefox"  = @("firefox")
        "WeChat"  = @("wechat", "WeChat")
        "微信"    = @("wechat", "WeChat")
        "飞书"    = @("larkshell", "feishu", "LarkShell")
        "钉钉"    = @("dingtalk", "DingTalk")
        "Trae CN" = @("trae", "traecn")
        "Trae"    = @("trae")
        "TRAE SOLO CN" = @("traesolo", "trae-solo")
        "Code"    = @("code", "vscode")
        "VS Code" = @("code", "vscode")
    }
    foreach ($key in $map.Keys) {
        if ($AppName -like "*$key*" -or $key -like "*$AppName*") {
            return $map[$key]
        }
    }
    return @()
}

function Test-AppRunning {
    param([string]$AppName, [string]$AppPath)
    $names = Get-AppProcessNames $AppName
    if ($names.Count -eq 0) { return $false }
    $running = Get-Process | Where-Object { $_.ProcessName -in $names } | Select-Object -First 1
    if ($running) {
        Write-Host "   ⚠️ $AppName 正在运行(PID:$($running.Id))，跳过清理" -ForegroundColor Yellow
        return $true
    }
    return $false
}

function Clean-Directory {
    param([string]$Path, [string]$Label, [bool]$Preview)
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) { return 0 }
    $r = Get-FolderSizeFast $Path
    if (-not $r.Found -or $r.Size -eq 0) { return 0 }
    $sizeMB = [math]::Round($r.Size / 1MB, 2)
    $sizeStr = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB/1024,2)) GB" } else { "$sizeMB MB" }
    Write-Host "   $Label : $sizeStr" -NoNewline -ForegroundColor DarkGray
    if (-not $Preview) {
        $ok = Remove-Directory -Path $Path -ShowProgress
        if ($ok) { return $r.Size }
        Write-Host "   跳过" -ForegroundColor Yellow
        return 0
    }
    Write-Host " (将清理)" -ForegroundColor Yellow
    return $r.Size
}

# ----- 主流程 -----

$totalFreed = 0L
$cleanedCount = 0
$skippedCount = 0
$totalItems = 0

$filterApps = if ($Apps) { $Apps -split "," | ForEach-Object { $_.Trim() } } else { @() }

$sigFile = Join-Path (Get-SkillRoot) "extensions\app-signatures.json"
$sigs = Get-Content $sigFile -Raw -Encoding UTF8 | ConvertFrom-Json

# 先统计总数用于进度显示
$allApps = @()
foreach ($catName in $sigs.categories.PSObject.Properties.Name) {
    $category = $sigs.categories.$catName
    if (-not $category.apps) { continue }
    foreach ($app in @($category.apps)) {
        if ($filterApps.Count -gt 0 -and $app.name -notin $filterApps) { continue }
        $risk = Convert-RiskLevel $app.cleanable
        if ($RiskLevel -eq "safe" -and $risk -ne "safe") { continue }
        if ($RiskLevel -eq "cautious" -and $risk -eq "forbidden") { continue }
        $result = Test-AppSignature $app
        if ($result.Found -and $result.Size -ge 1MB) {
            $allApps += @{ App = $app; Result = $result; Risk = $risk; Category = $catName }
        }
    }
}
$totalItems = $allApps.Count
$appIdx = 0

if (-not $WhatIf -and $totalItems -gt 0) {
    Write-Host "即将清理 $totalItems 项，预计释放可观空间"
    Write-Host "使用 cmd /c rmdir 高速删除，大目录通常在 30-60 秒完成" -ForegroundColor Yellow
    Write-Host ""
}

foreach ($item in $allApps) {
    $appIdx++
    $app = $item.App
    $result = $item.Result
    $risk = $item.Risk
    $catName = $item.Category

    $sizeMB = [math]::Round($result.Size / 1MB, 2)
    $sizeStr = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB/1024,2)) GB" } else { "$sizeMB MB" }
    $riskIcon = switch ($risk) { "safe" { "✅" } "cautious" { "⚠️" } "forbidden" { "🔴" } default { "⚠️" } }

    Write-Host ""
    Write-Host "[$appIdx/$totalItems] $riskIcon [$catName] $($app.name) — $sizeStr" -ForegroundColor $(switch ($risk) { "safe" { "Green" } "cautious" { "Yellow" } default { "Red" } })
    Write-Host "   路径: $($result.Path)" -ForegroundColor DarkGray

    # 进程检测：如果应用在运行，跳过
    if (-not $WhatIf -and (Test-AppRunning -AppName $app.name -AppPath $result.Path)) {
        $skippedCount++
        continue
    }

    $appFreed = 0L

    if ($app.sub_paths -and $app.sub_cleanable) {
        $subsToClean = @()
        if ($app.sub_cleanable -is [string]) {
            $subsToClean = ($app.sub_cleanable -split ",") | ForEach-Object { $_.Trim() }
            $availableSubs = @($app.sub_paths)
            foreach ($subName in $subsToClean) {
                $matched = $availableSubs | Where-Object { $_ -like "*$subName*" -or $subName -like "*$_*" }
                if ($matched) { $subsToClean += $matched }
            }
        } else {
            $subsToClean = @($app.sub_paths)
        }
        # 通过 sub_paths + 匹配到的 sub_cleanable 来清理
        $uniqueSubs = $subsToClean | Select-Object -Unique
        foreach ($sub in $uniqueSubs) {
            $fullPath = Join-Path $result.Path $sub
            $freed = Clean-Directory -Path $fullPath -Label $sub -Preview:$WhatIf
            $appFreed += $freed
        }
    } elseif ($app.cleanable -eq $true) {
        if (-not $WhatIf) {
            $ok = Remove-Directory -Path $result.Path -ShowProgress
            if ($ok) {
                $appFreed = $result.Size
            }
        } else {
            Write-Host "   (将清理整个目录)" -ForegroundColor Yellow
            $appFreed = $result.Size
        }
    } else {
        Write-Host "   ⏭️ 跳过 (需确认: $($app.cleanable))" -ForegroundColor DarkGray
        $skippedCount++
        continue
    }

    if ($appFreed -gt 0) {
        $totalFreed += $appFreed
        $cleanedCount++
    }
}

# 自定义签名
$customApps = Load-CustomSigs
$customIdx = 0
foreach ($app in @($customApps)) {
    if ($filterApps.Count -gt 0 -and $app.name -notin $filterApps) { continue }
    $risk = Convert-RiskLevel $app.cleanable
    if ($RiskLevel -eq "safe" -and $risk -ne "safe") { continue }

    $result = Test-AppSignature $app
    if (-not $result.Found -or $result.Size -lt 1MB) { continue }

    $customIdx++
    $sizeMB = [math]::Round($result.Size / 1MB, 2)
    Write-Host ""
    Write-Host "[自定义] $($app.name) — $([math]::Round($sizeMB/1024,2)) GB" -ForegroundColor Green
    Write-Host "   路径: $($result.Path)" -ForegroundColor DarkGray

    if (-not $WhatIf) {
        $ok = Remove-Directory -Path $result.Path -ShowProgress
        if ($ok) {
            $totalFreed += $result.Size
            $cleanedCount++
        }
    } else {
        Write-Host "   (将清理)" -ForegroundColor Yellow
        $totalFreed += $result.Size
    }
}

$totalMB = [math]::Round($totalFreed / 1MB, 2)
$totalGB = [math]::Round($totalFreed / 1GB, 2)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host "预计释放: $totalMB MB ($totalGB GB) | 清理项: $cleanedCount | 跳过: $skippedCount" -ForegroundColor Yellow
    Write-Host "确认无误后运行: .\clean-apps.ps1 -RiskLevel $RiskLevel" -ForegroundColor Yellow
} else {
    Write-Host "已释放: $totalMB MB ($totalGB GB) | 清理项: $cleanedCount" -ForegroundColor Green
    $space = Get-DriveSpace
    if ($space) {
        Write-Host "C盘当前: $($space.UsedGB) GB / $($space.TotalGB) GB (剩余 $($space.FreeGB) GB, $($space.UsedPercent)%)" -ForegroundColor Cyan
    }
}
Write-Host "========================================" -ForegroundColor Cyan
