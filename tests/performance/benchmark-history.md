# CleanSight 性能基准测试历史

> **记录每次性能测试的基线数据，追踪性能变化趋势。**

---

## 基准测试基线（2026-05-16）

### 测试环境

| 项目 | 配置 |
|------|------|
| 操作系统 | Windows 11 Pro 23H2 |
| C盘类型 | NVMe SSD |
| C盘容量 | 148.91 GB |
| 初始使用率 | 91.7% (136.54 GB) |
| 引擎版本 | CleanSight v6.1.0 |

---

## 性能数据记录

### 测试 1：标准模式（12 类全量扫描）

| 指标 | 数值 |
|------|------|
| 扫描日期 | 2026-05-16 14:05 |
| 扫描耗时 | 2003.3 秒 (~33 分钟) |
| 扫描类别 | A-L 共 12 类 |
| 发现项目数 | 46+ 项 |
| 报告大小 | ~261 行 |
| 是否报错 | 无 |

### 测试 2：快速模式（6 类扫描）

| 指标 | 第一次 (14:05) | 第二次 (15:09) | 第三次 (16:08) |
|------|---------------|---------------|---------------|
| 扫描耗时 | 待统计 | 待统计 | 2003.3s |
| 可安全释放 | 28.3 GB | 28.3 GB | 28.39 GB |
| 需确认释放 | 30.67 GB | 30.67 GB | 30.67 GB |
| 健康评分 | 17/100 | 17/100 | 17/100 |
| 数据一致性 | — | ✅ | ✅ |

### 测试 3：清理后快速模式（2026-05-18）

| 指标 | 数值 |
|------|------|
| 扫描日期 | 2026-05-18 16:28 |
| 扫描耗时 | **584.4 秒 (~9.7 分钟)** |
| 扫描类别 | B,C,D,E,F (快速模式 6 类) |
| 健康评分 | **50/100** 🟡 (从 17 升到 50) |
| 已用空间 | 110.74 GB / 148.91 GB (74.4%) |
| 是否报错 | 无 (F 类大文件扫描出错，单独处理) |
| 数据一致性 | — |

> 注：由于 Trae CN 等 15 GB 缓存已被清理，扫描耗时从 33 分钟降到 9.7 分钟（-71%）。

### 清理前后性能对比

| 指标 | 清理前 (5/16) | 清理后 (5/18) | 变化 |
|------|-------------|-------------|------|
| 健康评分 | 17/100 🔴 | 50/100 🟡 | **+33** |
| 使用率 | 91.7% | 74.4% | **↓ 17.3%** |
| 扫描耗时 | ~33 分钟 | ~9.7 分钟 | **↓ 71%** |
| 可用空间 | 12.37 GB | 38.17 GB | **+25.8 GB** |

### 数据一致性分析

本次扫描相比前三次扫描：
- 健康评分：从稳定的 17/100 跳到 50/100 ✅（因为清理后使用率下降了）
- 扫描耗时：从 33 分钟降到 9.7 分钟 ✅（因为大目录被清理后遍历更快）
- 数据可信度：高，与前三次一致

---

## 性能优化追踪

### 当前瓶颈

| 瓶颈 | 说明 | 优化方向 |
|------|------|---------|
| E 类扫描慢 | 应用数据需递归遍历大量文件夹 | 增量扫描 / 缓存机制 |
| J 类检测慢 | Electron 运行时检测需遍历所有应用 | 预编译签名数据库 |
| 全量扫描耗时（原33分已优化到9.7分） | 清理后大目录减少 | 已部分优化 |

### 目标性能

| 模式 | 上次耗时 | 最新耗时 | 优化目标 |
|------|---------|---------|---------|
| 🚀 极速 | 待测 | 待测 | 15-30 秒 |
| ⚡ 快速 | 33 分钟 | **9.7 分钟** | 1-2 分钟（需增量扫描） |
| 🔬 标准 | 33 分钟 | 待测 | 3-5 分钟 |
| 🎯 自定义 | 待测 | 30-60秒（2类） | 30-60 秒 |

---

*最后更新: 2026-05-18（含清理后扫描 + 性能对比）*

---

## v6.2.0：有界迭代与增长扫描（2026-08-10）

| 模式 | 实际耗时 | 说明 |
|---|---:|---|
| `track-growth.ps1 -Mode compare` | 约 20-35 秒 | 重点目录 robocopy `/L` 统计，不复制文件 |
| `analyze.ps1 -Fast` | 约 84 秒 | 14 类快速证据集，跳过 F/H |
| `scan-large-files.ps1` | 约 122 秒 | 仍是慢速、按需执行的全盘文件排行 |
| `iteration-loop.ps1 -Mode diagnose` | 约 105 秒 | 扫描、增长对比、清理预览、状态落盘完整收口 |

