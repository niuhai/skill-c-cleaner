<#
.SYNOPSIS
    CleanSight v6.2 - Conversation Memory Logger
.DESCRIPTION
    记录对话历史，学习用户行为模式，支持个性化推荐
.NOTES
    Version: 6.2.0-preview
    Part of Learning Loop system
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("scan_start", "scan_complete", "cleanup_start", "cleanup_complete", "question_asked", "recommendation_given", "user_feedback", "error_occurred")]
    [string]$EventType,
    
    [string]$SessionId,
    [hashtable]$Metadata = @{},
    [string]$MemoryPath = "$PSScriptRoot\..\memory\conversation-memory.json"
)

$ErrorActionPreference = "SilentlyContinue"

function Get-MetadataValue {
    param(
        [hashtable]$Data,
        [string]$Key,
        $Default
    )
    if ($Data -and $Data.ContainsKey($Key) -and $null -ne $Data[$Key]) { return $Data[$Key] }
    return $Default
}

if (-not $SessionId) {
    $SessionId = "session-$((Get-Date).ToString('yyyyMMddHHmmss'))"
}

$timestamp = (Get-Date).ToString("o")

$eventEntry = @{
    timestamp = $timestamp
    session_id = $SessionId
    event_type = $EventType
    metadata = $Metadata
}

if (-not (Test-Path $MemoryPath)) {
    $memoryData = @{
        schema_version = "1.0.0"
        conversation_log = @()
        session_summaries = @()
        learning_points = @()
        pattern_recognition = @{
            user_concerns = @()
            repeated_questions = @()
            successful_solutions = @()
            avoided_topics = @()
        }
    }
} else {
    $memoryData = Get-Content $MemoryPath | ConvertFrom-Json
    $memoryData.conversation_log = @($memoryData.conversation_log)
}

$memoryData.conversation_log += $eventEntry

switch ($EventType) {
    "question_asked" {
        $questionText = Get-MetadataValue -Data $Metadata -Key "question" -Default ""
        if ($questionText) {
            $existing = $memoryData.pattern_recognition.repeated_questions | Where-Object { $_.text -eq $questionText }
            if ($existing) {
                $existing.count++
                $existing.lastAsked = $timestamp
            } else {
                $memoryData.pattern_recognition.repeated_questions += @{
                    text = $questionText
                    count = 1
                    firstAsked = $timestamp
                    lastAsked = $timestamp
                    context = Get-MetadataValue -Data $Metadata -Key "context" -Default ""
                }
            }
            
            $concernCategory = DetectUserConcern -Question $questionText
            if ($concernCategory) {
                $memoryData.pattern_recognition.user_concerns += @{
                    category = $concernCategory
                    timestamp = $timestamp
                    intensity = if ($questionText -match "紧急|快满|救命|马上") { "high" } elseif ($questionText -match "怎么|如何|帮助") { "medium" } else { "low" }
                }
            }
        }
    }
    
    "recommendation_given" {
        $recType = Get-MetadataValue -Data $Metadata -Key "recommendation_type" -Default "general"
        $recTarget = Get-MetadataValue -Data $Metadata -Key "target" -Default ""
        
        $solution = @{
            type = $recType
            target = $recTarget
            timestamp = $timestamp
            context = Get-MetadataValue -Data $Metadata -Key "context" -Default ""
            status = "pending_feedback"
        }
        
        $memoryData.pattern_recognition.successful_solutions += $solution
    }
    
    "user_feedback" {
        $feedbackValue = Get-MetadataValue -Data $Metadata -Key "feedback" -Default ""
        $targetRec = Get-MetadataValue -Data $Metadata -Key "target_recommendation" -Default ""
        
        if ($memoryData.pattern_recognition.successful_solutions.Count -gt 0) {
            $lastSolution = $memoryData.pattern_recognition.successful_solutions[-1]
            if ($targetRec -or $lastSolution.status -eq "pending_feedback") {
                $lastSolution.status = if ($feedbackValue -match "accept|采纳|好|执行|同意") { "accepted" } elseif ($feedbackValue -match "reject|拒绝|不要|跳过|忽略") { "rejected" } else { "neutral" }
                $lastSolution.feedback = $feedbackValue
                $lastSolution.feedback_timestamp = $timestamp
            }
        }
        
        if ($feedbackValue -match "reject|拒绝|不要|跳过|忽略|不喜欢") {
            $memoryData.pattern_recognition.avoided_topics += @{
                topic = Get-MetadataValue -Data $Metadata -Key "topic" -Default $targetRec
                reason = $feedbackValue
                timestamp = $timestamp
            }
        }
    }
    
    "cleanup_complete" {
        $spaceFreed = Get-MetadataValue -Data $Metadata -Key "space_freed_mb" -Default 0
        $actionsTaken = Get-MetadataValue -Data $Metadata -Key "actions" -Default @()
        
        if ([int]$spaceFreed -gt 0) {
            $summary = @{
                session_id = $SessionId
                timestamp = $timestamp
                space_freed_mb = [int]$spaceFreed
                actions_count = ($actionsTaken | Measure-Object).Count
                effectiveness = if ([int]$spaceFreed -gt 500) { "excellent" } elseif ([int]$spaceFreed -gt 200) { "good" } elseif ([int]$spaceFreed -gt 50) { "modest" } else { "minimal" }
            }
            
            $memoryData.session_summaries += $summary
            
            foreach ($action in $actionsTaken) {
                AddLearningPoint -MemoryData ([ref]$memoryData) -Action $action -Effectiveness $summary.effectiveness
            }
        }
    }
}

