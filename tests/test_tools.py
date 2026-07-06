from pathlib import Path

import pytest
from fastmcp.exceptions import ToolError

from skillz import SkillRegistry, build_server
from skillz._server import SkillError


def write_skill(directory: Path, name: str = "echo") -> Path:
    skill_dir = directory / name
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(
        """---
name: {name}
description: Echoes task-specific instructions. Use for echo tests.
compatibility: Works with MCP clients that support tools and resources.
allowed-tools: Bash(git:*) Read
metadata:
  owner: tests
---
Echo body.
""".format(name=name),
        encoding="utf-8",
    )
    (skill_dir / "references").mkdir()
    (skill_dir / "references" / "guide.md").write_text(
        "Reference guide.",
        encoding="utf-8",
    )
    return skill_dir


@pytest.mark.asyncio
async def test_server_exposes_read_only_skill_tools(tmp_path: Path) -> None:
    write_skill(tmp_path, name="echo")

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    tools = await server.get_tools()

    assert set(tools) == {"list_skills", "echo"}


@pytest.mark.asyncio
async def test_list_skills_returns_current_metadata_only(
    tmp_path: Path,
) -> None:
    write_skill(tmp_path, name="echo")

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    tools = await server.get_tools()

    assert "current metadata only" in tools["list_skills"].description

    result = await tools["list_skills"].fn()

    assert result["count"] == 1
    assert result["skills"][0]["slug"] == "echo"
    assert result["skills"][0]["name"] == "echo"
    assert result["skills"][0]["description"].startswith("Echoes")
    assert set(result["skills"][0]) == {"slug", "name", "description"}
    assert "instructions" not in result["skills"][0]


@pytest.mark.asyncio
async def test_dynamic_skill_tool_returns_instructions_and_resources(
    tmp_path: Path,
) -> None:
    write_skill(tmp_path, name="echo")

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    tools = await server.get_tools()

    result = await tools["echo"].fn(task="Use the echo skill")

    assert result["skill"] == "echo"
    assert result["metadata"]["name"] == "echo"
    assert result["metadata"]["compatibility"].startswith("Works with MCP")
    assert result["metadata"]["metadata"] == {"owner": "tests"}
    assert result["metadata"]["allowed_tools"] == [
        "Bash(git:*)",
        "Read",
    ]
    assert result["instructions"] == "Echo body.\n"
    assert result["resources"] == [
        {
            "uri": "resource://skillz/echo/references/guide.md",
            "name": "echo/references/guide.md",
            "mime_type": "text/markdown",
        }
    ]
    assert "native MCP resource fetching" in result["usage"]


@pytest.mark.asyncio
async def test_dynamic_skill_tool_rejects_empty_task(
    tmp_path: Path,
) -> None:
    write_skill(tmp_path, name="echo")

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    tools = await server.get_tools()

    with pytest.raises(ToolError, match="non-empty string"):
        await tools["echo"].fn(task="   ")


@pytest.mark.asyncio
async def test_reserved_skill_slug_does_not_replace_list_skills(
    tmp_path: Path,
) -> None:
    write_skill(tmp_path, name="list-skills")

    registry = SkillRegistry(tmp_path)
    registry.load()

    with pytest.raises(SkillError, match="conflicts"):
        build_server(registry)
