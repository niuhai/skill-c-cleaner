# CleanSight 测试与评测体系

> **配套文档**: 与 [CONTEST-SUBMISSION.md](../CONTEST-SUBMISSION.md) 同步维护
> **核心理念**: 主代码改了 → 测试文件也跟着改 → 不断记录想法和优化

---

## 目录结构

```
tests/
├── README.md                       ← 你在这里
├── TEST-RESULTS-LOG.md             ← 真实测试结果日志（持续追加）
├── IDEA-LOG.md                     ← 想法、创意、优化追踪（持续更新）
├── validate-managed-storage.ps1    ← 厂商托管存储结构、只读行为与无直接 cleaner 验证
├── validate-scan-reuse.ps1         ← F 全盘聚合向 MX 共享测量缓存的报告验证
│
├── methodology/                     ← 测试方法论
│   └── test-strategies.md          ← 各模式测试方法说明
│
├── scenarios/                       ← 场景测试记录
│   └── all-scenarios.md            ← 完整场景测试结果汇总
│
└── performance/                     ← 性能基准测试
    └── benchmark-history.md         ← 性能数据历史记录
```

## 同步维护规则

| 事件 | 你需要做的事 |
|------|------------|
| 修改了 scanner/ 下的脚本 | 更新 TEST-RESULTS-LOG.md + scenarios 对应记录 |
| 修改了 memory/ 下的脚本 | 更新 IDEA-LOG.md（记录新的学习能力） |
| 修改了 analyze.ps1 | 更新 benchmark-history.md（性能变化） |
| 有了新的想法 | 记录到 IDEA-LOG.md |
| 做了新的测试 | 追加到 TEST-RESULTS-LOG.md |
| 更新了 CONTEST-SUBMISSION.md | 同步更新这里的对应数据 |

## 文件说明

| 文件 | 用途 | 谁维护 |
|------|------|--------|
| `TEST-RESULTS-LOG.md` | 按时间线记录每次真实测试的结果 | AI + 用户共同维护 |
| `IDEA-LOG.md` | 记录优化想法、新功能点子、踩坑经验 | AI 主动提出 + 用户补充 |
| `methodology/test-strategies.md` | 各模式的测试方法和验收标准 | AI 维护 |
| `scenarios/all-scenarios.md` | 按场景组织的测试结果 | AI 维护 |
| `performance/benchmark-history.md` | 性能基线数据追踪 | AI 维护 |