if ($memoryData.conversation_log.Count -gt 1000) {
    $keepCount = 500
    $olderEntries = $memoryData.conversation_log[0..($memoryData.conversation_log.Count - $keepCount - 1)]
    
    $olderSessions = $olderEntries | Group-Object session_id | ForEach-Object {
        @{
            session_id = $_.Name
            event_count = $_.Count
            time_span = @{
                start = $_.Group[0].timestamp
                end = $_.Group[-1].timestamp
            }
            event_types = ($_.Group.event_type | Group-Object | ForEach-Object { "$($_.Name)x$($_.Count)" }) -join ", "
        }
    }
    
    if (-not $memoryData.session_summaries) {
        $memoryData.session_summaries = @()
    }
    $memoryData.session_summaries += $olderSessions
    
    $memoryData.conversation_log = $memoryData.conversation_log[$keepCount..($memoryData.conversation_log.Count - 1)]
}

$memoryJson = $memoryData | ConvertTo-Json -Depth 10 -Compress
Set-Content -Path $MemoryPath -Value $memoryJson -Encoding UTF8

return $eventEntry

function DetectUserConcern {
    param([string]$Question)
    
    $patterns = @{
        "disk_space_urgent" = "紧急|快满了|只剩.*GB|磁盘空间不足|out of space"
        "performance_slow" = "卡顿|慢|性能|速度|响应慢|lag"
        "specific_cleanup" = "清理.*缓存|删除.*临时|清理.*日志|清理.*浏览器"
        "learning_howto" = "怎么|如何|教程|方法|步骤|教我"
        "safety_concern" = "安全|危险|风险|会不会|能不能删|误删"
        "automation_need" = "自动|定时|计划任务|scheduled|cron"
        "migration_help" = "迁移|移动|转移到|移到D盘"
    }
    
    foreach ($category in $patterns.Keys) {
        if ($Question -match $patterns[$category]) {
            return $category
        }
    }
    
    return $null
}

function AddLearningPoint {
    param(
        [ref]$MemoryData,
        [string]$Action,
        [string]$Effectiveness
    )
    
    $existingPoint = $MemoryData.Value.learning_points | Where-Object { $_.action -eq $Action }
    
    if ($existingPoint) {
        $existingPoint.usage_count++
        $existingPoint.last_used = $timestamp
        $existingPoint.effectiveness_history += $Effectiveness
        
        $successRate = ($existingPoint.effectiveness_history | Where-Object { $_ -in @("good","excellent") }).Count / $existingPoint.effectiveness_history.Count * 100
        $existingPoint.success_rate = [math]::Round($successRate, 1)
    } else {
        $MemoryData.Value.learning_points += @{
            action = $Action
            usage_count = 1
            first_used = $timestamp
            last_used = $timestamp
            effectiveness_history = @($Effectiveness)
            success_rate = if ($Effectiveness -in @("good","excellent")) { 100 } else { 0 }
            user_type_context = if ($profile -and $profile.user_type -and $profile.user_type.primary) { $profile.user_type.primary } else { "unknown" }
        }
    }
}
