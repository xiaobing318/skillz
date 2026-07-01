import os
from pathlib import Path

import pytest
from starlette.middleware.cors import CORSMiddleware

from skillz import main, parse_args
from skillz._server import build_cors_middleware


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


def test_build_cors_middleware_returns_empty_without_origins() -> None:
    assert build_cors_middleware(()) == []


def test_build_cors_middleware_configures_browser_headers() -> None:
    middleware = build_cors_middleware(("http://127.0.0.1:8282",))

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
