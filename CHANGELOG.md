# CHANGELOG — CleanSight 版本变更记录

| 版本 | 日期 | 关键词 | 规模 |
|------|------|--------|------|
| v7.4.0 | 2026-09-09 | 启动时询问产物目录、可持久化、去掉硬编码盘符 | ⚡ Minor |
| v7.3.1 | 2026-09-09 | 报告渲染修复、VM 段修复、产物默认落到 D 盘 | 🐛 Patch |
| v7.3.0 | 2026-09-09 | TRAE 实测白名单收敛、隐私产物隔离 | ⚡ Minor |
| v7.2.0 | 2026-09-08 | 厂商托管存储、WPS/ESP-IDF、F→MX 复用 | ⚡ Minor |
| v7.1.0 | 2026-09-08 | 未解释字节队列、19 类 AI 工具、逻辑/分配口径校正 | ⚡ Minor |
| v7.0.0 | 2026-09-08 | AI 软件生命周期、一遍核算、实机学习队列、迁移规划 | 🚀 Major |
| v6.7.0 | 2026-08-14 | 全局批量测量、统一删除门禁、管理员深度核算 | ⚡ Minor |
| v6.6.0 | 2026-08-14 | 定向快速扫描、原生测量、junction 安全 | ⚡ Minor |
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

## v7.4.0 (2026-09-09) — ⚡ 启动时询问产物目录

**背景**：v7.3.1 把产物默认写死到 `D:\deepseek\workspace\cleansight`。这解决了"清理工具自己在 C 盘留痕"，但把某台机器的目录写进了通用代码。

**改为询问式**
- 技能启动第一步：AI 用一句话问用户报告/产物存到哪里，确认后再跑扫描（写入 SKILL.md 的「启动第一步」章节）。
- 新增 `set-output-root.ps1`：`-Path` 保存、无参查看、`-Clear` 清除。保存前校验绝对路径、拒绝盘符根、自动建目录并做写权限探测（写临时文件再删），失败时明确报错而不是静默回退。
- 选择持久化到 `extensions\output-root.json`，后续运行不再重复询问。

**解析优先级**（去掉硬编码）
`analyze.ps1 -OutputRoot` > `$Global:CDriveArtifactRoot` > `CLEANSIGHT_OUTPUT_DIR` > `extensions\output-root.json` > 技能目录（兜底，兼容 v7.3.0 行为）。

- 未选择时不再指向任何固定盘符；`analyze.ps1` 头部会打印当前生效的产物目录。
- 版本号升至 v7.4.0，同步 SKILL.md 与 CHANGELOG.md。

---

## v7.3.1 (2026-09-09) — 🐛 报告渲染与产物位置修复

**问题 1：Markdown 报告内容缺失。** `analyze.ps1` 的 `BuildReport` 只写了执行摘要、MX 与 VM 三段，`findings` / Tier 分级建议 / 类别明细从未渲染，且出现两个「二、」标题。控制台与 JSON 才是完整证据源。

- 新增 `# 二、清理建议（Tier 分级）`：按 safe / cautious+dangerous / forbidden 分三档，输出项目、类别、大小、路径、建议，并给出每档合计。
- 新增 `# 三、扫描明细（按类别）`：按类别汇总条目数、合计与其中可安全清理量。
- 执行摘要补充健康评分、禁止删除量、扫描合计与产物目录；MX 改为 `# 四、C盘零碎空间信息（解释层）`，VM 改为 `# 五`，并新增 `# 六、下一步与产物位置`。
- dedup 行只保留测量字段，因此按 `Category|Name` 重建 Advice 映射，保证建议列不丢。

**问题 2：虚拟内存段落渲染为空并给出矛盾建议。**

