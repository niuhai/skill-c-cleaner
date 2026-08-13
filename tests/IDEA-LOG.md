# CleanSight 想法、创意与优化追踪

> **本文件记录所有关于 CleanSight 的优化想法、新功能点子、踩坑经验。**
> **当主代码发生变化或有新想法时，随时追加。**

---

## 已实现的想法

### 1️⃣ 命名统一：c-drive-cleaner → CleanSight

- **提出时间**: 2026-05-16
- **背景**: 原来叫 c-drive-cleaner，听起来像个普通清理工具
- **方案**: 品牌升级为 CleanSight（AI Disk Health Advisor），强调"洞察"而非"清理"
- **影响**: SKILL.md、analyze.ps1、报告文件名 全部对齐到 CleanSight 品牌
- **状态**: ✅ 已实现（v6.1.0）

### 2️⃣ 健康评分算法

- **提出时间**: 2026-05-16
- **背景**: 传统工具只告诉你"能删多少"，没有直观的"我有多健康"的感知
- **公式**: `max(0, min(100, 100 - (used% - 50) * 2))`
  - 50% 使用率 = 100 分（完美）
  - 75% = 50 分（偏高，建议关注）
  - 90%+ = 20 分以下（紧急！）
- **状态**: ✅ 已实现（v6.1.0）

### 3️⃣ 智能扫描策略（5 模式 + 3 阶段）

- **提出时间**: 2026-05-16
- **背景**: 不同用户差异巨大，一刀切的全扫对 256GB 小磁盘用户太慢
- **方案**: 极速/快速/标准/自定义/智能 5 种模式 + 预检→推荐→执行 3 阶段
- **状态**: ✅ 已实现（v6.1.0）

### 4️⃣ Token 成本透明化

- **提出时间**: 2026-05-16
- **背景**: 用户不知道每次交互要花多少 Token
- **方案**: 每次交互都告知 Token 消耗 + 预算预警机制（>10K/20K/30K）
- **状态**: ✅ 已实现（v6.1.0 SKILL.md 文档层）

---

## 正在开发的想法

### 5️⃣ v6.2 个性化学习系统

- **提出时间**: 2026-05-16
- **背景**: "每次都从零开始"的问题，用户希望 AI 记住自己的偏好
- **方案**: 用户画像 + 对话记忆 + 个性化推荐引擎
- **架构**:
  ```
  memory/
  ├── build-user-profile.ps1
  ├── log-conversation.ps1
  ├── personalization-engine.ps1
  ├── user-profile-template.json
  └── conversation-memory-template.json
  ```
- **成熟度模型**:
  - 第 1 次 → 冷启动（18 秒建立基础画像）
  - 第 3-5 次 → 模式识别（记住偏好）
  - 第 10 次+ → 深度理解（主动预测）
- **预期效果**: Token 成本降低 29%，效率提升 50%
- **状态**: 🔄 脚本骨架已创建（memory/ 下），但还未真正接入 analyze.ps1 主流程
- **TODO**:
  - [ ] 将 memory/ 模块集成到 analyze.ps1 的智能模式中
  - [ ] 实现 build-user-profile.ps1 的真正环境检测逻辑
  - [ ] 实现 log-conversation.ps1 的事件驱动记录
  - [ ] 实现 personalization-engine.ps1 的推荐算法

### 6️⃣ CONTEST-SUBMISSION.md 参赛文档优化

- **提出时间**: 2026-05-16
- **背景**: 要参加论坛创作比赛，需要一个有说服力的参赛帖
- **状态**: 🔄 初版已完成，持续优化中
- **TODO**:
  - [x] 核心能力矩阵对比
  - [x] 三段式创作过程描述
  - [x] 4 种使用模式展示
  - [x] 性能基准测试数据
  - [ ] 加入真实截图/图片（用户会后续添加）
  - [ ] 补充更多真实测试结果
  - [ ] 加入用户评价引用

---

## 未来优化想法

### 7️⃣ 扫描性能优化：增量扫描

