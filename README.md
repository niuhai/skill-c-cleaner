<p align="center">
  <h1 align="center">🧠 c-drive-cleaner</h1>
  <p align="center">
    <strong>AI 驱动的 C 盘智能决策顾问</strong><br>
    不是清理工具，而是你的磁盘健康私人 AI 管家<br>
    <em>理解你 · 分析数据 · 智能建议 · 赋能执行</em>
  </p>
  
  <p align="center">
    <a href="#-核心特性">特性</a> •
    <a href="#-快速开始">快速开始</a> •
    <a href="#-使用场景">场景</a> •
    <a href="#-与传统工具对比">对比</a> •
    <a href="#-贡献指南">贡献</a>
  </p>
  
  <p align="center">
    <img src="https://img.shields.io/badge/version-v6.0.0-blue.svg" alt="Version"/>
    <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"/>
    <img src="https://img.shields.io/badge/powershell-5.1%2B-blue.svg" alt="PowerShell"/>
    <img src="https://img.shields.io/badge/platform-windows-lightgrey.svg" alt="Platform"/>
    <img src="https://img.shields.io/badge/status-production%20ready-brightgreen.svg" alt="Status"/>
  </p>
</p>

---

## 🎯 一句话定位

**我不是清理工具，我是你的 AI 磁盘健康顾问。**

```
传统工具（CCleaner/BleachBit/WizTree）= 执行层：帮你删文件（但不懂你）
本 Skill（AI Decision Layer）          = 决策层：理解你 + 分析数据 + 智能建议 + 教你安全执行
```

**核心价值**: 不是"帮你打扫"，而是 **"教你如何管理系统空间 + 根据你的情况做最优决策"**。

---

## ✨ 核心特性

### 🧠 AI 决策能力（传统工具没有的）

| 能力 | 说明 | 价值 |
|------|------|------|
| **上下文感知** | 结合你的操作历史给出 timely 建议 | 不是机械列表，而是个性化方案 |
| **动态风险评估** | 基于使用场景实时分析，而非固定规则 | 一分为二的分析，不是简单的是/否 |
| **用户画像识别** | 自动检测开发者/设计师/普通用户身份 | 定制化策略，拒绝一刀切 |
| **预测性维护** | 趋势分析 + 未来预警 | 防患于未然 |
| **知识赋能** | FAQ + 最佳实践 + 教程 | 让你学会自己管理空间 |
| **对话式交互** | 自然语言追问 + 动态分析 | 像聊天一样操作 |

### 🔬 深度扫描能力（12 类别全覆盖）

```
A-系统隐藏 │ B-临时缓存 │ C-开发缓存 │ D-浏览器数据
E-应用数据 │ F-大文件   │ G-特殊占用 │ H-安全软件
I-多版本   │ J-重复运行时│ K-输入法   │ L-即时通讯
```

### 📊 现象级报告系统（v6 AI Decision Edition）

- **9 大核心模块**：从执行摘要到总结闭环
- **混合布局**：精简结论 + 可展开详情
- **AI 决策透明化**：每个建议都包含理由和替代方案
- **分阶段行动计划**：按风险排序，10分钟见效

[查看完整示范报告 →](reports/sample-report-v6-ai-decision-full.md)

---

## 🚀 快速开始

### 前置要求

- Windows 10/11
- PowerShell 5.1+ （Windows 自带）
- 管理员权限（部分操作需要）

### 安装使用

```bash
# 1. 克隆仓库
git clone https://github.com/your-username/c-drive-cleaner.git
cd c-drive-cleaner

# 2. 运行完整分析（控制台输出）
.\analyze.ps1

# 3. 生成 AI 决策报告（Markdown 格式）
.\analyze.ps1 -OutputFormat markdown -Template v6-ai-decision

# 4. 只扫描特定类别（例如：开发缓存 + 浏览器）
.\analyze.ps1 -Categories "C,D"

# 5. 输出 JSON 格式（可被其他工具消费）
.\analyze.ps1 -OutputFormat json
```

### 示例输出

运行后会生成类似这样的报告：

```markdown
# C盘深度分析报告 - AI 决策版 v6.0

## 🎯 执行摘要（30秒速览）
**空间健康评分: 72/100 ⚠️ 需关注**
- 可立即释放: 8.7 GB ✅ 安全
- 需确认后释放: 23.2 GB ⚠️ 需谨慎

## ⚡ 快速行动方案
1. **立即执行** (5分钟, 释放 3.2GB): 清理临时文件 + 浏览器缓存
2. **本周完成** (需备份, 释放 12.3GB): 清理开发工具缓存
3. **长期优化** (周末, 避免 4.5GB/月增长): 迁移 Docker + WSL 到 D 盘

...（完整的 9 大模块内容）
```

