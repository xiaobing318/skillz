"""Skillz MCP server exposing local Agent Skills via FastMCP.

Skills provide instructions and resources via MCP. Clients are responsible
for reading resources (including any scripts) and executing them if needed.
"""

from __future__ import annotations

import argparse
import logging
import mimetypes
from pathlib import PurePosixPath
import re
import sys
import textwrap
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import (
    Any,
    Awaitable,
    Callable,
    Dict,
    Iterable,
    Iterator,
    Mapping,
    Optional,
    TypedDict,
)
from urllib.parse import quote

import yaml
from fastmcp import Context, FastMCP
from fastmcp.exceptions import ToolError
from starlette.middleware import Middleware
from starlette.middleware.cors import CORSMiddleware

from ._version import __version__


LOGGER = logging.getLogger("skillz")
FRONT_MATTER_PATTERN = re.compile(r"^---\s*\n(.*?)\n---\s*\n(.*)", re.DOTALL)
SKILL_MARKDOWN = "SKILL.md"
DEFAULT_SKILLS_ROOT = Path("~/.skillz")
DEFAULT_LOG_FILE = Path(".skillz/skillz.log")
SERVER_NAME = "Skillz MCP Server"
SERVER_VERSION = __version__
MCP_SESSION_ID_HEADER = "mcp-session-id"
CORS_ALLOW_METHODS = ["GET", "POST", "DELETE", "OPTIONS"]
SKILL_NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
RESERVED_TOOL_NAMES = frozenset(
    {
        "list_skills",
    }
)


def _path_is_relative_to(path: Path, root: Path) -> bool:
    """Return True when path is contained by root after resolution."""

    try:
        path.resolve(strict=True).relative_to(root.resolve(strict=True))
    except (OSError, ValueError):
        return False
    return True


def _validate_relative_resource_path(rel_path: str) -> None:
    """Reject resource paths that escape their skill package."""

    parts = PurePosixPath(rel_path).parts
    if rel_path.startswith("/") or any(part in {"", ".."} for part in parts):
        raise SkillError(f"Invalid resource path: {rel_path}")


class SkillError(Exception):
    """Base exception for skill-related failures."""

    def __init__(self, message: str, *, code: str = "skill_error") -> None:
        super().__init__(message)
        self.code = code


class SkillValidationError(SkillError):
    """Raised when a skill fails validation."""

    def __init__(self, message: str) -> None:
        super().__init__(message, code="validation_error")


@dataclass(slots=True)
class SkillMetadata:
    """Structured metadata extracted from a skill front matter block."""

    name: str
    description: str
    license: Optional[str] = None
    compatibility: Optional[str] = None
    allowed_tools: tuple[str, ...] = ()
    metadata: Dict[str, str] = field(default_factory=dict)
    extra: Dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class Skill:
    """Runtime representation of a skill directory or zip file."""

    slug: str
    directory: Path
    instructions_path: Path
    metadata: SkillMetadata
    resources: tuple[Path, ...]
    zip_path: Optional[Path] = None
    zip_root_prefix: str = ""
    _zip_members: Optional[set[str]] = field(default=None, init=False)

    def __post_init__(self) -> None:
        """Cache zip members for efficient lookups."""
        if self.zip_path is not None:
            with zipfile.ZipFile(self.zip_path) as z:
                # Cache file members (exclude directory entries)
                # Strip the root prefix if present
                all_members = {
                    name
                    for name in z.namelist()
                    if not name.endswith("/")
                }
                if self.zip_root_prefix:
                    # Store members without the prefix for easier access
                    self._zip_members = {
                        name[len(self.zip_root_prefix):]
                        for name in all_members
                        if name.startswith(self.zip_root_prefix)
                    }
                else:
                    self._zip_members = all_members

    @property
    def is_zip(self) -> bool:
        """Check if this skill is backed by a zip file."""
        return self.zip_path is not None

    def open_bytes(self, rel_path: str) -> bytes:
        """Read file content as bytes."""
        _validate_relative_resource_path(rel_path)
        if self.is_zip:
            with zipfile.ZipFile(self.zip_path) as z:
                # Add the root prefix if present
                zip_member_path = self.zip_root_prefix + rel_path
                return z.read(zip_member_path)

        candidate = self.directory / rel_path
        if not _path_is_relative_to(candidate, self.directory):
            raise SkillError(
                f"Resource '{rel_path}' escapes skill directory "
                f"{self.directory}"
            )
        return candidate.read_bytes()

    def exists(self, rel_path: str) -> bool:
        """Check if a relative path exists in this skill."""
        if self.is_zip:
            return rel_path in (self._zip_members or set())

        candidate = self.directory / rel_path
        return candidate.exists() and _path_is_relative_to(
            candidate, self.directory
        )

    def iter_resource_paths(self) -> Iterator[str]:
        """Iterate over resource file paths (excluding SKILL.md)."""
        if self.is_zip:
            # Yield file paths from zip, skip SKILL.md and macOS metadata
            for name in sorted(self._zip_members or []):
                if name == SKILL_MARKDOWN:
                    continue
                if "__MACOSX/" in name or name.endswith(".DS_Store"):
                    continue
                yield name
        else:
            for file_path in self.resources:
                try:
                    rel_path = file_path.relative_to(self.directory)
                except ValueError:
                    continue
                yield rel_path.as_posix()

    def read_body(self) -> str:
        """Return the Markdown body of the skill."""

        LOGGER.debug("Reading body for skill %s", self.slug)
        if self.is_zip:
            data = self.open_bytes(SKILL_MARKDOWN)
            text = data.decode("utf-8")
        else:
            text = self.instructions_path.read_text(encoding="utf-8")
        match = FRONT_MATTER_PATTERN.match(text)
        if match:
            return match.group(2).lstrip()
        raise SkillValidationError(
            f"Skill {self.slug} is missing YAML front matter "
            "and cannot be served."
        )


