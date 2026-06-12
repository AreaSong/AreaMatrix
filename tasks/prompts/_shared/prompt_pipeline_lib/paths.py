from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[4]
PROMPTS_ROOT = ROOT / "tasks" / "prompts"
SHARED_ROOT = PROMPTS_ROOT / "_shared"
MANIFEST_ROOT = SHARED_ROOT / "manifests"
AUDIT_RULES = SHARED_ROOT / "audit-rules.md"
TASK_SLICING_RULES = SHARED_ROOT / "task-slicing-rules.md"
ENGINEERING_QUALITY_RULES = SHARED_ROOT / "engineering-quality-rules.md"
DEPENDENCY_GRAPH = SHARED_ROOT / "dependency-graph.md"
CODING_STANDARDS = ROOT / "docs" / "development" / "coding-standards.md"
PROGRESS_PATH = SHARED_ROOT / "progress.json"
COPY_READY_ROOT = SHARED_ROOT / "copy-ready"
VERIFY_READY_ROOT = SHARED_ROOT / "verify-ready"
SKILL_SOURCE_ROOT = ROOT / ".codex" / "skills-src"
SKILL_DISCOVERY_ROOT = ROOT / ".agents" / "skills"

REPO_LOCAL_SKILLS = (
    "areamatrix-task-loop",
    "areamatrix-validation-driver",
    "areamatrix-doc-sync",
    "areamatrix-file-safety",
)

VALIDATION_DRIVER_SKILL = SKILL_SOURCE_ROOT / "areamatrix-validation-driver" / "SKILL.md"
VALIDATION_DRIVER_MATRIX = (
    SKILL_SOURCE_ROOT / "areamatrix-validation-driver" / "references" / "validation-matrix.md"
)
VALIDATION_DRIVER_REPORT = (
    SKILL_SOURCE_ROOT / "areamatrix-validation-driver" / "references" / "report-format.md"
)

ALLOWED_NEW_ROOTS = (
    "AGENTS.md",
    "README.md",
    "README.zh-CN.md",
    "CHANGELOG.md",
    "SECURITY.md",
    "CONTRIBUTING.md",
    "LICENSE",
    ".ai-governance/",
    ".codex/",
    ".github/",
    "apps/",
    "core/",
    "docs/",
    "scripts/",
    "specs/",
    "tasks/",
)

HIGH_RISK_PATH_PATTERNS = (
    "adopt",
    "ai-summary",
    "area_matrix.udl",
    "core-api",
    "data-model",
    "db",
    "ffi",
    "fs-watcher",
    "icloud",
    "migration",
    "privacy",
    "recovery",
    "source-of-truth",
    "staging",
    "storage",
    "sync",
    "transactional",
    "local-ai",
    "stage3-ai",
)

TASK_RE = re.compile(r"^task-(\d+)-")
BATCH_RE = re.compile(r"^(\d+-\d+)-")
PHASE_RE = re.compile(r"^phase-(\d+)$")
LABEL_RE = re.compile(r"^(\d+-\d+)/task-(\d+)$")
LABEL_IN_TEXT_RE = re.compile(r"(\d+-\d+)/task-(\d+)")
MANIFEST_HEADING_RE = re.compile(r"^##\s+(.+)$", re.M)
UX_DOC_RE = re.compile(r"/(S(?:[1-3]-\d+|4-[A-Z]+-\d+)-[^/]+)\.md$")
CAPABILITY_DOC_RE = re.compile(r"/(C[1-4]-\d+)-[^/]+\.md$")
PAGE_ID_RE = re.compile(r"^S(?:[1-3]-\d+|4-[A-Z]+-\d+)$")
CAPABILITY_ID_RE = re.compile(r"C[1-4]-\d+")
CORE_VERIFY_RE = re.compile(r"\bC[1-4]-\d+\b.*\bintegration-verify\b", re.IGNORECASE)
PAGE_VERIFY_RE = re.compile(
    r"\bS(?:[1-3]-\d+|4-[A-Z]+-\d+)\b.*\bpage[- ]integration[- ]verify\b",
    re.IGNORECASE,
)
MARKDOWN_LINK_RE = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
EXTERNAL_LINK_RE = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")


@dataclass(frozen=True)
class TaskFile:
    label: str
    phase: str
    phase_number: int
    batch: str
    path: Path
    title: str


@dataclass
class ManifestEntry:
    label: str
    manifest_path: Path
    source_task: str = ""
    depends: list[str] = field(default_factory=list)
    sections: dict[str, list[str]] = field(default_factory=dict)
    raw: str = ""

    @property
    def risk(self) -> str:
        values = self.sections.get("Risk Level", [])
        return values[0] if values else "Unspecified"

    @property
    def exact_docs(self) -> list[str]:
        return self.sections.get("Exact Docs", [])

    @property
    def existing_code(self) -> list[str]:
        return self.sections.get("Existing Code", [])

    @property
    def expected_new_paths(self) -> list[str]:
        return self.sections.get("Expected New Paths", [])

    @property
    def validation(self) -> list[str]:
        return self.sections.get("Validation", [])

    @property
    def forbidden_touches(self) -> list[str]:
        return self.sections.get("Forbidden Touches", [])


@dataclass(frozen=True)
class PageContract:
    page_id: str
    page_name: str
    capabilities: tuple[str, ...]
    prompt_labels: tuple[str, ...]
    control_map_path: Path
    line_no: int


GLOBAL_CODEX_SKILL_PATH = "~/.codex/skills-src/..."


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def prompt_rel(path: Path) -> str:
    """Human-facing repo-relative path for copy/verify-ready prompts."""
    relative = rel(path)
    if relative == ".":
        return "."
    return f"./{relative}"


def label_sort_key(label: str) -> tuple[int, int, int]:
    match = LABEL_RE.match(label)
    if not match:
        return (999, 999, 999)
    batch = match.group(1)
    first, second = batch.split("-")
    return (int(first), int(second), int(match.group(2)))
