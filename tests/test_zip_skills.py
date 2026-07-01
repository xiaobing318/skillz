"""Tests for zip-based skills support."""

from pathlib import Path
import zipfile

import pytest
from fastmcp.exceptions import NotFoundError

from skillz import SkillRegistry, build_server


def create_zip_skill(
    zip_path: Path, name: str | None = None, with_resources: bool = True
) -> None:
    """Create a standard Agent Skill in a zip or .skill file."""
    skill_name = name or zip_path.stem
    with zipfile.ZipFile(zip_path, "w") as z:
        skill_md_content = f"""---
name: {skill_name}
description: Test skill from zip
---
Test skill instructions from zip file.
"""
        z.writestr("SKILL.md", skill_md_content)

        if with_resources:
            z.writestr("text/hello.txt", "Hello from zip!")
            z.writestr("bin/data.bin", b"\xff\xfe\x00\x01\x80\x90")
            z.writestr("scripts/run.py", "print('hello')")


def test_zip_skill_loads_and_parses_skill_md(tmp_path: Path) -> None:
    """Test that a zip with SKILL.md at root is loaded correctly."""
    zip_path = tmp_path / "my-skill.zip"
    create_zip_skill(zip_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 1
    skill = registry.get("my-skill")
    assert skill.metadata.name == "my-skill"
    assert skill.metadata.description == "Test skill from zip"
    assert skill.is_zip
    assert skill.zip_path == zip_path.resolve()


def test_zip_skill_resources_are_discovered(tmp_path: Path) -> None:
    """Test that resources in zip are discovered with correct URIs."""
    zip_path = tmp_path / "my-skill.zip"
    create_zip_skill(zip_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    skill = registry.get("my-skill")

    from fastmcp import FastMCP
    from skillz._server import register_skill_resources

    mcp = FastMCP()
    metadata = register_skill_resources(mcp, skill)

    assert len(metadata) == 3

    uris = {m["uri"] for m in metadata}
    assert "resource://skillz/my-skill/text/hello.txt" in uris
    assert "resource://skillz/my-skill/bin/data.bin" in uris
    assert "resource://skillz/my-skill/scripts/run.py" in uris

    names = {m["name"] for m in metadata}
    assert "my-skill/text/hello.txt" in names
    assert "my-skill/bin/data.bin" in names
    assert "my-skill/scripts/run.py" in names

    for m in metadata:
        assert "SKILL.md" not in m["name"]


@pytest.mark.asyncio
async def test_zip_skill_text_resource_read(tmp_path: Path) -> None:
    """Test reading text resource from zip-based skill."""
    zip_path = tmp_path / "test-skill.zip"
    create_zip_skill(zip_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    result = await server._mcp_read_resource(
        "resource://skillz/test-skill/text/hello.txt"
    )

    assert len(result) == 1
    assert result[0].mime_type == "text/plain"
    assert result[0].content == "Hello from zip!"


@pytest.mark.asyncio
async def test_zip_skill_binary_resource_read(tmp_path: Path) -> None:
    """Test reading binary resource from zip-based skill."""
    zip_path = tmp_path / "test-skill.zip"
    create_zip_skill(zip_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    result = await server._mcp_read_resource(
        "resource://skillz/test-skill/bin/data.bin"
    )

    assert len(result) == 1
    assert result[0].mime_type in [None, "application/octet-stream"]
    assert result[0].content == b"\xff\xfe\x00\x01\x80\x90"


def test_zip_missing_skill_md_is_ignored(tmp_path: Path) -> None:
    """Test that zip without SKILL.md at root is ignored."""
    zip_path = tmp_path / "invalid.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        z.writestr("README.md", "# Not a skill")
        z.writestr("some/nested/file.txt", "content")

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 0


def test_corrupt_zip_is_ignored(tmp_path: Path) -> None:
    """Test that corrupt zip file is ignored gracefully."""
    zip_path = tmp_path / "corrupt.zip"
    zip_path.write_bytes(b"This is not a valid zip file at all!")

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 0


def test_zip_inside_dir_skill_is_ignored(tmp_path: Path) -> None:
    """Test that zip files inside directory skills are ignored."""
    skill_dir = tmp_path / "directory-skill"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(
        """---
name: directory-skill
description: A directory-based skill
---
Directory skill content.
""",
        encoding="utf-8",
    )

    zip_path = skill_dir / "nested.zip"
    create_zip_skill(zip_path, name="nested")

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 1
    skill = registry.get("directory-skill")
    assert skill.metadata.name == "directory-skill"
    assert not skill.is_zip


def test_zips_in_non_skill_subdirectories_are_loaded(tmp_path: Path) -> None:
    """Test that zips in subdirectories without SKILL.md are loaded."""
    packs_a = tmp_path / "packs" / "a"
    packs_a.mkdir(parents=True)
    packs_b = tmp_path / "packs" / "b"
    packs_b.mkdir(parents=True)

    create_zip_skill(packs_a / "skill-a.zip")
    create_zip_skill(packs_b / "skill-b.zip")

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 2
    skill_a = registry.get("skill-a")
    skill_b = registry.get("skill-b")
    assert skill_a.metadata.name == "skill-a"
    assert skill_b.metadata.name == "skill-b"
    assert skill_a.is_zip
    assert skill_b.is_zip


def test_nested_zip_not_treated_as_skill(tmp_path: Path) -> None:
    """Test that zip files inside zip-based skills are just resources."""
    zip_path = tmp_path / "outer.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        z.writestr(
            "SKILL.md",
            """---
name: outer
description: Outer skill
---
Outer skill content.
""",
        )
        inner_zip_data = b"PK\x03\x04\x00\x00\x00\x00\x00\x00\x00\x00"
        z.writestr("resources/inner.zip", inner_zip_data)

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 1
    skill = registry.get("outer")
    assert skill.metadata.name == "outer"
    assert skill.is_zip

    from fastmcp import FastMCP
    from skillz._server import register_skill_resources

    mcp = FastMCP()
    metadata = register_skill_resources(mcp, skill)

    resource_names = {m["name"] for m in metadata}
    assert "outer/resources/inner.zip" in resource_names


def test_skill_name_collision_skips_zip(tmp_path: Path) -> None:
    """Test that zip with duplicate name is skipped."""
    skill_dir = tmp_path / "foo"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(
        """---
name: foo
description: Directory skill
---
Content.
""",
        encoding="utf-8",
    )

    zip_path = tmp_path / "foo.zip"
    create_zip_skill(zip_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 1
    skill = registry.get("foo")
    assert not skill.is_zip
    assert skill.metadata.name == "foo"


@pytest.mark.asyncio
async def test_zip_skill_instructions_read_correctly(tmp_path: Path) -> None:
    """Test that skill instructions are read correctly from zip."""
    zip_path = tmp_path / "test-instructions.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        z.writestr(
            "SKILL.md",
            """---
name: test-instructions
description: Test reading instructions
---
These are the skill instructions.

With multiple lines.
""",
        )

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    tools = await server.get_tools()
    skill_tool = tools["test-instructions"]

    result = await skill_tool.fn(task="test task")

    assert "instructions" in result
    assert "These are the skill instructions." in result["instructions"]
    assert "With multiple lines." in result["instructions"]


def test_zip_skill_with_macos_metadata_filtered(tmp_path: Path) -> None:
    """Test that __MACOSX and .DS_Store files are filtered out."""
    zip_path = tmp_path / "mac-skill.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        z.writestr(
            "SKILL.md",
            """---
name: mac-skill
description: Skill with macOS metadata
---
Content.
""",
        )
        z.writestr("script.py", "print('hello')")
        z.writestr("__MACOSX/._script.py", b"\x00\x01\x02")
        z.writestr(".DS_Store", b"DS_Store content")

    registry = SkillRegistry(tmp_path)
    registry.load()

    skill = registry.get("mac-skill")

    from fastmcp import FastMCP
    from skillz._server import register_skill_resources

    mcp = FastMCP()
    metadata = register_skill_resources(mcp, skill)

    assert len(metadata) == 1
    assert metadata[0]["name"] == "mac-skill/script.py"


@pytest.mark.asyncio
async def test_zip_path_traversal_rejected(tmp_path: Path) -> None:
    """Test that path traversal attempts are rejected."""
    zip_path = tmp_path / "test-skill.zip"
    create_zip_skill(zip_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)

    with pytest.raises(NotFoundError):
        await server._mcp_read_resource(
            "resource://skillz/test-skill/../../../etc/passwd"
        )


def test_mixed_directory_and_zip_skills(tmp_path: Path) -> None:
    """Test that both directory and zip skills can coexist."""
    dir_skill = tmp_path / "dir-skill"
    dir_skill.mkdir()
    (dir_skill / "SKILL.md").write_text(
        """---
name: dir-skill
description: Directory skill
---
Dir content.
""",
        encoding="utf-8",
    )

    zip_path = tmp_path / "zip-skill.zip"
    create_zip_skill(zip_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 2

    dir_skill_obj = registry.get("dir-skill")
    zip_skill_obj = registry.get("zip-skill")

    assert not dir_skill_obj.is_zip
    assert zip_skill_obj.is_zip
    assert dir_skill_obj.metadata.name == "dir-skill"
    assert zip_skill_obj.metadata.name == "zip-skill"


def test_zip_with_top_level_directory(tmp_path: Path) -> None:
    """Test zip with single top-level directory containing SKILL.md."""
    zip_path = tmp_path / "my-skill.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        z.writestr(
            "my-skill/SKILL.md",
            """---
name: my-skill
description: Test skill in top-level dir
---
Instructions.
""",
        )
        z.writestr("my-skill/resource.txt", "Hello from nested structure!")
        z.writestr("my-skill/scripts/run.py", "print('test')")

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 1
    skill = registry.get("my-skill")
    assert skill.metadata.name == "my-skill"
    assert skill.is_zip
    assert skill.zip_root_prefix == "my-skill/"


@pytest.mark.asyncio
async def test_zip_with_top_level_directory_resources(
    tmp_path: Path,
) -> None:
    """Test reading resources from zip with top-level directory."""
    zip_path = tmp_path / "test-skill.zip"
    with zipfile.ZipFile(zip_path, "w") as z:
        z.writestr(
            "test-skill/SKILL.md",
            """---
name: test-skill
description: Test
---
Content.
""",
        )
        z.writestr("test-skill/data.txt", "Test data from nested structure")

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    result = await server._mcp_read_resource(
        "resource://skillz/test-skill/data.txt"
    )

    assert len(result) == 1
    assert result[0].content == "Test data from nested structure"


def test_skill_extension_loads_like_zip(tmp_path: Path) -> None:
    """Test that files with .skill extension are loaded as zip files."""
    skill_path = tmp_path / "skill-extension.skill"
    create_zip_skill(skill_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 1
    skill = registry.get("skill-extension")
    assert skill.metadata.name == "skill-extension"
    assert skill.is_zip
    assert skill.zip_path == skill_path.resolve()


@pytest.mark.asyncio
async def test_skill_extension_resources_readable(tmp_path: Path) -> None:
    """Test that resources in .skill files can be read correctly."""
    skill_path = tmp_path / "test-skill-ext.skill"
    create_zip_skill(skill_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    server = build_server(registry)
    result = await server._mcp_read_resource(
        "resource://skillz/test-skill-ext/text/hello.txt"
    )

    assert len(result) == 1
    assert result[0].content == "Hello from zip!"


def test_mixed_zip_and_skill_extensions(tmp_path: Path) -> None:
    """Test that both .zip and .skill files can coexist."""
    zip_path = tmp_path / "skill-one.zip"
    create_zip_skill(zip_path)

    skill_path = tmp_path / "skill-two.skill"
    create_zip_skill(skill_path)

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 2

    skill_one = registry.get("skill-one")
    skill_two = registry.get("skill-two")

    assert skill_one.metadata.name == "skill-one"
    assert skill_two.metadata.name == "skill-two"
    assert skill_one.is_zip
    assert skill_two.is_zip
    assert skill_one.zip_path == zip_path.resolve()
    assert skill_two.zip_path == skill_path.resolve()
