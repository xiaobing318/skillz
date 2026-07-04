---
name: qgis-raster-dem-terrain-products
description: DEM 地形产品生成。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: raster
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-raster-dem-terrain-products
---

# DEM 地形产品生成

## 任务目标

从 DEM 生成坡度、坡向、阴影和等高线等地形产品，并保留每步日志。

## 输入

- dem_raster：DEM 栅格。
- output_dir：输出目录。
- contour_interval：等高距。
- z_factor：高程缩放系数。

## 输出

- slope.tif、aspect.tif、hillshade.tif。
- contours.gpkg 或 contours.shp。
- 地形产品 summary.json。

## 固定工作流

1. 准备任务
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在。

2. DEM 预检
   - 工具：`exec_shell_command`。
   - 做法：使用 gdalinfo -stats 检查 DEM。
   - 日志：`logs/step-02-dem-info.log`。
   - 成功判定：DEM 可读且有统计值。

3. 生成坡度
   - 工具：`exec_shell_command`。
   - 做法：使用 gdaldem.exe slope。
   - 日志：`logs/step-03-slope.log`。
   - 成功判定：slope.tif 存在。

4. 生成坡向
   - 工具：`exec_shell_command`。
   - 做法：使用 gdaldem.exe aspect。
   - 日志：`logs/step-04-aspect.log`。
   - 成功判定：aspect.tif 存在。

5. 生成阴影
   - 工具：`exec_shell_command`。
   - 做法：使用 gdaldem.exe hillshade。
   - 日志：`logs/step-05-hillshade.log`。
   - 成功判定：hillshade.tif 存在。

6. 生成等高线
   - 工具：`exec_shell_command`。
   - 做法：使用 gdal_contour.exe。
   - 日志：`logs/step-06-contour.log`。
   - 成功判定：contours 输出存在。

7. 质量检查
   - 工具：`exec_shell_command`。
   - 做法：对每个成果运行 gdalinfo 或 ogrinfo。
   - 日志：`logs/step-07-check.log`。
   - 成功判定：全部成果可读。

8. 写摘要
   - 工具：`exec_shell_command`。
   - 做法：记录输出路径、等高距和统计信息。
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