class SkillResourceMetadata(TypedDict):
    """Metadata describing a registered skill resource following MCP spec.

    According to MCP specification:
    - uri: Unique identifier for the resource (with protocol)
    - name: Human-readable name (path without protocol prefix)
    - mimeType: Optional MIME type for the resource
    """

    uri: str
    name: str
    mime_type: Optional[str]


def slugify(value: str) -> str:
    """Convert names into stable slug identifiers."""

    cleaned = re.sub(r"[^a-zA-Z0-9]+", "-", value.strip().lower()).strip("-")
    return cleaned or "skill"


RESERVED_SKILL_SLUGS = frozenset(slugify(name) for name in RESERVED_TOOL_NAMES)


def _parse_allowed_tools(value: Any) -> tuple[str, ...]:
    """Parse the optional Agent Skills allowed-tools field."""

    if isinstance(value, str):
        return tuple(
            part for part in re.split(r"[\s,]+", value.strip()) if part
        )
    if isinstance(value, Iterable):
        return tuple(
            str(item).strip() for item in value if str(item).strip()
        )
    return ()


def _read_front_matter(path: Path) -> str:
    """Read only the YAML front matter from a SKILL.md file."""

    with path.open("r", encoding="utf-8", newline="") as handle:
        first_line = handle.readline()
        if first_line.strip() != "---":
            raise SkillValidationError(
                f"{path} must begin with YAML front matter delimited by "
                "'---'."
            )

        front_matter_lines: list[str] = []
        for line in handle:
            if line.strip() == "---":
                return "".join(front_matter_lines)
            front_matter_lines.append(line)

    raise SkillValidationError(
        f"{path} must close YAML front matter with '---'."
    )


def _read_zip_front_matter(z: zipfile.ZipFile, member_name: str) -> str:
    """Read only the YAML front matter from a zipped SKILL.md file."""

    with z.open(member_name) as handle:
        first_line = handle.readline().decode("utf-8")
        if first_line.strip() != "---":
            raise SkillValidationError(
                f"{member_name} must begin with YAML front matter "
                "delimited by '---'."
            )

        front_matter_lines: list[str] = []
        for raw_line in handle:
            line = raw_line.decode("utf-8")
            if line.strip() == "---":
                return "".join(front_matter_lines)
            front_matter_lines.append(line)

    raise SkillValidationError(
        f"{member_name} must close YAML front matter with '---'."
    )


