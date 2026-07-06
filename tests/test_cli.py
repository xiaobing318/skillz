import os
from pathlib import Path

import pytest
from starlette.middleware.cors import CORSMiddleware

from skillz import main, parse_args
from skillz._server import (
    SkillError,
    build_cors_middleware,
)


def write_skill(directory: Path, name: str = "echo") -> Path:
    skill_dir = directory / name
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(
        f"""---
name: {name}
description: Echoes task-specific instructions. Use for echo tests.
---
Echo body.
""",
        encoding="utf-8",
    )
    return skill_dir


def test_parse_args_defaults_to_home_directory(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    fake_home = Path("/tmp/fake-home")
    if os.name == "nt":
        monkeypatch.setenv("USERPROFILE", str(fake_home))
        monkeypatch.delenv("HOME", raising=False)
    else:
        monkeypatch.setenv("HOME", str(fake_home))

    args = parse_args([])

    assert args.skills_root == fake_home / ".skillz"
    assert args.transport == "stdio"
    assert args.list_skills is False
    assert args.cors_origin == ()
    assert args.cors_allow_credentials is False
    assert args.cors_allow_private_network is False


def test_parse_args_custom_root(tmp_path: Path) -> None:
    args = parse_args([str(tmp_path)])

    assert args.skills_root == Path(tmp_path)
    assert args.transport == "stdio"
    assert args.list_skills is False


def test_parse_args_overrides(tmp_path: Path) -> None:
    args = parse_args(
        [
            str(tmp_path),
            "--transport",
            "http",
            "--host",
            "0.0.0.0",
            "--port",
            "9000",
            "--path",
            "/custom",
            "--cors-origin",
            "http://127.0.0.1:8282",
            "--cors-origin",
            "http://localhost:8282",
            "--cors-allow-credentials",
            "--cors-allow-private-network",
            "--log",
            "--log-file",
            str(tmp_path / "skillz.log"),
            "--list-skills",
        ]
    )

    assert args.transport == "http"
    assert args.host == "0.0.0.0"
    assert args.port == 9000
    assert args.path == "/custom"
    assert args.cors_origin == (
        "http://127.0.0.1:8282",
        "http://localhost:8282",
    )
    assert args.cors_allow_credentials is True
    assert args.cors_allow_private_network is True
    assert args.log is True
    assert args.log_file == tmp_path / "skillz.log"
    assert args.list_skills is True


def test_parse_args_rejects_wildcard_credentials() -> None:
    with pytest.raises(SystemExit) as exc_info:
        parse_args(
            [
                "--transport",
                "http",
                "--cors-origin",
                "*",
                "--cors-allow-credentials",
            ]
        )

    assert exc_info.value.code == 2


def test_parse_args_rejects_wildcard_private_network() -> None:
    with pytest.raises(SystemExit) as exc_info:
        parse_args(
            [
                "--transport",
                "http",
                "--cors-origin",
                "*",
                "--cors-allow-private-network",
            ]
        )

    assert exc_info.value.code == 2


def test_parse_args_rejects_private_network_without_origin() -> None:
    with pytest.raises(SystemExit) as exc_info:
        parse_args(
            [
                "--transport",
                "http",
                "--cors-allow-private-network",
            ]
        )

    assert exc_info.value.code == 2


def test_build_cors_middleware_returns_empty_without_origins() -> None:
    assert build_cors_middleware(()) == []


def test_build_cors_rejects_private_network_without_origin() -> None:
    with pytest.raises(
        SkillError,
        match="requires at least one --cors-origin",
    ):
        build_cors_middleware((), allow_private_network=True)


def test_build_cors_middleware_configures_browser_headers() -> None:
    middleware = build_cors_middleware(
        ("http://127.0.0.1:8282",),
        allow_private_network=True,
    )

    assert len(middleware) == 1
    assert middleware[0].cls is CORSMiddleware
    assert middleware[0].kwargs["allow_origins"] == [
        "http://127.0.0.1:8282"
    ]
    assert middleware[0].kwargs["allow_credentials"] is False
    assert middleware[0].kwargs["allow_methods"] == [
        "GET",
        "POST",
        "DELETE",
        "OPTIONS",
    ]
    assert middleware[0].kwargs["allow_headers"] == ["*"]
    assert middleware[0].kwargs["expose_headers"] == ["mcp-session-id"]
    assert middleware[0].kwargs["allow_private_network"] is True


@pytest.mark.asyncio
async def test_cors_and_private_network_preflight_headers() -> None:
    async def app(scope, receive, send) -> None:  # noqa: ANN001
        await send({"type": "http.response.start", "status": 200})
        await send({"type": "http.response.body", "body": b""})

    middleware = build_cors_middleware(
        ("https://example.tailnet.ts.net",),
        allow_private_network=True,
    )
    wrapped_app = app
    for entry in reversed(middleware):
        wrapped_app = entry.cls(wrapped_app, **entry.kwargs)

    messages: list[dict[str, object]] = []

    async def receive() -> dict[str, object]:
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send(message: dict[str, object]) -> None:
        messages.append(message)

    await wrapped_app(
        {
            "type": "http",
            "method": "OPTIONS",
            "path": "/mcp",
            "headers": [
                (b"origin", b"https://example.tailnet.ts.net"),
                (b"access-control-request-method", b"POST"),
                (b"access-control-request-private-network", b"true"),
            ],
        },
        receive,
        send,
    )

    response_start = messages[0]
    headers = {
        key.lower(): value
        for key, value in response_start["headers"]
    }
    assert response_start["status"] == 200
    assert headers[b"access-control-allow-origin"] == (
        b"https://example.tailnet.ts.net"
    )
    assert headers[b"access-control-allow-private-network"] == b"true"


def test_main_passes_http_transport_kwargs(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_skill(tmp_path)
    captured: dict[str, object] = {}

    def fake_run(self: object, **kwargs: object) -> None:
        captured.update(kwargs)

    monkeypatch.setattr("fastmcp.FastMCP.run", fake_run)

    main(
        [
            str(tmp_path),
            "--transport",
            "http",
            "--host",
            "127.0.0.1",
            "--port",
            "8765",
            "--path",
            "/mcp",
            "--cors-origin",
            "http://127.0.0.1:8282",
            "--cors-allow-private-network",
        ]
    )

    assert captured["transport"] == "http"
    assert captured["host"] == "127.0.0.1"
    assert captured["port"] == 8765
    assert captured["path"] == "/mcp"
    assert len(captured["middleware"]) == 1


def test_main_passes_sse_transport_without_http_path(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_skill(tmp_path)
    captured: dict[str, object] = {}

    def fake_run(self: object, **kwargs: object) -> None:
        captured.update(kwargs)

    monkeypatch.setattr("fastmcp.FastMCP.run", fake_run)

    main(
        [
            str(tmp_path),
            "--transport",
            "sse",
            "--host",
            "127.0.0.1",
            "--port",
            "8765",
        ]
    )

    assert captured == {
        "transport": "sse",
        "host": "127.0.0.1",
        "port": 8765,
    }