[查看完整的 900+ 行示范报告 →](reports/sample-report-v6-ai-decision-full.md)

---

## 💡 使用场景

### 场景 1: 日常例行检查

**用户**: "帮我看一下 C 盘"

**AI 执行**:
1. 运行完整 12 类别扫描
2. 生成 v6 AI 决策报告
3. 展示摘要：健康评分、可释放空间、Top 3 行动

### 场景 2: 紧急释放空间

**用户**: "C 盘只剩 10GB 了，很卡！"

**AI 执行**:
1. 识别紧急状态
2. 生成分阶段紧急方案（按风险排序）
3. 提供精确命令，预期效果量化
4. 30 分钟后 C 盘可用空间翻倍

### 场景 3: 特定应用咨询

**用户**: "Docker 太占空间了"

**AI 执行**:
1. 详细分析 Docker 占用构成（镜像/数据卷/WSL）
2. 提供 3 个选项（清理/迁移/重置）
3. 附完整迁移教程和回滚方案

### 场景 4: 学习最佳实践

**用户**: "怎么避免 C 盘再次被占满？"

**AI 执行**:
1. 分析历史增长趋势
2. 识别主要增长源
3. 生成长期预防方案（环境变量设置/路径规范/自动化任务）

---

## 🆚 与传统工具的对比

### 为什么不直接用 CCleaner / BleachBit？

| 能力 | CCleaner | BleachBit | WizTree | **本 Skill (AI)** |
|------|----------|-----------|---------|------------------|
| 自动删除 | ✅ | ✅ | ❌ | ❌ (**更安全**) |
| **个性化建议** | ❌ | ❌ | ❌ | ✅ **(杀手锏)** |
| **风险智能评估** | ❌ 固定规则 | ❌ 固定规则 | ❌ | ✅ **动态分析** |
| **场景化策略** | ❌ | ❌ | ❌ | ✅ **(用户适配)** |
| **异常检测** | ❌ | ❌ | ❌ | ✅ **(AI 洞察)** |
| **对话式交互** | ❌ GUI | ❌ GUI | ❌ GUI | ✅ **(自然语言)** |
| **学习进化** | ❌ | ❌ | ❌ | ✅ **(持续优化)** |
| **迁移指导** | ❌ | ❌ | ❌ | ✅ **(完整方案)** |
| **预测性维护** | ❌ | ❌ | ❌ | ✅ **(趋势分析)** |

### 真实场景对比

#### 发现 10GB 的 node_modules

**传统工具**:
```
显示: "node_modules - 10GB - 可删除"
用户: "删不删？不知道，万一以后要用呢？"
结果: 犹豫不决，或者误删
```

**AI 决策层**:
```
显示: "检测到 node_modules 10GB，位于项目 X"
分析: "该项目最后编译时间是 30 天前"
推理: "你最近主要在做 Python 项目，这个 Node.js 项目近期不太可能活跃"
建议: "可以安全删除。如果未来需要，`npm install` 即可恢复。
      另外，建议设置 .gitignore 忽略 node_modules，
      或使用 pnpm 的全局存储功能（附配置方法）"
结果: 用户放心删除 + 学到最佳实践 ✅
```

### 我们不是替代品，是互补品

```
┌─────────────────────────────────────────┐
│         用户的工作流程                    │
│                                         │
│  1️⃣ c-drive-cleaner (AI)               │
│     ↓                                   │
│     深度分析 + 智能决策 + 生成方案        │
│     ↓                                   │
│  2️⃣ 用户确认方案                        │
│     ↓                                   │
│  3️⃣ BleachBit / WizTree               │
│     ↓                                   │
│     根据 AI 方案执行具体删除操作          │
│                                         │
└─────────────────────────────────────────┘
```

**比喻**: 
- **AI (本 Skill)** = 建筑师（设计蓝图、规划方案）
- **BleachBit/WizTree** = 施工队（按蓝图执行）

两者结合，效果最佳。

---

## 📁 项目结构

