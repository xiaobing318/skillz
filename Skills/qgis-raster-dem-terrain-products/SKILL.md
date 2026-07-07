---
name: qgis-raster-dem-terrain-products
description: DEM 地形产品生成。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
  - write_file
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

## 普通提示词处理规则

- 如果用户只给出测试数据目录，直接按该目录下的 `input`、`output`、`logs` 和 `output\scratch` 处理，不要求用户补充完整参数。
- 在 `C:\Data\QGISData\TestData\qgis-raster-dem-terrain-products` 测试目录中，默认使用 `input\dem.tif` 作为 DEM 输入。
- 用户没有给出等高距时，测试数据默认使用 `10`。没有给出 z_factor 时默认使用 `1`。必须在 `logs\step-01-prepare.log` 和 `summary.json` 中写明默认值、CRS 和高程单位。
- 先创建 `output`、`logs`、`output\scratch` 三个目录，再做任何检查、转换或输出。不得修改 `input` 原始数据。
- 用户要求“生成”或“分析”时，本轮默认重新生成标准成果，不要只读取已有的 `summary.json` 或旧成果后宣称完成。若 `output` 中已有同名标准成果，只能覆盖本技能约定的 `slope.tif`、`aspect.tif`、`hillshade.tif`、`contours.gpkg` 和 `summary.json`，并在日志中写明覆盖对象。也可以改用带本轮时间后缀的输出文件。

## 输出

- slope.tif、aspect.tif、hillshade.tif。
- contours.gpkg 或 contours.shp。
- 地形产品 summary.json。

## 固定工作流

1. 准备任务
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs、output\scratch。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在，日志包含 contour_interval、z_factor 和 scratch_dir。

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
- 每条命令都用 `exec_shell_command` 执行。优先直接调用完整工具路径，避免把整条 Windows 命令再包进额外的外层引号。
- 本技能只使用 `exec_shell_command`、`read_file` 和 `write_file`。不要调用 `edit_file`。日志、SQL、JSON、参数文件或脚本写错时，用 `write_file` 重写完整文件，或用 `exec_shell_command` 重新生成。
- 向工具的 JSON 参数写 Windows 路径时，不要直接写单反斜杠路径。使用双反斜杠 `C:\\Data\\...\\input\\dem.tif`，或使用正斜杠 `C:/Data/.../input/dem.tif`，避免 `\r`、`\t` 被当成 JSON 控制字符导致路径变形。
- 对 `mkdir`、`dir`、`copy`、`move`、`del` 这类 cmd 内置命令，先 `cd /d C:\Data\QGISData\TestData\qgis-raster-dem-terrain-products` 到测试根目录，再用相对路径执行。例如 `cd /d C:\Data\QGISData\TestData\qgis-raster-dem-terrain-products && mkdir output 2>nul && mkdir logs 2>nul && mkdir output\scratch 2>nul`。不要反复尝试 `mkdir "C:\Data\...\output"` 形式。
- Python 脚本可以把中文写入 UTF-8 文件，但控制台输出尽量只写 ASCII 状态、数字和路径。确实需要输出中文时，在命令前设置 `PYTHONIOENCODING=utf-8`，避免 Windows 控制台编码触发 `UnicodeEncodeError`。
- 已核验的工具入口：
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdaldem.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdal_contour.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\ogrinfo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat`
- `qgis_process-qgis-qt6.bat` 会自行调用 QGIS 环境。不要改用未核验的 qgis_process 入口，也不要手工拼接旧式环境初始化命令链。
- 最小探测命令：

```cmd
"C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe" --version
"C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat" plugins list
```

- 任务命令中的单个路径参数可以加双引号，但不要把整条命令作为带引号的一个参数提交。测试目录路径当前不含空格时，可直接使用完整路径，减少转义错误。
- 需要写参数文件、SQL、JSON 或摘要时，优先使用 `write_file` 写到 `logs` 或 `output`。如果改用 `exec_shell_command` 重定向生成文件，先确认父目录存在。
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