### 性能结论

快速模式不再因为全盘大文件扫描超时而丢失收口；增长追踪可作为每日监控的轻量入口。F 类仍需作为独立里程碑任务运行，不能伪装成即时扫描。

---

## v6.4.0：实际占用与层级增长（2026-08-12）

| 操作 | 实际耗时 | 说明 |
|---|---:|---|
| v2 层级增长扫描 | 约 49-118 秒 | 37 个 coverage/detail 路径，只读 `/L /XJ` 测量；Temp 活跃时波动较大 |
| SA 八个重点路径 | 约 7.5 秒 | 文件级 NTFS 分配字节与硬链接去重 |
| WU 更新残留扫描 | 约 3.2 秒 | WinRE、更新下载、CBS/DISM、待重启信号 |
| Qoder 实际占用核算 | 约 5-6 秒 | 约 10,733 个文件 |

SA 是按需核算层，不默认加入快速模式；增长扫描保留低置信度状态并用覆盖根与驱动器增量对账。

## v6.4.1 — large-file scanner benchmark (2026-08-12)

| Mode | Measured time | Evidence |
|---|---:|---|
| `scan-large-files.ps1 -TopN 20` | 97.3 seconds | .NET in-process enumeration; 504,251 files; 6 skipped directories |
| previous PowerShell recursive path | over 5 minutes without output | stopped before producing a complete TOP list |

The new scanner is still an on-demand scan, but it now completes on this machine and preserves the read-only boundary.

## v6.5.0 — partitioned native scan and growth reuse (2026-08-13)

| Mode | Before | v6.5.0 measured | Evidence |
|---|---:|---:|---|
| F TOP 20 full C scan | about 111 s / 504k–577k files | 14.9–36.2 s / about 580k files | 422 partitions, parallelism 4, 140 inaccessible directories reported |
| J Electron/CEF inventory | 21.4 s | 11.5–14.4 s | 376k–377k files; vendor containers split into product roots |
| GR in Fast mode | 114.9 s live rescan | 0.2 s cached snapshot | timestamp and measurement source are displayed |
| F followed by GR | about 150 s class | 16.0 s total; GR 0.5 s | 37 growth targets aggregated during F enumeration |
| `analyze.ps1 -Fast` | 153.6 s | 26.6 s | 16 categories, JSON report, no scanner failures |

The ranges reflect Windows filesystem cache and active application churn. Coverage and inaccessible counts are retained so a faster result cannot silently claim higher confidence.

## v6.6.0 — focused fast path and native measurements (2026-08-14)

| Mode | v6.5.0 baseline | v6.6.0 measured | Evidence |
|---|---:|---:|---|
| `analyze.ps1 -Fast` | 26.6 s warm; 45.2 s cold observation | 9.5-11.7 s | 16 categories, JSON output, no scanner failures |
| J focused runtime inventory | 21.4 s before focused mode | 0.6 s native traversal; 1.9 s category | 17,613 files, same 8 findings as broad J |
| J broad runtime inventory | 21.4 s class | 22.1 s native traversal | 383,651 files, 247 candidates, 8 findings, 2 skipped directories |
| VM assessment | 5.7 s | 0.6-0.7 s | one CIM association/disk batch for C/D/E |
| O targeted measurement | 2.3-3.8 s | 0.8 s | four-way native batch; redirected Qoder tree excluded |

The fast path is explicitly partial discovery, not a replacement for broad J. Reparse-point ancestry is treated as a volume-accounting boundary so D/E targets cannot inflate C reclaim estimates.

## v6.7.0 — global measurement plan (2026-08-14)

| Mode | v6.6.0 measured | v6.7.0 measured | Evidence |
|---|---:|---:|---|
| `analyze.ps1 -Fast` | 9.5-11.7 s | 5.7-5.9 s analyzer / 6.3-6.4 s wall | 16 categories, JSON output, no scanner failures |
| Logical path measurement | sequential cache misses | 1.4 s native batch | 88 unique paths seeded; 91 downstream hits / 0 misses |
| B category after planning | included in sequential work | 0.1 s | 26 planned paths in isolated B run; 26 hits / 0 misses |

The planner performs exact-path deduplication only. It does not collapse parents and children globally because scanners may require separate child evidence. Protected paths and reparse boundaries retain their original status.