- `${drive.Drive}` / `${drive.FreeGB}` / `${primaryDrive.Drive}` 在 PowerShell 中是**字面变量名**（`${...}` 不做属性展开），导致「驱动器 :」和「可用空间 GB」为空。改为 `$($drive.Drive)` 形式，并把迁移目标改为表格（含介质与说明）。
- 「实施步骤」原本硬编码「在 C 盘建 4096 MB 页面文件」并提示「保持 4GB 页面文件在 C 盘」，与技能自身规则（未确认崩溃转储需求前不动 C 盘页面文件）及实测状态（C 盘无页面文件）矛盾。现在按状态分支：
  - C 盘无页面文件 → 只给说明，明确「不要为释放 C 盘空间而新建 C 盘页面文件」；
  - C 盘有页面文件且有合适迁移目标 → 步骤使用真实盘符与可用空间，并提示仅在确认不需要完整崩溃转储时才缩小/移除；
  - 无满足余量的目标盘 → 不建议迁移。
- 新增「已配置的页面文件」表，列出每个页面文件的配置与实际占用（不可读时显式标注权限原因）。

**产物位置统一到 D 盘。** 新增 `_common.ps1` 中的 `Get-CleanSightArtifactRoot` / `Get-CleanSightArtifactPath` / `Initialize-CleanSightArtifactDirectory`，默认根目录 `D:\deepseek\workspace\cleansight`，解析优先级：`analyze.ps1 -OutputRoot` 参数 > `$Global:CDriveArtifactRoot` > `CLEANSIGHT_OUTPUT_DIR` 环境变量 > 内置默认值。

- 覆盖范围：报告与 JSON（`reports`）、增长基线（`reports\growth`）、AI 足迹基线（`reports\ai-footprints`）、清理会话（`reports\cleanup-sessions`）、迭代状态（`reports\iterations`）、搜索索引排除表、清理日志、未知应用发现建议、注册表备份与前后快照（`snapshots`）、每日监控日志（`snapshots\daily`）。
- `safety\backup-registry.ps1`、`safety\snapshot-before-after.ps1`、`scheduled\daily-monitor.ps1` 原先写 `C:\cleanup_snapshots`，改为统一产物目录，避免清理工具自己在 C 盘留痕。
- 迁移既有基线：把旧 `skills\c-drive-cleaner\reports` 复制到新产物根，保证增长对比连续。

**编码回归修复。** 编辑过程曾丢失 9 个脚本的 UTF-8 BOM（`analyze.ps1`、`_common.ps1`、`clean-safe.ps1`、`clean-apps.ps1`、`scan-search-index.ps1`、`backup-registry.ps1`、`snapshot-before-after.ps1`、`daily-monitor.ps1`、`scan-discover.ps1`）。PowerShell 5.1 在无 BOM 时按 ANSI 解析，会破坏中文输出；已按编辑前状态恢复 BOM，并用 UTF-8 显式解析全量校验 53 个脚本语法通过。

---

## v7.3.0 (2026-09-09) — ⚡ TRAE 实测白名单与隐私收口

- 将一次成功的 TRAE CN / TRAE SOLO CN 清理结论沉淀到 AF 生命周期层：缓存目标全部清空且无失败项，可稳定回收多 GB 空间。
- 为两类 TRAE 补齐 Dawn、WebGPU 与 Shader 可重建缓存；继续保留 `User`、`ModularData`、`WebStorage` 和 `Local Storage`。
- TRAE 继续走 AF 单一事实源，不在 O 类重复计量，避免同一路径重复形成清理额度。
- 原始清理结果、设备容量、软件清单、性能基线和发布草稿改为本地隐私产物，由 `.gitignore` 排除；公共文档只保留匿名化结论与临时夹具测试。
- 版本发布前完成路径、用户名、主机名、邮箱、IP、密钥和当前设备值扫描，未发现待提交敏感项。

---

## v7.2.0 (2026-09-08) — ⚡ 厂商托管存储与全盘结果复用

- 新增 `MS` 类和 `extensions/managed-storage.json`，把“容量很大但必须由产品自身管理”的目录从普通 inventory 提升为明确的谨慎项，同时不提供直接删除器。
- 脱敏验证确认：WPS `cachedata` 必须保持厂商托管，只建议同步完成后使用“释放空间”或更换位置。
- 脱敏验证确认：ESP-IDF 只把 `dist` 下载归档列为厂商 CLI 谨慎项，保留当前 `tools` 与 `python_env`。
- 新增厂商托管存储结构/行为测试，使用临时夹具验证只读测量、谨慎风险和“无直接 cleaner”不变量。
- F 扫描把 growth 精确聚合写入同轮测量缓存；MX 对剩余 C 盘一级目录做批量测量，脱敏性能验证确认不再重复全盘遍历。
- 新增 WPS 与 ESP-IDF 官方处理说明。发布测试没有删除、迁移或修改 WPS/ESP-IDF 数据。

