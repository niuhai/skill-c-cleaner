# 实际占用、增长归因与再生验证

## 目录

- [三种空间数值](#三种空间数值)
- [层级化增长追踪](#层级化增长追踪)
- [清理后再生验证](#清理后再生验证)
- [Windows 更新残留](#windows-更新残留)

## 三种空间数值

必须区分：

- `entryLogicalBytes`：目录项声明的文件长度总和；硬链接会重复出现。
- `uniqueLogicalBytes`：按 NTFS 文件标识去重后的逻辑长度。
- `allocatedBytes`：通过 `GetCompressedFileSizeW` 测得、并按文件标识去重的分配字节；用于解释稀疏、压缩和硬链接差异。

`measure-space.ps1` 对文件逐个探测，因此必须受 `MaxFiles` 和 `MaxSeconds` 限制。状态为 `bounded-partial`、`partial` 或 `probe-unavailable` 时，不得声称结果精确。

清理成效的最终依据仍是同一时段的 C 盘 `AvailableFreeSpace` 差值。后台写入可能让驱动器差值与目标分配字节不完全一致，必须同时报告两者，不得把逻辑大小称为“实际释放”。

## 层级化增长追踪

`growth-watch.json` 将目标分成：

- `coverage`：互不嵌套的 C 盘覆盖根，可用于和驱动器实际增量对账。
- `detail`：应用和子目录明细，只用于归因，绝不与父目录相加。

快照 schema 或 measurementVersion 改变时，主动废弃旧基线并建立新基线。比较时要求前后状态一致；权限造成的 `partial` 允许低置信度比较，但报告必须标记 `consistent-partial`。

若覆盖根增量与驱动器增量相差超过容差，标记 `measurement-mismatch`，不得给出确定归因。优先检查权限变化、重分析点、未覆盖根文件和后台写入。

## 清理后再生验证

定向清理器执行时自动记录：

- 清理前目标逻辑/分配字节；
- 清理后即时目标逻辑/分配字节；
- C 盘实际可用空间变化；
- 删除失败或仍残留的路径。

使用 `track-regeneration.ps1 -Mode check -SessionId <id>` 在约 5 分钟、1 小时和 24 小时后复测。应用重新生成超过 100 MB 时，将其视为再生源；不要反复删除，应优先修改应用缓存策略、关闭后台更新或迁移数据。

## Windows 更新残留

`WU` 类读取 `$WinREAgent`、SoftwareDistribution、Delivery Optimization、CBS/DISM 日志，并检查待重启信号。

- 有待重启信号时，保留恢复和更新工作目录。
- 更新完成后优先使用 Windows“存储/临时文件”清理入口。
- 不自动删除 `$WinREAgent`、组件存储、恢复目录或服务中的更新目录。
