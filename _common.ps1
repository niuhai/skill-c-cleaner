# _common.ps1 - c-drive-cleaner shared functions
# Dot-source: . (Join-Path (Split-Path -Parent $PSCommandPath) "_common.ps1")
# Or from scanners: . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1")

if (-not $Global:CDriveScanResults) {
    $Global:CDriveScanResults = [System.Collections.ArrayList]::new()
}

function Get-SkillRoot {
    if ($PSCommandPath) {
        $dir = Split-Path -Parent $PSCommandPath
        if (Test-Path (Join-Path $dir "_common.ps1")) { return $dir }
        $parent = Split-Path -Parent $dir
        if (Test-Path (Join-Path $parent "_common.ps1")) { return $parent }
    }
    return "C:\.trae\skills\c-drive-cleaner"
}

function Get-FolderSizeFast {
    param([string]$Path)
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) { return @{ Size = 0; Count = 0; Found = $false } }
    try {
        $dummy = "C:\__ROBOSIZE_$(Get-Random)__"
        $output = & robocopy $Path $dummy /L /S /NFL /NDL /NJH /BYTES 2>&1
        $bytesLine = $output | Where-Object { $_ -match '^\s*Bytes' } | Select-Object -Last 1
        if ($bytesLine) {
            $nums = [regex]::Matches($bytesLine, '\d+') | ForEach-Object { $_.Value }
            if ($nums.Count -ge 1) {
                return @{ Size = [long]$nums[0]; Count = 0; Found = $true }
            }
        }
    } catch {}
    $files = Get-ChildItem $Path -Recurse -Force -File -ErrorAction SilentlyContinue
    $size = ($files | Measure-Object Length -Sum).Sum
    return @{ Size = if ($size) { [long]$size } else { 0 }; Count = @($files).Count; Found = $true }
}

function Expand-EnvPath {
    param([string]$Path)
    return $Path -replace '%USERPROFILE%', $env:USERPROFILE `
        -replace '%LOCALAPPDATA%', $env:LOCALAPPDATA `
        -replace '%APPDATA%', $env:APPDATA `
        -replace '%PROGRAMFILES\(X86\)%', ${env:ProgramFiles(x86)} `
        -replace '%PROGRAMFILES%', $env:ProgramFiles `
        -replace '%PROGRAMDATA%', $env:ProgramData `
        -replace '%DOCUMENTS%', ([Environment]::GetFolderPath("MyDocuments"))
}

function Load-SignatureDb {
    param([string]$Category)
    $sigFile = Join-Path (Get-SkillRoot) "extensions\app-signatures.json"
    if (-not (Test-Path $sigFile)) { return @() }
    try {
        $sigs = Get-Content $sigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $catApps = $sigs.categories.$Category.apps
        if ($catApps) { return @($catApps) } else { return @() }
    } catch { return @() }
}

function Load-CustomSigs {
    $customFile = Join-Path (Get-SkillRoot) "extensions\user-custom.json"
    if (-not (Test-Path $customFile)) { return @() }
    try {
        $cust = Get-Content $customFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cust.apps -and @($cust.apps).Count -gt 0) { return @($cust.apps) } else { return @() }
    } catch { return @() }
}

function Test-AppSignature {
    param([PSObject]$App)
    $found = $false
    $totalSize = 0L
    $foundPath = ""
    foreach ($dp in $App.detect_paths) {
        $expanded = Expand-EnvPath $dp
        if (-not (Test-Path $expanded -ErrorAction SilentlyContinue)) { continue }
        $found = $true
        $foundPath = $expanded
        if ($App.sub_paths) {
            $subSize = 0L
            foreach ($sub in $App.sub_paths) {
                $subFull = Join-Path $expanded $sub
                $r = Get-FolderSizeFast $subFull
                if ($r.Found) { $subSize += $r.Size }
            }
            $totalSize += $subSize
        } else {
            $r = Get-FolderSizeFast $expanded
            $totalSize += $r.Size
        }
    }
    return @{ Found = $found; Size = $totalSize; Path = $foundPath }
}

function Convert-RiskLevel {
    param($Cleanable)
    if ($Cleanable -eq $true) { return "safe" }
    if ($Cleanable -eq "cautious") { return "cautious" }
    if ($Cleanable -eq $false) { return "forbidden" }
    return "cautious"
}