---

## v7.1.0 (2026-09-08) — ⚡ 未解释字节学习与 AI 覆盖扩展

- 学习队列改为 `容器逻辑字节 - 已分类路径并集逻辑字节`，只把超过阈值的未解释部分留在 review；父子嵌套策略先折叠为最外层覆盖，既不会把已解释的父目录整块重复报成未知，也不会因重复扣减隐藏未知空间。
- 实机发现并纳入 DoubaoWork、ZCode、LobsterAI、CodeBuddy，同时补齐 Doubao、iChat 和 GitHub Copilot；生命周期配置从 12 类扩为 19 类。
- DoubaoWork 的浏览器缓存精确识别为 163.7 MB，sandbox runtime、环境、SDK 和应用状态保留；ZCode 的 311.7 MB updater 残留列为谨慎项，CLI、workspace 和 session 保留。
- 配置测试增加“旧 `ai_tools` 签名必须映射到 AF 根”的覆盖约束，未来新增 AI 签名时不能静默漏过生命周期核算。
- 修正计量术语：AF 默认值是位于 C 盘且排除 reparse 目标的逻辑字节，不再称作物理/分配占用；真实释放仍由 cleanup session 和 SA 的 NTFS 分配字节验证。
- 脱敏复扫确认：配置分类、safe/managed/preserve 边界、未解释热点队列与原生枚举均正常收敛；未删除或迁移数据。

---

## v7.0.0 (2026-09-08) — 🚀 AI 软件生命周期与实机学习闭环

- 新增 AF 类和 `extensions/ai-footprints.json`，统一核算 Trae、TRAE SOLO、Qoder/QoderWork、WorkBuddy、Codex、Playwright、Ollama、Hugging Face、本地模型缓存和 Cursor 的安装、用户数据、runtime、模型、扩展、索引、状态及更新残留。
- Win32 一遍扫描同时聚合根目录、精确组件和一级热点；整个应用目录只进入 inventory，只有显式 `safe-clean`/`managed-clean` 组件进入可释放额度。
- 新增 `discovery_candidates` 实机学习队列。大而未分类的 mixed-data 子目录默认 `review`，不得自动升级为删除规则。
- 新增 AF 专用清理器：默认预览，执行时检查活跃进程、允许根和重解析点，并记录实际盘符增量、分配字节回收与再生复测会话。
- 新增只读迁移规划器，优先 Playwright/Ollama/Hugging Face 官方环境变量与工具命令，并将第三方 Electron IDE junction 降为谨慎方案。
- 修复空可选正则会匹配全部注册表/AppX 包的归属缺陷，增加配置结构、关键保留项、应用专属进程门禁和空正则回归测试。
- 脱敏验证确认：AF 在一轮“发现→分类→复扫”后显著减少误归属和未分类热点；未在发布验证中删除或迁移用户数据。

---

## v6.7.0 (2026-08-14) — ⚡ 全局测量计划、统一安全门禁与管理员核算

- 分析器先解析所选签名、多版本和 Windows Update 精确路径，以四路原生批量测量预热共享缓存，避免各扫描器逐路径重复遍历。
- 所有正式 cleaner 和定时日志清理统一经过 fail-closed 门禁：必须声明允许根目录，并拒绝相对路径、盘符/系统/用户根目录、非 C 卷以及任意祖先 junction、符号链接或挂载点。
- 修复 `clean-apps` 的范围错配：带 `sub_cleanable` 的签名直接消费扫描得到的精确 measurement 路径，不再从“只统计缓存”落入“删除整个应用数据根目录”的执行分支。
- 新增 `AD` 管理员只读核算：VSS、DISM WinSxS、WindowsApps、Installer、DriverStore 与 Reserved Storage；全部隔离在 inventory，不进入可释放额度。
- 新增 `tests/validate-cleanup-guard.ps1`，覆盖正常目录/文件、根目录、允许根越界、junction 和跨盘路径。
- 脱敏只读验证确认：Fast 预热后的逻辑测量命中共享缓存，AD 普通权限降级输出通过；未删除、移动或修改用户/系统源数据。

