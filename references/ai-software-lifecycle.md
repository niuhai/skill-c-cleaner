# AI 软件生命周期占用与实机迭代

AI 桌面软件不能只按“安装目录”核算。一次 AF 扫描同时区分：安装包、Electron/浏览器会话数据、当前与旧 runtime、模型、扩展、索引、工作区状态、崩溃转储和更新残留。整个应用目录只进入 inventory；只有配置中精确标成 `safe-clean` 或 `managed-clean` 的子路径才进入可释放额度。

## 实机闭环

1. **发现**：运行 `./analyze.ps1 -Categories AF -OutputFormat json -RecordGrowth`，得到应用级 C 盘逻辑占用、安装盘、活跃进程、清理额度、迁移候选和未分类热点。AF 排除重解析目标，但逻辑字节不等于 NTFS 实际分配字节；执行清理时用 cleanup session 核验分配字节与盘符可用空间，慢速审计可用 SA 类。
2. **分类**：对 `scanner_metadata.AF.discovery_candidates` 逐项判断为 `safe-clean`、`managed-clean`、`preserve` 或 `review`。未拿到应用语义或权威依据前保持 `review`。
3. **沉淀**：把已验证根和精确组件加入 `extensions/ai-footprints.json`；不能把整个 `User`、`workspaceStorage`、`History`、数据库、当前 runtime、模型或扩展目录写成安全缓存。
4. **验证**：运行 `tests/validate-ai-footprints.ps1`、AF 复扫和清理预览。检查父子去重、重解析点、空正则、进程门禁和报告总量。
5. **执行与复盘**：默认只预览 `cleaners/clean-ai-footprints.ps1`；执行必须显式加 `-ReallyDelete`。用生成的 cleanup session 在 5 分钟、1 小时和 24 小时复测再生。反复生成的内容改为迁移、限额或工具自带清理，不继续机械删除。

这就是“边发现问题、边优化 Skill”：扫描结果产生学习队列，人工/Agent 结合语义和来源晋级规则，随后用同一台机器复扫。发现本身不会自动获得删除权限。

## 迁移优先级

- **官方环境变量或 CLI**：优先。例如 Playwright 的 `PLAYWRIGHT_BROWSERS_PATH`、Ollama 的 `OLLAMA_MODELS`、Hugging Face 的 `HF_HOME`/`HF_HUB_CACHE`。
- **应用设置或安装器**：其次。安装目录应由应用商店、Windows 设置或厂商安装器移动，不能直接拖动或删除。
- **Junction**：最后手段。仅在应用完全退出后执行复制、字节核验、保留回滚副本、建链、重启应用验证和 C 盘复扫。扫描和清理不得沿 junction 进入目标盘。

运行 `./migrators/plan-ai-footprints.ps1` 可从最新 AF JSON 报告生成只读迁移计划；它不会移动、建链、改环境变量或删除源目录。迁移候选与缓存清理候选可能重叠，不能相加。

## 上游依据

- Electron 默认把 `userData` 放在应用数据目录，并默认让 `sessionData` 与它同址；官方特别说明 Chromium 磁盘缓存可能很大，并允许应用在 ready 前把 `sessionData` 指向其他位置：<https://github.com/electron/electron/blob/main/docs/api/app.md>
- Playwright 浏览器二进制在 Windows 默认进入 `%USERPROFILE%\AppData\Local\ms-playwright`，支持 `PLAYWRIGHT_BROWSERS_PATH`，并提供 `install --list`、`uninstall` 等生命周期命令：<https://github.com/microsoft/playwright/blob/main/docs/src/browsers.md>
- Ollama 官方 Windows 文档说明模型可能占几十到数百 GB，并支持 `OLLAMA_MODELS` 指定模型位置：<https://github.com/ollama/ollama/blob/main/docs/windows.mdx>
- Hugging Face 官方环境变量文档定义 `HF_HOME`、`HF_HUB_CACHE`、Xet 与 assets 缓存；Windows 禁用符号链接会产生大文件副本警告：<https://github.com/huggingface/huggingface_hub/blob/main/docs/source/en/package_reference/environment_variables.md>
- Hugging Face CLI 提供 `hf cache ls`、`rm --dry-run` 和 `prune --dry-run`，因此模型/快照优先走工具自身的引用感知清理：<https://github.com/huggingface/huggingface_hub/blob/main/docs/source/en/package_reference/cli.md>
- VS Code CLI 支持 `--user-data-dir` 和 `--extensions-dir`；衍生 IDE 只有在本机版本验证支持时才能采用，不能把 VS Code 能力直接假定为第三方兼容：<https://github.com/microsoft/vscode-docs/blob/main/docs/configure/command-line.md>
- Czkawka 的做法提醒扫描器默认不跟随符号链接、硬链接按同一物理数据处理，并对删除使用多阶段确认：<https://github.com/qarmin/czkawka/blob/master/instructions/FAQ.md>
- dua 展示了并行、低开销的磁盘统计与分阶段删除安全设计；CleanSight 的 AF 类同样把高性能盘点和删除授权分开：<https://github.com/Byron/dua-cli>