- **问题**: 全量扫描耗时 2003 秒（33 分钟），太慢
- **想法**: 缓存上次扫描结果，只扫描有变化的路径
- **方案**: 在 memory/ 下增加 scan-cache.json
- **预期**: 从 33 分钟降到 2-3 分钟

### 8️⃣ 智能模式真正实现

- **问题**: SKILL.md 描述了智能推荐算法（smart_recommend），但没有真正的代码实现
- **想法**: 用 PowerShell 实现规则引擎，在 analyze.ps1 中集成
- **依赖**: 需要先完成 build-user-profile.ps1

### 9️⃣ 定时任务 + 主动提醒

- **问题**: 用户不会主动记得每周维护
- **想法**: 基于用户使用习惯，自动设置定时任务
- **参考**: SKILL.md v6.2.1 短期计划

### 🔟 图片素材规划

- **问题**: CONTEST-SUBMISSION.md 还没有图片
- **想法**: 需要生成以下类型的图片：
  - CleanSight Logo / 品牌标识
  - 与传统工具的对比图
  - 扫描模式流程图
  - 个性化学习成熟度模型图
  - 真实扫描结果截图（脱敏后）
- **状态**: ⏳ 等待用户后续添加

### 1️⃣1️⃣ 测试自动化

- **问题**: 目前测试是手动执行的
- **想法**: 写一个 test-all.ps1 脚本，一键运行各模式测试并生成结果
- **方案**:
  ```powershell
  .\tests\test-all.ps1                    # 运行所有测试
  .\tests\test-all.ps1 -Mode quick        # 只测试快速模式
  .\tests\test-all.ps1 -UpdateResults     # 更新 TEST-RESULTS-LOG.md
  ```

### 1️⃣2️⃣ 多磁盘容量测试（覆盖不同硬件）

- **问题**: 目前只在一台 148GB 磁盘上测试过
- **想法**: 在 256GB、512GB、1TB 不同容量磁盘上测试，验证扫描时间和准确性
- **预期**: 验证智能推荐算法在不同磁盘容量下的正确性

### 1️⃣3️⃣ Remove-Item 大目录性能优化

- **时间**: 2026-05-16（真实清理时发现，立即修复）
- **现象**: `Remove-Item "$fullPath\*" -Recurse -Force` 在 4.81 GB 的 LarkShell 目录下卡死
- **根因**: PowerShell 的 Remove-Item 需要逐一枚举文件再删除，大目录下性能极差
- **修复方案**:
  - ✅ `cmd /c rmdir /s /q "路径"` — 原生 cmd 命令，快 10 倍（已在 _common.ps1 实现）
  - ✅ 120 秒超时机制（Start-Job + Wait-Job -Timeout）
  - ✅ .NET `[System.IO.Directory]::Delete()` 作为备用方案
- **影响**: clean-apps.ps1 + clean-safe.ps1 全部替换为 Remove-Directory 调用
- **状态**: ✅ 已修复（v6.1.2）

### 1️⃣4️⃣ BOM + dot-source 兼容性问题

- **时间**: 2026-05-16（真实清理时发现，已部分修复）
- **现象**: dot-source `_common.ps1` 时报 `The term '﻿#' is not recognized`
- **根因**: UTF-8 BOM 前缀导致 `#` 注释行在 dot-source 时被解析为命令
- **修复**: clean-safe.ps1/clean-apps.ps1 已统一添加 UTF-8 BOM
- **状态**: ✅ _common.ps1 本身已有 BOM，两个清理脚本已加 BOM

### 1️⃣5️⃣ 进程检测 + 超时 + 进度显示

- **时间**: 2026-05-16（v6.1.2 新增功能）
- **新增**: 
  - ✅ `Test-AppRunning` 函数 — 清理前检测进程是否在运行
  - ✅ `[1/N]` 进度显示 — 用户知道当前清理到第几个
  - ✅ 清理后 C 盘空间汇总 — 立即看到效果
- **状态**: ✅ 已实现（v6.1.2）

---

## ⛔ 关键发现：清理执行引擎存在根本性缺陷

