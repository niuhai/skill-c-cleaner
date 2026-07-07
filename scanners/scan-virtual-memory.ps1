# scan-virtual-memory.ps1 - 虚拟内存智能评估模块
# 只读评估，不修改任何系统设置

if (-not (Get-Command "Get-FolderSizeFast" -ErrorAction SilentlyContinue)) { . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "_common.ps1") }

Write-Host "`n===== 虚拟内存智能评估 =====" -ForegroundColor Cyan

$isAdmin = Test-Admin
if (-not $isAdmin) {
    Write-Host "  ⚠️  提示: 管理员权限可获取更详细的虚拟内存信息" -ForegroundColor Yellow
}

$driveC = Get-PSDrive C -ErrorAction SilentlyContinue
if (-not $driveC) {
    Write-Host "  ❌ 无法获取C盘信息" -ForegroundColor Red
    return
}

$freePercent = [math]::Round($driveC.Free / ($driveC.Used + $driveC.Free) * 100, 1)
$freeGB = [math]::Round($driveC.Free / 1GB, 2)
$totalGB = [math]::Round(($driveC.Used + $driveC.Free) / 1GB, 2)

Write-Host "`n  [系统状态]" -ForegroundColor White
Write-Host "  C盘可用空间: $freeGB GB ($freePercent%)" -ForegroundColor $(if ($freePercent -lt 20) { "Red" } elseif ($freePercent -lt 30) { "Yellow" } else { "Green" })

$pagefileInfo = @{
    OnC = $false
    TotalSize = 0L
    Usage = 0L
    Location = @()
    Recommendation = ""
    OptimizationPotential = 0L
    Assessment = "normal"
}

$pagefilePath = "C:\pagefile.sys"
if (Test-Path $pagefilePath) {
    $pageSize = (Get-Item $pagefilePath -Force).Length
    $pagefileInfo.TotalSize = $pageSize
    $pagefileInfo.OnC = $true
    
    Write-Host "`n  [页面文件检测]" -ForegroundColor White
    $sizeGB = [math]::Round($pageSize / 1GB, 2)
    Write-Host "  位置: C:\pagefile.sys" -ForegroundColor Yellow
    Write-Host "  大小: $sizeGB GB" -ForegroundColor Yellow
}

try {
    $wmiPagefiles = Get-WmiObject -Class Win32_PageFileUsage -ErrorAction SilentlyContinue
    if ($wmiPagefiles) {
        foreach ($pf in $wmiPagefiles) {
            $location = $pf.Name
            $allocatedMB = $pf.AllocatedBaseSize
            $currentMB = $pf.CurrentUsage
            $peakMB = $pf.PeakUsage
            
            Write-Host "`n  [WMI详细信息]" -ForegroundColor White
            Write-Host "  位置: $location" -ForegroundColor DarkGray
            Write-Host "  初始大小: $allocatedMB MB" -ForegroundColor DarkGray
            Write-Host "  当前使用: $currentMB MB" -ForegroundColor DarkGray
            Write-Host "  峰值使用: $peakMB MB" -ForegroundColor DarkGray
            
            $pagefileInfo.Location += $location
            
            if ($currentMB -gt 0) {
                $pagefileInfo.Usage = $currentMB * 1MB
            }
        }
    }
} catch {
    Write-Host "  提示: 需要管理员权限获取详细WMI信息" -ForegroundColor DarkGray
}

$drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Free -gt 0 }
$recommendations = @()

Write-Host "`n  [优化潜力分析]" -ForegroundColor White

