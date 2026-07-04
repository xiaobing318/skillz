---
name: qgis-vector-clip-overlay-stats
description: 矢量裁剪叠加统计。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理矢量数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
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

## 输出

- 裁剪后的矢量成果。
- 按分类字段汇总的 CSV 或 JSON。
- 每一步对应日志和 summary.json。
- encoding-normalization.json 或 summary.json.encoding，记录源字符集、目标字符集、转换命令和人工核查点。

## 固定工作流

1. 准备目录和参数
   - 工具：`exec_shell_command`。
   - 做法：创建输出目录，记录 subject、overlay、group_field。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：日志包含两个输入路径。

2. 检查主体图层
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo.exe -so 检查主体图层几何类型和要素数。
   - 日志：`logs/step-02-subject.log`。
   - 成功判定：要素数大于 0。

3. 探测并统一字符集
   - 工具：`exec_shell_command`。
   - 做法：读取 .cpg、ogrinfo 输出和 CSV 文本头信息，识别 GBK/CP936、ISO-8859-1、Windows-1252 或 UTF-8。发现非 UTF-8 时，使用 ogr2ogr -oo ENCODING=<源编码> -lco ENCODING=UTF-8 写入 scratch 中的 UTF-8 副本；输出 Shapefile 必须写 .cpg=UTF-8，GPKG 和 GeoJSON 记录为 UTF-8 安全容器。
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
   - 做法：使用 qgis_process native:clip 或 ogr2ogr -clipsrc。
   - 日志：`logs/step-06-clip.log`。
   - 成功判定：裁剪成果存在且可读。

7. 计算面积或长度
   - 工具：`exec_shell_command`。
   - 做法：用 QGIS 表达式或 OGR SQL 写入 area_m2/length_m 字段。
   - 日志：`logs/step-07-measure.log`。
   - 成功判定：统计字段存在且有非空值。

8. 分组统计
   - 工具：`exec_shell_command`。
   - 做法：用 ogrinfo SQL 或 Python/OGR 汇总 group_field。
   - 日志：`logs/step-08-stats.log`。
   - 成功判定：统计表存在，行数符合分类数。

9. 输出摘要
   - 工具：`exec_shell_command`。
   - 做法：写 summary.json，记录裁剪数量和统计字段。
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
