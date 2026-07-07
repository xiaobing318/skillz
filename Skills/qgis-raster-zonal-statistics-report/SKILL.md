---
name: qgis-raster-zonal-statistics-report
description: 栅格分区统计报告。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理栅格数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
  - write_file
metadata:
  domain: qgis
  data-kind: raster
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-raster-zonal-statistics-report
---

# 栅格分区统计报告

## 任务目标

按矢量分区统计栅格均值、总和和像元数，输出图层和报告。用户明确要求最小值、最大值时，再补充对应统计参数或二次统计。

## 输入

- zones_layer：分区矢量图层。
- value_raster：待统计栅格。
- zone_id_field：分区编号字段。
- output_dir：输出目录。

## 普通提示词处理规则

- 如果用户只给出测试数据目录，直接按该目录下的 `input`、`output`、`logs` 和 `output\scratch` 处理，不要求用户补充完整参数。
- 在 `C:\Data\QGISData\TestData\qgis-raster-zonal-statistics-report` 测试目录中，默认使用 `input\zones.shp` 作为分区图层，使用 `input\population.tif` 作为统计栅格。
- 用户没有给出分区编号字段时，先从 `zones.shp` 字段中选择 `zone_id`，不存在时再选择第一个稳定编号字段并写入日志。默认统计项为像元数、总和和均值。
- 先创建 `output`、`logs`、`output\scratch` 三个目录，再做任何检查、转换或输出。不得修改 `input` 原始数据。
- 用户要求“统计”或“生成报告”时，本轮默认重新生成标准成果，不要只读取已有的 `summary.json` 或旧成果后宣称完成。若 `output` 中已有同名标准成果，只能覆盖本技能约定的 `zonal_stats.csv`、分区统计图层和 `summary.json`，并在日志中写明覆盖对象。也可以改用带本轮时间后缀的输出文件。

## 输出

- 带统计字段的分区图层。
- zonal_stats.csv。
- summary.json 和日志。

## 固定工作流

1. 准备目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs、output\scratch。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在，日志包含 zones_layer、value_raster、zone_id_field 和 scratch_dir。

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
   - 做法：使用 `write_file` 生成 `logs\zonal_stats_input.json`，再调用 qgis_process-qgis-qt6.bat run native:zonalstatisticsfb。不要改用 QGIS Python，也不要临时猜测 `INPUT_VECTOR`、`STATS` 等未跑通参数。
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
- 每条命令都用 `exec_shell_command` 执行。优先直接调用完整工具路径，避免把整条 Windows 命令再包进额外的外层引号。
- 本技能只使用 `exec_shell_command`、`read_file` 和 `write_file`。不要调用 `edit_file`。日志、SQL、JSON、参数文件或脚本写错时，用 `write_file` 重写完整文件，或用 `exec_shell_command` 重新生成。
- 向工具的 JSON 参数写 Windows 路径时，不要直接写单反斜杠路径。使用双反斜杠 `C:\\Data\\...\\input\\zones.gpkg`，或使用正斜杠 `C:/Data/.../input/zones.gpkg`，避免 `\r`、`\t` 被当成 JSON 控制字符导致路径变形。
- 对 `mkdir`、`dir`、`copy`、`move`、`del` 这类 cmd 内置命令，先 `cd /d C:\Data\QGISData\TestData\qgis-raster-zonal-statistics-report` 到测试根目录，再用相对路径执行。例如 `cd /d C:\Data\QGISData\TestData\qgis-raster-zonal-statistics-report && mkdir output 2>nul && mkdir logs 2>nul && mkdir output\scratch 2>nul`。不要反复尝试 `mkdir "C:\Data\...\output"` 形式。
- Python 脚本可以把中文写入 UTF-8 文件，但控制台输出尽量只写 ASCII 状态、数字和路径。确实需要输出中文时，在命令前设置 `PYTHONIOENCODING=utf-8`，避免 Windows 控制台编码触发 `UnicodeEncodeError`。
- 已核验的工具入口：
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\ogrinfo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\ogr2ogr.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe`
- `qgis_process-qgis-qt6.bat` 会自行调用 QGIS 环境。不要改用未核验的 qgis_process 入口，也不要手工拼接旧式环境初始化命令链。
- 已核验算法包括 `native:zonalstatisticsfb`。
- 本技能已跑通的分区统计参数文件固定如下。路径使用正斜杠，减少转义问题：

```json
{
  "inputs": {
    "INPUT": "C:/Data/QGISData/TestData/qgis-raster-zonal-statistics-report/input/zones.shp",
    "INPUT_RASTER": "C:/Data/QGISData/TestData/qgis-raster-zonal-statistics-report/input/population.tif",
    "COLUMN_PREFIX": "zone_",
    "OUTPUT": "C:/Data/QGISData/TestData/qgis-raster-zonal-statistics-report/output/scratch/zones_with_stats.gpkg"
  }
}
```

- 调用命令固定使用：

```cmd
C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat run native:zonalstatisticsfb - < C:\Data\QGISData\TestData\qgis-raster-zonal-statistics-report\logs\zonal_stats_input.json
```

- 核查输出属性时使用 `ogrinfo.exe <gpkg> -al -so -fields YES -geom NO`。不要使用 `-fields 3` 这类无效参数。
- 最小探测命令：

```cmd
"C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe" --version
"C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat" plugins list
```

- 任务命令中的单个路径参数可以加双引号，但不要把整条命令作为带引号的一个参数提交。测试目录路径当前不含空格时，可直接使用完整路径，减少转义错误。
- 写 OGR SQL 或统计参数时，优先使用 `write_file` 放到 `logs\*.sql` 或 `logs\*.json`，再用 `-sql @<sql文件路径>` 或对应参数文件调用，避免内联 SQL 引号被命令执行器拆坏。
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
