---
name: qgis-vector-clip-overlay-stats
description: 矢量裁剪叠加统计。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理矢量数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
  - write_file
metadata:
  domain: qgis
  data-kind: vector
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-vector-clip-overlay-stats
---

# 矢量裁剪叠加统计

## 任务目标

把主体图层按边界裁剪，计算面积或长度，并按分类字段输出统计表。

## 输入

- subject_layer：主体面或线图层。
- overlay_layer：裁剪边界或统计分区。
- output_dir：裁剪成果和统计表目录。
- group_field：可选分类字段。

## 普通提示词处理规则

- 如果用户只给出测试数据目录，直接按该目录下的 `input`、`output`、`logs` 和 `output\scratch` 处理，不要求用户补充完整参数。
- 在 `C:\Data\QGISData\TestData\qgis-vector-clip-overlay-stats` 测试目录中，默认使用 `input\parcels.shp` 作为主体图层，使用 `input\district_boundary.shp` 作为裁剪边界。
- 用户没有给出分类字段时，先从 `parcels.shp` 字段中选择 `landuse`，不存在时按第一个稳定分类字段统计，并在日志中写明。面积统计必须记录 CRS 和面积单位。
- `legacy_names_gbk.*` 和 `legacy_names_latin1.*` 是编码样本，只参与字符集探测和转换记录，不作为裁剪统计的主体图层。
- 先创建 `output`、`logs`、`output\scratch` 三个目录，再做任何检查、转换或输出。不得修改 `input` 原始数据。
- 用户要求“裁剪”“叠加”或“统计”时，本轮默认重新生成标准成果，不要只读取已有的 `summary.json` 或旧成果后宣称完成。若 `output` 中已有同名标准成果，只能覆盖本技能约定的 `clipped_parcels.gpkg`、统计表、`summary.json` 和 `encoding-normalization.json`，并在日志中写明覆盖对象。也可以改用带本轮时间后缀的输出文件。
- 测试数据的主体和边界为 EPSG:4326。不要直接在经纬度图层上用 `$area` 生成 `area_m2`，那只会得到度平方。先把裁剪成果重投影到米制 CRS，再计算面积。当前测试根目录固定使用 `EPSG:32631` 作为面积计算 CRS，并在 `summary.json` 中写明。

## 输出

- 裁剪后的矢量成果。
- 按分类字段汇总的 CSV 或 JSON。
- 每一步对应日志和 summary.json。
- encoding-normalization.json 或 summary.json.encoding，记录源字符集、目标字符集、转换命令和人工核查点。

## 固定工作流

1. 准备目录和参数
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs、output\scratch，记录 subject、overlay、group_field。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：日志包含两个输入路径、group_field 和 scratch_dir。

2. 检查主体图层
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo.exe -so 检查主体图层几何类型和要素数。
   - 日志：`logs/step-02-subject.log`。
   - 成功判定：要素数大于 0。

3. 探测并统一字符集
   - 工具：`exec_shell_command`。
   - 做法：读取 .cpg、ogrinfo 输出和 CSV 文本头信息，识别 GBK/CP936、ISO-8859-1、Windows-1252 或 UTF-8。发现非 UTF-8 时，使用 ogr2ogr -oo ENCODING=<源编码> -lco ENCODING=UTF-8 写入 scratch 中的 UTF-8 副本。输出 Shapefile 必须写 .cpg=UTF-8，GPKG 和 GeoJSON 记录为 UTF-8 安全容器。
   - 日志：`logs/step-03-encoding.log`。
   - 成功判定：日志包含 source_encoding、target_encoding=UTF-8 和 STEP_OK，summary.json 或 manifest.json 记录转换结果。

4. 检查裁剪边界
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo.exe -so 检查边界图层 CRS 和范围。
   - 日志：`logs/step-04-overlay.log`。
   - 成功判定：边界图层可读且范围非空。

5. 坐标系统一
   - 工具：`exec_shell_command`。
   - 做法：若 CRS 不一致，使用 ogr2ogr -t_srs 先转到共同坐标系。
   - 日志：`logs/step-05-crs.log`。
   - 成功判定：后续裁剪使用同一 CRS。

6. 执行裁剪
   - 工具：`exec_shell_command`。
   - 做法：使用 qgis_process-qgis-qt6.bat run native:clip 或 ogr2ogr -clipsrc。
   - 日志：`logs/step-06-clip.log`。
   - 成功判定：裁剪成果存在且可读。

7. 计算面积或长度
   - 工具：`exec_shell_command`。
   - 做法：面图层先运行 `qgis_process-qgis-qt6.bat run native:reprojectlayer`，把 `output\clipped_parcels.gpkg` 写成 `output\scratch\clipped_parcels_metric.gpkg`。当前测试数据使用 `TARGET_CRS=EPSG:32631`。再运行 `native:fieldcalculator`，输入米制图层，写出 `output\clipped_parcels_with_area.gpkg`，字段名 `area_m2`，`FIELD_TYPE=0`，`FIELD_PRECISION=2`，表达式 `$area`。不要先在 EPSG:4326 图层上计算 `area_m2`。
   - 日志：`logs/step-07-measure.log`。
   - 成功判定：`ogrinfo -so -al output\clipped_parcels_with_area.gpkg` 能读到 `area_m2`，且抽样值非空。不要因为 `ogrinfo -sql` 显示层名为 `SELECT` 或字段类型文本不同就反复重算，字段存在、要素数正确、面积值非空即可进入统计。

