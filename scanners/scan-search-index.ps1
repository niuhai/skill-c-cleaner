# scan-search-index.ps1 - SI class: Dynamic Search Index Optimization Scanner
# Scan-only, discovers development directories and index burdens dynamically
# Generates exclusion list based on actual project structure found on system

# 复用 _common.ps1 的 Get-SkillRoot 和 Get-FolderSizeFast（robocopy 方案，比 Get-ChildItem 快 10-100 倍）
# Get-FolderSizeMB 作为本地包装函数，调用 Get-FolderSizeFast 并转换为 MB
function Get-FolderSizeMB {
    param([string]$Path)
    $r = Get-FolderSizeFast $Path
    if (-not $r.Found -or $r.Size -eq 0) { return 0 }
    return [math]::Round($r.Size / 1MB, 2)
}

$SkillRoot = Get-SkillRoot
$SearchIndexFile = Join-Path $SkillRoot "reports\search-index-exclusions.json"

# Privacy: sanitize paths by replacing actual username with %USERPROFILE%
function Sanitize-Path([string]$p) {
    $userProfile = $env:USERPROFILE -replace '\\', '\\'
    return $p -replace $userProfile, '%USERPROFILE%'
}
function Sanitize-List($list) {
    return $list | ForEach-Object { Sanitize-Path $_ }
}

# Initialize scan results if not already done
if (-not $Global:CDriveScanResults) {
    $Global:CDriveScanResults = [System.Collections.ArrayList]::new()
}

Write-Host "===== [SI] Search Index Optimization Scan =====" -ForegroundColor Cyan
Write-Host "Dynamically discovering development directories and index burdens..." -ForegroundColor Yellow
Write-Host ""

# 1. Scan common development root directories (prioritize user's actual paths)
$userName = $env:USERNAME
$devRoots = @(
    "C:\Users\$userName\source\repos",
    "C:\Users\$userName\source",
    "C:\Users\$userName\Documents\GitHub",
    "C:\Users\$userName\Documents\Projects",
    "C:\Users\$userName\Desktop\Projects",
    "D:\GitHub",
    "D:\Projects",
    "D:\Code",
    "D:\source",
    "D:\dev",
    "D:\work",
    "D:\Workspace",
    "D:\src",
    "C:\Users\$env:USERNAME\source",
    "C:\Users\$env:USERNAME\Documents\GitHub",
    "C:\Users\$env:USERNAME\Documents\Projects",
    "C:\Users\$env:USERNAME\Desktop\Projects"
)

$foundProjects = @()
$foundRoots = @()

foreach ($root in $devRoots) {
    if (-not (Test-Path $root)) { continue }
    $foundRoots += $root
    
    $projects = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^(\.|desktop\.ini)' }
    
    foreach ($proj in $projects) {
        $foundProjects += [PSCustomObject]@{
            ProjectPath = $proj.FullName
            ProjectName = $proj.Name
            RootDir = $root
        }
    }
}

Write-Host "Found $($foundRoots.Count) development roots, $($foundProjects.Count) projects" -ForegroundColor White

# 2. Scan for index burden patterns in each project
$indexBurdens = @()
$totalWastedMB = 0

$patternsToScan = @(
    @{ Pattern = "node_modules"; Category = "node_modules (JS/TS)"; Risk = "safe" }
    @{ Pattern = ".git"; Category = ".git (version control)"; Risk = "safe" }
    @{ Pattern = "build"; Category = "build output"; Risk = "safe" }
    @{ Pattern = "dist"; Category = "dist output"; Risk = "safe" }
    @{ Pattern = "target"; Category = "target (Java/Kotlin)"; Risk = "safe" }
    @{ Pattern = ".gradle"; Category = ".gradle (caches)"; Risk = "safe" }
    @{ Pattern = "bin"; Category = "bin (binary)"; Risk = "cautious" }
    @{ Pattern = "obj"; Category = "obj (objects)"; Risk = "cautious" }
    @{ Pattern = "Debug"; Category = "Debug build"; Risk = "safe" }
    @{ Pattern = "Release"; Category = "Release build"; Risk = "safe" }
    @{ Pattern = "__pycache__"; Category = "__pycache__"; Risk = "safe" }
    @{ Pattern = "venv"; Category = "venv (Python)"; Risk = "safe" }
    @{ Pattern = ".venv"; Category = ".venv (Python)"; Risk = "safe" }
    @{ Pattern = "vendor"; Category = "vendor (deps)"; Risk = "safe" }
    @{ Pattern = "packages"; Category = "packages"; Risk = "cautious" }
    @{ Pattern = "Library"; Category = "Unity Library"; Risk = "safe" }
    @{ Pattern = ".next"; Category = ".next (Next.js)"; Risk = "safe" }
    @{ Pattern = "node_modules\.cache"; Category = "npm cache"; Risk = "safe" }
    @{ Pattern = ".vs"; Category = ".vs (VS config)"; Risk = "safe" }
    @{ Pattern = "TestResults"; Category = "TestResults"; Risk = "safe" }
)

