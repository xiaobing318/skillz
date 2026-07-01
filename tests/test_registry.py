from pathlib import Path

from skillz import SkillRegistry


def write_skill(directory: Path, name: str = "echo") -> Path:
    skill_dir = directory / name
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(
        """---
name: {name}
description: Test skill
---
Body
""".format(name=name),
        encoding="utf-8",
    )
    return skill_dir


def test_registry_discovers_skill(tmp_path: Path) -> None:
    write_skill(tmp_path, name="echo")

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert len(registry.skills) == 1
    skill = registry.get("echo")
    assert skill.metadata.name == "echo"
    assert skill.instructions_path.name == "SKILL.md"


def test_registry_skips_non_standard_skill_name(tmp_path: Path) -> None:
    skill_dir = tmp_path / "echo"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(
        """---
name: Echo
description: Test skill
---
Body
""",
        encoding="utf-8",
    )

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert registry.skills == ()


def test_registry_skips_directory_name_mismatch(tmp_path: Path) -> None:
    skill_dir = tmp_path / "echo"
    skill_dir.mkdir()
    (skill_dir / "SKILL.md").write_text(
        """---
name: other-skill
description: Test skill
---
Body
""",
        encoding="utf-8",
    )

    registry = SkillRegistry(tmp_path)
    registry.load()

    assert registry.skills == ()
