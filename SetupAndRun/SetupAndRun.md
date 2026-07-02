# SetupAndRun

脚本 `SetupAndRun.ps1` 用来在当前 Skillz 仓库位置配置 Python 虚拟环境，并启动 Skillz MCP Server 服务。仓库复制到其它目录后仍可直接使用，因为脚本会按自身位置解析仓库根目录。

## 常用命令

```powershell
# 进入到指定目录
cd PathToDir\skillz
# 启动默认 HTTP MCP Server
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1
```

```powershell
# 进入到指定目录
cd PathToDir\skillz
# 只检查配置并打印启动命令，不启动服务
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1 -SkipSync -NoLaunch -PrintCommand
```


```powershell
# 进入到指定目录
cd PathToDir\skillz
# 运行脚本测试
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRunTests.ps1
```

## Python 和 uv 配置

默认情况下，脚本会从 `PATH` 中查找 `uv`。如果当前机器没有把 `uv` 加入 `PATH`，可以在 `SetupAndRun.json` 的 `python.interpreter` 中指定 Python 解释器，然后脚本会通过这个解释器执行 `python -m uv`。

`python.interpreter` 可以写完整解释器路径，也可以写包含 Python 启动器的目录：

```json
"python": {
  "interpreter": "E:/QGISPackages/QGIS34407-Release/apps/Python312",
  "uvSync": true,
  "frozen": true
}
```

如果写目录，Windows 下脚本会依次查找 `python.exe`、`python.cmd`、`python.bat`。相对路径按配置文件所在目录解析。

脚本不会自动安装 `uv`。如果指定解释器后提示缺少 `uv`，先手动执行：

```powershell
E:\QGISPackages\QGIS34407-Release\apps\Python312\python.exe -m pip install uv
```

安装后可以先打印命令确认解析结果：

```powershell
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1 -NoLaunch -PrintCommand
```

## llama-ui 配置

默认配置会启动：

```text
http://127.0.0.1:8000/mcp
```

在 llama-ui 的 MCP Servers 页面添加这个 URL 值，浏览器直连时，`corsOrigins` 必须包含地址栏里的 llama-ui origin 地址信息，例如 `http://127.0.0.1:8282` 或 `https://example.tailnet.ts.net` 地址。

当 llama-ui 是 HTTPS 页面，并且浏览器要访问本机或局域网里的 HTTP Skillz 服务时，Chrome 可能触发本地网络访问预检。此时在配置中把 `corsAllowPrivateNetwork` 设为 `true`，并确保 `corsOrigins` 只写明确可信的 llama-ui origin，不要和通配符 `*` 搭配使用。

Chrome 142 及更新版本还可能要求对 llama-ui 站点单独授予 Local Network Access / Apps on device 权限。如果 llama-ui 中显示 `Failed to fetch`，但本机 `curl`、PowerShell 或 MCP 客户端能正常访问 Skillz，先在 Chrome 地址栏左侧的站点设置中允许该站点访问本机/本地网络，再刷新 MCP Server 卡片。这个浏览器权限和 Skillz 的 CORS/PNA 响应头不是同一层检查。

## 两台电脑

第一种情况：电脑 B 运行 Skillz 服务，而 Chrome 也在 B 电脑，打开电脑 A 的 llama-ui，保持 `host` 为 `127.0.0.1` 值，在 llama-ui 中填 `http://127.0.0.1:8000/mcp`，不要启用 llama-server proxy 配置，并把电脑 A 的 llama-ui origin 加入 `corsOrigins` 配置中。此时 `127.0.0.1` 是浏览器所在的 B 电脑。

第二种情况：服务 Skillz 和 llama-server 都在 A 电脑，而 Chrome 在 B 电脑，推荐 llama-server 启用 `--ui-mcp-proxy` 参数，服务 Skillz 仍绑定 `127.0.0.1` 地址，llama-ui 中填 `http://127.0.0.1:8000/mcp` 并启用 proxy 配置。启用 proxy 后，`127.0.0.1` 是运行 llama-server 的 A 电脑。若不用 proxy 配置，则 Skillz 需要绑定 `0.0.0.0` 或电脑 A 的局域网 IP，并放行防火墙端口。