function Write-ScanResult {
    param(
        [string]$Category,
        [string]$Name,
        [long]$Size,
        [string]$Risk,
        [string]$Path,
        [string]$Advice,
        [string]$Migration,
        [string]$Note,
        [string]$Source = ""
    )
    $sizeMB = [math]::Round($Size / 1MB, 2)
    $sizeGB = [math]::Round($Size / 1GB, 2)
    $sizeStr = if ($sizeGB -ge 1) { "$sizeGB GB" } else { "$sizeMB MB" }
    $riskIcon = switch ($Risk) {
        "safe"      { "✅" }
        "cautious"  { "⚠️" }
        "dangerous" { "❌" }
        "forbidden" { "🔴" }
        default     { "⚠️" }
    }
    $color = switch ($Risk) {
        "safe"      { "Green" }
        "cautious"  { "Yellow" }
        "dangerous" { "Red" }
        "forbidden" { "Red" }
        default     { "Yellow" }
    }
    if ($sizeMB -gt 0) {
        $srcTag = if ($Source) { " [$Source]" } else { "" }
        Write-Host "  $riskIcon ${Name}${srcTag}: $sizeStr" -ForegroundColor $color
        if ($Path) { Write-Host "     路径: $Path" -ForegroundColor DarkGray }
        if ($Advice) { Write-Host "     建议: $Advice" -ForegroundColor DarkGray }
        if ($Migration) { Write-Host "     迁移: $Migration" -ForegroundColor DarkGray }
        if ($Note) { Write-Host "     备注: $Note" -ForegroundColor DarkGray }
    }
    [void]$Global:CDriveScanResults.Add(@{
        Category = $Category
        Name     = $Name
        SizeMB   = $sizeMB
        Risk     = $Risk
        Path     = $Path
        Advice   = $Advice
        Migration = $Migration
        Note     = $Note
        Source   = $Source
    })
}

