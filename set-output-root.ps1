# set-output-root.ps1 - 记录 / 查看 / 清除 CleanSight 产物目录
# 报告、增长基线、清理会话、日志、快照都写入这个目录。
# 技能启动时应先询问用户存放位置，再用本脚本持久化，避免每次都问。
#
# 用法:
#   .\set-output-root.ps1                      # 查看当前生效值与配置
#   .\set-output-root.ps1 -Path "D:\CleanSight"
#   .\set-output-root.ps1 -Clear               # 清除配置，回到兜底路径

param(
    [string]$Path = "",
    [switch]$Show,
    [switch]$Clear
)

$skillRoot = Split-Path -Parent $PSCommandPath
if (-not $skillRoot -or -not (Test-Path (Join-Path $skillRoot "_common.ps1"))) {
    throw "Skill root could not be resolved from the script location."
}
. (Join-Path $skillRoot "_common.ps1")

function Show-CleanSightOutputRootState {
    $configPath = Get-CleanSightOutputRootConfigPath
    $configured = Get-CleanSightConfiguredOutputRoot
    Write-Host ""
    Write-Host "===== CleanSight 产物目录 =====" -ForegroundColor Cyan
    Write-Host ("  当前生效: " + (Get-CleanSightArtifactRoot)) -ForegroundColor White
    if ($configured) {
        Write-Host ("  已保存配置: " + $configured) -ForegroundColor Green
    } else {
        Write-Host "  已保存配置: （无，使用兜底路径：技能目录）" -ForegroundColor Yellow
    }
    Write-Host ("  配置文件: " + $configPath) -ForegroundColor DarkGray
    Write-Host ("  报告目录: " + (Get-CleanSightArtifactPath "reports")) -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  优先级: -OutputRoot > `$Global:CDriveArtifactRoot > CLEANSIGHT_OUTPUT_DIR > 配置文件 > 技能目录" -ForegroundColor DarkGray
    Write-Host ""
}

if ($Show -or (-not $Path -and -not $Clear)) {
    Show-CleanSightOutputRootState
    exit 0
}

try {
    if ($Clear) {
        $result = Set-CleanSightOutputRoot -Clear
        Write-Host "已清除产物目录配置，当前生效: $($result.ArtifactRoot)" -ForegroundColor Green
    } else {
        $result = Set-CleanSightOutputRoot -Path $Path
        Write-Host "已保存产物目录: $($result.ArtifactRoot)" -ForegroundColor Green
        Write-Host "配置文件: $($result.ConfigPath)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Show-CleanSightOutputRootState
