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

## llama-ui 配置

默认配置会启动：

```text
http://127.0.0.1:8000/mcp
```

在 llama-ui 的 MCP Servers 页面添加这个 URL 值，浏览器直连时，`corsOrigins` 必须包含地址栏里的 llama-ui origin 地址信息，例如 `http://127.0.0.1:8282` 或 `https://example.tailnet.ts.net` 地址。

## 两台电脑

第一种情况：电脑 B 运行 Skillz 服务，而 Chrome 也在 B 电脑，打开电脑 A 的 llama-ui保持 `host` 为 `127.0.0.1` 值，在 llama-ui 中填 `http://127.0.0.1:8000/mcp`，不要启用 llama-server proxy 配置，并把电脑 A 的 llama-ui origin 加入 `corsOrigins` 配置中。

第二种情况：服务 Skillz 和 llama-server 都在 A 电脑，而 Chrome 在 B 电脑，推荐 llama-server 启用 `--ui-mcp-proxy` 参数，服务 Skillz 仍绑定 `127.0.0.1` 地址，llama-ui 中填 `http://127.0.0.1:8000/mcp` 并启用 proxy 配置。若不用 proxy 配置，则 Skillz 需要绑定 `0.0.0.0` 或电脑 A 的局域网 IP，并放行防火墙端口。