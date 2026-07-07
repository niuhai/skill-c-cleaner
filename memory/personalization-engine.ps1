<#
.SYNOPSIS
    CleanSight v6.2 - Personalization Engine
.DESCRIPTION
    基于用户画像 + 对话历史生成个性化推荐
.NOTES
    Version: 6.2.0-preview
    Core intelligence component for "越用越懂你"
#>

param(
    [string]$UserProfilePath = "$PSScriptRoot\..\memory\user-profile.json",
    [string]$ConversationMemoryPath = "$PSScriptRoot\..\memory\conversation-memory.json",
    [string]$CurrentContext = "routine",
    [int]$FreeSpaceGB = 0
)

# ===== 函数定义（必须先定义后调用，PowerShell 5.1 要求）=====

function AnalyzeContext {
    param($Profile, [string]$Context, [int]$FreeSpaceGB)
    
    $analysis = @{
        label = ""
        urgency = "low"
        description = ""
        space_pressure = "normal"
    }
    
    if ($FreeSpaceGB -gt 0 -and $FreeSpaceGB -le 10) {
        $analysis.label = "磁盘空间紧急"
        $analysis.urgency = "critical"
        $analysis.space_pressure = "critical"
        $analysis.description = "C盘空间严重不足（剩余${FreeSpaceGB}GB），需要立即释放空间。"
    } elseif ($FreeSpaceGB -gt 10 -and $FreeSpaceGB -le 20) {
        $analysis.label = "磁盘空间紧张"
        $analysis.urgency = "high"
        $analysis.space_pressure = "high"
        $analysis.description = "C盘空间偏紧（剩余${FreeSpaceGB}GB），建议近期进行清理。"
    } elseif ($Context -eq "emergency") {
        $analysis.label = "紧急救援模式"
        $analysis.urgency = "critical"
        $analysis.space_pressure = "unknown"
        $analysis.description = "用户触发紧急模式，需要快速定位可安全清理的大容量项目。"
    } elseif ($Context -eq "first_time") {
        $analysis.label = "首次使用"
        $analysis.urgency = "low"
        $analysis.space_pressure = "unknown"
        $analysis.description = "新用户首次使用，需要全面了解系统状态并建立基准画像。"
    } elseif ($Context -eq "routine") {
        $analysis.label = "日常维护"
        $analysis.urgency = "low"
        $analysis.space_pressure = "normal"
        $analysis.description = "定期维护场景，基于历史习惯优化扫描范围和操作建议。"
    } elseif ($Context -eq "post_cleanup") {
        $analysis.label = "清理后检查"
        $analysis.urgency = "low"
        $analysis.space_pressure = "good"
        $analysis.description = "上次清理后的跟进，验证效果并识别新的优化机会。"
    } else {
        $analysis.label = "常规分析"
        $analysis.urgency = "medium"
        $analysis.space_pressure = "normal"
        $analysis.description = "标准分析场景，平衡信息完整性和效率。"
    }
    
    return $analysis
}

