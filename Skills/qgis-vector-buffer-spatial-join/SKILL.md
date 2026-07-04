---
name: qgis-vector-buffer-spatial-join
description: 矢量缓冲区空间连接。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理矢量数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: vector
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-vector-buffer-spatial-join
---

# 矢量缓冲区空间连接

## 任务目标

围绕道路、管线或设施生成缓冲区，把点位或目标图层按空间关系连接到缓冲结果。

## 输入

- line_or_polygon_layer：需要生成缓冲区的图层。
- join_layer：待连接的点、线或面图层。
- buffer_distance：缓冲距离。
- predicate：空间关系，默认 intersects。

## 输出

- 缓冲区图层。
- 空间连接后的成果图层。
- 命中统计表和步骤日志。
- encoding-normalization.json 或 summary.json.encoding，记录源字符集、目标字符集、转换命令和人工核查点。

## 固定工作流

1. 准备任务目录
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs，并记录缓冲距离和空间关系。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：日志包含 buffer_distance。

2. 检查缓冲输入
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo.exe -so 检查道路或设施图层。
   - 日志：`logs/step-02-source.log`。
   - 成功判定：输入可读且要素数大于 0。

3. 探测并统一字符集
   - 工具：`exec_shell_command`。
   - 做法：读取 .cpg、ogrinfo 输出和 CSV 文本头信息，识别 GBK/CP936、ISO-8859-1、Windows-1252 或 UTF-8。发现非 UTF-8 时，使用 ogr2ogr -oo ENCODING=<源编码> -lco ENCODING=UTF-8 写入 scratch 中的 UTF-8 副本；输出 Shapefile 必须写 .cpg=UTF-8，GPKG 和 GeoJSON 记录为 UTF-8 安全容器。
   - 日志：`logs/step-03-encoding.log`。
   - 成功判定：日志包含 source_encoding、target_encoding=UTF-8 和 STEP_OK，summary.json 或 manifest.json 记录转换结果。

4. 检查连接图层
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo.exe -so 检查 join_layer。
   - 日志：`logs/step-04-join.log`。
   - 成功判定：连接图层可读。

5. 统一 CRS
   - 工具：`exec_shell_command`。
   - 做法：必要时把两个图层重投影到同一投影坐标系。
   - 日志：`logs/step-05-crs.log`。
   - 成功判定：距离单位和缓冲距离一致。

6. 生成缓冲区
   - 工具：`exec_shell_command`。
   - 做法：使用 qgis_process native:buffer 或 ogr2ogr SQL 生成缓冲。
   - 日志：`logs/step-06-buffer.log`。
   - 成功判定：缓冲成果存在。

7. 空间连接
   - 工具：`exec_shell_command`。
   - 做法：使用 qgis_process native:joinattributesbylocation。
   - 日志：`logs/step-07-join.log`。
   - 成功判定：连接成果存在并保留来源字段。

8. 统计命中结果
   - 工具：`exec_shell_command`。
   - 做法：按道路编号或类型统计命中数量。
   - 日志：`logs/step-08-stats.log`。
   - 成功判定：统计表存在。

9. 写运行摘要
   - 工具：`exec_shell_command`。
   - 做法：写 summary.json 并列出未命中对象。
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