$projectExclusions = @()
$languageSummary = @{}
$languageSummary["JavaScript/TypeScript"] = @{ count = 0; total_mb = 0 }
$languageSummary["Java/Kotlin"] = @{ count = 0; total_mb = 0 }
$languageSummary["Python"] = @{ count = 0; total_mb = 0 }
$languageSummary[".NET/C#"] = @{ count = 0; total_mb = 0 }
$languageSummary["Rust"] = @{ count = 0; total_mb = 0 }
$languageSummary["Go"] = @{ count = 0; total_mb = 0 }
$languageSummary["Unity/Unreal"] = @{ count = 0; total_mb = 0 }
$languageSummary["Flutter/Dart"] = @{ count = 0; total_mb = 0 }
$languageSummary["Git"] = @{ count = 0; total_mb = 0 }

# Language mapping
$langMap = @{
    "node_modules" = "JavaScript/TypeScript"
    ".next" = "JavaScript/TypeScript"
    "dist" = "JavaScript/TypeScript"
    "target" = "Java/Kotlin"
    ".gradle" = "Java/Kotlin"
    "build" = "Java/Kotlin"
    "__pycache__" = "Python"
    "venv" = "Python"
    ".venv" = "Python"
    "vendor" = "Go"
    "bin" = ".NET/C#"
    "obj" = ".NET/C#"
    "packages" = ".NET/C#"
    "Debug" = ".NET/C#"
    "Release" = ".NET/C#"
    "TestResults" = ".NET/C#"
    "Library" = "Unity/Unreal"
    "node_modules\.cache" = "JavaScript/TypeScript"
    ".vs" = ".NET/C#"
    ".git" = "Git"
}

foreach ($proj in $foundProjects) {
    $projPath = $proj.ProjectPath
    
    foreach ($pattern in $patternsToScan) {
        $matches = Get-ChildItem -Path $projPath -Filter $pattern.Pattern -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue
        
        foreach ($match in $matches) {
            $sizeMB = Get-FolderSizeMB -Path $match.FullName
            
            if ($sizeMB -gt 1.0) {
                $entry = [PSCustomObject]@{
                    Path = $match.FullName
                    Category = $pattern.Category
                    SizeMB = $sizeMB
                    Risk = $pattern.Risk
                    Project = $proj.ProjectName
                }
                $indexBurdens += $entry
                $totalWastedMB += $sizeMB
                
                # Track for exclusion list (dedup)
                if ($projectExclusions -notcontains $match.FullName) {
                    $projectExclusions += $match.FullName
                }
                
                # Track by language
                $lang = $langMap[$pattern.Pattern]
                if ($lang -and $languageSummary.ContainsKey($lang)) {
                    $languageSummary[$lang].count++
                    $languageSummary[$lang].total_mb += $sizeMB
                }
            }
        }
    }
}

# Check system package manager caches
$packageCachePaths = @(
    @{ Path = "$env:USERPROFILE\.nuget\packages"; Name = ".nuget\packages (NuGet)" }
    @{ Path = "$env:USERPROFILE\.gradle\caches"; Name = ".gradle\caches (Gradle)" }
    @{ Path = "$env:USERPROFILE\.m2\repository"; Name = ".m2\repository (Maven)" }
    @{ Path = "$env:USERPROFILE\.cargo\registry"; Name = ".cargo\registry (Rust)" }
    @{ Path = "$env:USERPROFILE\.npm"; Name = ".npm (Node.js)" }
    @{ Path = "$env:LOCALAPPDATA\npm-cache"; Name = "npm-cache (Node.js)" }
    @{ Path = "$env:LOCALAPPDATA\pip\cache"; Name = "pip cache (Python)" }
    @{ Path = "$env:USERPROFILE\.pub-cache"; Name = ".pub-cache (Dart/Flutter)" }
)

$systemExclusions = @()
foreach ($pkg in $packageCachePaths) {
    if (Test-Path $pkg.Path) {
        $sizeMB = Get-FolderSizeMB -Path $pkg.Path
        if ($sizeMB -gt 1.0) {
            $indexBurdens += [PSCustomObject]@{
                Path = $pkg.Path
                Category = $pkg.Name
                SizeMB = $sizeMB
                Risk = "safe"
                Project = "System Cache"
            }
            $totalWastedMB += $sizeMB
            $systemExclusions += $pkg.Path
        }
    }
}

