# DEM 地形产品生成测试清单

- Skill slug：`qgis-raster-dem-terrain-products`
- 测试数据目录：`C:\Data\QGISData\TestData\qgis-raster-dem-terrain-products`
- 运行前检查：确认 `input`、`output`、`logs`、`chrome-prompts` 四个目录存在。
- 命令侧检查：运行 `_tests\Run-QgisSkillzCommandTests.ps1` 后查看 `logs`。
- 文本检查：确认报告、CSV、JSON 和日志使用 UTF-8。
- Chrome 检查：使用 `chrome-prompts\invoke-skill-tool.md` 中的完整提示词调用同名 skill tool。
- 人工复测：不要改原始 input 数据，清理 output/logs 后可重复执行。
