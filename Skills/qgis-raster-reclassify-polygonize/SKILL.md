---
name: qgis-raster-reclassify-polygonize
description: 栅格重分类矢量化。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
  - write_file
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

## 普通提示词处理规则

- 如果用户只给出测试数据目录，直接按该目录下的 `input`、`output`、`logs` 和 `output\scratch` 处理，不要求用户补充完整参数。
- 在 `C:\Data\QGISData\TestData\qgis-raster-reclassify-polygonize` 测试目录中，默认使用 `input\landcover.tif` 作为待处理栅格，使用 `input\reclass_table.csv` 作为重分类规则。
- 用户没有给出目标 CRS 时保持输入 CRS。没有给出小斑块阈值时跳过筛选并在日志中写明。必须在 `logs\step-01-prepare.log` 和 `summary.json` 中写明规则表、NoData 策略和默认值。
- 本测试目录默认走确定性 Python/GDAL 路线：用 `write_file` 生成短脚本后运行 `C:\Data\QGISPackages\QGIS34407-Release\apps\Python312\python.exe`。不要先摸索 `native:reclassifybytable` 参数，也不要因为一次 `Cannot open` 就反复把同一路径改成正斜杠、双反斜杠或不同引号。
- 先创建 `output`、`logs`、`output\scratch` 三个目录，再做任何检查、转换或输出。不得修改 `input` 原始数据。
- 用户要求“重分类”“矢量化”或“统计”时，本轮默认重新生成标准成果，不要只读取已有的 `summary.json` 或旧成果后宣称完成。若 `output` 中已有同名标准成果，只能覆盖本技能约定的 `reclassified.tif`、`polygonized.gpkg`、`category_stats.csv` 和 `summary.json`，并在日志中写明覆盖对象。也可以改用带本轮时间后缀的输出文件。

## 输出

- reclassified.tif。
- polygonized.gpkg。
- category_stats.csv 和日志。

## 固定工作流

1. 准备目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs、output\scratch。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在，日志包含 reclass_table、nodata_policy 和 scratch_dir。

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
   - 工具：`write_file` + `exec_shell_command`。
   - 做法：默认写 `output\scratch\reclassify.py`，脚本用 `osgeo.gdal` 和 `csv` 读取 `input\landcover.tif` 与 `input\reclass_table.csv`，按 `from <= value <= to` 把像元改写为 `value`，复制输入 GeoTransform、Projection 和 NoData，再写 `output\reclassified.tif`。本测试目录不要优先调用 `native:reclassifybytable`。
   - 命令模板：`"C:\Data\QGISPackages\QGIS34407-Release\apps\Python312\python.exe" "C:\Data\QGISData\TestData\qgis-raster-reclassify-polygonize\output\scratch\reclassify.py"`。
   - 日志：`logs/step-04-reclass.log`。
   - 成功判定：reclassified.tif 存在。

5. 筛选小斑块
   - 工具：`exec_shell_command`。
   - 做法：用户没有给出小斑块阈值时不要调用 sieve，直接写日志说明 `skipped: no threshold provided`。只有用户给出阈值时，才使用 `python.exe -m osgeo_utils.gdal_sieve` 清理碎斑。
   - 日志：`logs/step-05-sieve.log`。
   - 成功判定：输出存在或记录跳过。

6. 矢量化
   - 工具：`exec_shell_command`。
   - 做法：默认使用 `python.exe -m osgeo_utils.gdal_polygonize` 生成面图层，不需要查询 QGIS 算法参数。
   - 命令模板：`"C:\Data\QGISPackages\QGIS34407-Release\apps\Python312\python.exe" -m osgeo_utils.gdal_polygonize "C:\Data\QGISData\TestData\qgis-raster-reclassify-polygonize\output\reclassified.tif" -f GPKG "C:\Data\QGISData\TestData\qgis-raster-reclassify-polygonize\output\polygonized.gpkg" polygonized class_value`。
   - 日志：`logs/step-06-polygonize.log`。
   - 成功判定：polygonized 成果存在。

7. 类别统计
   - 工具：`write_file` + `exec_shell_command`。
   - 做法：默认写 `output\scratch\category_stats.py`，从 `output\reclassified.tif` 读取像元值，按 `reclass_table.csv` 的 `value,label` 统计像元数和面积，面积使用 `abs(pixel_width * pixel_height)`，写 `output\category_stats.csv`。不要用复杂内联 OGR SQL。脚本运行时只在控制台输出 ASCII 状态、数字和路径，中文类别名只写入 UTF-8 CSV 或 JSON，避免 Windows 控制台编码错误。
   - 日志：`logs/step-07-stats.log`。
   - 成功判定：category_stats.csv 存在。