if ($pagefileInfo.OnC) {
    if ($freePercent -lt 30) {
        $pagefileInfo.Assessment = "critical"
        $potentialGB = [math]::Round($pagefileInfo.TotalSize / 1GB, 2)
        $pagefileInfo.OptimizationPotential = $pagefileInfo.TotalSize
        
        Write-Host "  ⚠️  评估状态: 危急" -ForegroundColor Red
        Write-Host "  问题: C盘空间不足且页面文件占用大量空间" -ForegroundColor Red
        Write-Host "  优化潜力: 可释放约 $potentialGB GB 空间" -ForegroundColor Yellow
        
        $recommendations += @{
            Priority = "high"
            Action = "迁移页面文件"
            Detail = "将页面文件迁移到其他分区，缓解C盘压力"
            SpaceRelease = $potentialGB
            PerformanceGain = "显著"
        }
        
        $recommendations += @{
            Priority = "medium"
            Action = "优化方案"
            Detail = "混合方案：保留4GB在C盘作为备份路径，主页面文件迁移到空间充足的分区"
            SpaceRelease = [math]::Max(0, $potentialGB - 4)
            PerformanceGain = "中等"
        }
    } elseif ($freePercent -lt 50) {
        $pagefileInfo.Assessment = "warning"
        $potentialGB = [math]::Round($pagefileInfo.TotalSize / 1GB, 2)
        $pagefileInfo.OptimizationPotential = [math]::Round($pagefileInfo.TotalSize * 0.5)
        
        Write-Host "  ⚠️  评估状态: 警告" -ForegroundColor Yellow
        Write-Host "  问题: C盘空间偏紧，页面文件可考虑优化" -ForegroundColor Yellow
        Write-Host "  优化潜力: 建议释放约 $([math]::Round($pagefileInfo.OptimizationPotential/1GB, 2)) GB" -ForegroundColor Yellow
        
        $recommendations += @{
            Priority = "medium"
            Action = "评估后迁移"
            Detail = "如果其他分区有足够空间，可考虑迁移页面文件以优化性能"
            SpaceRelease = [math]::Round($pagefileInfo.OptimizationPotential/1GB, 2)
            PerformanceGain = "轻微"
        }
    } else {
        $pagefileInfo.Assessment = "normal"
        Write-Host "  ✅ 评估状态: 正常" -ForegroundColor Green
        Write-Host "  C盘空间充足，当前页面文件配置合理" -ForegroundColor Green
        
        $recommendations += @{
            Priority = "low"
            Action = "无需优化"
            Detail = "当前配置满足系统需求，无需调整"
            SpaceRelease = 0
            PerformanceGain = "无"
        }
    }
    
    if ($recommendations -and $recommendations.Count -gt 0 -and $recommendations[0].Priority -ne "low") {
        Write-Host "`n  [可用驱动器分析]" -ForegroundColor White
        
        $suitableDrives = @()
        foreach ($drive in $drives) {
            if ($drive.Name -eq "C") { continue }
            
            $driveFreeGB = [math]::Round($drive.Free / 1GB, 2)
            $driveTotalGB = [math]::Round(($drive.Free + $drive.Used) / 1GB, 2)
            
            if ($driveFreeGB -gt 30) {
                $isSSD = $false
                try {
                    $disk = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.Number -eq (Get-Partition -DriveLetter $drive.Name -ErrorAction SilentlyContinue).DiskNumber }
                    if ($disk -and $disk.MediaType -match "SSD|Solid") {
                        $isSSD = $true
                    }
                } catch {}
                
                $suitableDrives += @{
                    Drive = $drive.Name
                    FreeGB = $driveFreeGB
                    IsSSD = $isSSD
                    Recommendation = if ($isSSD) { "⭐ 推荐（SSD高速分区）" } else { "可用" }
                }
                
                Write-Host "  驱动器 ${drive.Name}: 可用空间 ${driveFreeGB} GB" -ForegroundColor $(if ($isSSD) { "Green" } else { "White" }) -NoNewline
                if ($isSSD) {
                    Write-Host "  ⭐" -ForegroundColor Green -NoNewline
                }
                Write-Host ""
                Write-Host "    推荐理由: " -ForegroundColor DarkGray -NoNewline
                if ($isSSD) {
                    Write-Host "高速SSD分区，虚拟内存读写性能更佳" -ForegroundColor Green
                } else {
                    Write-Host "空间充足" -ForegroundColor DarkGray
                }
            }
        }
        
        if ($suitableDrives.Count -eq 0) {
            Write-Host "  ⚠️  未找到合适的迁移目标驱动器（需要至少30GB可用空间）" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  ✅ 页面文件不在C盘" -ForegroundColor Green
    $recommendations += @{
        Priority = "info"
        Action = "配置良好"
        Detail = "页面文件已配置在非系统分区，无需调整"
        SpaceRelease = 0
        PerformanceGain = "N/A"
    }
}

Write-Host "`n  [智能优化建议]" -ForegroundColor White

if ($recommendations -and $recommendations.Count -gt 0) {
    foreach ($rec in $recommendations) {
        $priorityColor = switch ($rec.Priority) {
            "high" { "Red" }
            "medium" { "Yellow" }
            "low" { "Green" }
            default { "White" }
        }
        
        $priorityLabel = switch ($rec.Priority) {
            "high" { "🔴 高优先级" }
            "medium" { "⚠️  中优先级" }
            "low" { "✅ 低优先级" }
            default { "ℹ️  信息" }
        }
        
        Write-Host "  $priorityLabel" -ForegroundColor $priorityColor
        Write-Host "    操作: $($rec.Action)" -ForegroundColor White
        Write-Host "    说明: $($rec.Detail)" -ForegroundColor DarkGray
        if ($rec.SpaceRelease -gt 0) {
            Write-Host "    预期效果: 释放 $($rec.SpaceRelease) GB 空间 | 性能收益: $($rec.PerformanceGain)" -ForegroundColor DarkGray
        }
    }
}

if ($pagefileInfo.Assessment -ne "normal") {
    Write-Host "`n  [实施步骤]" -ForegroundColor White
    Write-Host "  1. 按 Win+R，输入 sysdm.cpl，回车打开系统属性" -ForegroundColor DarkGray
    Write-Host "  2. 切换到「高级」选项卡，点击「性能」区域的「设置」" -ForegroundColor DarkGray
    Write-Host "  3. 切换到「高级」选项卡，点击「虚拟内存」区域的「更改」" -ForegroundColor DarkGray
    Write-Host "  4. 取消勾选「自动管理所有驱动器的分页文件大小」" -ForegroundColor DarkGray
    Write-Host "  5. 选择C盘，勾选「自定义大小」，设置初始: 4096 MB，最大: 4096 MB，点击「设置」" -ForegroundColor DarkGray
    
    if ($suitableDrives -and $suitableDrives.Count -gt 0) {
        $primaryDrive = $suitableDrives | Where-Object { $_.IsSSD } | Select-Object -First 1
        if (-not $primaryDrive) {
            $primaryDrive = $suitableDrives | Select-Object -First 1
        }
        
        if ($primaryDrive) {
            Write-Host "  6. 选择 ${primaryDrive.Drive}: 盘，勾选「自定义大小」，" -ForegroundColor DarkGray -NoNewline
            Write-Host "初始: 32768 MB，最大: 65536 MB，点击「设置」" -ForegroundColor DarkGray
            Write-Host "  7. 连续点击「确定」，重启计算机使更改生效" -ForegroundColor DarkGray
        }
    }
}

$globalVMResult = [PSCustomObject]@{
    Assessment = $pagefileInfo.Assessment
    OnC = $pagefileInfo.OnC
    TotalSize = $pagefileInfo.TotalSize
    FreePercent = $freePercent
    Recommendations = $recommendations
    SuitableDrives = $suitableDrives
}

if (-not $Global:VMAssessResult) {
    $Global:VMAssessResult = $globalVMResult
}

Write-Host ""
