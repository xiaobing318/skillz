"""Test that resource metadata follows MCP specification."""

from pathlib import Path

import pytest

from skillz import SkillRegistry
from skillz._server import register_skill_resources


def write_skill_with_resources(
    directory: Path, name: str = "test-skill"
) -> Path:
    """Create a test skill with multiple resource types."""
    skill_dir = directory / name
    skill_dir.mkdir()

    (skill_dir / "SKILL.md").write_text(
        f"""---
name: {name}
description: Test skill with resources
---
Test skill instructions.
""",
        encoding="utf-8",
    )

    (skill_dir / "scripts").mkdir()
    (skill_dir / "scripts" / "run.py").write_text(
        "print('hello')",
        encoding="utf-8",
    )
    (skill_dir / "references").mkdir()
    (skill_dir / "references" / "README.md").write_text(
        "# README",
        encoding="utf-8",
    )
    (skill_dir / "assets").mkdir()
    (skill_dir / "assets" / "data.bin").write_bytes(b"\x00\x01\x02\x03")

    return skill_dir


def test_resource_metadata_follows_mcp_spec(tmp_path: Path) -> None:
    """Resources should have uri, name, and mimeType (no description)."""
    write_skill_with_resources(tmp_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    skill = registry.get("test-skill")

    from fastmcp import FastMCP

    mcp = FastMCP()
    metadata = register_skill_resources(mcp, skill)

    assert len(metadata) == 3

    for resource in metadata:
        assert "uri" in resource
        assert "name" in resource
        assert "mime_type" in resource

        assert "description" not in resource
        assert "relative_path" not in resource

        assert resource["uri"].startswith("resource://skillz/test-skill/")
        assert resource["name"].startswith("test-skill/")
        assert not resource["name"].startswith("resource://")
        assert "SKILL.md" not in resource["name"]


def test_resource_mime_types(tmp_path: Path) -> None:
    """MIME types should be detected correctly."""
    write_skill_with_resources(tmp_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    skill = registry.get("test-skill")

    from fastmcp import FastMCP

    mcp = FastMCP()
    metadata = register_skill_resources(mcp, skill)

    resources_by_name = {r["name"]: r for r in metadata}

    assert "test-skill/SKILL.md" not in resources_by_name
    assert (
        resources_by_name["test-skill/scripts/run.py"]["mime_type"]
        == "text/x-python"
    )
    assert (
        resources_by_name["test-skill/references/README.md"]["mime_type"]
        == "text/markdown"
    )
    assert resources_by_name["test-skill/assets/data.bin"]["mime_type"] in [
        None,
        "application/octet-stream",
    ]


def test_resource_uris_use_resource_protocol(tmp_path: Path) -> None:
    """Resource URIs should use resource:// protocol, not file://."""
    write_skill_with_resources(tmp_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    skill = registry.get("test-skill")

    from fastmcp import FastMCP

    mcp = FastMCP()
    metadata = register_skill_resources(mcp, skill)

    for resource in metadata:
        assert resource["uri"].startswith("resource://")
        assert not resource["uri"].startswith("file://")


def test_directory_resources_skip_links_outside_skill_root(
    tmp_path: Path,
) -> None:
    """Directory skills should not expose linked files outside the skill."""
    skill_dir = write_skill_with_resources(tmp_path)
    external_file = tmp_path / "outside-secret.txt"
    external_file.write_text("secret", encoding="utf-8")
    link_path = skill_dir / "linked-secret.txt"

    try:
        link_path.symlink_to(external_file)
    except OSError as exc:
        pytest.skip(f"Symlinks are not available in this environment: {exc}")

    registry = SkillRegistry(tmp_path)
    registry.load()

    skill = registry.get("test-skill")

    from fastmcp import FastMCP

    mcp = FastMCP()
    metadata = register_skill_resources(mcp, skill)

    resource_names = {resource["name"] for resource in metadata}
    assert "test-skill/linked-secret.txt" not in resource_names
