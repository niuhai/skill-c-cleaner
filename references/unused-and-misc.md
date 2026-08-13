# U / MX 扫描边界

## 目录

- [U：不常用软件候选](#u不常用软件候选)
- [MX：C 盘零碎空间信息](#mx-c-盘零碎空间信息)
- [解释和执行边界](#解释和执行边界)

## U：不常用软件候选

`scanners/scan-unused-software.ps1` 读取三组卸载注册表：当前用户、64 位机器和 32 位机器。

候选条件：

- 估计占用至少 200 MB；并且安装日期早于 180 天；或没有安装日期但估计占用至少 1 GB。
- 排除 Windows 更新、运行库、WebView、.NET、Visual C++、补丁和注册表标记为系统组件的项目。
- 同名同发行者的 32/64 位重复记录只保留体积较大的记录。

输出必须称为“候选”而不是“未使用软件”。Windows 卸载注册表没有统一、可靠的最后使用时间字段，因此 U 类只能提供待确认清单，不能自动调用卸载器、删除安装目录或修改注册表。

`EstimatedSize` 是软件自己写入注册表的估计值，可能不等于 NTFS 实际占用；若缺失，扫描器才尝试按安装目录估算。WindowsApps 受 ACL 保护时，Store 应用可能缺失，需要管理员只读扫描补充。

## MX：C 盘零碎空间信息

`scanners/scan-misc-space.ps1` 是解释层，不是清理器，覆盖：

- `C:\` 一级目录的只读大小和不可访问状态；
- C 盘根目录的 pagefile、hiberfil、转储等文件；
- Desktop、Documents、Downloads 和 WPS Cloud Files 的一级散落文件；
- 散落文件的扩展名分布；
- `WindowsApps`、`System Volume Information` 等权限盲区。

MX 结果可能与 A、B、E、F、O 等类别重叠，不能把 MX 的目录总量和清理候选相加。它的目标是回答“这部分空间是什么”，不是直接回答“这部分能删多少”。

MX 默认只做一级目录和一级散落文件检查，避免每次快速诊断都递归扫描整个 C 盘；需要完整文件排行时使用 F 类慢速扫描。

## 解释和执行边界

- U 的结果统一为 `cautious`，用户确认前不卸载。
- MX 的结果进入 `inventory`，不进入可安全释放、需确认释放或禁止删除的合计。
- `analyze.ps1 -OutputFormat json` 同时输出 `findings` 和 `inventory`，消费方必须区分两者。
- `-Fast` 包含 U，但跳过 MX/F/H/SA；MX 虽然有界，仍会测量多个一级目录，因此保留为按需解释层。