---

## v6.6.0 (2026-08-14) — ⚡ 定向快速扫描与重解析点安全

- J 类增加双层覆盖：`-Fast` 读取卸载注册表安装位置和 `extensions/runtime-inventory.json` 的精确候选；普通模式继续广泛扫描 AppData/Program Files。脱敏验证确认快速与深度模式归属一致。
- 通用目录体积测量改为进程内 Win32 `FindFirstFileExW`，保留 robocopy 兼容回退；O 类定向目标使用四路批量测量。
- 对目标及其所有祖先检查 junction/符号链接。重定向到 D/E 盘的数据不再计作 C 盘可释放量，定向清理也不会沿链接删除。
- VM 用 `Win32_LogicalDiskToPartition` 和 `Win32_DiskDrive` 一次映射所有固定盘，从约 5.7 秒降至约 0.6 秒。
- U 类复用卸载注册表；快速模式不测软件目录，完整模式只补测可能相关的 C 盘目录，避免为 D/E 软件做无效遍历。
- 脱敏只读验证确认：快速模式显著减少 J 类遍历量，深度模式仍可完整覆盖；未删除或移动数据。

---

## v6.5.0 (2026-08-13) — ⚡ 高性能扫描与可信核算

- 新增 Win32 `FindFirstFileExW` 原生扫描器，将 Users/AppData、Windows、ProgramData 和 Program Files 拆成有界并发分片；跨分片用户目录统计统一合并。
- F 类在同一遍约 58 万文件枚举中同时生成 TOP 20、用户一级目录大小和 37 个增长目标统计，不再为 GR 重扫父子目录。
- 快速模式读取带时间戳和 `measurementSource` 的增长快照；F→GR 复用显著降低重复测量耗时。
- 重写 J 类 Electron/CEF 盘点，拆分 Microsoft/Google/Tencent 厂商容器；整个应用体积和 runtime-shaped 字节只进入 inventory，不进入可清理额度。
- 应用签名只核算 `sub_cleanable` 精确子路径；Search 索引负担只作为优化线索；最终清理总量按路径层级去重。
- 增加逐分类耗时、文件数、分区数、跳过目录、缓存命中和 JSON scanner metadata，便于后续持续优化。
- 脱敏验证确认：F 与 `analyze.ps1 -Fast` 均显著提速；全程只读，未删除数据。

---

## v6.4.1 — F scanner performance

- Replaced the PowerShell `Get-ChildItem -Recurse` large-file scan with an in-process .NET directory enumerator.
- Maintains a bounded TOP-N candidate set, skips reparse-point directories, and continues through inaccessible folders while reporting skip counts.
- Keeps protected Windows trees out of the file-level scan because A/WU/SA already provide their directory-level evidence.
- An anonymized fixture and read-only validation confirmed bounded TOP-N behavior; no files were modified.

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
  - 清理前提示匹配项目数与预计释放量
  - 清理后显示匿名化空间汇总，不把本机结果写入仓库

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
- **创建完整测试体系**: `tests/` 目录维护测试方法与临时夹具；真实结果仅保存在本地
- **本地结果日志**: 记录真实扫描与清理验证，但不进入公开仓库
- **本地想法日志**: 记录优化想法与踩坑经验，但不进入公开仓库
- **methodology/test-strategies.md**: 各模式的测试方法和验收标准
- **场景与性能记录**: 本机容量、软件清单和性能基线统一作为隐私产物处理

### 📝 发布材料
- 发布草稿与真实测试数据保持在本地，不纳入版本控制
- 诚实标注 v6.2 memory/ 系统状态（骨架完成，待接入主流程）
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
- **脱敏扫描通过**: 全类别扫描完整执行；原始耗时与设备数据仅留本地
- **结构化报告生成通过**: 报告结构、风险分层与行动建议均完成验证
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