function GenerateScanStrategy {
    param($Profile, $Memory, $ContextData)
    
    $strategy = @{
        recommended_mode = "auto"
        focus_categories = @()
        skip_categories = @()
        estimated_tokens = 0
        estimated_time_min = 0
        personalization_factors = @()
    }
    
    $baseMode = if ($Profile) { $Profile.preferences.scan_mode_preference } else { "auto" }
    
    switch ($ContextData.urgency) {
        "critical" {
            $strategy.recommended_mode = "quick"
            $strategy.focus_categories = @("B", "F")
            $strategy.estimated_tokens = 500
            $strategy.estimated_time_min = 1
            $strategy.personalization_factors += "紧急优先级覆盖默认偏好"
        }
        "high" {
            if ($baseMode -eq "custom" -or $baseMode -eq "quick") {
                $strategy.recommended_mode = $baseMode
            } else {
                $strategy.recommended_mode = "standard"
            }
            
            if ($Profile -and $Profile.preferences.preferred_categories.Count -gt 0) {
                $strategy.focus_categories += $Profile.preferences.preferred_categories[0..1]
                $strategy.personalization_factors += "聚焦用户最关注的类别"
            } else {
                $strategy.focus_categories = @("B", "D", "F")
            }
            
            $strategy.estimated_tokens = 1500
            $strategy.estimated_time_min = 3
        }
        default {
            $strategy.recommended_mode = $baseMode
            
            if ($Profile -and $Profile.preferences.preferred_categories.Count -gt 0) {
                $strategy.focus_categories = $Profile.preferences.preferred_categories
                $strategy.personalization_factors += "完全匹配用户偏好类别"
            } else {
                $strategy.focus_categories = @("B", "D", "L", "F")
            }
            
            if ($Profile -and $Profile.preferences.ignored_categories.Count -gt 0) {
                $strategy.skip_categories = $Profile.preferences.ignored_categories
                $strategy.personalization_factors += "排除用户忽略的类别"
            }
            
            switch ($strategy.recommended_mode) {
                "custom" { $strategy.estimated_tokens = 3000; $strategy.estimated_time_min = 8 }
                "standard" { $strategy.estimated_tokens = 2000; $strategy.estimated_time_min = 5 }
                "quick" { $strategy.estimated_tokens = 800; $strategy.estimated_time_min = 2 }
                default { $strategy.estimated_tokens = 1500; $strategy.estimated_time_min = 4 }
            }
        }
    }
    
    if ($Memory -and $Memory.learning_points.Count -gt 0) {
        $successfulActions = $Memory.learning_points | Where-Object { $_.success_rate -ge 70 } | Sort-Object usage_count -Descending
        
        if ($successfulActions.Count -gt 0) {
            $topAction = $successfulActions[0]
            $strategy.personalization_factors += "历史成功率最高的操作: $($topAction.action) ($($topAction.success_rate)%)"
        }
        
        $recentSessions = $Memory.session_summaries | Sort-Object timestamp -Descending | Select-Object -First 3
        if ($recentSessions.Count -ge 2) {
            $avgSpace = ($recentSessions | Measure-Object -Property space_freed_mb -Average).Average
            $strategy.personalization_factors += "历史平均释放: $([math]::Round($avgSpace))MB"
        }
    }
    
    return $strategy
}

function IdentifyPriorityActions {
    param($Profile, $Memory, $ContextData)
    
    $actions = @()
    
    if ($ContextData.urgency -in @("critical", "high")) {
        $actions += @{
            name = "临时文件快速清理"
            category = "B"
            priority = "critical"
            estimated_space_mb = 500
            safety_level = "safe"
            command_template = ".\cleaners\clean-safe.ps1"
            personalized_reason = "紧急情况下的最快见效方案"
        }
        
        if ($Profile -and $Profile.user_type.detection_signals.dev_tools_installed) {
            $actions += @{
                name = "开发缓存清理"
                category = "C"
                priority = "high"
                estimated_space_mb = 300
                safety_level = "safe"
                command_template = ".\cleaners\clean-dev-caches.ps1"
                personalized_reason = "检测到开发环境，npm/pip缓存通常占用较大"
            }
        }
    } else {
        if ($Profile) {
            switch ($Profile.user_type.primary) {
                "devops_engineer" {
                    $actions += @{
                        name = "Docker系统清理"
                        category = "G"
                        priority = "high"
                        estimated_space_mb = 2000
                        safety_level = "needs_review"
                        command_template = "docker system prune -f"
                        personalized_reason = "Docker用户常见问题源，镜像和卷可能大量占用空间"
                    }
                    
                    $actions += @{
                        name = "npm缓存深度清理"
                        category = "C"
                        priority = "medium"
                        estimated_space_mb = 500
                        safety_level = "safe"
                        command_template = "npm cache clean --force"
                        personalized_reason = "基于您的DevOps画像，定期清理可避免累积"
                    }
                }
                "developer" {
                    $actions += @{
                        name = "浏览器缓存清理"
                        category = "D"
                        priority = "medium"
                        estimated_space_mb = 200
                        safety_level = "safe"
                        command_template = "手动清理或使用浏览器内置工具"
                        personalized_reason = "开发者常忽视浏览器缓存，但积累快且安全清理"
                    }
                    
                    $actions += @{
                        name = "IDE临时文件清理"
                        category = "E"
                        priority = "low"
                        estimated_space_mb = 150
                        safety_level = "safe"
                        command_template = "删除 .idea/, .vs/, node_modules/ 等目录"
                        personalized_reason = "检测到多个IDE，可能有残留的临时文件"
                    }
                }
                default {
                    $actions += @{
                        name = "系统临时文件清理"
                        category = "B"
                        priority = "medium"
                        estimated_space_mb = 300
                        safety_level = "safe"
                        command_template = ".\cleaners\clean-safe.ps1"
                        personalized_reason = "适合所有用户的日常维护项"
                    }
                    
                    $actions += @{
                        name = "回收站清空"
                        category = "B"
                        priority = "low"
                        estimated_space_mb = 100
                        safety_level = "safe"
                        command_template = "Clear-RecycleBin -Force"
                        personalized_reason = "简单但经常被忽视的安全清理项"
                    }
                }
            }
        }
        
        if ($Memory -and $Memory.pattern_recognition.avoided_topics.Count -gt 0) {
            $avoidedList = $Memory.pattern_recognition.avoided_topics | Select-Object -ExpandProperty topic -Unique
            
            foreach ($action in $actions) {
                if ($avoidedList -contains $action.name) {
                    $action.priority = "low"
                    $action.personalized_reason = "您之前表示不关注此项，已降低优先级"
                }
            }
        }
        
        if ($Memory -and $Memory.learning_points.Count -gt 0) {
            $topHistoryAction = $Memory.learning_points | Sort-Object success_rate, usage_count -Descending | Select-Object -First 1
            
            if ($topHistoryAction -and $topHistoryAction.success_rate -ge 80) {
                $historyBasedAction = @{
                    name = $topHistoryAction.action
                    category = "learned"
                    priority = "medium"
                    estimated_space_mb = 0
                    safety_level = "known_good"
                    command_template = "（基于历史记录的操作）"
                    personalized_reason = "您历史上执行过此操作且效果好（成功率 $($topHistoryAction.success_rate)%）"
                }
                
                $actions = @($historyBasedAction) + $actions
            }
        }
    }
    
    return $actions
}

