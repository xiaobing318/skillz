---
name: qgis-raster-mosaic-clip-overview
description: 栅格镶嵌裁剪概览。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
  - write_file
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

## 普通提示词处理规则

- 如果用户只给出测试数据目录，直接按该目录下的 `input`、`output`、`logs` 和 `output\scratch` 处理，不要求用户补充完整参数。
- 在 `C:\Data\QGISData\TestData\qgis-raster-mosaic-clip-overview` 测试目录中，默认使用 `input\tile_west.tif` 和 `input\tile_east.tif` 作为待镶嵌栅格，使用 `input\clip_mask.shp` 作为裁剪掩膜。
- 用户没有给出重采样方式时默认使用 `near`。必须在 `logs\step-01-prepare.log` 和 `summary.json` 中写明默认值、瓦片数量和掩膜图层。
- 先创建 `output`、`logs`、`output\scratch` 三个目录，再做任何检查、转换或输出。不得修改 `input` 原始数据。
- 用户要求“镶嵌”“裁剪”或“建立概览”时，本轮默认重新生成标准成果，不要只读取已有的 `summary.json` 或旧成果后宣称完成。若 `output` 中已有同名标准成果，只能覆盖本技能约定的 `mosaic.vrt`、`mosaic.tif`、裁剪成果和 `summary.json`，并在日志中写明覆盖对象。也可以改用带本轮时间后缀的输出文件。

## 输出

- mosaic.vrt 和镶嵌 GeoTIFF。
- 裁剪后的 GeoTIFF。
- 概览层和检查日志。

## 固定工作流

1. 准备目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs、output\scratch。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在，日志包含 raster_count、mask_layer 和 scratch_dir。

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
- 每条命令都用 `exec_shell_command` 执行。优先直接调用完整工具路径，避免把整条 Windows 命令再包进额外的外层引号。
- 本技能只使用 `exec_shell_command`、`read_file` 和 `write_file`。不要调用 `edit_file`。日志、SQL、JSON、参数文件或脚本写错时，用 `write_file` 重写完整文件，或用 `exec_shell_command` 重新生成。
- 向工具的 JSON 参数写 Windows 路径时，不要直接写单反斜杠路径。使用双反斜杠 `C:\\Data\\...\\input\\tile_a.tif`，或使用正斜杠 `C:/Data/.../input/tile_a.tif`，避免 `\r`、`\t` 被当成 JSON 控制字符导致路径变形。
- 对 `mkdir`、`dir`、`copy`、`move`、`del` 这类 cmd 内置命令，先 `cd /d C:\Data\QGISData\TestData\qgis-raster-mosaic-clip-overview` 到测试根目录，再用相对路径执行。例如 `cd /d C:\Data\QGISData\TestData\qgis-raster-mosaic-clip-overview && mkdir output 2>nul && mkdir logs 2>nul && mkdir output\scratch 2>nul`。不要反复尝试 `mkdir "C:\Data\...\output"` 形式。
- Python 脚本可以把中文写入 UTF-8 文件，但控制台输出尽量只写 ASCII 状态、数字和路径。确实需要输出中文时，在命令前设置 `PYTHONIOENCODING=utf-8`，避免 Windows 控制台编码触发 `UnicodeEncodeError`。
- 已核验的工具入口：
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdalbuildvrt.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdal_translate.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdalwarp.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdaladdo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\ogrinfo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat`
- `qgis_process-qgis-qt6.bat` 会自行调用 QGIS 环境。不要改用未核验的 qgis_process 入口，也不要手工拼接旧式环境初始化命令链。
- 最小探测命令：

```cmd
"C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe" --version
"C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat" plugins list
```

- 任务命令中的单个路径参数可以加双引号，但不要把整条命令作为带引号的一个参数提交。测试目录路径当前不含空格时，可直接使用完整路径，减少转义错误。
- Shapefile 掩膜必须成组检查 `.shp/.shx/.dbf/.prj/.cpg`，缺少 sidecar 时停止并说明。
- 需要写 VRT 清单、参数文件、JSON 或摘要时，优先使用 `write_file` 写到 `logs` 或 `output`。如果改用 `exec_shell_command` 重定向生成文件，先确认父目录存在。
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
