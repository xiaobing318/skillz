---
name: qgis-vector-merge-deduplicate-index
description: 矢量合并去重建索引。面向 Windows AMD64 QGIS 3.44.7 发布包，按固定日志和输出约定处理地理矢量数据。
compatibility: Skillz HTTP MCP Server, llama-ui, exec_shell_command, QGIS 3.44.7 Qt6 Release on Windows AMD64.
allowed-tools:
  - exec_shell_command
  - read_file
metadata:
  domain: qgis
  data-kind: vector
  qgis-package: QGIS34407-Release
  test-root: C:/Data/QGISData/TestData/qgis-vector-merge-deduplicate-index
---

# 矢量合并去重建索引

## 任务目标

把多源同类矢量合并，按业务键和几何去重，必要时溶解并创建空间索引。

## 输入

- input_dir：多源矢量目录。
- name_glob：文件名筛选规则。
- dedup_key：业务去重字段。
- dissolve_field：可选溶解字段。

## 输出

- 合并去重后的 GPKG。
- 重复记录报告。
- 空间索引和运行摘要。
- encoding-normalization.json 或 summary.json.encoding，记录源字符集、目标字符集、转换命令和人工核查点。

## 固定工作流

1. 准备合并任务
   - 工具：`exec_shell_command`。
   - 做法：创建 output、logs 并记录 name_glob。
   - 日志：`logs/step-01-prepare.log`。
   - 成功判定：输出目录存在。

2. 扫描源文件
   - 工具：`exec_shell_command`。
   - 做法：使用 dir 或 file_glob_search 找到匹配数据。
   - 日志：`logs/step-02-scan.log`。
   - 成功判定：匹配文件数量符合预期。

3. 探测并统一字符集
   - 工具：`exec_shell_command`。
   - 做法：读取 .cpg、ogrinfo 输出和 CSV 文本头信息，识别 GBK/CP936、ISO-8859-1、Windows-1252 或 UTF-8。发现非 UTF-8 时，使用 ogr2ogr -oo ENCODING=<源编码> -lco ENCODING=UTF-8 写入 scratch 中的 UTF-8 副本；输出 Shapefile 必须写 .cpg=UTF-8，GPKG 和 GeoJSON 记录为 UTF-8 安全容器。
   - 日志：`logs/step-03-encoding.log`。
   - 成功判定：日志包含 source_encoding、target_encoding=UTF-8 和 STEP_OK，summary.json 或 manifest.json 记录转换结果。

4. 结构一致性检查
   - 工具：`exec_shell_command`。
   - 做法：使用 ogrinfo 检查几何类型、字段和 CRS。
   - 日志：`logs/step-04-schema.log`。
   - 成功判定：字段和 CRS 可统一。

5. 统一字段和 CRS
   - 工具：`exec_shell_command`。
   - 做法：使用 ogr2ogr 预处理各源数据。
   - 日志：`logs/step-05-normalize.log`。
   - 成功判定：每个临时图层可读。

6. 合并图层
   - 工具：`exec_shell_command`。
   - 做法：使用 ogr2ogr -append 或 qgis_process native:mergevectorlayers。
   - 日志：`logs/step-06-merge.log`。
   - 成功判定：合并成果存在。

7. 去重
   - 工具：`exec_shell_command`。
   - 做法：按 dedup_key 和几何 WKT 生成重复报告并保留第一条。
   - 日志：`logs/step-07-dedup.log`。
   - 成功判定：重复数量写入报告。

8. 可选溶解
   - 工具：`exec_shell_command`。
   - 做法：若提供 dissolve_field，运行 native:dissolve。
   - 日志：`logs/step-08-dissolve.log`。
   - 成功判定：溶解成果存在或记录跳过原因。

9. 建立索引和摘要
   - 工具：`exec_shell_command`。
   - 做法：创建空间索引，写 summary.json。
   - 日志：`logs/step-09-index-summary.log`。
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
