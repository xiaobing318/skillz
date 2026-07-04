---
name: qgis-vector-quality-repair-export
description: 矢量质检修复导出。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理矢量数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: vector
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-vector-quality-repair-export
---

# 矢量质检修复导出

## 任务目标

对单个或批量矢量数据做结构体检、几何修复、坐标系统一和成果导出。

## 输入

- input_dir 或 input_file：待处理矢量数据，支持 shp、gpkg、geojson。
- output_dir：成果输出目录。
- target_crs：目标坐标系，默认 EPSG:4326。
- required_fields：人工指定的必需字段，可为空。

## 输出

- 修复后的 GeoPackage 或 Shapefile 成果。
- 每个输入数据的检查日志和修复日志。
- summary.json，记录输入、输出、失败原因和人工复核点。
- encoding-normalization.json 或 summary.json.encoding，记录源字符集、目标字符集、转换命令和人工核查点。

## 固定工作流

1. 建立任务目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs、scratch 子目录，并写入 run-start.log。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在且日志末尾出现 STEP_OK。

2. 扫描输入数据
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo.exe 或 dir 枚举输入目录，确认数据包完整。
   - 日志：`logs/step-02-scan.log`。
   - 成功判定：每个目标数据至少包含主文件和可读图层。

3. 探测并统一字符集
   - 工具：`exec_shell_command`。
   - 做法：读取 .cpg、ogrinfo 输出和 CSV 文本头信息，识别 GBK/CP936、ISO-8859-1、Windows-1252 或 UTF-8。发现非 UTF-8 时，使用 ogr2ogr -oo ENCODING=<源编码> -lco ENCODING=UTF-8 写入 scratch 中的 UTF-8 副本；输出 Shapefile 必须写 .cpg=UTF-8，GPKG 和 GeoJSON 记录为 UTF-8 安全容器。
   - 日志：`logs/step-03-encoding.log`。
   - 成功判定：日志包含 source_encoding、target_encoding=UTF-8 和 STEP_OK，summary.json 或 manifest.json 记录转换结果。

4. 读取元信息
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo.exe -so 读取图层、字段、要素数和 CRS。
   - 日志：`logs/step-04-metadata.log`。
   - 成功判定：日志包含 Layer name、Feature Count 或 Geometry。

5. 检查字段和空几何
   - 工具：`exec_shell_command`。
   - 做法：用 qgis_process 或 Python/OGR 检查必需字段、空几何、重复记录。
   - 日志：`logs/step-05-quality.log`。
   - 成功判定：无阻塞问题，或问题已写入 summary.json。

6. 修复几何
   - 工具：`exec_shell_command`。
   - 做法：优先调用 qgis_process native:fixgeometries，必要时使用 ogr2ogr -makevalid。
   - 日志：`logs/step-06-repair.log`。
   - 成功判定：输出图层存在，日志无 ERROR。

7. 统一坐标系
   - 工具：`exec_shell_command`。
   - 做法：使用 ogr2ogr -t_srs 或 qgis_process native:reprojectlayer。
   - 日志：`logs/step-07-reproject.log`。
   - 成功判定：输出 CRS 等于 target_crs。

8. 导出成果
   - 工具：`exec_shell_command`。
   - 做法：使用 ogr2ogr 导出为 GPKG 或 Shapefile，不覆盖未确认文件。
   - 日志：`logs/step-08-export.log`。
   - 成功判定：成果文件存在且 ogrinfo 可读。

9. 汇总并清理
   - 工具：`exec_shell_command`。
   - 做法：写 summary.json，删除 scratch 中可安全清理的临时文件。
   - 日志：`logs/step-09-summary.log`。
   - 成功判定：summary.json status 为 ok 或 partial。

## 字符集规则

- 处理属性字段前先探测字符集，优先读取 `.cpg`，没有声明时记录为 `unknown` 并抽样检查字段值。
- 非 UTF-8 输入先转换到 `output\scratch`，后续步骤只使用 UTF-8 副本，不能直接覆盖原始 input。
- 转换命令必须写入日志，日志中保留 `source_encoding`、`target_encoding=UTF-8`、输入路径和输出路径。
- 输出为 Shapefile 时必须写 `.cpg=UTF-8`，输出为 GPKG 或 GeoJSON 时在摘要中标明 UTF-8 安全容器。
- 发现乱码、无法识别字符集或字段值丢失时停止后续步骤，先说明修复方式。

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
