---
name: qgis-vector-reproject-convert-package
description: 矢量重投影转换打包。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理矢量数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: vector
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-vector-reproject-convert-package
---

# 矢量重投影转换打包

## 任务目标

把单个或批量矢量数据统一重投影、转换格式、整理字段并生成交付清单。

## 输入

- input_dir 或 input_file：待转换矢量数据。
- target_crs：目标 CRS。
- target_format：gpkg、shp 或 geojson。
- field_map：可选字段重命名或保留清单。

## 输出

- 转换后的矢量成果。
- manifest.json，记录来源、目标 CRS、格式和字段映射。
- 每个转换步骤的日志。
- encoding-normalization.json 或 summary.json.encoding，记录源字符集、目标字符集、转换命令和人工核查点。

## 固定工作流

1. 准备输出包
   - 工具：`exec_shell_command`。
   - 做法：创建 package、logs、scratch 目录。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：目录存在。

2. 枚举输入数据
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo 或目录扫描识别矢量文件。
   - 日志：`logs/step-02-scan.log`。
   - 成功判定：待转换清单不为空。

3. 探测并统一字符集
   - 工具：`exec_shell_command`。
   - 做法：读取 .cpg、ogrinfo 输出和 CSV 文本头信息，识别 GBK/CP936、ISO-8859-1、Windows-1252 或 UTF-8。发现非 UTF-8 时，使用 ogr2ogr -oo ENCODING=<源编码> -lco ENCODING=UTF-8 写入 scratch 中的 UTF-8 副本；输出 Shapefile 必须写 .cpg=UTF-8，GPKG 和 GeoJSON 记录为 UTF-8 安全容器。
   - 日志：`logs/step-03-encoding.log`。
   - 成功判定：日志包含 source_encoding、target_encoding=UTF-8 和 STEP_OK，summary.json 或 manifest.json 记录转换结果。

4. 检查源 CRS
   - 工具：`exec_shell_command`。
   - 做法：使用 gdalsrsinfo 或 ogrinfo 读取每个输入 CRS。
   - 日志：`logs/step-04-crs.log`。
   - 成功判定：每个数据都有可解释 CRS 或记录为需人工确认。

5. 字段预检
   - 工具：`exec_shell_command`。
   - 做法：检查字段名长度、重复字段和字段映射。
   - 日志：`logs/step-05-fields.log`。
   - 成功判定：field_map 可应用。

6. 执行重投影
   - 工具：`exec_shell_command`。
   - 做法：使用 ogr2ogr -t_srs target_crs。
   - 日志：`logs/step-06-reproject.log`。
   - 成功判定：输出 CRS 正确。

7. 格式转换
   - 工具：`exec_shell_command`。
   - 做法：按 target_format 写 GPKG、Shapefile 或 GeoJSON。
   - 日志：`logs/step-07-convert.log`。
   - 成功判定：成果文件存在且可读。

8. 生成清单
   - 工具：`exec_shell_command`。
   - 做法：写 manifest.json 和人工核查说明。
   - 日志：`logs/step-08-manifest.log`。
   - 成功判定：manifest.json 覆盖所有输入。

9. 最终检查
   - 工具：`exec_shell_command`。
   - 做法：用 ogrinfo 复核成果数量和字段。
   - 日志：`logs/step-09-check.log`。
   - 成功判定：日志无 ERROR。

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
