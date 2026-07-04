# 矢量合并去重建索引测试清单

- Skill slug：`qgis-vector-merge-deduplicate-index`
- 测试数据目录：`C:\Data\QGISData\TestData\qgis-vector-merge-deduplicate-index`
- 运行前检查：确认 `input`、`output`、`logs`、`chrome-prompts` 四个目录存在。
- 命令侧检查：运行 `_tests\Run-QgisSkillzCommandTests.ps1` 后查看 `logs`。
- 编码检查：矢量测试数据包含 GBK/CP936 和 ISO-8859-1 样本，运行后确认输出统一为 UTF-8。
- Chrome 检查：使用 `chrome-prompts\invoke-skill-tool.md` 中的完整提示词调用同名 skill tool。
- 人工复测：不要改原始 input 数据，清理 output/logs 后可重复执行。
