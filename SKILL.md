---
name: "c-drive-cleaner"
description: "AI驱动的C盘空间诊断与安全清理顾问。通过 NTFS 实际分配空间测量、父子目录去重、应用级增长与清理后再生追踪、Windows 更新残留、不常用软件和零碎空间盘点，定位空间为何增长及清理为何无效。当用户询问C盘空间不足、清理不动、可用空间未增加、缓存重新生成、想查不常用软件/大文件/隐藏占用、迁移数据或复盘清理效果时调用此技能。"
---

## 定向优化（O 类）

运行 `.\analyze.ps1 -Categories "O"` 扫描已知的高价值定向项：

- Qoder：只清理 `SharedClientCache\index`、`SharedClientCache\cache`、`CachedData` 等缓存；保留 `User\workspaceStorage`、`User\History` 和 `User\globalStorage`。
- WorkBuddy：只匹配 `%LOCALAPPDATA%\Temp\workbuddy-update-*` 更新残留；关闭 WorkBuddy 后再处理。
- Codex：只处理 `.cache\codex-runtimes` 下的 `codex-runtime-install-*` 与 `codex-primary-runtime.previous-*`；保留当前 `codex-primary-runtime`。Whisper 模型单独列为谨慎项。

使用 `.\cleaners\clean-targeted-optimization.ps1 -WhatIf` 预览，确认后追加 `-ReallyDelete`；脚本会检查相关进程并阻止越界路径。

如果目标本身或任意祖先目录是 junction/符号链接，C 盘扫描不得沿链接统计或清理。应报告为 `partial`；链接目标位于 D/E 盘时，删除只会释放目标盘空间。

## 不常用软件与 C 盘零碎信息

- `U` 类按安装日期、体积和证据质量列出“待确认候选”；快速模式只复用卸载注册表体积，完整模式仅为可能相关的 C 盘安装目录补测体积，不遍历 D/E 盘软件。它不能可靠知道最后使用时间，不自动卸载，也不建议直接删除安装目录。
- `MX` 类解释清理规则之外的空间：C 盘一级目录、根目录系统文件、用户目录一级散落文件、扩展名分布和权限盲区。MX 是信息层，结果之间可能重叠，不能把它们相加当成可释放空间。
- 详细边界和判定依据见 [`references/unused-and-misc.md`](references/unused-and-misc.md)。

## 实际占用与再生追踪

- 运行 `.\measure-space.ps1 -Paths "<精确路径>"` 比较目录项逻辑大小、硬链接去重后的逻辑大小和 NTFS 分配字节；慢速全量核算使用 `SA` 类。
- 运行 `.\track-growth.ps1 -Mode compare -Record` 建立层级化 v2 基线。只汇总互不重叠的 `coverage` 根；`detail` 只归因，不与父目录相加。
- 定向清理执行后读取清理会话给出的 SessionId，并在 5 分钟、1 小时、24 小时后运行 `.\track-regeneration.ps1 -Mode check -SessionId <id>`。
- 运行 `.\analyze.ps1 -Categories "WU"` 检查 `$WinREAgent`、Windows Update 下载、Delivery Optimization 和待重启信号。
- 管理员 PowerShell 中运行 `.\analyze.ps1 -Categories "AD"`，只读核算 VSS、WinSxS、WindowsApps、Installer、DriverStore 和 Reserved Storage；这些结果只进入 inventory，不计为可清理额度。详细边界见 [`references/admin-deep-accounting.md`](references/admin-deep-accounting.md)。
- 详细规则见 [`references/space-accounting-and-regeneration.md`](references/space-accounting-and-regeneration.md)。

## 四件套迭代闭环

本技能采用四层 Loop Engineering 机制，解决“扫描后清理效果不明显、空间持续增长但不知道来源”的问题：

- `references/iteration-loop.md`：总循环——多源发现 → 入池规划 → 执行 → 验证 → 沉淀 → 下一轮。
- `references/project-pilot.md`：项目级 PDCA，固定 8 步状态机并要求每一步有证据。
- `references/concurrent-dispatcher.md`：独立扫描/预览的并发调度规则，限制并发、隔离输出、避免重叠清理。
- `references/code-review-checklist.md`：改前契约、改后自检、里程碑外审三层门禁。

