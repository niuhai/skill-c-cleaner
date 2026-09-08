# 厂商托管存储

有些大目录确实是缓存或下载归档，但不能因为路径名含 `cache`、`dist` 就直接删除。`MS` 类只负责发现和核算；它没有对应的直接删除器。

## WPS 云文档缓存

`%USERPROFILE%\WPS Cloud Files\.*\cachedata` 是 WPS 云文档的本地传输/离线缓存。下载内容可重新获取，但尚未完成上传的数据可能还没有云端副本。因此先确认同步状态，再使用 WPS 云盘设置里的“释放空间”。长期治理应在“全局设置 → 存储管理”中更换云文档缓存位置。

- 清理与更换位置：[WPS 学堂：如何删除 WPS 云盘文件](https://www.wps.cn/learning/question/detail/id/333345)
- 新版存储管理：[WPS 学堂：更改文档备份和云文档缓存位置](https://www.wps.cn/learning/question/detail/id/335637)

## ESP-IDF 下载归档

ESP-IDF 默认把工具放在 `%USERPROFILE%\.espressif`，也可由 `IDF_TOOLS_PATH` 改写。`dist` 保存下载归档，`tools` 保存当前工具链，`python_env` 保存虚拟环境。只把 `dist` 列为谨慎管理项；绝不把整个 `.espressif` 或 `tools/python_env` 当缓存删除。

优先从当前 ESP-IDF 树运行：

```powershell
python "$env:IDF_PATH\tools\idf_tools.py" uninstall --dry-run --remove-archives
```

核对 active IDF 版本与 dry-run 输出后，才能考虑去掉 `--dry-run`。后续迁移优先在安装前设置 `IDF_TOOLS_PATH`，Python 环境可用 `IDF_PYTHON_ENV_PATH` 单独放置。

- 官方结构、环境变量和卸载命令：[ESP-IDF Downloadable Tools](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/tools/idf-tools.html)
