# CHANGELOG — CleanSight 版本变更记录

| 版本 | 日期 | 关键词 | 规模 |
|------|------|--------|------|
| v6.5.0 | 2026-08-13 | 原生并发扫描、同遍增长聚合、精确去重 | ⚡ Minor |
| v6.4.1 | 2026-08-12 | 原生大文件扫描初版 | ⚡ Patch |
| v6.4.0 | 2026-08-12 | 定向优化、实际占用、增长再生、虚拟内存 | 📐 Minor |
| v6.3 | 2026-05-18 | 清理引擎深度优化 | ⚡ Hotfix |
| v6.1.2 | 2026-05-16 | 清理引擎性能修复 | ⚡ Hotfix |
| v6.1.0 | 2026-05-16 | 生产级重构 | 🏭 Major |
| v6.0.0 | 2026-05-13 | AI 决策层 | 🧠 Major |
| v4.1.0 | 2026-05-12 | 扩展性系统 | 🔌 Minor |
| v4.0.0 | 2026-05-12 | 文件组架构 | 🏗️ Major |
| v3.0.0 | 2026-04-02 | 四维深度分析 | 📊 Major |
| v2.0.0 | 2026-04-01 | 结构化报告 | 📋 Minor |
| v1.0.0 | 2026-04-01 | 初始版本 | 🚀 Initial |

---

## v6.5.0 (2026-08-13) — ⚡ 高性能扫描与可信核算

- 新增 Win32 `FindFirstFileExW` 原生扫描器，将 Users/AppData、Windows、ProgramData 和 Program Files 拆成有界并发分片；跨分片用户目录统计统一合并。
- F 类在同一遍约 58 万文件枚举中同时生成 TOP 20、用户一级目录大小和 37 个增长目标统计，不再为 GR 重扫父子目录。
- 快速模式读取带时间戳和 `measurementSource` 的增长快照；GR 从 114.9 秒降到 0.2 秒，完整 F→GR 复用时约 0.5 秒。
- 重写 J 类 Electron/CEF 盘点，拆分 Microsoft/Google/Tencent 厂商容器；整个应用体积和 runtime-shaped 字节只进入 inventory，不进入可清理额度。
- 应用签名只核算 `sub_cleanable` 精确子路径；Search 索引负担只作为优化线索；最终清理总量按路径层级去重。
- 增加逐分类耗时、文件数、分区数、跳过目录、缓存命中和 JSON scanner metadata，便于后续持续优化。
- 本机验证：F 从约 111 秒降到 14.9–36.2 秒；`analyze.ps1 -Fast` 从 153.6 秒降到 26.6 秒；全程只读，未删除数据。

---

## v6.4.1 — F scanner performance

- Replaced the PowerShell `Get-ChildItem -Recurse` large-file scan with an in-process .NET directory enumerator.
- Maintains a bounded TOP-N candidate set, skips reparse-point directories, and continues through inaccessible folders while reporting skip counts.
- Keeps protected Windows trees out of the file-level scan because A/WU/SA already provide their directory-level evidence.
- Real-machine validation: 504,251 files in about 97 seconds for TOP 20; no files were modified.

## v6.4.0 (2026-08-12) — 📐 可验证空间核算

- 新增 Qoder、WorkBuddy、Codex 定向扫描与清理配置；默认预览，保留工作区、历史、全局状态、当前 runtime 和模型文件。
- 新增进程占用检查、允许目录边界校验与风险分级，降低误删风险。
- 强化虚拟内存分析：区分配置上限、实际占用、提交容量和 I/O 性能；不把迁移页面文件描述为必然提速。
- 新增 NTFS 分配字节测量，按文件标识去重硬链接，并标记稀疏/压缩文件和部分读取状态。
- 将增长目标分为互不重叠的 `coverage` 根和仅用于归因的 `detail` 项，避免父子目录重复相加。
- 升级增长快照为 schema 2；旧版测量基线自动失效，不产生伪增量。
- 新增 Trae、TRAE SOLO、LarkShell、WPS、Temp、Playwright、剪映、updater、Windows Update 等应用级追踪。
- 新增 WU 类和 `$WinREAgent`、更新下载、待重启信号检查。
- 定向清理记录目标分配字节与 C 盘真实可用空间变化，并支持 5m/1h/24h 再生复测。
- 移除脚本中的固定本机安装路径，按脚本位置和环境变量解析。