日常诊断使用：

```powershell
.\iteration-loop.ps1 -Mode diagnose -RecordGrowth
```

它默认不删除文件，只记录当前 C 盘和重点目录快照。下次运行会显示每个路径的增量和日增长速度；只有在快速证据不足时才追加 `-IncludeSlowScan`。

# CleanSight — AI Disk Health Advisor

**我不是清理工具，我是你的 AI 磁盘健康顾问。**

```
传统工具 = 执行层：帮你删文件（但不懂你）
CleanSight = 决策层：理解你 → 分析数据 → 智能建议 → 教你安全执行
```

---

## 💰 Token 成本预估（重要）

> **本技能的核心工作是纯本地的**：扫描（PowerShell）、分析逻辑、报告生成全部在本地运行，**不消耗 Token**。
>
> AI 对话轮次会消耗 Token（接入的模型费用），但这取决于你问了多少问题。

| 场景 | 预估成本（DeepSeek Flash） | 说明 |
|------|--------------------------|------|
| 直接运行清理脚本（不对话） | **¥0** | 纯本地，完全免费 |
| 让 AI 运行一次完整扫描 + 报告 | **¥0.05-0.1** | AI 解读报告，给建议 |
| 让 AI 指导执行清理 + 后续追问 | **¥0.1-0.3** | 正常使用范围 |
| 调试 bug + 反复修复 | **¥1.0+** | 异常情况，不应发生 |

> 💡 **省钱技巧**: 直接运行 `.\cleaners\clean-safe.ps1 -ReallyDelete` 或 `.\cleaners\clean-apps.ps1 -RiskLevel safe` 是完全免费的。

---

## 🧠 三大核心优势（为什么用 AI 而不是 CCleaner）

| 优势 | 传统工具 | CleanSight |
|------|---------|-----------|
| **上下文感知** | 固定规则，一刀切 | 基于你的使用习惯动态分析 |
| **动态风险评估** | 只说"能删/不能删" | 告诉你为什么 + 替代方案 + 迁移指导 |
| **知识赋能** | 删完就结束 | 教你根本解决方法，一劳永逸 |

**差异化公式**: `迁移 > 删除 > 忽略` — 传统工具只会删，AI 教你迁移保留功能的同时释放空间。

---

## 🔧 工作流程

```
用户触发 "C盘快满了" / "帮我分析C盘"
  ↓
1. 执行类别只读扫描 + 路径级增长快照（scanners/）
  ↓
2. 生成 AI 决策报告（健康评分 + Tier 分级建议 + 增长证据）
  ↓
3. 先预览和规划，不把“可清理”误报成“已释放”
  ↓
4. 用户选择执行项 → 执行 → 重扫同一路径 → 记录实际释放量
```

### 一键模式

```powershell
.\analyze.ps1                                          # 控制台输出
.\analyze.ps1 -OutputFormat markdown                   # 生成 Markdown 报告
.\analyze.ps1 -OutputFormat json                       # JSON 格式
.\analyze.ps1 -Categories "C,D"                        # 只扫描开发缓存+浏览器
.\analyze.ps1 -Fast                                     # 快速证据集；GR 读取带时间戳快照，跳过 F/H/MX/AD/SA
.\analyze.ps1 -Categories "F,GR" -RecordGrowth          # 原生全盘扫描并建立同源增长基线
.\track-growth.ps1 -Mode compare -Record               # 无 F 结果时的 robocopy 兼容基线
.\measure-space.ps1 -Paths "%APPDATA%\Qoder"          # 核算逻辑大小与 NTFS 分配字节
```

### 扫描类别速查