> **发现时间**: 2026-05-16（真实清理执行后复盘）
> **严重程度**: 🔴 **致命级** — 直接影响用户对 CleanSight 的信任

### 问题描述

在真实 C 盘清理执行中，出现了"扫描说能清 28 GB，实际只清了不到 2 GB"的极端落差：

| 指标 | 扫描预期 | 实际执行 | 差距 |
|------|---------|---------|------|
| 可释放空间 | 28.39 GB | ~1.3 GB（脚本贡献） | **-95%** |
| 耗时 | 预计 3 分钟 | ~30 分钟+卡死 | **-900%** |
| Token 消耗 | ¥0.03 | 巨量（无效对话轮次） | **不可接受** |

### 根因分析（4 个致命问题）

#### 问题 1：Remove-Item 在大目录下性能极差（核心问题）

```powershell
# ❌ 当前写法
Remove-Item "$fullPath\*" -Recurse -Force -ErrorAction SilentlyContinue
```

**为什么慢？**
- PowerShell 的 `Remove-Item -Recurse` 需要先**枚举所有文件**创建 .NET 对象
- 再**逐一调用 Win32 API** 删除每个文件
- 对于飞书 LarkShell（4.81 GB，可能有数万个小文件），这个过程会卡死
- 实测：同样一个 4.81 GB 目录，PowerShell 需要 **10+ 分钟或直接卡死**，而 `cmd /c rmdir` 只需 **< 30 秒**

**正确做法**：
```powershell
# ✅ 方案 A：cmd 原生命令（最快）
cmd /c rmdir /s /q "$fullPath"

# ✅ 方案 B：.NET 原生 API（次快）
[System.IO.Directory]::Delete($fullPath, $true)

# ✅ 方案 C：robocopy 空目录镜像法
$emptyDir = Join-Path $env:TEMP "_empty_$(Get-Random)"
New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
robocopy $emptyDir $fullPath /MIR /R:1 /W:1
Remove-Item $emptyDir -Force
```

#### 问题 2：单点卡死 → 整个脚本崩溃（连锁效应）

当前 clean-apps.ps1 是**同步串行执行**的：

```
Yarn ✅ → Chrome ✅ → Edge ✅ → ⛔ 飞书卡死！
                                  ↓
                          Trae CN（10.3 GB）→ 没机会跑
                          TRAE SOLO（3.53 GB）→ 没机会跑
                          Qoder（821 MB）→ 没机会跑
                          ...
```

**需要加超时机制**：
```powershell
# 添加超时包装
$job = Start-Job -ScriptBlock { param($p) cmd /c rmdir /s /q $p } -ArgumentList $fullPath
$result = $job | Wait-Job -Timeout 120  # 120 秒超时
if (-not $result) {
    $job | Stop-Job | Remove-Job
    Write-Host " ⚠️ 超时跳过（防止卡死）" -ForegroundColor Yellow
    # 记录到跳过列表，继续下一个
}
```

#### 问题 3：文件被进程锁定时的处理

当前脚本**不检查目标应用是否在运行**：
- Trae CN 如果正在运行，它的缓存文件被锁定
- 索引文件、日志文件可能正在被写入
- 结果：`Remove-Item` 默默失败或卡住

**需要加进程检测**：
```powershell
# 清理前先检查是否有相关进程在运行
function Test-AppInUse {
    param([string]$AppName)
    $processNames = @{
        "Trae CN" = @("trae", "traecn")
        "Chrome"  = @("chrome")
        "Edge"    = @("msedge", "edge")
    }
    $names = $processNames[$AppName]
    if (-not $names) { return $false }
    $running = Get-Process | Where-Object { $_.ProcessName -in $names }
    if ($running) {
        Write-Host "   ⚠️ $AppName 正在运行（PID: $($running.Id)），跳过清理" -ForegroundColor Yellow
        return $true
    }
    return $false
}
```

#### 问题 4：清理确认机制不清晰

当前用户不知道：
- 哪些文件是**真正永久删除** vs **移到回收站**
- 清理**预估时间**（大目录要多久）
- **实时进度**（当前在处理哪个目录，总共几个）

