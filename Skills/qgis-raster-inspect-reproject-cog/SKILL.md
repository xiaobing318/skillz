---
name: qgis-raster-inspect-reproject-cog
description: 栅格检查重投影 COG 导出。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: raster
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-raster-inspect-reproject-cog
---

# 栅格检查重投影 COG 导出

## 任务目标

检查单个或批量栅格的范围、NoData、统计值，按目标 CRS 输出压缩 GeoTIFF 或 COG。

## 输入

- input_raster 或 input_dir：待处理栅格。
- target_crs：目标坐标系。
- output_dir：输出目录。
- creation_options：压缩和瓦片选项。

## 输出

- 重投影后的 GeoTIFF/COG。
- gdalinfo 元信息和统计日志。
- summary.json。

## 固定工作流

1. 准备输出目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs、scratch。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在。

2. 读取元信息
   - 工具：`exec_shell_command`。
   - 做法：使用 gdalinfo.exe 读取 CRS、大小、波段和 NoData。
   - 日志：`logs/step-02-info.log`。
   - 成功判定：日志包含 Size is 和 Coordinate System。

3. 计算统计值
   - 工具：`exec_shell_command`。
   - 做法：使用 gdalinfo -stats 或 Python/GDAL 计算统计。
   - 日志：`logs/step-03-stats.log`。
   - 成功判定：日志包含 STATISTICS。

4. 检查 NoData
   - 工具：`exec_shell_command`。
   - 做法：确认 NoData 设置和异常值范围。
   - 日志：`logs/step-04-nodata.log`。
   - 成功判定：异常值写入 summary.json。

5. 重投影
   - 工具：`exec_shell_command`。
   - 做法：使用 gdalwarp.exe -t_srs target_crs。
   - 日志：`logs/step-05-warp.log`。
   - 成功判定：输出栅格存在。

6. 导出 COG
   - 工具：`exec_shell_command`。
   - 做法：使用 gdal_translate.exe -of COG -co COMPRESS=LZW。
   - 日志：`logs/step-06-cog.log`。
   - 成功判定：COG 文件存在且 gdalinfo 可读。

7. 最终校验
   - 工具：`exec_shell_command`。
   - 做法：再次运行 gdalinfo 并写 summary.json。
   - 日志：`logs/step-07-summary.log`。
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