| 类别 | 脚本 | 覆盖 | 适用 |
|------|------|------|------|
| A-系统隐藏 | scan-system-hidden | hiberfil/pagefile/还原点/WinSxS | 了解即可 |
| B-临时缓存 | scan-temp-files | Temp/缩略图/回收站/Update缓存 | ✅ 日常首选 |
| C-开发缓存 | scan-dev-caches | npm/pip/cargo/maven/gradle等 | 开发者必看 |
| D-浏览器 | scan-browsers | Chrome/Edge/Firefox等 | 所有人 |
| E-应用数据 | scan-app-data | IDE/媒体/办公/AI工具 | 深度清理 |
| F-大文件 | scan-large-files | 原生并发 TOP 20 + 用户目录排行 + 增长聚合 | 快速定位 |
| G-特殊占用 | scan-special-sources | Docker/WSL/游戏平台 | 特殊需求 |
| H-安全软件 | scan-security-software | EDR/NAC/杀毒 | 仅了解 |
| I-多版本 | scan-multi-version | 多版本残留 | 整洁度 |
| J-重复运行时 | scan-duplicate-runtimes | Electron/CEF重复 | 高级优化 |
| K-输入法 | scan-ime-data | 词库/日志 | 细节清理 |
| L-即时通讯 | scan-im-apps | 微信/QQ/钉钉缓存 | 社交应用 |
| U-不常用软件候选 | scan-unused-software | 卸载注册表、安装时间、体积候选 | 只建议确认，不自动卸载 |
| MX-C盘零碎信息 | scan-misc-space | 根目录、一级目录、散落文件、权限盲区 | 解释空间，不等于可删除 |
| WU-Windows更新残留 | scan-windows-update-residue | WinRE/更新下载/待重启/CBS日志 | 只读，更新完成前保留 |
| AD-管理员深度核算 | scan-admin-deep-accounting | VSS/WinSxS/WindowsApps/Installer/DriverStore/Reserved Storage | 管理员只读解释层 |
| SA-NTFS实际占用 | scan-space-accounting | 逻辑、硬链接去重、分配字节 | 慢速按需核算 |

---

## 🛡️ 安全原则

### 风险等级

| 标记 | 含义 | 处理 |
|------|------|------|
| ✅ | 纯临时/缓存，删除无副作用 | 可直接执行 |
| ⚠️ | 需人工确认的低风险项 | 备份后执行 |
| ❌ | 系统核心/企业管控/用户数据 | 绝不触碰 |
| 🔴 | 可疑/未知，AI无法确定 | 引导自行判断 |

### 安全红线（永远不自动执行）

- ❌ 删除系统还原点 / 关闭休眠 / 移动页面文件
- ❌ 清理 WinSxS /ResetBase
- ❌ 删除 Program Files / 用户文档/桌面/下载
- ❌ 触碰企业安全软件(EDR/NAC/杀毒)
- ❌ vssadmin / diskpart 操作

### 安全机制

1. **只读默认**: 扫描脚本只读不写
2. **WhatIf 模式**: 清理脚本支持 `-WhatIf` 预览
3. **明确确认**: 危险操作需 `-ReallyDelete`
4. **管理员检测**: 清理前自动检查管理员权限（v6.1.2）
5. **永久删除提示**: 执行前显示"文件将永久删除，不经过回收站"（v6.1.2）
6. **统一删除门禁**: 所有正式 cleaner 在删除前校验允许根目录、C 盘边界、受保护根和任意祖先重解析点；无门禁参数时拒绝执行（v6.7.0）

---

## 📐 架构

```
c-drive-cleaner/
├── SKILL.md                    ← 你在这里
├── _common.ps1                 ← 公共模块（性能+统一接口）
├── analyze.ps1                 ← 一键入口（console/markdown/json）
│
├── scanners/   (类别只读扫描，含 GR/U/MX/WU/AD/SA)
├── cleaners/   (5个清理: safe/deep/dev-caches/apps/targeted)
├── migrators/  (3个迁移: appdata/dev-caches/wsl-docker)
├── extensions/
│   ├── app-signatures.json     ← 100+ 应用签名（14类别）
│   ├── user-custom.json        ← 用户自定义签名
│   └── scan-discover.ps1       ← 未知应用发现引擎
├── safety/     (备份+快照+回滚)
├── reports/    (生成的报告)
├── scheduled/  (定期自动化)
├── references/  (四件套迭代机制与审查门禁)
├── iteration-loop.ps1  (有界迭代入口，默认只诊断/预览)
├── track-growth.ps1    (路径级快照、增量与日增长率)
├── measure-space.ps1   (NTFS 分配字节与硬链接去重核算)
├── track-regeneration.ps1 (清理后 5m/1h/24h 再生检查)
├── tests/      (测试评测体系 — 与 CONTEST-SUBMISSION.md 同步维护)
│   ├── TEST-RESULTS-LOG.md     ← 真实测试结果
│   ├── IDEA-LOG.md             ← 想法与优化追踪
│   └── migration-guide.md      ← 缓存迁移方案选择指南
└── memory/     (v6.2 个性化系统 — 架构设计中)
```