8. 分组统计
   - 工具：`write_file` 和 `exec_shell_command`。
   - 做法：优先用 `write_file` 写一个完整的 `logs\build_stats.py`，脚本只读取 `output\clipped_parcels_with_area.gpkg`，按 `landuse` 或实际 group_field 汇总 `area_m2`，输出 `output\area_stats.json` 和 `output\area_stats.csv`。脚本用 `C:\Data\QGISPackages\QGIS34407-Release\apps\Python312\python.exe` 执行，控制台只输出 ASCII 状态。不要调用 `C:\Data\QGISPackages\QGIS34407-Release\bin\python.exe -c` 导入 QGIS。
   - 日志：`logs/step-08-stats.log`。
   - 成功判定：统计表存在，行数符合分类数。

9. 输出摘要
   - 工具：`write_file`。
   - 做法：写 `summary.json`，记录输入、输出、日志、裁剪数量、分类字段、面积 CRS、面积单位、统计文件和结论。
   - 日志：`logs/step-09-summary.log`。
   - 成功判定：summary.json status 为 ok。

## 字符集规则

- 处理属性字段前先探测字符集，优先读取 `.cpg`，没有声明时记录为 `unknown` 并抽样检查字段值。
- 非 UTF-8 输入先转换到 `output\scratch`，后续步骤只使用 UTF-8 副本，不能直接覆盖原始 input。
- 转换命令必须写入日志，日志中保留 `source_encoding`、`target_encoding=UTF-8`、输入路径和输出路径。
- 输出为 Shapefile 时必须写 `.cpg=UTF-8`，输出为 GPKG 或 GeoJSON 时在摘要中标明 UTF-8 安全容器。
- 发现乱码、无法识别字符集或字段值丢失时停止后续步骤，先说明修复方式。

## 命令执行约定

- 默认发布包根目录是 `C:\Data\QGISPackages\QGIS34407-Release`。
- 每条命令都用 `exec_shell_command` 执行。优先直接调用完整工具路径，避免把整条 Windows 命令再包进额外的外层引号。
- 本技能只使用 `exec_shell_command`、`read_file` 和 `write_file`。不要调用 `edit_file`。日志、SQL、JSON、参数文件或脚本写错时，用 `write_file` 重写完整文件，或用 `exec_shell_command` 重新生成。
- 向工具的 JSON 参数写 Windows 路径时，不要直接写单反斜杠路径。使用双反斜杠 `C:\\Data\\...\\input\\parcels.gpkg`，或使用正斜杠 `C:/Data/.../input/parcels.gpkg`，避免 `\r`、`\t` 被当成 JSON 控制字符导致路径变形。
- 对 `mkdir`、`dir`、`copy`、`move`、`del` 这类 cmd 内置命令，先 `cd /d C:\Data\QGISData\TestData\qgis-vector-clip-overlay-stats` 到测试根目录，再用相对路径执行。例如 `cd /d C:\Data\QGISData\TestData\qgis-vector-clip-overlay-stats && mkdir output 2>nul && mkdir logs 2>nul && mkdir output\scratch 2>nul`。不要反复尝试 `mkdir "C:\Data\...\output"` 形式。
- Python 脚本可以把中文写入 UTF-8 文件，但控制台输出尽量只写 ASCII 状态、数字和路径。确实需要输出中文时，在命令前设置 `PYTHONIOENCODING=utf-8`，避免 Windows 控制台编码触发 `UnicodeEncodeError`。
- 已核验的工具入口：
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\ogrinfo.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\ogr2ogr.exe`
  - `C:\Data\QGISPackages\QGIS34407-Release\bin\gdalinfo.exe`
- `qgis_process-qgis-qt6.bat` 会自行调用 QGIS 环境。不要改用未核验的 qgis_process 入口，也不要手工拼接旧式环境初始化命令链。
- 已核验算法包括 `native:clip`。直接使用 `run <algorithm> -- PARAM=VALUE`，不要用 `help`、`show` 或 `info` 试探算法。
- 最小探测命令：

```cmd
"C:\Data\QGISPackages\QGIS34407-Release\bin\ogrinfo.exe" --version
"C:\Data\QGISPackages\QGIS34407-Release\bin\qgis_process-qgis-qt6.bat" plugins list
```

- 任务命令中的单个路径参数可以加双引号，但不要把整条命令作为带引号的一个参数提交。测试目录路径当前不含空格时，可直接使用完整路径，减少转义错误。
- Shapefile 输入必须成组检查 `.shp/.shx/.dbf/.prj/.cpg`，缺少 sidecar 时停止并说明。
- 写 OGR SQL 或统计参数时，优先使用 `write_file` 放到 `logs\*.sql` 或 `logs\*.json`，再用 `-sql @<sql文件路径>` 或对应参数文件调用。这样可以避免内联 SQL 引号被命令执行器拆坏。
- 本技能中 OGR SQL 只用于少量只读抽样，不用于面积计算主流程。不要反复执行 `SELECT pid, district, value, area_m2 ...` 来确认同一件事。若一次抽样命令因为引号或层名失败，改用 `ogrinfo -so -al <数据源>` 确认字段，或进入统计脚本生成最终表。
- `ogr2ogr -sql` 生成的新 GPKG 可能默认把图层命名为 `SELECT`。如果必须保存 SQL 结果，显式加 `-nln <目标图层名>`。不要围绕 `SELECT` 图层名继续猜表名。
- `Warning 3: Cannot find tms_NZTM2000.json (GDAL_DATA is not defined)` 且退出码为 0 时，按警告记录，不作为失败重试理由。
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