---

## v6.3 (2026-05-18) — ⚡ 清理引擎深度优化（Timeout + robocopy 回退 + 慢速扫描消除）

### 🔴 根因：虽然 v6.1.2 将 `Remove-Item` 换为 `cmd /c rmdir`，但仍有 3 个隐患

#### Bug 1: `& cmd /c` 同步阻塞无超时（P0）
- **问题**: `Remove-Directory` 直接 `& cmd /c "rmdir /s /q"`，如果 rmdir 卡住，脚本永久阻塞
- **修复**: 改用 `System.Diagnostics.Process.Start()` + `WaitForExit(120s)` 带超时控制
  - 120 秒内未完成 → `$p.Kill()` 终止进程 → 进入回退方案
  - 旧方案: `& cmd /c`（无超时，一旦卡死全脚本崩溃）
- **代码**: `_common.ps1:Remove-Directory`

#### Bug 2: .NET `[System.IO.Directory]::Delete()` 回退仍然慢（P1）
- **问题**: 当 `cmd /c rmdir` 失败时，回退方案 `.NET API` 同样需要枚举所有文件，大目录下依然慢
- **修复**: 改用 `robocopy $emptyDir $Path /MIR` 清空内容，再用 `rmdir` 删除空目录
  - robocopy 是 Windows 原生复制引擎，跳过被锁文件，速度比 .NET Delete 快数倍
  - .NET API 保留为最后手段（方案 C）
- **代码**: `_common.ps1:Remove-Directory`

#### Bug 3: 清理前扫描仍用 `Get-ChildItem -Recurse` 算大小（P1）
- **问题**: `clean-dev-caches.ps1` 和 `clean-deep.ps1` 在删除前用 `Get-ChildItem -Recurse` 计算目录占用
  - 这和 `Remove-Item` 一样，需要先枚举全部文件，大目录下极慢
- **修复**: 全部替换为 `Get-FolderSizeFast`（基于 `robocopy /L /S /BYTES`，快 10-100 倍）
- **受影响的脚本**:
  - `clean-dev-caches.ps1` — Clean-Cache 函数 + NuGet 段 + Maven 段（共 4 处）
  - `clean-deep.ps1` — Windows 更新缓存段（1 处）

### ✅ 优化后状态

| 维度 | v6.1.2 | v6.3 | 提升 |
|------|--------|------|------|
| 删除主方案 | `& cmd /c rmdir`（无超时） | `Process.Start()` + 120s 超时 | ✅ 不再阻塞 |
| 删除回退方案 | `.NET Delete`（慢） | `robocopy /MIR`（快数倍） | ✅ 10x+ |
| 最后手段 | 无 | `.NET Delete` 保留 | ✅ 三层保障 |
| 清理前扫描 | `Get-ChildItem -Recurse` | `Get-FolderSizeFast`（robocopy） | ✅ 10-100x |
| 所有清理脚本 | 2 个脚本用慢扫描 | 全部统一高性能 | ✅ 统一 |

### 📝 涉及文件

| 文件 | 变更 |
|------|------|
| `_common.ps1` | `Remove-Directory` 重写：超时+回退+最后手段三层策略 |
| `cleaners/clean-dev-caches.ps1` | 4 处 `Get-ChildItem -Recurse` → `Get-FolderSizeFast` |
| `cleaners/clean-deep.ps1` | 1 处 `Get-ChildItem -Recurse` → `Get-FolderSizeFast` |

---