### 扩展性

新软件签名只需一行 JSON，无需修改代码：

```json
{ "name": "我的软件", "detect_paths": ["%LOCALAPPDATA%\\MyApp\\cache"], "cleanable": true, "risk_level": "safe" }
```

编辑 `extensions/user-custom.json` 保存即生效。`scan-discover.ps1` 可自动发现未知大文件夹。

---

## 🛠️ 清理执行（v6.1.2 优化）

### 性能对比

| 操作 | 修复前 | 修复后 (v6.1.2) | 提升 |
|------|--------|-----------------|------|
| 删除 4.81 GB 飞书目录 | ❌ 卡死 30 分钟 | ✅ ~30 秒 | **60x+** |
| 删除 10.3 GB Trae CN | ❌ 没机会跑 | ✅ ~60 秒 | **∞** |
| 清理 3 项共 15.8 GB | ❌ 卡死后全崩 | ✅ ~3 分钟 | **∞** |

### 管理员权限

执行清理前自动检测管理员权限，未提权时给出明确提示。

### 安全提示

所有清理都是**永久删除（不经过回收站）**，执行前会红色警示。

---

## 📋 报告命名规范

| 格式 | 示例 | 含义 |
|------|------|------|
| Markdown | `CleanSight-CS-20260513-143022-72.md` | 品牌-日期-时间-健康评分 |
| JSON | `CleanSight-CS-20260513-143022-72.json` | 同上 |

报告自动包含：执行摘要 → 扫描明细 → AI决策建议(Tier分级) → 使用指南 → 工具推荐

---

## 🔄 维护规范（AI Agent Skill 工程化标准）

### 版本管理

- 遵循语义化版本：`MAJOR.MINOR.PATCH`
- 所有变更记录在 `CHANGELOG.md`
- `app-signatures.json` 的 `_schema` 版本号与主版本同步

### 更新流程

1. **签名更新**: 编辑 `app-signatures.json` 或 `user-custom.json`，无需改代码
2. **扫描器更新**: 修改 `scanners/` 下对应脚本
3. **报告格式更新**: 修改 `analyze.ps1` 中的报告生成逻辑
4. **版本发布**: 更新 `SKILL.md` version + `analyze.ps1` $VERSION + `CHANGELOG.md`

### 兼容性要求

- PowerShell 5.1+（Windows 自带）
- 不使用 PS7+ 专有语法（如三元运算符 `?:`）
- 路径使用环境变量（`$env:LOCALAPPDATA` 等）
- 应用检测前置 `Test-Path`（不存在则跳过）

### 测试验证

```powershell
# 验证扫描器正常
.\analyze.ps1 -Categories "B"    # 测试临时文件扫描
.\analyze.ps1 -OutputFormat json # 测试 JSON 输出

# 验证清理脚本
.\cleaners\clean-safe.ps1                      # WhatIf 预览
.\cleaners\clean-apps.ps1 -WhatIf -RiskLevel safe  # 预览可清理项
```

---

## 🔄 缓存迁移说明

> 详见 [tests/migration-guide.md](tests/migration-guide.md)

| 操作 | 方式 | 复杂程度 | 推荐 |
|------|------|---------|------|
| 搬 npm/pip/yarn 缓存到 D 盘 | 一行命令（Skill 自动） | 🟢 低 | **✅ 强烈推荐** |
| 搬微信/飞书缓存 | 无自动化脚本，目录结构复杂 | 🔴 高 | ❌ 不建议 |
| 搬 JetBrains 配置 | 配置文件与缓存混在一起 | 🔴 高 | ❌ 不建议 |

