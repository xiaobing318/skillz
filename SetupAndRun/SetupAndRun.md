# SetupAndRun

脚本 `SetupAndRun.ps1` 用来在当前 Skillz 仓库位置配置 Python 虚拟环境，并启动 Skillz MCP Server 服务。仓库复制到其它目录后仍可直接使用，因为脚本会按自身位置解析仓库根目录。

## 常用命令

**场景一：配置和启动服务**
```powershell
# 进入到指定目录
cd PathToDir\skillz
# 启动默认 HTTP MCP Server
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1
```

默认运行会先打印实际执行的环境同步命令和 Skillz MCP Server 启动命令，格式如下：

```text
Python environment command: <python> -m uv sync ...
Skillz MCP command: <python> -m uv run ... skillz ...
```

**场景二：配置并打印启动命令**
```powershell
# 进入到指定目录
cd PathToDir\skillz
# 只检查配置并打印解析后的命令，不启动服务
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1 -SkipSync -NoLaunch -PrintCommand
```

**场景三：只停止旧服务**
```powershell
# 进入到指定目录
cd PathToDir\skillz
# 仅停止配置端口上的同一个 Skillz 服务，不重新启动
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1 -StopOnly
```

**场景四：清理旧服务后启动**
```powershell
# 进入到指定目录
cd PathToDir\skillz
# 仅当确认旧的同端口监听者就是同一个 Skillz 服务时使用
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1 -SkipSync -StopExisting
```

脚本在真正启动 HTTP/SSE 服务前会检查配置端口是否已被监听。默认行为是拒绝启动并打印脱敏后的监听进程信息，不会自动杀进程。传入 `-StopExisting` 时，脚本只会停止命令行中能识别为同一 `skillsRoot` 和同一端口的 Skillz 监听进程，然后继续启动。传入 `-StopOnly` 时只执行同样的安全停止逻辑，然后退出，不重新启动。`-StopOnly` 只要求配置中存在停止服务需要的 `transport`、`port` 和 `skillsRoot` 字段，不要求 Python 环境配置可用。如果端口被其它程序占用，或路径只是前缀相似但不是同一个 `skillsRoot`，会拒绝停止，避免误杀。

HTTP/SSE 服务启动后，脚本会把本次启动的 `uv`、Python 和 Skillz 子进程放入 Windows Job Object 中，并在脚本退出时执行清理。正常退出、按 `Ctrl+C`、关闭当前终端或由 Codex 中止父脚本时，都会尽量关闭本次启动的进程树并释放端口。若需要刷新 Skills 或重新做 Chrome 页面测试，先执行 `-StopOnly`，确认旧服务关闭后再重新启动。

**场景五：运行测试用例**
```powershell
# 进入到指定目录
cd PathToDir\skillz
# 运行脚本测试
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRunTests.ps1
```

## Python 和 uv 配置

`skillsRoot` 和 `python.interpreter` 只支持数组写法，用来在不同机器之间保存候选路径。脚本会按数组顺序选择第一个可用候选，字段 `skillsRoot` 不会合并多个目录，只会把最终选中的一个目录传给 Skillz MCP Server 服务，下列是具体示例：

```json
"skillsRoot": [
  "C:/Softwares/codex/skills",
  "E:/softwares/CodexHome/skills"
],
"python": {
  "interpreter": [
    "E:/QGISPackages/QGIS34407-Release/apps/Python312",
    "C:/Data/QGISPackages/QGIS34407-Release/apps/Python312"
  ],
  "uvSync": true,
  "frozen": true
}
```

脚本只会从 `SetupAndRun.json` 配置文件的 `python.interpreter` 候选列表解析 Python 解释器，并通过最终选中的解释器执行 `python -m uv` 命令，脚本不会从 `PATH` 查找 `uv` 包，也不会在未配置解释器时回退到全局 `uv` 包。`python.interpreter` 候选可以写完整解释器路径，也可以写包含 Python 启动器的目录；如果候选写目录，那么 Windows 下脚本会依次查找 `python.exe`、`python.cmd`、`python.bat` 文件。相对路径按配置文件所在目录解析。

脚本不会自动安装 `uv` 包，如果配置的解释器环境提示缺少 `uv`，可以手动执行下列命令：

```powershell
# 使用指定解释器安装环境管理工具
E:\QGISPackages\QGIS34407-Release\apps\Python312\python.exe -m pip install uv
```

安装后可以先打印命令确认解析结果：
```powershell
# 进入到指定目录
cd PathToDir\skillz
# 运行脚本确认解析结果，不启动服务
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1 -NoLaunch -PrintCommand
```

## llama-ui 配置

默认配置会启动配置文件中指定的地址，在 llama-ui 的 MCP Servers 页面添加这个 URL 值，在浏览器直连的情况下，配置 `corsOrigins` 必须包含地址栏里的 llama-ui origin 地址信息，例如 `http://127.0.0.1:8282` 或 `https://example.tailnet.ts.net` 地址。

当 llama-ui 是 HTTPS 页面，并且浏览器要访问本机或局域网里的 HTTP Skillz 服务时，浏览器可能触发本地网络访问预检，此时在配置中把 `corsAllowPrivateNetwork` 设为 `true`，并确保 `corsOrigins` 只写明确可信的 llama-ui origin，不要和通配符 `*` 搭配使用。较新的 Chrome 版本还可能要求对 llama-ui 站点单独授予 Local Network Access / Apps on device 权限。如果 llama-ui 中显示 `Failed to fetch` 信息，但本机 curl/PowerShell 或 MCP 客户端能正常访问 Skillz 服务，先在 Chrome 地址栏左侧的站点设置中允许该站点访问本机/本地网络，再刷新 MCP Server 卡片。这个浏览器权限和 Skillz 的 CORS/PNA 响应头不是同一层检查。

## 两台电脑

第一种情况：电脑 B 运行 Skillz 服务，而 Chrome 也在 B 电脑，打开电脑 A 的 llama-ui，保持 `host` 为 `127.0.0.1` 值，在 llama-ui 中填 `http://127.0.0.1:8000/mcp`，不要启用 llama-server proxy 配置，并把电脑 A 的 llama-ui origin 加入 `corsOrigins` 配置中。此时 `127.0.0.1` 是浏览器所在的 B 电脑。

第二种情况：服务 Skillz 和 llama-server 都在 A 电脑，而 Chrome 在 B 电脑，推荐 llama-server 启用 `--ui-mcp-proxy` 参数，服务 Skillz 仍绑定 `127.0.0.1` 地址，llama-ui 中填 `http://127.0.0.1:8000/mcp` 并启用 proxy 配置。启用 proxy 后，地址 `127.0.0.1` 是运行 llama-server 的 A 电脑。若不用 proxy 配置，则 Skillz 需要绑定 `0.0.0.0` 或电脑 A 的局域网 IP，并放行防火墙端口。
