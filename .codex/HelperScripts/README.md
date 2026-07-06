## 1. 目录用途

目录 HelperScripts 是 Codex 在进入分析、实现、测试或验证前使用的上下文发现入口。当前仓库只复用平台信息发现能力，用来生成可审查的 UTF-8 JSON 证据。这些脚本只负责识别当前宿主的操作系统信息、指令集架构等信息。它们不负责构建、测试、安装、发布、打包、下载依赖，也不负责扫描 skillz 项目资料目录或 Skills 内容。

## 2. 支持参数

| 参数 | 作用 | 默认行为 |
| --- | --- | --- |
| `--help` | 输出帮助信息后退出。 | 不与其它参数组合使用。 |
| `--config <path>` | 指定 JSON 配置文件。 | 读取入口脚本同目录的 `ResolveCodexContext.json`。 |
| `--outputJsonPath <path>` | 指定 JSON 写出文件。 | 不写文件，只把 JSON 输出到终端。 |

`--outputJsonPath` 会创建或覆盖目标 JSON 文件。验证时应写入临时目录，验证结束后清理。在 Linux 和 macOS 平台，入口使用 `python3` 解析 JSON 配置。若目标系统缺少 `python3`，入口会返回 `InvalidInput`，需要先补齐运行环境或改用默认平台信息脚本的等效静态核验。

## 3. 配置文件

每个平台入口默认读取同目录的 `ResolveCodexContext.json`。若提供顶层 `EnabledScripts`，它必须是字符串数组，当前只允许启用平台信息脚本。若缺少 `EnabledScripts`，入口会使用默认平台信息脚本；若显式提供空数组，入口不会执行发现脚本，并通过 `Messages` 返回 `NoDiscoveryScriptsEnabled`。

Windows:

```json
{
  "EnabledScripts": [
    "ResolvePlatformInfo.ps1"
  ]
}
```

Linux 和 macOS:

```json
{
  "EnabledScripts": [
    "ResolvePlatformInfo.sh"
  ]
}
```

## 4. 输出 JSON 契约

- `Status` 可能为 `Ok`、`Unsupported` 或 `InvalidInput`。当前宿主落在支持矩阵中且输入有效时为 `Ok`；输入有效但宿主 OS/ISA 不在支持矩阵中时为 `Unsupported`；参数或配置无效时为 `InvalidInput`。
- `PlatformInfo` 只在平台信息脚本启用时输出，字段包括 `OS`、`OSVersion`、`ISA` 和 `RawArchitecture`。Linux 和 macOS 入口不输出旧版平台键字段。
- `Messages` 是可选数组，元素包含 `Level`、`Code` 和 `Text`。常见错误码包括 `UnknownArgument`、`MissingConfigPath`、`MissingOutputJsonPath`、`ConfigNotFound`、`ConfigInvalid`、`EnabledScriptsInvalid` 和 `Python3NotFound`；空 `EnabledScripts` 会返回信息码 `NoDiscoveryScriptsEnabled`。
- 支持矩阵为 `Windows/AMD64`、`Windows/ARM64`、`Linux/AMD64`、`Linux/ARM64` 和 `macOS/ARM64`。当前不把 `macOS/AMD64` 写入支持矩阵。

## 5. 使用场景与完整命令

### 5.1 查看帮助

Windows:

```powershell
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 查看帮助信息
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Windows\ResolveCodexContext.ps1 --help
```

Linux:

```bash
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 查看帮助信息
bash ./Linux/ResolveCodexContext.sh --help
```

macOS:

```bash
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 查看帮助信息
bash ./macOS/ResolveCodexContext.sh --help
```

### 5.2 使用默认配置并输出到终端

适用于本轮尚未锁定平台信息，需要先生成 `Status` 和 `PlatformInfo` 供用户审查的场景。该模式不写文件。

Windows:

```powershell
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 使用默认配置并输出到终端
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Windows\ResolveCodexContext.ps1
```

Linux:

```bash
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 使用默认配置并输出到终端
bash ./Linux/ResolveCodexContext.sh
```

macOS:

```bash
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 使用默认配置并输出到终端
bash ./macOS/ResolveCodexContext.sh
```

### 5.3 指定配置文件并输出到终端

适用于需要切换配置文件或明确指定平台入口配置的场景。当前仓库的配置文件只允许启用平台信息脚本，不负责发现 skillz 项目资料目录或 Skills 内容。

Windows:

```powershell
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 指定配置文件并输出到终端
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Windows\ResolveCodexContext.ps1 --config .\Windows\ResolveCodexContext.json
```

Linux:

```bash
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 指定配置文件并输出到终端
bash ./Linux/ResolveCodexContext.sh --config ./Linux/ResolveCodexContext.json
```

macOS:

```bash
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 指定配置文件并输出到终端
bash ./macOS/ResolveCodexContext.sh --config ./macOS/ResolveCodexContext.json
```

### 5.4 指定 JSON 写出文件

适用于需要保留本轮平台发现证据的场景。执行前应说明写入范围；若目标 JSON 已存在，入口脚本会自动覆盖。验证完成后，临时输出文件应按任务要求清理。

Windows:

```powershell
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 指定 JSON 写出文件
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Windows\ResolveCodexContext.ps1 --config .\Windows\ResolveCodexContext.json --outputJsonPath .\Output\CodexContext.json
```

Linux:

```bash
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 指定 JSON 写出文件
bash ./Linux/ResolveCodexContext.sh --config ./Linux/ResolveCodexContext.json --outputJsonPath ./Output/CodexContext.json
```

macOS:

```bash
# 进入到指定目录中
cd Path2Repo/.codex/HelperScripts
# 指定 JSON 写出文件
bash ./macOS/ResolveCodexContext.sh --config ./macOS/ResolveCodexContext.json --outputJsonPath ./Output/CodexContext.json
```

## 6. 验证要求

- Windows 脚本应通过 PowerShell 语法解析，并保持 UTF-8 BOM 与 CRLF。
- Linux 和 macOS 脚本应通过 `bash -n`，并保持 UTF-8 与 LF。
- JSON 配置应能被平台原生工具或 `python3 -m json.tool` 正常解析。
- 默认输出必须包含 `Status` 和 `PlatformInfo`，且不写入仓库文件。