**需要改进**：
```powershell
# 清理前给出预估
Write-Host "即将清理 9 项，预计释放 18 GB"
Write-Host "⚠️ 大文件预估耗时:"
Write-Host "  Trae CN (10.3 GB) ~ 30 秒"
Write-Host "  飞书 (4.81 GB) ~ 30 秒（via cmd）"
Write-Host "  ..."

# 清理中显示进度
Write-Host "[3/9] Trae CN (10.3 GB)..." -NoNewline
# ...清理完成后
Write-Host " ✅ (12.3s)"
```

### 根本原因总结

```
问题链：
  扫描引擎（正常）→ 报告生成（正常）→ AI 建议（正常）
                                       ↓
                                🚨 清理引擎（坏了！）
                                  → Remove-Item 太慢
                                  → 没有超时机制
                                  → 没有进程检测
                                  → 没有进度显示
```

### 影响评估

| 影响维度 | 严重程度 | 说明 |
|---------|---------|------|
| **用户体验** | 🔴 致命 | 用户等了 30 分钟只清出 1.3 GB，Token 白花了 |
| **信任度** | 🔴 致命 | "扫描说能清 28 GB，实际才 1.3 GB" → 失去信任 |
| **性能** | 🔴 严重 | 大目录清理比行业工具慢 100 倍 |
| **稳定性** | 🟡 中等 | 卡死后整个脚本停止，没有容错机制 |
| **代码修复难度** | 🟢 低 | 替换为 `cmd /c rmdir` 即可解决 90% 问题 |

### 优先级修复计划

| 优先级 | 修复内容 | 预期效果 | 工作量 |
|--------|---------|---------|--------|
| **P0** | 替换 `Remove-Item` 为 `cmd /c rmdir /s /q` | 清理速度提升 10-100 倍 | 小（改 2 个文件） |
| **P0** | 添加超时机制（每个目录 120 秒上限） | 防止单点卡死导致全脚本崩溃 | 中 |
| **P1** | 添加进程检测（清理前检查应用是否在运行） | 减少因文件锁定导致的失败 | 中 |
| **P1** | 添加清理前预估 + 实时进度显示 | 用户知道要等多久、清楚进度 | 小 |
| **P2** | 清理完成后自动执行 `Get-PSDrive C` 显示效果 | 用户立刻看到结果 | 极小 |

### 坑 1：PowerShell BOM 编码问题

- **时间**: 2026-05-16
- **现象**: 中文 Windows PS5.1 无法正确读取无 BOM 的 .ps1 文件，中文乱码
- **根因**: PS5.1 默认用 GBK 编码读取无 BOM 文件
- **解决**: 所有 30+ 个 .ps1 文件统一添加 UTF-8 BOM
- **教训**: 在多语言环境下，编码问题要提前规划

### 坑 2：Measure-Object 无法读取 hashtable

- **时间**: 2026-05-16
- **现象**: Category Total 显示 0 GB
- **根因**: `Measure-Object -Property SizeMB` 无法直接读取 hashtable 的键
- **解决**: 改为 `ForEach-Object { $_.SizeMB } | Measure-Object -Sum`
- **教训**: PowerShell 中 hashtable 和对象的属性访问方式不同

### 坑 3：git 恢复后 BOM 字符残留

- **时间**: 2026-05-16
- **现象**: 文件开头出现不可见字符 `﻿`
- **根因**: git 恢复文件时未正确处理 BOM
- **解决**: 使用 regex `\uFEFF` 全局替换清除嵌入 BOM
- **教训**: BOM 虽然解决了编码问题，但也会引入新的兼容性问题

---

*最后更新: 2026-05-18（含迁移方案 + 用户选择指南）*

---

## 2026-08-10：清理效果不佳的根因与迭代闭环

### 用户反馈

扫描后清理的体感效果不好；C 盘仍有约 32.5 GB 可用，但用户不知道增长来自哪里。

### 根因