8. 写摘要
   - 工具：`write_file`。
   - 做法：写简短 `summary.json`，记录 `status`、输入文件、输出文件、日志文件、重分类规则数量、NoData 策略和筛选是否跳过。不把长日志、工具调用 timing 或大块文本塞进 summary。
   - 日志：`logs/step-08-summary.log`。
   - 成功判定：summary.json status 为 ok。

## 文本编码规则

- 栅格像元值不做字符集转换。
- CSV、JSON、日志和报告统一写 UTF-8，读取外部文本规则表前先确认编码。

## 命令执行约定

- 默认发布包根目录是 `C:\Data\QGISPackages\QGIS34407-Release`。
- 每条命令都用 `exec_shell_command` 执行。优先直接调用完整工具路径，避免把整条 Windows 命令再包进额外的外层引号。
- 本技能只使用 `exec_shell_command`、`read_file` 和 `write_file`。不要调用 `edit_file`。日志、SQL、JSON、参数文件或脚本写错时，用 `write_file` 重写完整文件，或用 `exec_shell_command` 重新生成。
- 向工具的 JSON 参数写 Windows 路径时，不要直接写单反斜杠路径。使用双反斜杠 `C:\\Data\\...\\input\\reclass_table.csv`，或使用正斜杠 `C:/Data/.../input/reclass_table.csv`，避免 `\r`、`\t` 被当成 JSON 控制字符导致路径变形。
- 对 `mkdir`、`dir`、`copy`、`move`、`del` 这类 cmd 内置命令，先 `cd /d C:\Data\QGISData\TestData\qgis-raster-reclassify-polygonize` 到测试根目录，再用相对路径执行。例如 `cd /d C:\Data\QGISData\TestData\qgis-raster-reclassify-polygonize && mkdir output 2>nul && mkdir logs 2>nul && mkdir output\scratch 2>nul`。不要反复尝试 `mkdir "C:\Data\...\output"` 形式。
- 生成 `reclassify.py` 和 `category_stats.py` 时先一次写完整脚本。脚本失败时优先用 `write_file` 覆盖完整脚本，不用 `edit_file` 对临时脚本打补丁。
- Python 脚本可以把中文写入 UTF-8 文件，但控制台输出尽量只写 ASCII 状态、数字和路径。确实需要输出中文时，在命令前设置 `PYTHONIOENCODING=utf-8`，避免 Windows 控制台编码触发 `UnicodeEncodeError`。
- 已核验的工具入口：
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\ogrinfo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat`
  - `C:\Data\QGISPackages\QGIS34407-Release\apps\Python312\python.exe`
- `python.exe` 可用模块包括 `osgeo_utils.gdal_calc`、`osgeo_utils.gdal_polygonize` 和 `osgeo_utils.gdal_sieve`。不要把这些模块写成未核验的脚本文件路径。
- `qgis_process-qgis-qt6.bat` 会自行调用 QGIS 环境。不要改用未核验的 qgis_process 入口，也不要手工拼接旧式环境初始化命令链。
- 已核验算法包括 `native:reclassifybytable`、`gdal:rastercalculator`、`gdal:sieve`、`gdal:polygonize` 和 `native:polygonize`。
- 对本测试目录，优先级是 Python/GDAL 脚本、`osgeo_utils.gdal_polygonize`、可选 `osgeo_utils.gdal_sieve`。`native:reclassifybytable` 只作为用户明确要求 QGIS Processing 算法时的备选，不作为默认路径。
- 最小探测命令：

```cmd
"C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe" --version
"C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat" plugins list
"C:\Data\QGISPackages\QGIS34407-Release\apps\Python312\python.exe" -m osgeo_utils.gdal_calc --help
```

- 任务命令中的单个路径参数可以加双引号，但不要把整条命令作为带引号的一个参数提交。测试目录路径当前不含空格时，可直接使用完整路径，减少转义错误。
- 需要写重分类参数、JSON 或摘要时，优先使用 `write_file` 写到 `logs` 或 `output`。如果改用 `exec_shell_command` 重定向生成文件，先确认父目录存在。
- 不把长日志直接贴到对话里。先写入 `logs\step-xx-*.log`，再读取日志末尾和关键错误行判断结果。
- 如果日志包含 `ERROR`、`Traceback`、`FAIL`、`Cannot open` 或工具返回非 0 退出码，停止后续步骤，解释失败原因并给出修复建议。
- 遇到 `Cannot open` 时，先核对正在执行的命令是否偏离本技能默认模板。不要连续尝试“改成正斜杠”“改成双反斜杠”“换 qgis_process 参数”这种无依据路径试错。
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