function Get-DriveSpace {
    $drive = Get-PSDrive C -ErrorAction SilentlyContinue
    if (-not $drive) { return $null }
    $totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    $usedGB = [math]::Round($drive.Used / 1GB, 2)
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    $usedPercent = [math]::Round($drive.Used / ($drive.Used + $drive.Free) * 100, 1)
    return @{
        TotalGB     = $totalGB
        UsedGB      = $usedGB
        FreeGB      = $freeGB
        UsedPercent = $usedPercent
    }
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ProgressBar {
    param([int]$Current, [int]$Total, [int]$Width = 30)
    if ($Total -le 0) { return "" }
    $pct = [math]::Min(100, [math]::Max(0, [int]($Current / $Total * 100)))
    $filled = [math]::Max(0, [math]::Min($Width, [int]($pct * $Width / 100)))
    $empty = $Width - $filled
    $bar = "[" + ("=" * $filled) + (">" * [math]::Min(1, $filled - [math]::Max(0, $filled - 1))) + (" " * $empty) + "]"
    return "$bar $pct%"
}

function Remove-Directory {
    <#
    .SYNOPSIS
    高性能递归删除目录，带进度反馈、超时控制和多级回退。
    主方案: cmd /c rmdir（快 10-100 倍）+ 每 5 秒进度反馈
    回退A: robocopy /MIR 快速清空后再 rmdir（比 .NET Delete 快数倍）
    回退B: .NET API 作为最后手段
    .PARAMETER Path
    要删除的目录路径
    .PARAMETER ShowTimer
    是否显示耗时
    .PARAMETER TimeoutSec
    超时秒数（默认 120，大目录 30-60 秒通常足够）
    .PARAMETER ShowProgress
    删除过程中是否定期输出进度（耗时+剩余大小检查）
    #>
    param(
        [string]$Path,
        [switch]$ShowTimer,
        [int]$TimeoutSec = 120,
        [switch]$ShowProgress
    )
    if (-not (Test-Path $Path -ErrorAction SilentlyContinue)) { return $true }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # 预先计算大小（用于进度估计）
    $initialSize = 0L
    $initialSizeStr = ""
    if ($ShowProgress) {
        $r = Get-FolderSizeFast $Path
        if ($r.Found) {
            $initialSize = $r.Size
            $sizeMB = [math]::Round($initialSize / 1MB, 2)
            $initialSizeStr = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB/1024,2)) GB" } else { "$sizeMB MB" }
        }
        Write-Host "  删除中 ($initialSizeStr)..." -ForegroundColor DarkGray
    } elseif ($ShowTimer) {
        Write-Host "  删除中..." -NoNewline -ForegroundColor DarkGray
    }

    # 方案 A: cmd /c rmdir 带超时保护和进度反馈
    $processExited = $true
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd"
        $psi.Arguments = "/c rmdir /s /q `"$Path`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)

        if ($ShowProgress) {
            $progressInterval = 5
            $prevRemainingStr = ""
            $cursorLeft = [Console]::CursorLeft
            while (-not $p.WaitForExit($progressInterval * 1000)) {
                $elapsed = $sw.Elapsed.TotalSeconds.ToString('0.0')
                $remainingSize = 0L
                $remainingStr = ""
                if (Test-Path $Path -ErrorAction SilentlyContinue) {
                    $rr = Get-FolderSizeFast $Path
                    if ($rr.Found) { $remainingSize = $rr.Size }
                }
                if ($remainingSize -gt 0 -and $initialSize -gt 0) {
                    $cleaned = $initialSize - $remainingSize
                    $cleanedMB = [math]::Round($cleaned / 1MB, 2)
                    $totalMB = [math]::Round($initialSize / 1MB, 2)
                    $pctDone = [math]::Min(99, [int]($cleaned / $initialSize * 100))
                    $remainingStr = " 已删 ${cleanedMB}MB/${totalMB}MB"
                    $bar = Get-ProgressBar -Current $cleaned -Total $initialSize -Width 20
                    # 用 \r 回到行首覆盖输出
                    Write-Host "`r  [${elapsed}s]$bar$remainingStr  " -NoNewline -ForegroundColor DarkGray
                } else {
                    Write-Host "`r  [${elapsed}s] 删除中...  " -NoNewline -ForegroundColor DarkGray
                }
            }
            $elapsed = $sw.Elapsed.TotalSeconds.ToString('0.0')
            Write-Host "`r  [${elapsed}s] 等待完成...     " -NoNewline -ForegroundColor DarkGray
            $processExited = $true
        } else {
            $processExited = $p.WaitForExit($TimeoutSec * 1000)
        }

        if (-not $processExited) {
            $p.Kill()
            if ($ShowTimer -or $ShowProgress) { Write-Host " 超时..." -NoNewline -ForegroundColor Yellow }
        }
    } catch {
        $processExited = $false
    }

    $stillExists = Test-Path $Path -ErrorAction SilentlyContinue
    if ($stillExists) {
        if ($ShowProgress -or $ShowTimer) {
            Write-Host " 回退(robocopy)..." -NoNewline -ForegroundColor Yellow
        }
        try {
            $emptyDir = Join-Path $env:TEMP "_empty_$(Get-Random)"
            $null = New-Item -ItemType Directory -Path $emptyDir -Force
            & robocopy $emptyDir $Path /MIR /R:1 /W:1 > $null 2>&1
            Remove-Item $emptyDir -Force -ErrorAction SilentlyContinue
            & cmd /c "rmdir /s /q `"$Path`"" 2>$null
        } catch {
            try { [System.IO.Directory]::Delete($Path, $true) } catch {}
        }
    }

    $sw.Stop()
    $stillExists = Test-Path $Path -ErrorAction SilentlyContinue
    if ($ShowTimer -or $ShowProgress) {
        $elapsed = $sw.Elapsed.TotalSeconds.ToString('0.0')
        if ($ShowProgress) {
            $icon = if (-not $stillExists) { "✅" } else { "❌" }
            Write-Host ""
            Write-Host "    $icon 耗时 ${elapsed}s" -ForegroundColor $(if (-not $stillExists) { "Green" } else { "Red" })
        } else {
            $msg = if (-not $stillExists) { " 完成($($elapsed)s)" } else { " 失败($($elapsed)s)" }
            Write-Host $msg -ForegroundColor $(if (-not $stillExists) { "Green" } else { "Red" })
        }
    }
    return (-not $stillExists)
}

function Invoke-SignatureScan {
    param(
        [string]$Category,
        [string]$CategoryLabel,
        [string[]]$AlreadyScanned = @()
    )
    $apps = Load-SignatureDb -Category $Category
    foreach ($app in $apps) {
        if ($app.name -in $AlreadyScanned) { continue }
        $result = Test-AppSignature $app
        if ($result.Found -and $result.Size -gt 1MB) {
            $risk = Convert-RiskLevel $app.cleanable
            $advice = ""
            if ($app.cleanable -eq $true) { $advice = "可安全清理" }
            elseif ($app.cleanable -eq "cautious") { $advice = "确认后可操作" }
            elseif ($app.cleanable -eq $false) { $advice = "不可删除" }
            if ($app.sub_cleanable) { $advice += " (可清理: $($app.sub_cleanable))" }
            $migration = ""
            if ($app.migratable -eq $true) {
                $migration = "可迁移"
                if ($app.migration_method) {
                    $methodLabel = switch -wildcard ($app.migration_method) {
                        'env_var*' { "设环境变量" }
                        'symlink*' { "符号链接" }
                        'config*'  { "改配置文件" }
                        'yarn_config*' { "yarn config set" }
                        'pnpm_config*' { "pnpm config set" }
                        'wsl_export*' { "wsl export/import" }
                        default { $app.migration_method }
                    }
                    $migration += " ($methodLabel)"
                    if ($app.migration_key) { $migration += " | key: $($app.migration_key)" }
                }
            }
            Write-ScanResult -Category $CategoryLabel -Name $app.name `
                -Size $result.Size -Risk $risk -Path $result.Path `
                -Advice $advice -Migration $migration -Note $app.note -Source "DB"
        }
    }
    $customApps = Load-CustomSigs
    foreach ($app in $customApps) {
        if ($app.name -in $AlreadyScanned) { continue }
        $result = Test-AppSignature $app
        if ($result.Found -and $result.Size -gt 1MB) {
            $risk = Convert-RiskLevel $app.cleanable
            Write-ScanResult -Category $CategoryLabel -Name $app.name `
                -Size $result.Size -Risk $risk -Path $result.Path `
                -Note $app.note -Source "自定义"
        }
    }
}