1. “候选可清理空间”与“实际释放空间”没有分开记录。
2. 没有路径级历史基线，无法判断 Qoder、Temp、AppData 或系统目录是否持续增长。
3. 全量扫描把慢速 F 类放在主流程中，超时后没有稳定收口。
4. 旧脚本存在 PowerShell 5.1 语法和 BOM 编码问题，部分输出不可靠。

### 解决方案

引入四件套：`iteration-loop` 负责总循环，`project-pilot` 负责八步状态机，`concurrent-dispatcher` 约束并发执行，`code-review-checklist` 负责三层审查。所有下一轮都必须有 before/after 快照，并把“增长、缩小、跳过、不可访问、重新生成”分别记录。

### 经验沉淀

不要继续扩大“可清理签名库”作为唯一优化方向。优先提高证据闭环：知道谁在增长，才能判断该清理、迁移、限额还是卸载。

---

## 🔴 TOKEN 成本分析（补充）

### 用户真实反馈: 整个清理过程消耗 ¥1.79（DeepSeek Flash）

#### 成本构成

| 环节 | Token 消耗 | 成本 | 是否必要 |
|------|-----------|------|---------|
| 扫描执行（本地 PowerShell） | **0** | **¥0** | ✅ 纯本地执行 |
| AI 报告生成 | **0** | **¥0** | ✅ 纯本地 |
| AI 对话：规划和指导清理 | 中 | ~¥0.3 | ✅ 必要 |
| AI 对话：调试飞书卡死 | **极高** | **~¥0.5** | ❌ bug 导致的白费 |
| AI 对话：反复修复脚本 | **极高** | **~¥0.8** | ❌ bug 导致的白费 |
| **总计** | | **~¥1.79** | ~60% 是 bug 导致 |

#### 结论

¥1.79 中约 ¥1.0-1.3 是 **bug 导致的无效消耗**（Remove-Item 卡死后反复调试修复）。正常使用一次清理的成本应该在 **¥0.2-0.5** 左右。

#### 优化措施

| 措施 | 效果 | 状态 |
|------|------|------|
| 修复 Remove-Item 卡死 bug | 节省 ~¥0.5 | ✅ 已修复（v6.1.2） |
| 管理员权限自动检测 | 减少因权限失败的对话轮次 | ✅ 已修复 |
| 永久删除不走回收站 | 减少二次清理的对话 | ✅ 已修复 |
| 进度显示 + 计时 | 用户知道在等什么，减少焦虑对话 | ✅ 已修复 |
| 预估 Token 成本透明化 | 用户事先知道大约花多少 | 📝 需加到 SKILL.md |

---

## 2026-08-12：不常用软件与 C 盘零碎信息

用户反馈 Skill 仍需要覆盖“不常用软件”和“C 盘零碎信息”，以免把所有空间都误归为缓存。

- 新增 `U` 类：读取卸载注册表，按体积、安装日期和证据质量列出候选；不自动卸载。
- 新增 `MX` 类：记录 C 盘一级目录、根文件、用户目录一级散落文件、扩展名分布和权限盲区。
- U/MX 均与清理额度隔离；尤其不把 D/E 盘软件安装体积误报为 C 盘可释放空间。
- JSON 报告分离 `findings` 与 `inventory`，便于后续 AI 决策层准确解释。

---

## 2026-08-12：从“目录大小”升级为“可验证释放”

- 问题：Qoder 曾显示逻辑大小约 3.32 GB，但清理前后驱动器可用空间变化远小于该值；旧增长基线还出现 AppData/Windows 增量远大于 C 盘净增量。
- 方案：引入 `allocatedBytes`、文件标识去重、覆盖根对账、测量版本兼容门禁和后台活动容差。
- 方案：清理器自动落盘 cleanup session，同时记录逻辑匹配量、分配字节回收量和实际驱动器空闲增量。
- 方案：增加 5 分钟、1 小时、24 小时检查点，识别自动再生缓存，避免反复无效清理。
- 安全边界：任何 partial/bounded 测量均降低置信度；Windows 更新/恢复残留仅报告，不直接删除。