## v6.1.2 (2026-05-16) — ⚡ 清理引擎性能紧急修复（Clean Engine Overhaul）

### 🔴 根因修复：清理引擎 4 个致命 bug

#### Bug 1: Remove-Item 大目录性能杀手（P0）
- **问题**: `Remove-Item "$Path\*" -Recurse -Force` 在大目录下比 `cmd /c rmdir` 慢 10-100 倍
  - 飞书 LarkShell 4.81 GB 目录清理卡死 30 分钟
  - 而 `cmd /c rmdir /s /q` 只需 < 30 秒
- **修复**: 新增 `Remove-Directory` 函数到 `_common.ps1`
  - 优先使用 `cmd /c rmdir /s /q`（job 内执行，不阻塞主线程）
  - 120 秒超时自动跳过（防止单点卡死）
  - .NET `[System.IO.Directory]::Delete()` 作为备用方案
  - 实时计时显示（`✅ (12.3s)`）
- **受影响的脚本**: `clean-apps.ps1`（3 处）、`clean-safe.ps1`（所有 Safe-Clean 调用）

#### Bug 2: 单点卡死导致全脚本崩溃（P0）
- **问题**: 飞书卡死后，Trae CN（10.3 GB）等更大的项根本没机会清理
- **修复**: 每个目录有独立的 120 秒超时，超时自动跳过，继续下一个
  - `Start-Job` + `Wait-Job -Timeout 120` 实现

#### Bug 3: 文件被进程锁定时无检测（P1）
- **问题**: 不检查目标应用是否在运行，锁定文件导致 Remove-Item 卡住
- **修复**: `clean-apps.ps1` 新增 `Test-AppRunning` 函数
  - 清理前检测对应进程（Chrome/Edge/Trae/飞书等）
  - 进程中时显示警告并跳过

#### Bug 4: 清理确认机制不清晰（P1）
- **问题**: 用户不知道要等多久、清了多少、进度如何
- **修复**: 
  - 进度显示: `[1/3] [2/3] [3/3]`
  - 清理前提示: "即将清理 3 项，预计释放 15.81 GB"
  - 清理后显示: "C盘当前: 130.93 GB / 148.91 GB (剩余 17.98 GB, 87.9%)"

### 🐛 其他修复
- **clean-safe.ps1 编码修复**: 添加 UTF-8 BOM，修复中文显示乱码
- **clean-safe.ps1 权限错误**: `Test-Path` 添加 `-ErrorAction SilentlyContinue`，避免系统保护路径报错
- **2 个新文件+1 个修改**: `_common.ps1` 新增 42 行 `Remove-Directory`，`clean-apps.ps1` 和 `clean-safe.ps1` 完全重写

### 📊 性能提升预期
| 场景 | 修复前 | 修复后 | 提升 |
|------|--------|--------|------|
| 清理 4.81 GB 飞书 | ❌ 卡死（>30分钟） | ✅ ~30 秒 | **60x+** |
| 清理 10.3 GB Trae CN | ❌ 没机会跑 | ✅ ~60 秒 | **∞** |
| 清理 15.81 GB (3项) | ❌ 飞书卡死后全崩 | ✅ ~3 分钟完成 | **∞** |

### 🧪 新增 tests/ 测试评测文件夹
- **创建完整测试体系**: `tests/` 目录，与 CONTEST-SUBMISSION.md 同步维护
- **TEST-RESULTS-LOG.md**: 记录真实扫描测试结果（基于 3 次实际扫描数据）
- **IDEA-LOG.md**: 记录优化想法、踩坑经验、TODO 清单（12 个已实现/开发中/未来想法）
- **methodology/test-strategies.md**: 各模式的测试方法和验收标准
- **scenarios/all-scenarios.md**: 按场景组织的测试结果（5 个真实场景）
- **performance/benchmark-history.md**: 性能基准历史追踪