# Sort by size
$indexBurdens = $indexBurdens | Sort-Object SizeMB -Descending
$totalWastedGB = [math]::Round($totalWastedMB / 1024, 2)

# Output results
Write-Host ""
Write-Host "===== Index Burden Analysis =====" -ForegroundColor Cyan

if ($indexBurdens.Count -eq 0) {
    Write-Host "No significant index burdens found" -ForegroundColor Green
} else {
    Write-Host "Found $($indexBurdens.Count) indexable directories, total $totalWastedGB GB" -ForegroundColor Yellow
    Write-Host ""
    
    # By language summary
    Write-Host "--- By Technology Stack ---" -ForegroundColor White
    $sortedLangs = $languageSummary.Keys | Sort-Object { $languageSummary[$_].total_mb } -Descending
    foreach ($lang in $sortedLangs) {
        $info = $languageSummary[$lang]
        if ($info.total_mb -gt 0) {
            $gb = [math]::Round($info.total_mb / 1024, 2)
            $color = if ($info.total_mb -gt 1024) { "Red" } elseif ($info.total_mb -gt 512) { "Yellow" } else { "Green" }
            Write-Host ("  {0,-25} : {1,8} GB ({2,4} dirs)" -f $lang, $gb, $info.count) -ForegroundColor $color
        }
    }
    
    Write-Host ""
    Write-Host "--- Top 10 Projects by Index Burden ---" -ForegroundColor White
    $projectSummary = $indexBurdens | Where-Object { $_.Project -ne "System Cache" } | Group-Object Project |
        Sort-Object { ($_.Group | Measure-Object SizeMB -Sum).Sum } -Descending | Select-Object -First 10
    foreach ($proj in $projectSummary) {
        $totalMB = ($proj.Group | Measure-Object SizeMB -Sum).Sum
        $gb = [math]::Round($totalMB / 1024, 2)
        Write-Host ("  {0,-30} : {1,8} GB ({2,3} dirs)" -f $proj.Name, $gb, $proj.Count) -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "--- Top 20 Largest Index Burdens ---" -ForegroundColor White
    $top20 = $indexBurdens | Select-Object -First 20
    $rank = 0
    foreach ($item in $top20) {
        $rank++
        $gb = [math]::Round($item.SizeMB / 1024, 2)
        $dirName = Split-Path $item.Path -Leaf
        Write-Host ("  [{0,2}] {1,-15} {2,8} GB  ({3})" -f $rank, $dirName, $gb, $item.Project) -ForegroundColor DarkGray
    }
    
    # Add to scan results
    $reportItem = [PSCustomObject]@{
        Category = "SI"
        Item = "Search index burden"
        SizeMB = [math]::Round($totalWastedMB, 2)
        Risk = "safe"
        Detail = "$($indexBurdens.Count) dirs, $totalWastedGB GB total - Exclude from Windows Search indexing"
    }
    [void]$Global:CDriveScanResults.Add($reportItem)
    
    # Generate dynamic exclusion lists
    Write-Host ""
    Write-Host "=== Dynamically Generated Search Index Exclusion List ===" -ForegroundColor Cyan
    
    # 1. Project-level exclusions
    Write-Host ""
    Write-Host "[Project-Level Exclusions] $($projectExclusions.Count) entries" -ForegroundColor Yellow
    foreach ($exc in ($projectExclusions | Sort-Object)) {
        Write-Host "  $exc" -ForegroundColor DarkGray
    }
    
    # 2. Wildcard exclusions (catch patterns not yet discovered)
    $wildcardExclusions = @()
    if ($foundProjects.Count -gt 0) {
        # Use the first found root to determine wildcard patterns
        $firstRoot = $foundRoots | Select-Object -First 1
        $wildcardExclusions = @(
            "$firstRoot\*\node_modules",
            "$firstRoot\*\build",
            "$firstRoot\*\dist",
            "$firstRoot\*\target",
            "$firstRoot\*\.git",
            "$firstRoot\*\.gradle",
            "$firstRoot\*\bin",
            "$firstRoot\*\obj",
            "$firstRoot\*\__pycache__",
            "$firstRoot\*\venv",
            "$firstRoot\*\.venv",
            "$firstRoot\*\vendor",
            "$firstRoot\*\packages",
            "$firstRoot\*\Debug",
            "$firstRoot\*\Release",
            "$firstRoot\*\TestResults",
            "$firstRoot\*\Library",
            "$firstRoot\*\.next"
        )
    }
    Write-Host ""
    Write-Host "[Wildcard Exclusions] $($wildcardExclusions.Count) entries (based on root: $($foundRoots[0]))" -ForegroundColor Yellow
    foreach ($exc in $wildcardExclusions) {
        Write-Host "  $exc" -ForegroundColor DarkGray
    }
    
    # 3. System-level exclusions
    Write-Host ""
    Write-Host "[System-Level Exclusions] $($systemExclusions.Count) entries" -ForegroundColor Yellow
    foreach ($exc in $systemExclusions) {
        Write-Host "  $exc" -ForegroundColor DarkGray
    }
    
    # 4. IDE/TRAE cache exclusions
    $ideCachePaths = @(
        "$env:APPDATA\Trae\Cache",
        "$env:APPDATA\Trae\CachedData",
        "$env:APPDATA\Trae\GPUCache",
        "$env:APPDATA\Trae\logs",
        "$env:APPDATA\Trae\Code Cache",
        "$env:APPDATA\Code\Cache",
        "$env:APPDATA\Code\CachedData",
        "$env:APPDATA\Code\GPUCache"
    )
    $ideExclusions = @()
    foreach ($path in $ideCachePaths) {
        if (Test-Path $path) {
            $ideExclusions += $path
        }
    }
    if ($ideExclusions.Count -gt 0) {
        Write-Host ""
        Write-Host "[IDE/TRAE Cache Exclusions] $($ideExclusions.Count) entries" -ForegroundColor Yellow
        foreach ($exc in $ideExclusions) {
            Write-Host "  $exc" -ForegroundColor DarkGray
        }
    }
    
    # Summary
    $totalExclusions = $projectExclusions.Count + $wildcardExclusions.Count + $systemExclusions.Count + $ideExclusions.Count
    Write-Host ""
    Write-Host "===== Exclusion Summary =====" -ForegroundColor Green
    Write-Host "Project-Level  : $($projectExclusions.Count) entries (precise matches to your projects)" -ForegroundColor White
    Write-Host "Wildcard       : $($wildcardExclusions.Count) entries (pattern-based, covers future projects)" -ForegroundColor White
    Write-Host "System Cache   : $($systemExclusions.Count) entries (package manager caches)" -ForegroundColor White
    Write-Host "IDE Cache      : $($ideExclusions.Count) entries (TRAE/Code caches)" -ForegroundColor White
    Write-Host "TOTAL          : $totalExclusions entries" -ForegroundColor Green
    Write-Host "Estimated freed CPU: ~$($indexBurdens.Count * 10) seconds per indexing cycle" -ForegroundColor Yellow
    
    # Save to JSON
    $searchIndexData = @{
        scan_time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        summary = @{
            total_index_burdens = $indexBurdens.Count
            total_wasted_gb = $totalWastedGB
            projects_scanned = $foundProjects.Count
            dev_roots_found = $foundRoots.Count
            total_exclusions_generated = $totalExclusions
        }
        language_summary = @{}
        exclusions = @{
            project_level = Sanitize-List ($projectExclusions | Sort-Object)
            wildcard = Sanitize-List $wildcardExclusions
            system_cache = Sanitize-List $systemExclusions
            ide_cache = Sanitize-List $ideExclusions
            total_count = $totalExclusions
        }
        top_burdens = $top20 | ForEach-Object {
            @{
                path = Sanitize-Path $_.Path
                category = $_.Category
                size_gb = [math]::Round($_.SizeMB / 1024, 2)
                project = $_.Project
            }
        }
    }
    
    # Also populate language_summary properly
    foreach ($lang in $sortedLangs) {
        $info = $languageSummary[$lang]
        if ($info.total_mb -gt 0) {
            $searchIndexData.language_summary[$lang] = @{
                dir_count = $info.count
                total_gb = [math]::Round($info.total_mb / 1024, 2)
            }
        }
    }
    
    # Ensure reports dir exists
    $reportsDir = Join-Path $SkillRoot "reports"
    if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
    
    $searchIndexData | ConvertTo-Json -Depth 5 | Out-File $SearchIndexFile -Encoding UTF8
    Write-Host ""
    Write-Host "Dynamic exclusion list saved to: $SearchIndexFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "1. Open Windows Search settings > Add these paths to exclusions" -ForegroundColor Yellow
    Write-Host "2. Use the project-level entries for maximum precision" -ForegroundColor Yellow
    Write-Host "3. Use the wildcard entries to catch future projects automatically" -ForegroundColor Yellow
}

Write-Host ""