def _parse_skill_metadata(
    front_matter: str,
    *,
    source: str,
    container_name: Optional[str],
) -> SkillMetadata:
    """Parse and validate Agent Skills front matter."""

    try:
        data = yaml.safe_load(front_matter) or {}
    except yaml.YAMLError as exc:  # pragma: no cover - defensive
        raise SkillValidationError(
            f"Unable to parse YAML in {source}: {exc}"
        ) from exc

    if not isinstance(data, Mapping):
        raise SkillValidationError(
            f"Front matter in {source} must define a mapping, "
            f"not {type(data).__name__}."
        )

    name = str(data.get("name", "")).strip()
    description = str(data.get("description", "")).strip()
    if not name:
        raise SkillValidationError(
            f"Front matter in {source} is missing 'name'."
        )
    if not description:
        raise SkillValidationError(
            f"Front matter in {source} is missing 'description'."
        )
    if len(name) > 64 or not SKILL_NAME_PATTERN.fullmatch(name):
        raise SkillValidationError(
            f"Skill name '{name}' in {source} must be 1-64 characters "
            "using lowercase letters, numbers, and single hyphens."
        )
    if container_name is not None and name != container_name:
        raise SkillValidationError(
            f"Skill name '{name}' in {source} must match its containing "
            f"directory or package name '{container_name}'."
        )
    if len(description) > 1024:
        raise SkillValidationError(
            f"Description in {source} must be 1024 characters or fewer."
        )

    allowed_list = _parse_allowed_tools(
        data.get("allowed-tools") or data.get("allowed_tools") or []
    )
    compatibility = (
        str(data["compatibility"]).strip()
        if data.get("compatibility")
        else None
    )
    if compatibility is not None and len(compatibility) > 500:
        raise SkillValidationError(
            f"Compatibility in {source} must be 500 characters or fewer."
        )

    raw_metadata = data.get("metadata") or {}
    if raw_metadata and not isinstance(raw_metadata, Mapping):
        raise SkillValidationError(
            f"Metadata in {source} must be a mapping when provided."
        )
    metadata = {
        str(key): str(value)
        for key, value in raw_metadata.items()
    }

    extra = {
        key: value
        for key, value in data.items()
        if key
        not in {
            "name",
            "description",
            "license",
            "compatibility",
            "metadata",
            "allowed-tools",
            "allowed_tools",
        }
    }

    metadata = SkillMetadata(
        name=name,
        description=description,
        license=(
            str(data["license"]).strip() if data.get("license") else None
        ),
        compatibility=compatibility,
        allowed_tools=allowed_list,
        metadata=metadata,
        extra=extra,
    )
    return metadata


def parse_skill_md(path: Path) -> tuple[SkillMetadata, str]:
    """Parse SKILL.md front matter and body."""

    raw = path.read_text(encoding="utf-8")
    match = FRONT_MATTER_PATTERN.match(raw)
    if not match:
        raise SkillValidationError(
            f"{path} must begin with YAML front matter delimited by '---'."
        )

    front_matter, body = match.groups()
    metadata = _parse_skill_metadata(
        front_matter,
        source=str(path),
        container_name=path.parent.name,
    )
    return metadata, body.lstrip()