function GeneratePersonalizedTips {
    param($Profile, $Memory, $ContextData)
    
    $result = @{
        tips = @()
        warnings = @()
        predicted_needs = @()
        confidence_score = 50
    }
    
    $confidenceFactors = 0
    $totalFactors = 6
    
    if ($Profile) {
        $confidenceFactors++
        
        if ($Profile.learning_insights.personalized_tips.Count -gt 0) {
            $result.tips += $Profile.learning_insights.personalized_tips
        }
        
        switch ($Profile.user_type.primary) {
            "devops_engineer" {
                $result.tips += "考虑设置 Docker 镜像自动清理策略（docker system prune -af --filter 'until=24h'）"
                $result.tips += "WSL 分区可以通过 diskpart 压缩来回收未使用空间"
                $result.predicted_needs += "未来可能需要容器存储优化建议"
                $result.predicted_needs += "可能需要多磁盘空间均衡方案"
                
                if ($ContextData.urgency -ne "critical") {
                    $result.warnings += "作为高级用户，您可能倾向于激进操作——但请记得先确认影响范围"
                }
            }
            "developer" {
                $result.tips += "项目完成后及时清理 node_modules 可显著释放空间"
                $result.tips += "使用 pnpm 或 yarn 替代 npm 可减少缓存占用"
                $result.tips += "IDE 的本地历史记录也会占用空间，可在设置中限制保留天数"
                $result.predicted_needs += "可能需要开发环境迁移到数据盘的指导"
                
                if ($Memory -and $Memory.conversation_log.Count -gt 5) {
                    $recentQuestions = $Memory.conversation_log | Where-Object { $_.event_type -eq "question_asked" } | Select-Object -Last 5
                    $codeRelatedQuestions = ($recentQuestions | Where-Object { $_.metadata.question -match "编译|构建|依赖|module|package" }).Count
                    
                    if ($codeRelatedQuestions -ge 2) {
                        $result.predicted_needs += "您似乎在处理依赖相关问题，可能需要项目级清理指导"
                    }
                }
            }
            default {
                $result.tips += "定期（每月）运行一次标准扫描可保持系统健康"
                $result.tips += "浏览器设置为'退出时清除缓存'可减少手动清理需求"
                $result.tips += "下载文件夹是容易忽视的空间占用源，建议定期整理"
                $result.predicted_needs += "可能需要简单的定时清理任务设置帮助"
            }
        }
        
        if ($Profile.behavioral_patterns.cleanup_frequency -eq "weekly" -and $Profile.usage_stats.total_scans -lt 2) {
            $result.warnings += "您设定的清理频率较高，但目前使用次数较少——建议从月度开始建立习惯"
        }
    }
    
    if ($Memory) {
        $confidenceFactors++
        
        if ($Memory.pattern_recognition.repeated_questions.Count -gt 0) {
            $topRepeated = $Memory.pattern_recognition.repeated_questions | Sort-Object count -Descending | Select-Object -First 1
            
            if ($topRepeated.count -ge 2) {
                $result.warnings += "您多次询问关于'$($topRepeated.text)'的问题——是否需要我将此添加到您的个人知识库？"
                $result.tips += "针对您反复关心的问题，我可以提供更深入的专题分析"
            }
        }
        
        if ($Memory.pattern_recognition.user_concerns.Count -gt 0) {
            $concernsByCategory = $Memory.pattern_recognition.user_concerns | Group-Object category | Sort-Object Count -Descending
            $primaryConcern = $concernsByCategory[0]
            
            if ($primaryConcern.Count -ge 2) {
                $concernLabels = @{
                    "disk_space_urgent" = "磁盘空间焦虑"
                    "performance_slow" = "性能问题关注"
                    "safety_concern" = "操作安全性顾虑"
                }
                
                # 修复: PowerShell 5.1 不支持 ?? 运算符，改用 if 表达式
                $concernKey = $primaryConcern.Name
                $label = if ($null -ne $concernLabels[$concernKey]) { $concernLabels[$concernKey] } else { $concernKey }
                $result.tips += "我注意到您特别关注'$label'——后续建议会侧重这方面"
            }
        }
        
        $recentSessions = $Memory.session_summaries | Sort-Object timestamp -Descending | Select-Object -First 5
        if ($recentSessions.Count -ge 3) {
            $avgEffectiveness = ($recentSessions | Measure-Object -Property effectiveness -Average)
            $effectivenessDist = $recentSessions | Group-Object effectiveness | Sort-Object Count -Descending
            
            $confidenceFactors++
            
            if ($effectivenessDist[0].Name -in @("modest", "minimal")) {
                $result.warnings += "最近几次清理效果一般——是否需要调整策略或扩大清理范围？"
                $result.tips += "尝试组合多个类别的清理可能获得更好的整体效果"
            }
        }
        
        if ($Memory.pattern_recognition.successful_solutions.Count -gt 0) {
            $acceptedSolutions = $Memory.pattern_recognition.successful_solutions | Where-Object { $_.status -eq "accepted" }
            $rejectedSolutions = $Memory.pattern_recognition.successful_solutions | Where-Object { $_.status -eq "rejected" }
            
            if ($acceptedSolutions.Count -gt $rejectedSolutions.Count) {
                $confidenceFactors++
                $result.tips += "感谢您的积极反馈！我会继续优化推荐的准确性"
            } elseif ($rejectedSolutions.Count -gt 2) {
                $result.warnings += "注意到您拒绝了几条建议——我会学习并调整推荐风格"
            }
        }
    }
    
    if ($ContextData.urgency -eq "critical") {
        $confidenceFactors++
        $result.tips = @("当前最紧迫的是快速释放空间，详细优化建议将在问题解决后提供") + $result.tips
        $result.warnings = @("紧急模式下请特别注意操作的准确性，避免误删重要文件") + $result.warnings
    }
    
    switch ($ContextData.label) {
        "首次使用" {
            $result.tips += "欢迎使用！前几次使用时我会学习您的习惯，之后建议会更精准"
            $result.predicted_needs += "完成首次扫描后，您可能想要了解如何设置定期维护"
        }
        "日常维护" {
            $confidenceFactors++
            $result.predicted_needs += "可能需要自动化定时任务的配置指导"
        }
    }
    
    $result.confidence_score = [math]::Round(($confidenceFactors / $totalFactors) * 100)
    
    $result.tips = $result.tips | Select-Object -Unique
    $result.warnings = $result.warnings | Select-Object -Unique
    $result.predicted_needs = $result.predicted_needs | Select-Object -Unique
    
    return $result
}