---

## v6.5.0 performance and accounting note

- `scan-large-files.ps1` uses 422 bounded NVMe-friendly partitions over a Win32 `FindFirstFileExW` engine. It keeps a bounded TOP-N set, merges cross-partition user totals, skips reparse targets, and reports inaccessible coverage.
- The same F pass aggregates the configured growth paths. GR reuses those totals in a full run; `-Fast` reads the most recent source-tagged snapshot and states its age instead of rescanning parent and child trees.
- Cleanup totals are built from exact measured paths with parent/child deduplication. Search-index burden and whole Electron/CEF application footprints are inventory only.
- Measured on this machine: F scanned about 580,000 files in 14.9-36.2 seconds; `F,GR` completed in 16.0 seconds; `-Fast` fell from 153.6 seconds to 26.6 seconds.

## v6.6.0 focused-fast and reparse safety note

- J uses registry install roots plus `extensions/runtime-inventory.json` in `-Fast`; ordinary J keeps broad AppData discovery. Both modes must state their coverage, and both found the same 8 runtime roots in the release test.
- Logical directory measurement now uses in-process Win32 enumeration with a robocopy compatibility fallback. Targeted paths are measured in a bounded four-way batch.
- Any reparse point in the target's ancestry stops C-drive accounting and targeted cleanup. This prevents redirected Qoder data on D from being reported as C reclaim.
- VM maps all drive letters through bulk CIM association queries. U reuses the registry inventory and avoids non-C fallback traversal.
- Measured on this machine: `-Fast` completed 16 categories in 9.5 seconds; focused J enumerated 17,613 files in 0.6 seconds, while broad J remained available and enumerated 383,651 files in 22.1 seconds.

## v6.7.0 global planning, cleanup guard, and admin accounting note

- The analyzer resolves all selected signature and multi-version targets first, measures cache misses through one bounded native batch, and seeds the shared cache. Scanner code still owns interpretation; the planner only removes repeated filesystem walks.
- Every maintained cleaner now passes through one fail-closed deletion gate. It rejects relative paths, drive/system/profile roots, targets outside caller-declared roots, non-C volumes, and any target whose ancestry contains a junction, symlink, or mount point.
- `clean-apps` executes the exact measured `sub_cleanable` paths; a cache-only signature must never fall through to deleting the whole application-data root.
- `AD` adds administrator-only, read-only accounting for VSS, WinSxS, WindowsApps, Installer, DriverStore, and Reserved Storage. Protected-store values remain inventory-only.
- Measured on this machine: `-Fast` completed 16 categories in 5.7-5.9 seconds; the planner seeded 88 unique paths and all 91 downstream logical measurements were cache hits.

*CleanSight v6.7.0 — AI Disk Health Advisor*
*理解你 · 分析数据 · 智能建议 · 赋能执行*
## 虚拟内存强化规则（VM）

运行 `analyze.ps1 -Categories "VM"` 时，优先读取注册表 `PagingFiles` 配置，再用 `pagefile.sys` 实际文件大小辅助判断。权限不足时必须标记“无法读取”，不能把页面文件误报为不存在。

- 先区分三件事：释放 C 盘空间、增加系统提交容量、获得 I/O 性能收益；迁移页面文件通常只保证前两者之一，不能默认提速。
- 页面文件最大配置值不是当前占用量；空间收益按实际文件大小或可验证的初始配置估算。
- 对 C/D/E 等固定盘逐一比较可用空间、物理磁盘编号、介质类型和总线类型；目标盘必须留出当前最大配置值之外的安全余量。
- 已存在“C 盘小页面文件 + 非 C 盘主页面文件”时，优先报告为混合布局，不重复建议大规模迁移。
- C 盘页面文件可能与崩溃转储有关；未确认转储需求前，不建议移除或改为 0。
- 不自动修改注册表、系统属性或页面文件；任何迁移/大小调整都必须先展示 WhatIf/预览、获得明确确认、重启后再次扫描验证。
