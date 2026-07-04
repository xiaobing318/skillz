---
name: qgis-raster-reclassify-polygonize
description: 栅格重分类矢量化。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: raster
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-raster-reclassify-polygonize
---

# 栅格重分类矢量化

## 任务目标

把分类或连续栅格按规则重分类，再矢量化并统计各类别面积。

## 输入

- input_raster：待重分类栅格。
- reclass_table：分类规则。
- output_dir：输出目录。
- target_crs：可选目标 CRS。

## 输出

- reclassified.tif。
- polygonized.gpkg。
- category_stats.csv 和日志。

## 固定工作流

1. 准备目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在。

2. 检查栅格
   - 工具：`exec_shell_command`。
   - 做法：使用 gdalinfo 读取像元大小、NoData、分类范围。
   - 日志：`logs/step-02-info.log`。
   - 成功判定：栅格可读。

3. 读取重分类规则
   - 工具：`exec_shell_command`。
   - 做法：读取 reclass_table 并检查区间是否重叠。
   - 日志：`logs/step-03-table.log`。
   - 成功判定：规则有效。

4. 执行重分类
   - 工具：`exec_shell_command`。
   - 做法：使用 gdal_calc.py、Python/GDAL 或 qgis_process native:reclassifybytable。
   - 日志：`logs/step-04-reclass.log`。
   - 成功判定：reclassified.tif 存在。

5. 筛选小斑块
   - 工具：`exec_shell_command`。
   - 做法：可选使用 gdal_sieve.py 清理碎斑。
   - 日志：`logs/step-05-sieve.log`。
   - 成功判定：输出存在或记录跳过。

6. 矢量化
   - 工具：`exec_shell_command`。
   - 做法：使用 gdal_polygonize.py 或 Python/GDAL 生成面图层。
   - 日志：`logs/step-06-polygonize.log`。
   - 成功判定：polygonized 成果存在。

7. 类别统计
   - 工具：`exec_shell_command`。
   - 做法：按类别统计面积和像元数。
   - 日志：`logs/step-07-stats.log`。
   - 成功判定：category_stats.csv 存在。

8. 写摘要
   - 工具：`exec_shell_command`。
   - 做法：写 summary.json。
   - 日志：`logs/step-08-summary.log`。
   - 成功判定：summary.json status 为 ok。

## 文本编码规则

- 栅格像元值不做字符集转换。
- CSV、JSON、日志和报告统一写 UTF-8，读取外部文本规则表前先确认编码。

## 命令执行约定

- 默认发布包根目录是 `C:\Data\QGISPackages\QGIS34407-Release`。
- 每条命令都用 `exec_shell_command` 执行，命令内部先进入发布包 `bin` 目录，再调用环境脚本。
- 命令模板：

```cmd
cd /d C:\Data\QGISPackages\QGIS34407-Release\bin && call qgis-qt6-env.bat && <具体工具命令> 1> "<日志文件>" 2>&1
```

- 不把长日志直接贴到对话里。先写入 `logs\step-xx-*.log`，再读取日志末尾和关键错误行判断结果。
- 如果日志包含 `ERROR`、`Traceback`、`FAIL`、`Cannot open` 或工具返回非 0 退出码，停止后续步骤，解释失败原因并给出修复建议。
- 成功后才能进入下一步。最后必须写 `summary.json`，记录输入、输出、命令、日志和结论。

## 批处理规则

- 单文件输入按一个任务处理。
- 目录输入按文件名排序逐个处理，每个输入独立日志，不能因为一个失败覆盖其它结果。
- 输出路径已存在时，除非用户明确要求覆盖，否则写入带时间或序号的新文件。
- 所有中间文件放在当前任务的 `output\scratch` 或 `logs` 中，不能修改原始输入。

## 人工复核点

- 检查 `summary.json` 的 `status`、`inputs`、`outputs`、`logs`。
- 随机抽查输出数据能被 `ogrinfo` 或 `gdalinfo` 打开。
- 核对输出 CRS、字段、范围、统计值是否符合任务目标。
