# CHANGELOG — c-drive-cleaner 版本变更记录

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

### 功能
- 智能删除建议 (✅推荐/⚠️谨慎/❌不建议)
- 迁移方案 (开发工具缓存迁移方法)
- 深度扫描 (大文件TOP N + 特殊占用源)
- 溯源分析 (为什么生成/为什么放C盘/迁移难度)

### 覆盖
- A类: 系统隐藏文件 (hiberfil, pagefile, 还原点, WinSxS)
- B类: 临时文件与缓存 (Windows Temp, 用户Temp, 缩略图, 回收站, Update缓存)
- C类: 开发工具缓存 (npm, pip, cargo, maven, gradle, nuget, yarn, pnpm, node-gyp)
- D类: 浏览器缓存 (Chrome, Edge)
- E类: 应用数据 (系统日志, JetBrains, 搜狗PDF)
- F类: 大文件TOP N
- G类: 特殊占用源 (Puppeteer, Docker, WSL, 根目录可疑文件)

---

## v2.0.0 — 结构化报告

- 添加报告输出格式模板
- 添加一键迁移指南汇总
- v1.0 vs v2.0 对比表

## v1.0.0 — 初始版本

- 基础C盘垃圾文件扫描
- 只读模式分析
