# 管理员深度空间核算（AD）

`AD` 是只读解释层，用于补足普通权限无法可靠统计的系统占用。它不会把受保护目录加入可清理额度，也不会自动删除、卸载或修改系统设置。

## 使用

在管理员 PowerShell 中运行：

```powershell
.\analyze.ps1 -Categories "AD" -OutputFormat json
```

普通权限运行时只读取可用的 Reserved Storage 策略线索，并明确返回 `admin-required`。不会通过绕过 ACL 的方式扫描。

## 核算范围

- `Win32_ShadowStorage`：系统还原/VSS 已用、已分配和上限。
- `DISM /AnalyzeComponentStore /English`：WinSxS 实际组件存储、共享部分、备份/禁用功能、缓存与可回收包数量。
- `Get-AppxPackage -AllUsers`：WindowsApps 各唯一 `InstallLocation` 的逻辑体积聚合及 TOP 20。
- `C:\Windows\Installer`：MSI/MSP 修复、更新和卸载缓存。
- `C:\Windows\System32\DriverStore\FileRepository`：驱动包存储。
- `ReserveManager`：Reserved Storage 策略基线和调整值；这是策略估计，不是当前物理占用。

## 解释边界

- WindowsApps 聚合是逻辑字节；包共享、硬链接、压缩会使它不同于 NTFS 实际分配空间。
- WinSxS 显示的“实际组件存储”与 Windows 目录存在包含关系，不能与 Windows 目录总量相加。
- Installer、DriverStore、WindowsApps、WinSxS 均为 `inventory only`。应用应通过“已安装的应用/winget”卸载，驱动通过 `pnputil` 或设备管理器处理，组件存储只通过 DISM 支持的维护命令处理。
- VSS 空间只能通过系统保护设置或 `vssadmin` 的显式管理流程调整；AD 本身不执行调整。
