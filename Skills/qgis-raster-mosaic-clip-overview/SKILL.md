---
name: qgis-raster-mosaic-clip-overview
description: 栅格镶嵌裁剪概览。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: raster
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-raster-mosaic-clip-overview
---

# 栅格镶嵌裁剪概览

## 任务目标

把多张相邻或重叠栅格构建 VRT、镶嵌为统一栅格，按掩膜裁剪并创建金字塔概览。

## 输入

- input_rasters：2 个以上栅格文件。
- mask_layer：可选裁剪掩膜。
- output_dir：输出目录。
- resampling：重采样方式。

## 输出

- mosaic.vrt 和镶嵌 GeoTIFF。
- 裁剪后的 GeoTIFF。
- 概览层和检查日志。

## 固定工作流

1. 准备目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在。

2. 检查瓦片
   - 工具：`exec_shell_command`。
   - 做法：逐个运行 gdalinfo 检查 CRS、分辨率和波段。
   - 日志：`logs/step-02-tiles.log`。
   - 成功判定：所有瓦片可读。

3. 构建 VRT
   - 工具：`exec_shell_command`。
   - 做法：使用 gdalbuildvrt.exe 构建 mosaic.vrt。
   - 日志：`logs/step-03-vrt.log`。
   - 成功判定：VRT 文件存在。

4. 生成镶嵌图
   - 工具：`exec_shell_command`。
   - 做法：使用 gdal_translate.exe 把 VRT 转为 GeoTIFF。
   - 日志：`logs/step-04-mosaic.log`。
   - 成功判定：mosaic.tif 存在。

5. 掩膜裁剪
   - 工具：`exec_shell_command`。
   - 做法：有 mask_layer 时使用 gdalwarp -cutline 裁剪。
   - 日志：`logs/step-05-clip.log`。
   - 成功判定：裁剪输出存在，或记录跳过。

6. 建立概览
   - 工具：`exec_shell_command`。
   - 做法：使用 gdaladdo.exe 生成 2、4、8 级概览。
   - 日志：`logs/step-06-overview.log`。
   - 成功判定：gdalinfo 能看到 overviews。

7. 写摘要
   - 工具：`exec_shell_command`。
   - 做法：记录瓦片数量、输出范围和概览状态。
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
