# 矢量缓冲区空间连接测试清单

- Skill slug：`qgis-vector-buffer-spatial-join`
- 测试数据目录：`C:\Data\QGISData\TestData\qgis-vector-buffer-spatial-join`
- 运行前检查：确认 `input`、`output`、`logs`、`output\scratch`、`chrome-prompts` 和 `user-prompt` 目录存在。
- 命令侧检查：先运行 `C:\Data\QGISPackages\QGIS34407-Release\bin\ogrinfo.exe --version` 和 `C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat plugins list`，确认工具入口可用后再执行处理命令。
- 编码检查：矢量测试数据包含 GBK/CP936 和 ISO-8859-1 样本，运行后确认输出统一为 UTF-8。
- Chrome 检查：普通用户场景使用 `user-prompt\short-prompt.md`，工具直连核验可使用 `chrome-prompts\invoke-skill-tool.md` 或 `chrome-prompts\invoke-skill-tool-02.md`。
- 旧成果检查：普通用户要求“生成”时，不能只读取已有 `summary.json` 当作完成；若覆盖标准输出，确认日志写明覆盖对象。
- 人工复测：不要改原始 input 数据，清理 output/logs 后可重复执行。