# ===== 主执行流程 =====

Write-Host "🧠 CleanSight Personalization Engine v6.2" -ForegroundColor Cyan

$personalizedRecommendation = @{
    scan_strategy = @{}
    priority_actions = @()
    personalized_tips = @()
    adaptive_warnings = @()
    predicted_needs = @()
    confidence_score = 0
    reasoning = ""
}

$profile = $null
$memory = $null

if (Test-Path $UserProfilePath) {
    try {
        $profile = Get-Content $UserProfilePath | ConvertFrom-Json
        Write-Host "   ✅ 已加载用户画像" -ForegroundColor Green
    } catch {
        Write-Host "   ⚠️ 画像文件损坏，使用默认配置" -ForegroundColor Yellow
    }
}

if (Test-Path $ConversationMemoryPath) {
    try {
        $memory = Get-Content $ConversationMemoryPath | ConvertFrom-Json
        Write-Host "   ✅ 已加载对话历史 ($($memory.conversation_log.Count) 条记录)" -ForegroundColor Green
    } catch {
        Write-Host "   ⚠️ 记忆文件损坏，将创建新记录" -ForegroundColor Yellow
    }
}

if (-not $profile) {
    Write-Host "`n📝 首次使用检测：正在构建基础画像..." -ForegroundColor Yellow
    & "$PSScriptRoot\build-user-profile.ps1" -OutputPath $UserProfilePath | Out-Null
    $profile = Get-Content $UserProfilePath | ConvertFrom-Json
}

