---
name: qgis-raster-zonal-statistics-report
description: 栅格分区统计报告。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: raster
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-raster-zonal-statistics-report
---

# 栅格分区统计报告

## 任务目标

按矢量分区统计栅格均值、最小值、最大值和像元数，输出图层和报告。

## 输入

- zones_layer：分区矢量图层。
- value_raster：待统计栅格。
- zone_id_field：分区编号字段。
- output_dir：输出目录。

## 输出

- 带统计字段的分区图层。
- zonal_stats.csv。
- summary.json 和日志。

## 固定工作流

1. 准备目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在。

2. 检查分区
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo 检查 zones_layer 和 zone_id_field。
   - 日志：`logs/step-02-zones.log`。
   - 成功判定：分区可读且编号字段存在。

3. 检查栅格
   - 工具：`exec_shell_command`。
   - 做法：使用 gdalinfo -stats 检查 value_raster。
   - 日志：`logs/step-03-raster.log`。
   - 成功判定：栅格可读。

4. CRS 和范围检查
   - 工具：`exec_shell_command`。
   - 做法：确认分区和栅格坐标系、范围有重叠。
   - 日志：`logs/step-04-overlap.log`。
   - 成功判定：范围重叠。

5. 执行分区统计
   - 工具：`exec_shell_command`。
   - 做法：使用 qgis_process native:zonalstatisticsfb 或 Python/GDAL。
   - 日志：`logs/step-05-zonal.log`。
   - 成功判定：统计结果表存在。

6. 写回或导出图层
   - 工具：`exec_shell_command`。
   - 做法：生成带统计字段的 GPKG，不直接覆盖原分区。
   - 日志：`logs/step-06-export.log`。
   - 成功判定：输出图层可读。

7. 生成报告
   - 工具：`exec_shell_command`。
   - 做法：写 CSV、summary.json 和人工复核说明。
   - 日志：`logs/step-07-report.log`。
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
