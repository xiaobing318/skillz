from pathlib import Path
import shutil
import zipfile

import pytest
from fastmcp.exceptions import NotFoundError

from skillz import SkillRegistry, build_server


def write_skill(
    root: Path,
    name: str,
    *,
    description: str | None = None,
    body: str | None = None,
    resources: dict[str, str | bytes] | None = None,
) -> Path:
    skill_dir = root / name
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(
        f"""---
name: {name}
description: {description or f"{name} test skill"}
---
{body or f"{name} body."}
""",
        encoding="utf-8",
    )
    for rel_path, content in (resources or {}).items():
        resource_path = skill_dir / rel_path
        resource_path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            resource_path.write_bytes(content)
        else:
            resource_path.write_text(content, encoding="utf-8")
    return skill_dir


def write_zip_skill(
    root: Path,
    name: str,
    *,
    body: str,
    resources: dict[str, str | bytes] | None = None,
) -> Path:
    zip_path = root / f"{name}.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        z.writestr(
            "SKILL.md",
            f"""---
name: {name}
description: {name} zip skill
---
{body}
""",
        )
        for rel_path, content in (resources or {}).items():
            z.writestr(rel_path, content)
    return zip_path


def load_server(root: Path):
    registry = SkillRegistry(root)
    registry.load()
    return build_server(registry)


@pytest.mark.asyncio
async def test_hot_reload_adds_skill_on_tool_call(tmp_path: Path) -> None:
    write_skill(tmp_path, "alpha", body="Alpha body.")
    server = load_server(tmp_path)

    write_skill(tmp_path, "bravo", body="Bravo body.")

    result = await server._mcp_call_tool("bravo", {"task": "use bravo"})

    assert result[1]["skill"] == "bravo"
    assert result[1]["instructions"] == "Bravo body.\n"


@pytest.mark.asyncio
async def test_hot_reload_removes_deleted_skill(tmp_path: Path) -> None:
    write_skill(tmp_path, "alpha")
    bravo_dir = write_skill(tmp_path, "bravo")
    server = load_server(tmp_path)

    assert set(await server.get_tools()) == {"list_skills", "alpha", "bravo"}

    shutil.rmtree(bravo_dir)
    tools = await server.get_tools()
    result = await tools["list_skills"].fn()

    assert set(tools) == {"list_skills", "alpha"}
    assert result["count"] == 1
    assert [skill["slug"] for skill in result["skills"]] == ["alpha"]


@pytest.mark.asyncio
async def test_hot_reload_updates_metadata_and_body(
    tmp_path: Path,
) -> None:
    skill_dir = write_skill(
        tmp_path,
        "alpha",
        description="Alpha old description",
        body="Alpha old body.",
    )
    server = load_server(tmp_path)

    (skill_dir / "SKILL.md").write_text(
        """---
name: alpha
description: Alpha new description with more detail
---
Alpha new body with more detail.
""",
        encoding="utf-8",
    )

    tools = await server.get_tools()
    result = await tools["alpha"].fn(task="use alpha")
    skills = await tools["list_skills"].fn()

    assert "Alpha new description" in tools["alpha"].description
    assert result["instructions"] == "Alpha new body with more detail.\n"
    assert skills["skills"][0]["description"].startswith("Alpha new")


@pytest.mark.asyncio
async def test_hot_reload_adds_and_removes_resources(
    tmp_path: Path,
) -> None:
    skill_dir = write_skill(tmp_path, "alpha")
    server = load_server(tmp_path)
    uri = "resource://skillz/alpha/references/guide.md"

    (skill_dir / "references").mkdir()
    (skill_dir / "references" / "guide.md").write_text(
        "Guide v1",
        encoding="utf-8",
    )

    resources = await server.get_resources()
    result = await server._mcp_read_resource(uri)

    assert uri in resources
    assert result[0].content == "Guide v1"

    (skill_dir / "references" / "guide.md").unlink()
    resources = await server.get_resources()

    assert uri not in resources
    with pytest.raises(NotFoundError):
        await server._mcp_read_resource(uri)


@pytest.mark.asyncio
async def test_hot_reload_updates_zip_skill(tmp_path: Path) -> None:
    write_zip_skill(
        tmp_path,
        "zip-alpha",
        body="Zip alpha body v1.",
        resources={"notes.txt": "zip notes v1"},
    )
    server = load_server(tmp_path)

    write_zip_skill(
        tmp_path,
        "zip-alpha",
        body="Zip alpha body v2 with more detail.",
        resources={"notes.txt": "zip notes v2 with more detail"},
    )

    tools = await server.get_tools()
    tool_result = await tools["zip-alpha"].fn(task="use zip alpha")
    resource_result = await server._mcp_read_resource(
        "resource://skillz/zip-alpha/notes.txt"
    )

    assert tool_result["instructions"] == (
        "Zip alpha body v2 with more detail.\n"
    )
    assert resource_result[0].content == "zip notes v2 with more detail"


@pytest.mark.asyncio
async def test_hot_reload_failure_keeps_previous_snapshot(
    tmp_path: Path,
) -> None:
    write_skill(tmp_path, "alpha", body="Alpha body.")
    server = load_server(tmp_path)

    write_skill(
        tmp_path,
        "list-skills",
        description="Reserved tool name should fail runtime registration",
        body="Bad body.",
    )

    tools = await server.get_tools()
    result = await tools["list_skills"].fn()

    assert set(tools) == {"list_skills", "alpha"}
    assert result["count"] == 1
    assert result["skills"][0]["slug"] == "alpha"

    shutil.rmtree(tmp_path / "list-skills")
    write_skill(tmp_path, "beta", body="Beta body.")

    tools = await server.get_tools()

    assert set(tools) == {"list_skills", "alpha", "beta"}