class SkillRegistry:
    """Discover and manage skills found under a root directory."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self._skills_by_slug: dict[str, Skill] = {}
        self._skills_by_name: dict[str, Skill] = {}

    @property
    def skills(self) -> tuple[Skill, ...]:
        return tuple(self._skills_by_slug.values())

    def load(self) -> None:
        if not self.root.exists() or not self.root.is_dir():
            raise SkillError(
                f"Skills root {self.root} does not exist "
                "or is not a directory."
            )

        LOGGER.info("Discovering skills in %s", self.root)
        self._skills_by_slug.clear()
        self._skills_by_name.clear()

        root = self.root.resolve()
        self._scan_directory(root)

        LOGGER.info("Loaded %d skills", len(self._skills_by_slug))

    def _scan_directory(self, directory: Path) -> None:
        """Recursively scan directory for skills (both dirs and zips)."""
        # If this directory has SKILL.md, treat it as a dir-based skill
        skill_md_path = directory / SKILL_MARKDOWN
        if skill_md_path.is_file():
            self._register_dir_skill(directory, skill_md_path)
            return  # Don't recurse into skill directories

        # Otherwise, look for zip files and subdirectories
        try:
            entries = list(directory.iterdir())
        except (OSError, PermissionError) as exc:
            LOGGER.warning("Cannot read directory %s: %s", directory, exc)
            return

        # First, recurse into subdirectories (to find directory skills first)
        # This ensures directory skills take precedence over zip skills
        for entry in sorted(entries):
            if entry.is_dir():
                self._scan_directory(entry)

        # Then check for zip files in this directory
        for entry in sorted(entries):
            if entry.is_file() and entry.suffix.lower() in (".zip", ".skill"):
                self._try_register_zip_skill(entry)

    def _register_dir_skill(self, directory: Path, skill_md: Path) -> None:
        """Register a directory-based skill."""
        try:
            metadata = _parse_skill_metadata(
                _read_front_matter(skill_md),
                source=str(skill_md),
                container_name=directory.name,
            )
        except SkillValidationError as exc:
            LOGGER.warning(
                "Skipping invalid skill at %s: %s", directory, exc
            )
            return

        slug = slugify(metadata.name)
        if slug in self._skills_by_slug:
            LOGGER.error(
                "Duplicate skill slug '%s'; skipping %s",
                slug,
                directory,
            )
            return

        if metadata.name in self._skills_by_name:
            LOGGER.warning(
                "Duplicate skill name '%s' found in %s; "
                "only first occurrence is kept",
                metadata.name,
                directory,
            )
            return

        resources = self._collect_resources(directory)

        skill = Skill(
            slug=slug,
            directory=directory.resolve(),
            instructions_path=skill_md.resolve(),
            metadata=metadata,
            resources=resources,
        )

        if directory.name != slug:
            LOGGER.debug(
                "Skill directory name '%s' does not match slug '%s'",
                directory.name,
                slug,
            )

        self._skills_by_slug[slug] = skill
        self._skills_by_name[metadata.name] = skill

    def _try_register_zip_skill(self, zip_path: Path) -> None:
        """Try to register a zip file as a skill."""
        try:
            with zipfile.ZipFile(zip_path) as z:
                # Check if SKILL.md exists at root or in single top-level dir
                members = {
                    name for name in z.namelist() if not name.endswith("/")
                }

                skill_md_path = None
                zip_root_prefix = ""

                # First, try SKILL.md at root
                if SKILL_MARKDOWN in members:
                    skill_md_path = SKILL_MARKDOWN
                else:
                    # Try to find SKILL.md in single top-level directory
                    # Pattern: skill-name.zip contains skill-name/SKILL.md
                    top_level_dirs = set()
                    for name in z.namelist():
                        if "/" in name:
                            top_dir = name.split("/", 1)[0]
                            top_level_dirs.add(top_dir)

                    # If there's exactly one top-level directory
                    if len(top_level_dirs) == 1:
                        top_dir = list(top_level_dirs)[0]
                        candidate = f"{top_dir}/{SKILL_MARKDOWN}"
                        if candidate in members:
                            skill_md_path = candidate
                            zip_root_prefix = f"{top_dir}/"

                if skill_md_path is None:
                    LOGGER.debug(
                        "Zip %s missing SKILL.md at root or in "
                        "single top-level directory; skipping",
                        zip_path,
                    )
                    return

                container_name = (
                    zip_root_prefix.rstrip("/")
                    if zip_root_prefix
                    else zip_path.stem
                )
                metadata = _parse_skill_metadata(
                    _read_zip_front_matter(z, skill_md_path),
                    source=f"{zip_path}!/{skill_md_path}",
                    container_name=container_name,
                )

        except zipfile.BadZipFile:
            LOGGER.warning("Invalid or corrupt zip file: %s", zip_path)
            return
        except SkillValidationError as exc:
            LOGGER.warning("Invalid skill in zip %s: %s", zip_path, exc)
            return
        except (OSError, UnicodeDecodeError) as exc:
            LOGGER.warning("Cannot read zip file %s: %s", zip_path, exc)
            return

        # Use zip stem as slug
        slug = slugify(metadata.name)
        if slug in self._skills_by_slug:
            LOGGER.warning(
                "Duplicate skill slug '%s'; skipping zip %s",
                slug,
                zip_path,
            )
            return

        if metadata.name in self._skills_by_name:
            LOGGER.warning(
                "Duplicate skill name '%s' found in zip %s; skipping",
                metadata.name,
                zip_path,
            )
            return

        # Create skill with zip_path set
        skill = Skill(
            slug=slug,
            directory=zip_path.parent.resolve(),
            instructions_path=zip_path.resolve(),
            metadata=metadata,
            resources=(),  # Will be populated from zip
            zip_path=zip_path.resolve(),
            zip_root_prefix=zip_root_prefix,
        )

        self._skills_by_slug[slug] = skill
        self._skills_by_name[metadata.name] = skill
        LOGGER.debug(
            "Registered zip-based skill '%s' from %s (root_prefix='%s')",
            slug,
            zip_path,
            zip_root_prefix,
        )

    def _collect_resources(self, directory: Path) -> tuple[Path, ...]:
        """Collect all files in skill directory except SKILL.md.

        SKILL.md is only returned from the tool, not as a resource.
        All other files in the skill directory and subdirectories are
        resources.

        Note: For zip-based skills, resources are collected via
        iter_resource_paths() directly from the Skill object.
        """
        root = directory.resolve()
        skill_md_path = root / SKILL_MARKDOWN
        files = []
        for file_path in sorted(root.rglob("*")):
            if not file_path.is_file():
                continue
            if file_path == skill_md_path:
                continue
            if not _path_is_relative_to(file_path, root):
                LOGGER.warning(
                    "Skipping resource outside skill directory: %s",
                    file_path,
                )
                continue
            files.append(file_path)
        return tuple(files)

    def get(self, slug: str) -> Skill:
        try:
            return self._skills_by_slug[slug]
        except KeyError as exc:  # pragma: no cover - defensive
            raise SkillError(f"Unknown skill '{slug}'") from exc


def _build_resource_uri(skill: Skill, relative_path: Path) -> str:
    """Build a resource URI following MCP specification.

    Format: [protocol]://[host]/[path]
    Example: resource://skillz/skill-name/path/to/file.ext
    """
    encoded_slug = quote(skill.slug, safe="")
    encoded_parts = [quote(part, safe="") for part in relative_path.parts]
    path_suffix = "/".join(encoded_parts)
    return f"resource://skillz/{encoded_slug}/{path_suffix}"


def _get_resource_name(skill: Skill, relative_path: Path) -> str:
    """Get resource name (path without protocol) following MCP specification.

    This is the URI path without the protocol prefix.
    Example: skillz/skill-name/path/to/file.ext
    """
    return f"{skill.slug}/{relative_path.as_posix()}"


def _detect_mime_type(file_path: Path) -> Optional[str]:
    """Detect MIME type for a file, returning None if unknown.

    Uses Python's mimetypes library for detection.
    """
    mime_type, _ = mimetypes.guess_type(str(file_path))
    return mime_type


def register_skill_resources(
    mcp: FastMCP, skill: Skill
) -> tuple[SkillResourceMetadata, ...]:
    """Register FastMCP resources for each file in a skill.

    Resources follow MCP specification:
    - URI format: resource://skillz/{skill-slug}/{path}
    - Name: {skill-slug}/{path} (URI without protocol)
    - MIME type: Detected from file extension
    - Content: UTF-8 text or base64-encoded binary

    Handles both directory-based and zip-based skills.
    """

    metadata: list[SkillResourceMetadata] = []

    if skill.is_zip:
        # For zip-based skills, iterate over resources from zip
        for rel_path_str in skill.iter_resource_paths():
            # Build URI and name
            slug_encoded = quote(skill.slug, safe="")
            path_encoded = quote(rel_path_str, safe="/")
            uri = f"resource://skillz/{slug_encoded}/{path_encoded}"
            name = f"{skill.slug}/{rel_path_str}"
            mime_type, _ = mimetypes.guess_type(rel_path_str)

            def _make_zip_resource_reader(
                s: Skill, p: str
            ) -> Callable[[], str | bytes]:
                def _read_resource() -> str | bytes:
                    try:
                        data = s.open_bytes(p)
                    except (OSError, KeyError) as exc:  # pragma: no cover
                        raise SkillError(
                            f"Failed to read resource '{p}' from zip: {exc}"
                        ) from exc

                    # Try to decode as UTF-8 text; if that fails, return binary
                    try:
                        return data.decode("utf-8")
                    except UnicodeDecodeError:
                        # FastMCP will handle base64 encoding for binary
                        return data

                return _read_resource

            mcp.resource(uri, name=name, mime_type=mime_type)(
                _make_zip_resource_reader(skill, rel_path_str)
            )

            metadata.append(
                {
                    "uri": uri,
                    "name": name,
                    "mime_type": mime_type,
                }
            )
    else:
        # For directory-based skills, iterate over file paths
        for resource_path in skill.resources:
            try:
                relative_path = resource_path.relative_to(skill.directory)
            except ValueError:  # pragma: no cover - defensive safeguard
                relative_path = Path(resource_path.name)

            uri = _build_resource_uri(skill, relative_path)
            name = _get_resource_name(skill, relative_path)
            mime_type = _detect_mime_type(resource_path)

            def _make_resource_reader(
                path: Path,
                root: Path,
            ) -> Callable[[], str | bytes]:
                def _read_resource() -> str | bytes:
                    if not _path_is_relative_to(path, root):
                        raise SkillError(
                            f"Resource '{path}' escapes skill directory "
                            f"{root}"
                        )
                    try:
                        data = path.read_bytes()
                    except OSError as exc:  # pragma: no cover
                        raise SkillError(
                            f"Failed to read resource '{path}': {exc}"
                        ) from exc

                    # Try to decode as UTF-8 text; if that fails, return binary
                    try:
                        return data.decode("utf-8")
                    except UnicodeDecodeError:
                        # FastMCP will handle base64 encoding for binary data
                        return data

                return _read_resource

            mcp.resource(uri, name=name, mime_type=mime_type)(
                _make_resource_reader(resource_path, skill.directory)
            )

            metadata.append(
                {
                    "uri": uri,
                    "name": name,
                    "mime_type": mime_type,
                }
            )

    return tuple(metadata)


def _skill_response(
    skill: Skill,
    *,
    task: str,
    resources: tuple[SkillResourceMetadata, ...],
) -> Mapping[str, Any]:
    """Build the standard response returned when a skill is invoked."""

    if not task.strip():
        raise SkillError("The 'task' parameter must be a non-empty string.")

    instructions = skill.read_body()
    resource_entries = [
        {
            "uri": entry["uri"],
            "name": entry["name"],
            "mime_type": entry["mime_type"],
        }
        for entry in resources
    ]

    return {
        "skill": skill.slug,
        "task": task,
        "metadata": {
            "name": skill.metadata.name,
            "description": skill.metadata.description,
            "license": skill.metadata.license,
            "compatibility": skill.metadata.compatibility,
            "allowed_tools": list(skill.metadata.allowed_tools),
            "metadata": skill.metadata.metadata,
            "extra": skill.metadata.extra,
        },
        "resources": resource_entries,
        "instructions": instructions,
        "usage": textwrap.dedent(
            """\
            HOW TO USE THIS SKILL:

            1. READ the instructions carefully - they contain
               specialized guidance for completing the task.

            2. UNDERSTAND the context:
               - The 'task' field contains the specific request
               - The 'metadata.allowed_tools' list specifies which
                 tools to use when applying this skill (if specified,
                 respect these constraints)
               - The 'resources' array lists additional files

            3. APPLY the skill instructions to complete the task:
               - Follow the instructions as your primary guidance
               - Use judgment to adapt instructions to the task
               - Instructions are authored by skill creators and may
                 contain domain-specific expertise, best practices,
                 or specialized techniques

            4. ACCESS resources when needed:
               - If instructions reference additional files or you
                 need them, retrieve from the MCP server
               - Use native MCP resource fetching with the URIs listed
                 in the 'resources' field

            5. RESPECT constraints:
               - If 'metadata.allowed_tools' is specified and
                 non-empty, prefer using only those tools when
                 executing the skill instructions
               - This helps ensure the skill works as intended

            Remember: Skills are specialized instruction sets
            created by experts. They provide domain knowledge and
            best practices you can apply to user tasks.
            """
        ).strip(),
    }


def _format_tool_description(skill: Skill) -> str:
    """Return the concise skill description for discovery responses."""

    description = skill.metadata.description.strip()
    if not description:  # pragma: no cover - defensive safeguard
        raise SkillValidationError(
            f"Skill {skill.slug} is missing a description after validation."
        )

    # Enhanced description that makes it clear this is a skill tool
    return (
        f"[SKILL] {description} - "
        "Invoke this to receive specialized instructions and "
        "resources for this task."
    )


def register_skill_tool(
    mcp: FastMCP,
    skill: Skill,
    *,
    resources: tuple[SkillResourceMetadata, ...],
) -> Callable[..., Awaitable[Mapping[str, Any]]]:
    """Register a tool that returns skill instructions and resource URIs.

    Clients are expected to read the instructions and retrieve any
    referenced resources from the MCP server as needed.
    """
    tool_name = skill.slug
    if tool_name in RESERVED_SKILL_SLUGS:
        raise SkillError(
            f"Skill slug '{tool_name}' conflicts with a Skillz management "
            "tool name."
        )

    description = _format_tool_description(skill)
    bound_skill = skill
    bound_resources = resources

    @mcp.tool(name=tool_name, description=description)
    async def _skill_tool(  # type: ignore[unused-ignore]
        task: str,
        ctx: Optional[Context] = None,
    ) -> Mapping[str, Any]:
        LOGGER.info(
            "Skill %s tool invoked task=%s",
            bound_skill.slug,
            task,
        )

        try:
            return _skill_response(
                bound_skill,
                task=task,
                resources=bound_resources,
            )
        except SkillError as exc:
            LOGGER.error(
                "Skill %s invocation failed: %s",
                bound_skill.slug,
                exc,
                exc_info=True,
            )
            raise ToolError(str(exc)) from exc

    return _skill_tool


def _skill_summary(skill: Skill, root: Path) -> Mapping[str, Any]:
    """Return lightweight startup discovery metadata for a skill."""

    return {
        "slug": skill.slug,
        "name": skill.metadata.name,
        "description": skill.metadata.description,
    }


def _register_discovery_tools(mcp: FastMCP, registry: SkillRegistry) -> None:
    """Register read-only tools that let clients inspect available skills."""

    @mcp.tool(
        name="list_skills",
        description=(
            "List skills currently available through Skillz using startup "
            "metadata only: "
            "slug, name, and description."
        ),
    )
    async def list_skills_tool(
        ctx: Optional[Context] = None,
    ) -> Mapping[str, Any]:
        return {
            "skills_root": str(registry.root.resolve()),
            "count": len(registry.skills),
            "skills": [
                _skill_summary(skill, registry.root)
                for skill in registry.skills
            ],
        }

def configure_logging(
    verbose: bool,
    log_to_file: bool,
    log_file: Path = DEFAULT_LOG_FILE,
) -> None:
    """Set up console logging and optional file logging."""

    log_format = "%(asctime)s | %(levelname)s | %(name)s | %(message)s"
    handlers: list[logging.Handler] = []

    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.DEBUG if verbose else logging.INFO)
    console_handler.setFormatter(logging.Formatter(log_format))
    handlers.append(console_handler)

    if log_to_file:
        log_path = log_file.expanduser()
        try:
            log_path.parent.mkdir(parents=True, exist_ok=True)
            file_handler = logging.FileHandler(
                log_path, mode="a", encoding="utf-8"
            )
        except OSError as exc:  # pragma: no cover - filesystem failure is rare
            print(
                f"Failed to configure log file {log_path}: {exc}",
                file=sys.stderr,
            )
        else:
            file_handler.setLevel(logging.DEBUG)
            file_handler.setFormatter(logging.Formatter(log_format))
            handlers.append(file_handler)

    logging.basicConfig(
        level=logging.DEBUG if (log_to_file or verbose) else logging.INFO,
        handlers=handlers,
        force=True,
    )


def build_cors_middleware(
    allowed_origins: Iterable[str],
    *,
    allow_credentials: bool = False,
) -> list[Middleware]:
    """Build optional CORS middleware for browser-hosted MCP clients."""

    origins = tuple(
        origin.strip() for origin in allowed_origins if origin.strip()
    )
    if not origins:
        return []

    if allow_credentials and "*" in origins:
        raise SkillError(
            "--cors-allow-credentials cannot be used with "
            "--cors-origin '*'."
        )

    return [
        Middleware(
            CORSMiddleware,
            allow_origins=list(origins),
            allow_credentials=allow_credentials,
            allow_methods=CORS_ALLOW_METHODS,
            allow_headers=["*"],
            expose_headers=[MCP_SESSION_ID_HEADER],
        )
    ]


def build_server(registry: SkillRegistry) -> FastMCP:
    summary = (
        ", ".join(skill.metadata.name for skill in registry.skills)
        or "No skills"
    )

    # Comprehensive server-level instructions for AI agents
    skill_count = len(registry.skills)
    server_instructions = textwrap.dedent(
        f"""\
        SKILLZ MCP SERVER - Specialized Instruction Provider

        This server provides access to {skill_count} skill(s):
        {summary}

        ## WHAT ARE SKILLS?

        Skills are specialized instruction sets created by domain experts.
        Each skill provides detailed guidance, best practices, and
        techniques for completing specific types of tasks. Think of skills
        as expert knowledge packages that you can apply to user requests.

        ## WHEN TO USE SKILLS

        Consider using a skill when:
        - A user's request matches a skill's description or domain
        - You need specialized knowledge or domain expertise
        - A task would benefit from expert-authored instructions or best
          practices
        - The skill provides relevant tools, resources, or techniques

        You should still use your own judgment about whether a skill is
        appropriate for the specific task at hand.

        ## HOW TO USE SKILLS

        1. DISCOVER: Review available skill tools (they're marked with
           [SKILL] prefix) to understand what specialized instructions
           are available.

        2. INVOKE: When a skill is relevant to a user's task, invoke the
           skill tool with the 'task' parameter describing what the user
           wants to accomplish.

        3. RECEIVE: The skill tool returns a structured response with:
           - instructions: Detailed guidance from the skill author
           - metadata: Info about the skill (name, allowed_tools, etc.)
           - resources: Additional files (scripts, datasets, etc.)
           - usage: Instructions for how to apply the skill

        4. APPLY: Read and follow the skill instructions to complete the
           user's task. Use your judgment to adapt the instructions to
           the specific request.

        5. RESOURCES: If the skill references additional files or you
           need them, retrieve them using native MCP resources.

        ## IMPORTANT GUIDELINES

        - Skills provide INSTRUCTIONS, not direct execution - you still
          need to apply the instructions to complete the user's task
        - Respect the 'allowed_tools' metadata when specified - these
          are tool constraints that help ensure the skill works as
          intended
        - Skills may contain domain expertise beyond your training data
          - treat their instructions as authoritative guidance from
          experts
        - You can invoke multiple skills if relevant to different
          aspects of a task
        - Always read the 'usage' field in skill responses for specific
          guidance

        ## SKILL TOOLS VS REGULAR TOOLS

        - Skill tools (marked [SKILL]): Return specialized instructions
          for you to apply
        - Regular tools: Perform direct actions

        When you see a [SKILL] tool, invoking it gives you expert
        instructions, not a completed result. You apply those
        instructions to help the user.
        """
    ).strip()

    mcp = FastMCP(
        name=SERVER_NAME,
        version=SERVER_VERSION,
        instructions=server_instructions,
    )
    _register_discovery_tools(mcp, registry)

    for skill in registry.skills:
        resource_metadata = register_skill_resources(mcp, skill)
        register_skill_tool(
            mcp,
            skill,
            resources=resource_metadata,
        )
    return mcp


def list_skills(registry: SkillRegistry) -> None:
    if not registry.skills:
        print("No valid skills discovered.")
        return
    for skill in registry.skills:
        print(
            f"- {skill.metadata.name} (slug: {skill.slug}) -> ",
            skill.directory,
            sep="",
        )


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Skillz MCP server.")
    parser.add_argument(
        "skills_root",
        type=Path,
        nargs="?",
        help=(
            "Directory containing skill folders "
            f"(default: {DEFAULT_SKILLS_ROOT})"
        ),
    )
    parser.add_argument(
        "--transport",
        choices=("stdio", "http", "sse"),
        default="stdio",
        help="Transport to use when running the server",
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host for HTTP/SSE transports",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="Port for HTTP/SSE transports",
    )
    parser.add_argument(
        "--path",
        default="/mcp",
        help="Path for HTTP transport",
    )
    parser.add_argument(
        "--cors-origin",
        action="append",
        default=[],
        metavar="ORIGIN",
        help=(
            "Allow browser clients from ORIGIN when using HTTP/SSE. "
            "Repeat to allow multiple origins; use '*' only for trusted "
            "local environments."
        ),
    )
    parser.add_argument(
        "--cors-allow-credentials",
        action="store_true",
        help=(
            "Allow credentialed browser CORS requests. Cannot be used "
            "with --cors-origin '*'."
        ),
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable debug logging",
    )
    parser.add_argument(
        "--log",
        action="store_true",
        help=f"Write very verbose logs to {DEFAULT_LOG_FILE}",
    )
    parser.add_argument(
        "--log-file",
        type=Path,
        default=DEFAULT_LOG_FILE,
        help="Log file path used with --log",
    )
    parser.add_argument(
        "--list-skills",
        action="store_true",
        help="List parsed skills and exit without starting the server",
    )
    args = parser.parse_args(argv)
    skills_root = args.skills_root or DEFAULT_SKILLS_ROOT
    if not isinstance(skills_root, Path):
        skills_root = Path(skills_root)
    args.skills_root = skills_root.expanduser()
    args.log_file = args.log_file.expanduser()
    args.cors_origin = tuple(
        origin.strip() for origin in args.cors_origin if origin.strip()
    )
    if args.cors_allow_credentials and "*" in args.cors_origin:
        parser.error(
            "--cors-allow-credentials cannot be used with --cors-origin '*'."
        )
    return args


def main(argv: Optional[list[str]] = None) -> None:
    args = parse_args(argv)
    configure_logging(args.verbose, args.log, args.log_file)

    if args.log:
        LOGGER.info("Verbose file logging enabled at %s", args.log_file)

    registry = SkillRegistry(args.skills_root)
    registry.load()

    if args.list_skills:
        list_skills(registry)
        return

    server = build_server(registry)
    run_kwargs: dict[str, Any] = {"transport": args.transport}
    if args.transport in {"http", "sse"}:
        run_kwargs.update({"host": args.host, "port": args.port})
        if args.transport == "http":
            run_kwargs["path"] = args.path
        middleware = build_cors_middleware(
            args.cors_origin,
            allow_credentials=args.cors_allow_credentials,
        )
        if middleware:
            run_kwargs["middleware"] = middleware

    server.run(**run_kwargs)


if __name__ == "__main__":
    main()