```
c-drive-cleaner/
├── SKILL.md                              # AI 决策层定义（核心文档）
├── _common.ps1                           # 公共模块（高性能函数库）
├── analyze.ps1                           # 一键入口脚本
│
├── scanners/  (12个只读扫描脚本)
│   ├── scan-system-hidden.ps1            # A类: 系统隐藏空间
│   ├── scan-temp-files.ps1               # B类: 临时缓存
│   ├── scan-dev-caches.ps1               # C类: 开发工具缓存
│   ├── scan-browsers.ps1                 # D类: 浏览器数据
│   ├── scan-app-data.ps1                 # E类: 应用程序数据
│   ├── scan-large-files.ps1              # F类: 大文件 TOP 20
│   ├── scan-special-sources.ps1          # G类: 特殊占用源
│   ├── scan-security-software.ps1        # H类: 安全软件
│   ├── scan-multi-version.ps1            # I类: 多版本共存
│   ├── scan-duplicate-runtimes.ps1       # J类: Electron 重复运行时
│   ├── scan-ime-data.ps1                 # K类: 输入法数据
│   └── scan-im-apps.ps1                  # L类: 即时通讯
│
├── cleaners/  (3个清理脚本)
│   ├── clean-safe.ps1                    # 安全清理（临时文件）
│   ├── clean-deep.ps1                    # 深度清理（需确认）
│   └── clean-dev-caches.ps1              # 开发缓存清理
│
├── migrators/ (3个迁移脚本)
│   ├── migrate-appdata-junction.ps1      # AppData Junction 迁移
│   ├── migrate-dev-caches.ps1            # 开发缓存迁移
│   └── migrate-wsl-docker.ps1            # WSL/Docker 迁移
│
├── extensions/
│   ├── app-signatures.json               # 100+ 应用签名数据库
│   ├── user-custom.json                  # 用户自定义签名
│   ├── scan-discover.ps1                 # 未知应用发现引擎
│   └── discovery-suggestions.txt
│
├── safety/    (备份+快照+回滚)
│   ├── snapshot-before-after.ps1         # 清理前后快照
│   ├── backup-registry.ps1               # 注册表备份
│   └── rollback-guide.md                 # 回滚指南
│
├── reports/   (报告模板)
│   ├── report-template.md                # 旧版模板（兼容）
│   ├── report-template-v6-ai-decision.md # ✨ 新版 AI 决策模板
│   └── sample-report-v6-ai-decision-full.md # ✨ 精品示范报告
│
├── scheduled/ (定期自动化)
│   ├── daily-monitor.ps1                 # 每日监控
│   └── weekly-cleanup.xml                # 每周清理任务
│
├── CHANGELOG.md                          # 版本变更记录
└── README.md                             # 你在这里
```

---

## 🛡️ 安全原则

### 只读优先设计

- ✅ 所有扫描脚本都是**只读**的
- ✅ 不自动删除任何文件
- ✅ 输出的是**带决策的建议报告**，而不是执行结果
- ✅ 清理脚本支持 `-WhatIf` 预览模式
- ✅ 危险操作需要 `-ReallyDelete` 明确确认

### 风险等级体系

| 等级 | 标记 | 含义 | 处理方式 |
|------|------|------|---------|
| ✅ | **强烈推荐** | 纯临时文件、缓存 | 可直接执行 |
| ⚠️ | **确认后操作** | 需人工确认的低风险项 | 建议备份后执行 |
| ❌ | **不建议/禁止** | 系统核心、企业管控 | 绝不触碰 |
| 🔴 | **必须人工检查** | 可疑文件、未知大文件 | 引导自行判断 |

### 安全红线（永远不自动执行）

- ❌ 删除系统还原点
- ❌ 关闭休眠 / 移动页面文件
- ❌ 清理 WinSxS `/ResetBase`
- ❌ 删除 Program Files 下任何目录
- ❌ 删除用户文档/桌面/下载
- ❌ 触碰企业安全软件(EDR/NAC/杀毒)

---

## 🎨 产品哲学

### 五大设计原则

1. **只读优先（Read-First）**
   - 信任是逐步建立的，让用户先看到 AI 的分析质量

2. **教育赋能（Empowerment Over Automation）**
   - 不是"我帮你删了"，而是"我分析了，建议这样做，理由是..."

3. **个性化适配（Personalization）**
   - 识别用户类型，拒绝一刀切

4. **透明可解释（Explainable AI）**
   - 每个建议都有明确理由，建立信任的关键

5. **渐进式信任（Progressive Trust Building）**
   - 尊重用户的掌控权，始终保留人工确认环节

