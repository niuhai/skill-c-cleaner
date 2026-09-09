# scan-discover.ps1 - 未知应用发现 & 扩展建议生成 (v4.0 新增)
# 扫描 C 盘寻找签名数据库中未覆盖的大文件夹和应用，自动生成 user-custom.json 扩展建议
# 只读模式，不修改任何文件

param(
    [int]$MinSizeMB = 100,
    [int]$MaxResults = 30
)

$SkillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $SkillRoot "_common.ps1")
$SignaturesFile = Join-Path $SkillRoot "extensions\app-signatures.json"
$CustomFile = Join-Path $SkillRoot "extensions\user-custom.json"
$SuggestionsFile = Join-Path (Initialize-CleanSightArtifactDirectory (Get-CleanSightArtifactPath "discovery")) "discovery-suggestions.txt"

$UserProfile = $env:USERPROFILE
$LocalAppData = $env:LOCALAPPDATA
$AppData = $env:APPDATA
$ProgramData = $env:ProgramData
$ProgramFiles = $env:ProgramFiles
$ProgramFiles86 = ${env:ProgramFiles(x86)}

Write-Host "===== 未知应用发现引擎 =====" -ForegroundColor Cyan
Write-Host "扫描 C 盘中签名数据库未覆盖的大文件夹..." -ForegroundColor Yellow
Write-Host ""

