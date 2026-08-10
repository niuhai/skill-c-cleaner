---
name: "c-drive-cleaner"
description: "AI驱动的C盘智能决策顾问——不是清理工具，而是你的磁盘健康私人AI管家。深度分析+个性化建议+安全执行指导。当用户询问C盘空间不足、想清理垃圾、释放磁盘空间、想将某些数据移出C盘时调用此技能。"
---

## 定向优化（O 类）

运行 `.\analyze.ps1 -Categories "O"` 扫描已知的高价值定向项：

- Qoder：只清理 `SharedClientCache\index`、`SharedClientCache\cache`、`CachedData` 等缓存；保留 `User\workspaceStorage`、`User\History` 和 `User\globalStorage`。
- WorkBuddy：只匹配 `%LOCALAPPDATA%\Temp\workbuddy-update-*` 更新残留；关闭 WorkBuddy 后再处理。
- Codex：只处理 `.cache\codex-runtimes` 下的 `codex-runtime-install-*` 与 `codex-primary-runtime.previous-*`；保留当前 `codex-primary-runtime`。Whisper 模型单独列为谨慎项。

使用 `.\cleaners\clean-targeted-optimization.ps1 -WhatIf` 预览，确认后追加 `-ReallyDelete`；脚本会检查相关进程并阻止越界路径。

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
1. 执行 12 类别只读扫描（scanners/）
  ↓
2. 生成 AI 决策报告（健康评分 + Tier 分级建议）
  ↓
3. 展示摘要 → 用户追问 → 深入分析
  ↓
4. 用户选择执行项 → AI 提供精确命令 + 安全提示
```

### 一键模式

```powershell
.\analyze.ps1                                          # 控制台输出
.\analyze.ps1 -OutputFormat markdown                   # 生成 Markdown 报告
.\analyze.ps1 -OutputFormat json                       # JSON 格式
.\analyze.ps1 -Categories "C,D"                        # 只扫描开发缓存+浏览器
```

### 扫描类别速查

| 类别 | 脚本 | 覆盖 | 适用 |
|------|------|------|------|
| A-系统隐藏 | scan-system-hidden | hiberfil/pagefile/还原点/WinSxS | 了解即可 |
| B-临时缓存 | scan-temp-files | Temp/缩略图/回收站/Update缓存 | ✅ 日常首选 |
| C-开发缓存 | scan-dev-caches | npm/pip/cargo/maven/gradle等 | 开发者必看 |
| D-浏览器 | scan-browsers | Chrome/Edge/Firefox等 | 所有人 |
| E-应用数据 | scan-app-data | IDE/媒体/办公/AI工具 | 深度清理 |
| F-大文件 | scan-large-files | TOP 20大文件+文件夹排行 | 快速定位 |
| G-特殊占用 | scan-special-sources | Docker/WSL/游戏平台 | 特殊需求 |
| H-安全软件 | scan-security-software | EDR/NAC/杀毒 | 仅了解 |
| I-多版本 | scan-multi-version | 多版本残留 | 整洁度 |
| J-重复运行时 | scan-duplicate-runtimes | Electron/CEF重复 | 高级优化 |
| K-输入法 | scan-ime-data | 词库/日志 | 细节清理 |
| L-即时通讯 | scan-im-apps | 微信/QQ/钉钉缓存 | 社交应用 |

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

---

## 📐 架构

```
c-drive-cleaner/
├── SKILL.md                    ← 你在这里
├── _common.ps1                 ← 公共模块（性能+统一接口）
├── analyze.ps1                 ← 一键入口（console/markdown/json）
│
├── scanners/   (12个只读扫描)
├── cleaners/   (3个清理: safe/deep/dev-caches)
├── migrators/  (3个迁移: appdata/dev-caches/wsl-docker)
├── extensions/
│   ├── app-signatures.json     ← 100+ 应用签名（14类别）
│   ├── user-custom.json        ← 用户自定义签名
│   └── scan-discover.ps1       ← 未知应用发现引擎
├── safety/     (备份+快照+回滚)
├── reports/    (生成的报告)
├── scheduled/  (定期自动化)
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

*CleanSight v6.4.0 — AI Disk Health Advisor*
*理解你 · 分析数据 · 智能建议 · 赋能执行*
## Virtual memory hardening (VM)

Run `analyze.ps1 -Categories "VM"` before making any paging-file decision. Read the registry `PagingFiles` configuration first, then use pagefile file metadata as a secondary signal. If permissions block a read, report the limitation instead of claiming that no pagefile exists.

- Separate C-drive space recovery, commit capacity, and I/O performance; moving a pagefile is not automatically a speed upgrade.
- Treat the maximum configured size as a limit, not current disk usage; estimate reclaimable space from actual file size or verifiable initial size.
- Compare every fixed drive by free space, physical disk number, media type, and bus type; leave headroom beyond the maximum required size.
- If a hybrid layout already exists, keep the non-C primary pagefile and avoid repeating a large migration recommendation.
- Keep a C pagefile until crash-dump requirements are confirmed. Never directly delete or move `pagefile.sys`.
- Do not change registry, system properties, or pagefiles automatically. Require preview, explicit confirmation, reboot, and a post-reboot verification scan.