### 📝 CONTEST-SUBMISSION.md 同步更新
- 加入真实扫描验证数据（148.91 GB 磁盘，91.7% 使用率，28.39 GB 可释放）
- 诚实标注 v6.2 memory/ 系统状态（骨架完成，待接入主流程）
- 文件结构新增 tests/ 目录引用
- 版本分化说明：稳定版 v6.1.0 / 开发版 v6.2.0

## v6.1.0 (2026-05-16) — 🏭 生产级重构（Production Ready）

### 🏷️ 品牌升级
- **品牌名**: `c-drive-cleaner` → **CleanSight** (AI Disk Health Advisor)
- **报告命名**: `report_YYYYMMDD_HHMMSS.md` → `CleanSight-CS-YYYYMMDD-HHMMSS-{score}.md`
  - 格式: 品牌 + 日期时间 + 健康评分
- **版本统一**: SKILL.md / analyze.ps1 / app-signatures.json 全部对齐到 v6.1.0

### 🔧 核心引擎重写 (analyze.ps1)
- **完全重写**: 从 7830 行旧版 → 全新生产级引擎
- **新增 `-Template` 参数**: 支持 `-Template v6-ai-decision` 模板选择
- **修复 SizeMB 兼容性**: hashtable 属性访问从 `Measure-Object SizeMB` 改为 `ForEach-Object { $_.SizeMB } | Measure-Object -Sum`
  - 修复 analyze.ps1 中 4 处 + scan-security-software.ps1 中 1 处
