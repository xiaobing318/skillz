# Skillz

## 👌 **Use _skills_ in any agent** _(Codex, Copilot, Cursor, etc...)_

[![PyPI version](https://img.shields.io/pypi/v/skillz.svg)](https://pypi.org/project/skillz/)
[![PyPI downloads](https://img.shields.io/pypi/dm/skillz.svg)](https://pypi.org/project/skillz/)

> ⚠️ **Experimental proof‑of‑concept. Potentially unsafe. Treat skills like untrusted code and run in sandboxes/containers. Use at your own risk.**

**Skillz** is an MCP server that turns [Agent Skills](https://agentskills.io/home) _(`SKILL.md` plus optional `scripts/`, `references/`, and `assets/`)_ into callable tools for any MCP client. It discovers each skill, exposes the authored instructions and resources, and leaves script execution to the MCP client.

> 💡 You can find skills to install at the **[Skills Supermarket](http://skills.intellectronica.net/)** directory.

## Quick Start

To run the MCP server in your agent, use the following config (or equivalent):

```json
{
  "skillz": {
    "command": "uvx",
    "args": ["skillz@latest"]
  }
}
```

with the skills residing at `~/.skillz`

_or_

```json
{
  "skillz": {
    "command": "uvx",
    "args": ["skillz@latest", "/path/to/skills/direcotry"]
  }
}
```

or Docker

You can run Skillz using Docker for isolation. The image is available on Docker Hub at `intellectronica/skillz`.

To run the Skillz MCP server with your skills directory mounted using Docker, configure your agent as follows: 

Replace `/path/to/skills` with the path to your actual skills directory. Any arguments after `intellectronica/skillz` in the array are passed directly to the Skillz CLI.

```json
{
  "skillz": {
    "command": "docker",
    "args": [
      "run",
      "-i",
      "--rm",
      "-v",
      "/path/to/skills:/skillz",
      "intellectronica/skillz",
      "/skillz"
    ]
  }
}
```

## Gemini CLI Extension

A Gemini CLI extension is available at [intellectronica/gemini-cli-skillz](https://github.com/intellectronica/gemini-cli-skillz).

Install it with:

```bash
gemini extensions install https://github.com/intellectronica/gemini-cli-skillz
```

This extension enables Anthropic-style Agent Skills in Gemini CLI using the skillz MCP server.

## Usage

Skillz looks for skills inside the root directory you provide (defaults to
`~/.skillz`). Each skill lives in its own folder or zip archive (`.zip` or `.skill`)
that includes a `SKILL.md` file with YAML front matter describing the skill. Any
other files in the skill become downloadable resources for your agent (scripts,
datasets, examples, etc.).

An example directory might look like this:

```text
~/.skillz/
├── summarize-docs/
│   ├── SKILL.md
│   ├── summarize.py
│   └── prompts/example.txt
├── translate.zip
├── analyzer.skill
└── web-search/
    └── SKILL.md
```

When packaging skills as zip archives (`.zip` or `.skill`), include the `SKILL.md`
either at the root of the archive or inside a single top-level directory:

```text
translate.zip
├── SKILL.md
└── helpers/
    └── translate.js
```

```text
data-cleaner.zip
└── data-cleaner/
    ├── SKILL.md
    └── clean.py
```

### Directory Structure: Skillz vs Claude Code

Skillz supports a more flexible skills directory than Claude Code. In addition to a flat layout, you can organize skills in nested subdirectories and include skills packaged as `.zip` or `.skill` files (as shown in the examples above).

Claude Code, on the other hand, expects a flat skills directory: every immediate subdirectory is a single skill. Nested directories are not discovered, and `.zip` or `.skill` files are not supported.

If you want your skills directory to be compatible with Claude Code (for example, so you can symlink one skills directory between the two tools), you must use the flat layout.

**Claude Code–compatible layout:**

```text
skills/
├── hello-world/
│   ├── SKILL.md
│   └── run.sh
└── summarize-text/
    ├── SKILL.md
    └── run.py
```

**Skillz-only layout examples** (not compatible with Claude Code):

```text
skills/
├── text-tools/
│   └── summarize-text/
│       ├── SKILL.md
│       └── run.py
├── image-processing.zip
└── data-analyzer.skill
```

You can use `skillz --list-skills` (optionally pointing at another skills root)
to verify which skills the server will expose before connecting it to your
agent.

### Browser clients such as llama-ui

Browser-hosted MCP clients cannot start Skillz through stdio. Run Skillz as an
HTTP MCP server and point the client at that URL instead:

```powershell
uv run --directory C:\Dev\github-repos\skillz --frozen skillz C:\Softwares\codex\skills --transport http --host 127.0.0.1 --port 8000 --path /mcp --cors-origin http://127.0.0.1:8282
```

Then open llama-ui's MCP Servers page and add:

```text
http://127.0.0.1:8000/mcp
```

The value passed to `--cors-origin` must match the browser page origin exactly,
including scheme, host, and port. Repeat `--cors-origin` to allow more than one
UI origin. If the UI is served over HTTPS from another machine and the browser
connects back to local Skillz, add `--cors-allow-private-network` so Chrome's
private-network preflight can succeed for that trusted origin. Keep Skillz bound
to `127.0.0.1` unless you intentionally want other machines to reach it.

If you do not enable CORS in Skillz, start `llama-server` with
`--ui-mcp-proxy` and enable `Use llama-server proxy` in the server card after
adding the URL. That proxy is only for HTTP/HTTPS MCP servers.

Chrome 142 and newer may also require a site permission for HTTPS pages that
connect to `localhost`, `127.0.0.1`, or other local-network targets. If
llama-ui shows `Failed to fetch` even though Skillz answers curl or MCP client
requests, allow local network or apps-on-device access for the llama-ui site in
Chrome, then refresh the server card. This browser permission is separate from
Skillz CORS headers.

For a two-computer setup where Chrome and Skillz both run on computer B while
llama-ui is served from computer A, keep Skillz on `127.0.0.1` and do not enable
the llama-server proxy in the UI. In that mode `http://127.0.0.1:8000/mcp`
means computer B, which is exactly where Skillz is running. If you enable the
proxy, `127.0.0.1` is resolved from the llama-server host instead.

For Windows users, `SetupAndRun/SetupAndRun.ps1` reads
`SetupAndRun/SetupAndRun.json`, validates it against
`SetupAndRun/SetupAndRunSchema.json` when `Test-Json` is available, applies
the same required field and type checks on Windows PowerShell 5.1, configures
the local uv environment, and starts Skillz:

```powershell
powershell -ExecutionPolicy Bypass -File .\SetupAndRun\SetupAndRun.ps1
```

See `SetupAndRun/SetupAndRun.md` for direct browser connections,
llama-server proxy connections, two-computer setups, and script tests.

### MCP tools

Skillz exposes one read-only discovery tool plus one tool per discovered skill:

| Tool | Purpose |
| --- | --- |
| `list_skills` | List the currently available skills using only startup metadata: slug, name, and description. |
| `<skill-slug>` | Invoke a specific skill and return its full instructions, metadata, and MCP resource URIs. |

Skillz does not expose MCP tools that add, remove, or fetch skill files. Manage
the skills directory with normal filesystem or package-management workflows.
When a skill response lists resource URIs, use the client's native MCP resource
reading support to fetch those files.

## CLI Reference

`skillz [skills_root] [options]`

| Flag / Option | Description |
| --- | --- |
| positional `skills_root` | Optional skills directory (defaults to `~/.skillz`). |
| `--transport {stdio,http,sse}` | Choose the FastMCP transport (default `stdio`). |
| `--host HOST` | Bind address for HTTP/SSE transports. |
| `--port PORT` | Port for HTTP/SSE transports. |
| `--path PATH` | URL path when using the HTTP transport. |
| `--cors-origin ORIGIN` | Allow a browser origin for HTTP/SSE transports. Repeat for multiple origins. |
| `--cors-allow-credentials` | Allow credentialed CORS requests. Cannot be used with `--cors-origin '*'`. |
| `--cors-allow-private-network` | Allow trusted browser origins to pass Chrome private-network preflights. Cannot be used with `--cors-origin '*'`. |
| `--list-skills` | List discovered skills and exit. |
| `--verbose` | Emit debug logging to the console. |
| `--log` | Mirror verbose logs to `.skillz/skillz.log` unless `--log-file` is set. |
| `--log-file PATH` | Log file path used with `--log`. |

---

> Made with 🫶 by [`@intellectronica`](https://intellectronica.net)