Write-Host "`n🎯 [1/4] 分析当前场景..." -ForegroundColor Yellow

$contextAnalysis = AnalyzeContext -Profile $profile -Context $CurrentContext -FreeSpaceGB $FreeSpaceGB
$personalizedRecommendation.reasoning = $contextAnalysis.description

Write-Host "   场景: $($contextAnalysis.label)" -ForegroundColor Cyan
Write-Host "   紧急度: $($contextAnalysis.urgency)" -ForegroundColor $(if ($contextAnalysis.urgency -eq "high") { "Red" } elseif ($contextAnalysis.urgency -eq "medium") { "Yellow" } else { "Green" })

Write-Host "`n📊 [2/4] 生成个性化扫描策略..." -ForegroundColor Yellow

$scanStrategy = GenerateScanStrategy -Profile $profile -Memory $memory -ContextData $contextAnalysis
$personalizedRecommendation.scan_strategy = $scanStrategy

Write-Host "   推荐模式: $($scanStrategy.recommended_mode)" -ForegroundColor White
Write-Host "   聚焦类别: $($scanStrategy.focus_categories -join ', ')" -ForegroundColor Gray
Write-Host "   预计Token: ~$($scanStrategy.estimated_tokens)" -ForegroundColor Gray
Write-Host "   预计时间: ~$($scanStrategy.estimated_time_min)分钟" -ForegroundColor Gray

Write-Host "`n⚡ [3/4] 识别高优先级操作..." -ForegroundColor Yellow

$priorityActions = IdentifyPriorityActions -Profile $profile -Memory $memory -ContextData $contextAnalysis
$personalizedRecommendation.priority_actions = $priorityActions

foreach ($action in $priorityActions | Select-Object -First 5) {
    $icon = switch ($action.priority) { "critical" { "🔴" } "high" { "🟠" } "medium" { "🟡" } default { "⚪" } }
    Write-Host "   $icon [$($action.priority.ToUpper())] $($action.name)" -ForegroundColor $(switch ($action.priority) { "critical" { "Red" } "high" { "Yellow" } "medium" { "Cyan" } default { "Gray" } })
    if ($action.personalized_reason) {
        Write-Host "      💡 $($action.personalized_reason)" -ForegroundColor DarkGray
    }
}

Write-Host "`n💡 [4/4] 生成个性化建议..." -ForegroundColor Yellow

$tipsAndWarnings = GeneratePersonalizedTips -Profile $profile -Memory $memory -ContextData $contextAnalysis
$personalizedRecommendation.personalized_tips = $tipsAndWarnings.tips
$personalizedRecommendation.adaptive_warnings = $tipsAndWarnings.warnings
$personalizedRecommendation.predicted_needs = $tipsAndWarnings.predicted_needs
$personalizedRecommendation.confidence_score = $tipsAndWarnings.confidence_score

Write-Host "" 
Write-Host "🎓 个性化提示:" -ForegroundColor Magenta
foreach ($tip in $tipsAndWarnings.tips | Select-Object -First 3) {
    Write-Host "   • $tip" -ForegroundColor White
}

if ($tipsAndWarnings.warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "⚠️  智能提醒 (基于您的历史):" -ForegroundColor Yellow
    foreach ($warning in $tipsAndWarnings.warnings) {
        Write-Host "   ⚡ $warning" -ForegroundColor DarkYellow
    }
}

if ($tipsAndWarnings.predicted_needs.Count -gt 0) {
    Write-Host ""
    Write-Host "🔮 预测需求:" -ForegroundColor Cyan
    foreach ($need in $tipsAndWarnings.predicted_needs) {
        Write-Host "   → $need" -ForegroundColor DarkCyan
    }
}

Write-Host ""
Write-Host "📈 置信度评分: $($tipsAndWarnings.confidence_score)/100" -ForegroundColor $(if ($tipsAndWarnings.confidence_score -ge 80) { "Green" } elseif ($tipsAndWarnings.confidence_score -ge 60) { "Yellow" } else { "Red" })

$recommendationJson = $personalizedRecommendation | ConvertTo-Json -Depth 5
$outputPath = "$PSScriptRoot\..\memory\latest-recommendation.json"
Set-Content -Path $outputPath -Value $recommendationJson -Encoding UTF8

Write-Host ""
Write-Host "✅ 个性化推荐已生成！" -ForegroundColor Green
Write-Host "   📄 详细报告: $outputPath" -ForegroundColor Cyan

return $personalizedRecommendation