# 加载已有签名 (所有已知路径)
Write-Host "正在加载已知应用签名..." -ForegroundColor DarkGray
$knownPaths = [System.Collections.ArrayList]::new()
try {
    $signatures = Get-Content $SignaturesFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($category in $signatures.categories.PSObject.Properties) {
        foreach ($app in $category.Value.apps) {
            foreach ($dp in $app.detect_paths) {
                $expanded = $dp -replace '%USERPROFILE%', $UserProfile `
                    -replace '%LOCALAPPDATA%', $LocalAppData `
                    -replace '%APPDATA%', $AppData `
                    -replace '%PROGRAMDATA%', $ProgramData `
                    -replace '%PROGRAMFILES%', $ProgramFiles `
                    -replace '%PROGRAMFILES\(X86\)%', $ProgramFiles86
                [void]$knownPaths.Add($expanded)
            }
        }
    }
    # 加上用户自定义
    $custom = Get-Content $CustomFile -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($app in $custom.apps) {
        foreach ($dp in $app.detect_paths) {
            $expanded = $dp -replace '%USERPROFILE%', $UserProfile `
                -replace '%LOCALAPPDATA%', $LocalAppData `
                -replace '%APPDATA%', $AppData `
                -replace '%PROGRAMDATA%', $ProgramData `
                -replace '%PROGRAMFILES%', $ProgramFiles `
                -replace '%PROGRAMFILES\(X86\)%', $ProgramFiles86
            [void]$knownPaths.Add($expanded)
        }
    }
} catch {
    Write-Host "  签名加载失败，将进行裸扫" -ForegroundColor DarkGray
}

$knownNormalized = $knownPaths | ForEach-Object { ($_ -replace '/','\').TrimEnd('\').ToLower() }

# 扫描路径
$scanRoots = @(
    @{Path=$AppData; Label="Roaming"},
    @{Path=$LocalAppData; Label="Local"},
    @{Path=$ProgramData; Label="ProgramData"},
    @{Path="$UserProfile"; Label="UserProfile"; MaxDepth=1}
)

$discoveries = @()
$rogueHits = @()

Write-Host "正在扫描..." -ForegroundColor Cyan

foreach ($root in $scanRoots) {
    if (-not (Test-Path $root.Path)) { continue }
    $depth = if ($root.MaxDepth) { $root.MaxDepth } else { 2 }
    
    $candidates = Get-ChildItem $root.Path -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^(Microsoft|Windows|desktop\.ini|NTUSER|\.|ntuser)' }
    
    foreach ($cand in $candidates) {
        $candPath = $cand.FullName
        $candNorm = $candPath.TrimEnd('\').ToLower()
        
        # 排除已知签名
        $isKnown = $false
        foreach ($k in $knownNormalized) {
            if ($candNorm -eq $k -or $candNorm.StartsWith($k)) {
                $isKnown = $true
                break
            }
        }
        if ($isKnown) { continue }
        
        # 计算大小
        $items = Get-ChildItem $candPath -Recurse -Force -ErrorAction SilentlyContinue
        $size = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 2)
        
        if ($sizeMB -lt $MinSizeMB) { continue }
        
        $discoveries += [PSCustomObject]@{
            Path = $candPath
            Name = $cand.Name
            SizeMB = $sizeMB
            Parent = $root.Label
            ItemCount = @($items).Count
        }
    }
}

# 排序 + 去重
$discoveries = $discoveries | Sort-Object SizeMB -Descending | Select-Object -First $MaxResults

Write-Host ""
Write-Host "===== 发现 $($discoveries.Count) 个未知应用/文件夹 =====" -ForegroundColor Yellow

if ($discoveries.Count -eq 0) {
    Write-Host "✅ 未发现签名数据库之外的大文件夹" -ForegroundColor Green
    Write-Host "   所有大于 ${MinSizeMB}MB 的文件夹都已被已知签名覆盖" -ForegroundColor Green
    exit 0
}

# 生成建议
$suggestionsJson = @()
$rank = 0

foreach ($d in $discoveries) {
    $rank++
    $icon = if ($d.SizeMB -gt 1000) { "🔴" } elseif ($d.SizeMB -gt 500) { "🟡" } else { "🟢" }
    
    # 流氓软件关键词匹配
    $rogueKeywords = @("360", "2345", "kzip", "kuaizip", "haozip", "xiaoniao", "birdwallpaper",
                      "ludashi", "LuDaShi", "wifiMaster", "WiFiMaster", "PPS", "PPTV", "PPLive",
                      "flash_helper", "FlashCenter", "liebao", "sogouexplorer", "kankan",
                      "myDrivers", "DriverGenius", "DriveTheLife", "QQLive", "Thunder")
    
    $isRogue = $false
    $matchKeyword = ""
    foreach ($kw in $rogueKeywords) {
        if ($d.Name.ToLower() -match $kw.ToLower()) {
            $isRogue = $true
            $matchKeyword = $kw
            break
        }
    }
    
    if ($isRogue) {
        $icon = "⚠️"
        $rogueHits += $d
    }
    
    $suggestion = @{
        name = $d.Name
        detect_paths = @("%$($d.Parent)%\$($d.Name)")
        cleanable = $(if ($isRogue) { "cautious" } else { "unknown" })
        migratable = "unknown"
        note = "自动发现 - ${sizeMB}MB, $($d.ItemCount)项"
        auto_discovered = $true
        is_rogue_suspect = $isRogue
        discovered_size_mb = $d.SizeMB
    }
    
    $suggestionsJson += $suggestion
    
    Write-Host ("[{0,2}] {1} {2}" -f $rank, $icon, $d.Name) -ForegroundColor $(if ($isRogue) { "Red" } else { "Yellow" })
    Write-Host "     路径: $($d.Path)" -ForegroundColor DarkGray
    Write-Host "     大小: $($d.SizeMB) MB ($($d.ItemCount)项)" -ForegroundColor DarkGray
    if ($isRogue) {
        Write-Host "     ⚠️ 流氓软件嫌疑! 匹配关键词: $matchKeyword" -ForegroundColor Red
    }
}

# 输出建议
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  扩展建议" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# 保存自动发现结果
$suggestionsJson | ConvertTo-Json -Depth 3 | Out-File $SuggestionsFile -Encoding UTF8
Write-Host "发现结果已保存: $SuggestionsFile" -ForegroundColor Green
Write-Host ""
Write-Host "📌 如何处理这些发现:" -ForegroundColor Yellow
Write-Host "1. 如果确认是安全软件 → 手动添加到 extensions/user-custom.json" -ForegroundColor DarkGray
Write-Host "2. 如果是流氓软件 → 建议卸载 (用 BCUninstaller 或控制面板)" -ForegroundColor DarkGray
Write-Host "3. 如果是未知工具 → 右键查看文件夹内容后判断" -ForegroundColor DarkGray
Write-Host "4. 欢迎贡献 PR 到 app-signatures.json 帮助更多人" -ForegroundColor DarkGray

if ($rogueHits.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠️ 发现 $($rogueHits.Count) 个疑似流氓软件！" -ForegroundColor Red
    Write-Host "   建议用 BCUninstaller (开源) 或 Geek Uninstaller 彻底卸载" -ForegroundColor Red
    Write-Host "   下载: https://github.com/Klocman/Bulk-Crap-Uninstaller" -ForegroundColor DarkGray
}
Write-Host ""