---

## 🔧 扩展性

### 添加自定义软件

编辑 `extensions/user-custom.json`：

```json
{
  "name": "我的特殊软件",
  "detect_paths": ["%LOCALAPPDATA%\\MyApp\\cache"],
  "cleanable": true,
  "note": "这是我装的软件，缓存可清理",
  "risk_level": "safe",
  "custom_advice": "删除后会重新下载，约需 5 分钟"
}
```

保存后下次扫描自动生效，无需修改任何代码。

### 流氓软件识别

`app-signatures.json` 中 `rogue_software` 类别收录了 17 种常见国产流氓/捆绑软件，扫描时会自动标记 ⚠️ 并给出卸载建议。

---

## 📈 发展路线图

### 已完成 ✅
- [x] v1.0: 基础扫描功能
- [x] v3.0: 签名驱动架构
- [x] v4.0: 文件组架构 + 通用化
- [x] v4.1: 扩展性系统（数据与代码分离）
- [x] v5.0: 性能优化 + 公共模块
- [x] v6.0: **AI 决策层 + 智能报告系统**

### 进行中 🔄
- [ ] v6.1: 对话式交互增强（多轮对话记忆）
- [ ] v6.2: 用户画像持久化（跨会话学习）
- [ ] v6.3: 预测性分析引擎（机器学习模型）

### 规划中 📋
- [ ] v7.0: Web Dashboard（可视化界面）
- [ ] v7.1: 多盘符支持（D/E/F 盘）
- [ ] v7.2: 企业版（合规性 + 策略管理）
- [ ] v8.0: 社区平台（签名共享 + 排行榜）

---

## 🤝 贡献指南

我们欢迎所有形式的贡献！

### 如何贡献

1. **Fork 本仓库**
2. **创建特性分支** (`git checkout -b feature/amazing-feature`)
3. **提交更改** (`git commit -m 'Add some amazing feature'`)
4. **推送到分支** (`git push origin feature/amazing-feature`)
5. **开启 Pull Request**

### 贡献方向

- 🆕 **新软件签名**（提交到 `app-signatures.json`，格式见文件内注释）
- 📝 **报告模板改进**（优化 v6 AI 决策模板）
- 🐛 **Bug 修复**（扫描器/清理脚本的边界情况）
- 🌐 **国际化**（翻译文档到其他语言）
- 📚 **文档完善**（补充教程、示例、最佳实践）
- 🧪 **测试用例**（添加自动化测试）

### 代码规范

- PowerShell 遵循官方风格指南
- 注释使用英文（代码层面）
- 文档使用中文（面向中文用户社区）
- 保持向后兼容性

---

## 📄 许可证

本项目基于 [MIT License](LICENSE) 开源。

```
MIT License

Copyright (c) 2026 c-drive-cleaner contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
```

---

## 🙏 致谢

- **开源工具**: [BleachBit](https://www.bleachbit.org/) | [WizTree](https://wiztreefree.com/) | [Bulk Crap Uninstaller](https://www.bcuninstaller.com/)
- **PowerShell 社区**: 提供的优秀语言特性和生态
- **所有贡献者**: 让这个项目变得更好

---

## 📞 支持与反馈

- **问题反馈**: [GitHub Issues](https://github.com/your-username/c-drive-cleaner/issues)
- **功能建议**: [GitHub Discussions](https://github.com/your-username/c-drive-cleaner/discussions)
- **Star 这个项目** ⭐ 如果觉得有用

---

## 🎉 总结

**c-drive-cleaner v6.0** 不是一个清理工具，它是：

> **🧠 AI 驱动的磁盘健康决策系统**
> 
> 理解你 · 分析数据 · 智能建议 · 赋能执行
> 
> **从"帮你打扫"升级为"教你如何生活得更整洁"**

**从 v1.0 到 v6.0 的进化历程**:
```
v1.0 基础扫描 → v2.0 结构化报告 → v3.0 四维分析 → v4.0 文件组架构
→ v4.1 扩展性系统 → v5.0 性能优化 → v6.0 🧠 AI 决策层（现象级产品）
```

---

<p align="center">
  <b>立即体验 AI 驱动的磁盘管理新时代！</b><br>
  <code>.\analyze.ps1 -OutputFormat markdown -Template v6-ai-decision</code>
</p>

<p align="center">
  Made with ❤️ by AI and Open Source Community
</p>