- **修复 PowerShell 反引号转义**: 报告中代码块 ``` 使用变量拼接避免解析错误
- **健康评分算法**: `max(0, min(100, 100 - (used% - 50) * 2))`

### 📝 SKILL.md 精简重写
- **588 行 → 198 行** (-66%): 砍掉冗余营销内容，保留核心信息
- 新增: 三大核心优势对比表、AI vs 传统工具矩阵、报告命名规范、维护规范章节
- 新增: AI Agent Skill 工程化标准（版本管理/更新流程/兼容性要求/测试验证）
- 保留: 安全原则/架构图/扫描类别速查/扩展性说明

### 📊 报告系统全面升级
- **删除旧模板**:
  - ~~`report-template.md`~~ (v4 遗留)
  - ~~`sample-report-v6-ai-decision-full.md`~~ (1500行假数据)
  - ~~`report-template-v6-ai-decision.md`~~ (v6 初版)
- **全新内嵌报告模板** (analyze.ps1 内):
  - 执行摘要（健康评分 + 空间状态表）
  - 12 类别扫描明细（按 Category A-L 分组）
  - **AI 决策建议**（7项能力对比矩阵）
  - **Tier 1/Tier 2 分级行动清单**
  - **4 步使用指南**（含可执行命令）
  - **推荐工具组合**（CleanSight + WizTree + BleachBit + BCU 工作流）
  - **AI 对话问题示例**
  - 报告元信息

### 🐛 关键 Bug 修复

#### 编码问题 (Critical)
- **PowerShell BOM 编码**: 中文 Windows PS5.1 必须用 UTF-8 BOM 才能正确读取中文 .ps1 文件
  - 所有 30+ 个 .ps1 文件统一添加 UTF-8 BOM
  - 根因: PS5.1 默认用 GBK 编码读取无 BOM 文件，导致中文乱码和首行注释无法识别
- **BOM 字符清理**: 修复 git 恢复后残留的多余 BOM 字符 (`﻿`)
  - 使用 regex `\uFEFF` 全局替换清除嵌入 BOM

#### 数据计算问题 (High)
- **Category Total 显示 0 GB**: `Measure-Object -Property SizeMB` 无法读取 hashtable 的键
  - 改用 `ForEach-Object { $_.SizeMB } | Measure-Object -Sum`
- **scan-security-software.ps1 同样问题**: 同步修复

#### 文件恢复事故 (Lesson Learned)
- fix-bom.ps1 脚本因 `Replace` 方法参数类型错误导致文件被清空
- 通过 `git checkout --` 成功恢复所有文件
- 教训: 批量操作前必须先 git commit 或备份

### ✅ 生产级质量验证
- **真实扫描通过**: 12 类别全量扫描，耗时 ~30 分钟
- **真实数据报告生成**: CleanSight-CS-20260516-140534-17.md (252 行)
  - 健康评分: 17/100 (CRITICAL)
  - 可安全释放: 28.11 GB
  - 需确认: 30.68 GB
  - 总扫描占用: 59.37 GB

---

## v6.0.0 (2026-05-13) — 🧠 AI 决策层（现象级升级）

### 🎯 核心定位变革
- **从"清理工具集"升级为"AI 磁盘健康决策顾问"**
- 新的使命：不是帮你打扫，而是**教你如何管理系统空间 + 根据你的情况做最优决策**
- 明确差异化：AI Decision Layer vs 传统工具（CCleaner/BleachBit/WizTree）

### 📝 全新文档体系
- **SKILL.md 完全重写**（177行 → 588行，+232%）
  - 明确 AI 决策层定位和产品哲学
  - 详细的功能对比矩阵（12项能力对比）
  - 三大核心优势详解（上下文感知/动态风险评估/教育型输出）
  - 4个真实使用场景示例
  - 完整的用户旅程说明
  - 与开源工具的互补关系说明
  - 发展路线图（v6.0 → v8.0）

### 🎨 现象级报告系统（v6 AI Decision Edition）
- **新增 `report-template-v6-ai-decision.md`**：
  - **9大核心模块**（从执行摘要到总结闭环）
  - 混合布局设计（精简 + 可展开 `<details>`）
  - AI 决策透明化（每个建议包含：是什么/为什么/怎么做/风险/替代方案）
  - 场景化适配（开发者/普通用户/企业环境动态调整）
  
- **新增 `sample-report-v6-ai-decision-full.md`**：
  - 900+ 行精品示范报告
  - 基于真实的"全栈开发者"用户画像
  - 包含完整的模拟数据和真实的分析逻辑
  - 展示所有 9 个模块的最佳实践

### 🧠 AI 能力增强
- **用户画像自动识别**：检测用户类型（开发者/设计师/普通用户/企业）
- **智能决策算法**：多维加权评分（空间收益30% + 安全性40% + 易用性20% + 个人相关性10%）
- **风险动态评估**：不再是固定规则，而是基于使用场景的实时分析
- **预测性维护**：趋势预测 + 长期优化路线图
- **知识赋能模块**：FAQ（6个常见问题）+ 最佳实践 + 教程
- **对话式交互支持**：追问示例 + 个性化学习

### 🆚 差异化证明
- 传统工具对比矩阵（5个工具 × 12项能力）
- 真实场景对比（3个场景：npm缓存/C盘紧急/Docker咨询）
- 核心价值主张："建筑师 vs 施工队"比喻

### 📐 报告结构创新
| 模块 | 内容 | 价值 |
|------|------|------|
| 一、执行摘要 | 30秒速览：健康评分 + 快速行动方案 | ⚡ 快速决策 |
| 二、用户画像 | 用户类型识别 + 使用习惯 + 个性化分析 | 🎯 精准适配 |
| 三、深度扫描结果 | 12类别详细数据 + AI逐项建议 | 🔬 完整覆盖 |
| 四、AI智能决策矩阵 | 风险/收益分析 + 推荐排序算法 | 🧠 核心差异化 |
| 五、与传统工具对比 | 为什么选AI而非CCleaner | 🆚 差异化证明 |
| 六、完整执行计划 | 分阶段行动指南（含命令）| 📋 可执行性 |
| 七、知识赋能 | FAQ + 最佳实践 + 教程 | 🎓 长期价值 |
| 八、趋势预测 | 历史对比 + 未来预测 + 路线图 | 🔮 前瞻性 |
| 九、总结与下一步 | Top3行动 + 后续问题建议 | ✅ 闭环 |

### 🔒 安全原则强化
- 只读优先（Read-First）设计哲学
- 教育赋能（Empowerment Over Automation）
- 透明可解释（Explainable AI）
- 渐进式信任建立（Progressive Trust Building）

### 📊 数据支撑
- 示范报告展示：从85.4%使用率优化到68%（释放40GB）
- 分阶段执行计划：10分钟 → 1小时 → 周末（分布3天）
- 长期效益：每月避免4.5GB增长（减少78-89%增量）

### 🎓 文档质量提升
- SKILL.md 从技术导向转为**用户价值导向**
- 所有建议都包含**决策理由**（不只是怎么做，还有为什么）
- 增加**产品哲学**章节（5大设计原则）
- 提供**进阶功能**说明（对话式深度分析/个性化学习）

---

## v4.1.0 (2026-05-12) — 扩展性系统

### 🔌 扩展性架构
- **新增 `extensions/` 目录**: 实现数据与代码分离
- **`app-signatures.json`**: 90+ 应用签名数据库，覆盖 14 个类别（开发者工具/IDE/浏览器/IM/办公/输入法/安全/虚拟化/游戏/媒体/云存储/AI工具/流氓软件）
- **`user-custom.json`**: 用户自定义扩展模板，修改即生效，零代码变更
- **`scan-discover.ps1`**: 未知大文件夹发现引擎，自动扫描签名数据库未覆盖的文件夹，生成扩展建议
- **流氓软件识别**: `rogue_software` 类别收录 17 种常见国产捆绑软件（2345全家桶/快压/小鸟壁纸/Flash中国版等），自动标记 ⚠️ + 卸载建议

### 🔧 混合扫描升级
- `scan-im-apps.ps1`: 支持从 JSON 签名数据库加载额外 IM 应用
- `scan-ime-data.ps1`: 支持从 JSON 签名数据库加载额外输入法
- `scan-browsers.ps1`: 支持从 JSON 加载额外浏览器（360/QQ/搜狗等国产浏览器）
- `scan-dev-caches.ps1`: 支持从 JSON 加载额外开发工具（Android SDK/Unity等）
- `scan-app-data.ps1`: 支持从 JSON 加载媒体/办公/云存储/AI工具应用
- `scan-special-sources.ps1`: 支持从 JSON 加载虚拟化/游戏平台
- `scan-security-software.ps1`: 支持从 JSON 加载额外安全软件（360/腾讯管家等）
- 输出前缀 `[DB]` / `[自定义]` 区分来源

### 🐛 修复 (自查)
- `scan-duplicate-runtimes.ps1`: 修正 Trae CN 路径错误（`LocalAppData\Programs\TraeCN\` → `AppData\Trae CN\`），新增 TRAE SOLO CN 和 Qoder 检测
- `scan-large-files.ps1`: 排除更多受保护路径（Huorong/SF/Sangfor/NAC/SecurityCore等），避免权限错误
- 清理 6 个脚本中的死变量声明
- 修正 PowerShell 5.1 不兼容的三元表达式 (`scan-security-software.ps1`)
- `scan-im-apps.ps1`: 扩展钩子补全 PROGRAMFILES/PROGRAMDATA/DOCUMENTS 路径展开
- SKILL.md 标题版本号从 v4.0 修正为 v4.1

---

## v4.0.0 (2026-05-12) — 文件组架构 + 通用化 + 自动化

### 🏗️ 架构升级
- **从单文件 SKILL.md (897行) 重构为文件组架构**: 14个扫描脚本 + 3个清理脚本 + 3个迁移脚本
- SKILL.md 精简为约 100 行，作为决策层入口，描述工作流和各子文件
- 新增 `scanners/`, `cleaners/`, `migrators/`, `safety/`, `reports/`, `scheduled/` 六个子目录

### 🔍 新增扫描类别 (v4.0)
- **H类**: 安全软件/管控数据检测 — 火绒、深信服EDR/NAC、安全审计日志
- **I类**: 多版本软件共存检测 — Edge/WPS/Ingress/Node.js多版本残留
- **J类**: 重复Chromium/CEF/Electron运行时检测 — 识别5+应用内嵌独立浏览器
- **K类**: 输入法数据扫描 — 搜狗/微软拼音/百度/手心输入法
- **L类**: 即时通讯数据扫描 — 微信/QQ/钉钉/飞书/企业微信/Slack/Teams

### 🔧 扩展覆盖范围
- C类开发缓存: +conda, go mod, npx
- D类浏览器: +Firefox, Brave, Opera
- E类应用数据: +VS Code, AI IDE(Trae/Qoder/LobsterAI), 网易云音乐
- B类临时文件: +Delivery Optimization, Prefetch

### 🧹 新增清理脚本
- `clean-safe.ps1`: 安全自动清理(含WhatIf预览模式，加-ReallyDelete才执行)
- `clean-deep.ps1`: 深度清理(逐项Y/N确认)
- `clean-dev-caches.ps1`: 开发缓存清理(逐项确认)

### 📦 新增迁移脚本
- `migrate-dev-caches.ps1`: 一键迁移7种开发工具缓存(npm/pip/yarn/pnpm/cargo/gradle/go)
- `migrate-appdata-junction.ps1`: AppData符号链接迁移(robocopy+mklink /J+回滚)
- `migrate-wsl-docker.ps1`: WSL/Docker Desktop数据迁移指南

### 🛡️ 安全机制
- `snapshot-before-after.ps1`: 操作前后快照对比
- `backup-registry.ps1`: 操作前注册表备份
- `rollback-guide.md`: 误操作回滚指南
- 安全红线定义（9项禁止自动化的操作）
- 5级自动化体系 (Level 0~4)

### 🌐 通用化
- 所有路径变量化 ($env:USERPROFILE, $env:LOCALAPPDATA)
- 应用检测前置 (Test-Path → 不存在则跳过)
- 20+ 应用类别覆盖
- 多盘符支持 (默认D盘，可自定义)

### 📋 计划任务
- `weekly-cleanup.xml`: 每周日02:00安全清理
- `daily-monitor.ps1`: 每日空间监控(超阈值告警)

---

## v3.0.0 (2026-04-02) — 四维深度分析

### 📋 功能
- 智能删除建议 (✅推荐/⚠️谨慎/❌不建议)
- 迁移方案 (开发工具缓存迁移方法)
- 深度扫描 (大文件TOP N + 特殊占用源)
- 溯源分析 (为什么生成/为什么放C盘/迁移难度)

### 🔍 覆盖
- A类: 系统隐藏文件 (hiberfil, pagefile, 还原点, WinSxS)
- B类: 临时文件与缓存 (Windows Temp, 用户Temp, 缩略图, 回收站, Update缓存)
- C类: 开发工具缓存 (npm, pip, cargo, maven, gradle, nuget, yarn, pnpm, node-gyp)
- D类: 浏览器缓存 (Chrome, Edge)
- E类: 应用数据 (系统日志, JetBrains, 搜狗PDF)
- F类: 大文件TOP N
- G类: 特殊占用源 (Puppeteer, Docker, WSL, 根目录可疑文件)

---

## v2.0.0 — 结构化报告

### 📋 主要更新
- **报告模板系统**: 添加报告输出格式模板，统一扫描结果展示
- **迁移指南汇总**: 添加一键迁移指南，汇总开发工具缓存迁移方案
- **版本对比**: v1.0 vs v2.0 功能对比表，清晰展示演进路径

---

## v1.0.0 — 初始版本

### 🚀 首发功能
- **基础扫描引擎**: 实现对 C 盘垃圾文件的只读扫描分析
- **安全优先**: 仅分析不删除，确保用户数据零风险
- **覆盖类别**: 系统临时文件、浏览器缓存、开发工具缓存等常见占用源
