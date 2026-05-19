"""Read-only backlog prompt package browser."""

from __future__ import annotations

from argparse import Namespace
from dataclasses import dataclass
from pathlib import Path
import re
import sys

from .common import ToolError


BACKLOG_ROOT = Path("tasks/backlog/prompts")
LIVE_QUEUE_ROOT = Path("tasks/prompts")
PROMPT_MODES = {"copy": "copy-ready", "verify": "verify-ready"}
PROMPT_LINK_PATTERN = re.compile(r"`((?:copy-ready|verify-ready)/[^`]+\.md)`")


@dataclass(frozen=True)
class BacklogPackage:
    slug: str
    title: str
    task_count: int
    copy_ready_count: int
    verify_ready_count: int


@dataclass(frozen=True)
class BacklogTask:
    number: int
    label: str
    copy_ready_path: Path | None
    verify_ready_path: Path | None


def _command_name(args: Namespace) -> str:
    if args.backlog_command == "list":
        return "./dev backlog list"
    if args.backlog_command == "show":
        command = f"./dev backlog show {args.package}"
        if args.task is not None:
            command += f" --task {args.task}"
        if args.mode is not None:
            command += f" --mode {args.mode}"
        return command
    return "./dev backlog"


def _prompt_files(package_dir: Path, prompt_dir_name: str) -> list[Path]:
    prompt_dir = package_dir / prompt_dir_name
    if not prompt_dir.is_dir():
        return []
    return sorted(path for path in prompt_dir.glob("*.md") if path.is_file())


def _relative_display(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def _read_title(readme: Path) -> str:
    first_line = readme.read_text(encoding="utf-8").splitlines()[0].strip()
    return first_line.lstrip("#").strip() or readme.parent.name


def discover_packages(root: Path) -> list[BacklogPackage]:
    """Return backlog packages sorted by slug.

    A package is available when it is an immediate child of the backlog prompt
    root, has a README, and has at least one prompt directory.
    """

    package_root = root / BACKLOG_ROOT
    if not package_root.is_dir():
        return []

    packages: list[BacklogPackage] = []
    for package_dir in sorted(path for path in package_root.iterdir() if path.is_dir()):
        readme = package_dir / "README.md"
        if not readme.is_file():
            continue
        copy_ready_files = _prompt_files(package_dir, "copy-ready")
        verify_ready_files = _prompt_files(package_dir, "verify-ready")
        if not (copy_ready_files or verify_ready_files):
            continue
        task_stems = {path.stem for path in copy_ready_files + verify_ready_files}
        packages.append(
            BacklogPackage(
                slug=package_dir.name,
                title=_read_title(readme),
                task_count=len(task_stems),
                copy_ready_count=len(copy_ready_files),
                verify_ready_count=len(verify_ready_files),
            )
        )
    return packages


def _format_packages(packages: list[BacklogPackage]) -> str:
    rows = [
        "Backlog prompt packages (sorted by slug)",
        "slug | title | tasks | copy-ready | verify-ready",
        "--- | --- | ---: | ---: | ---:",
    ]
    rows.extend(
        f"{package.slug} | {package.title} | {package.task_count} | {package.copy_ready_count} | {package.verify_ready_count}"
        for package in packages
    )
    return "\n".join(rows)


def _package_dir(root: Path, slug: str) -> Path:
    return root / BACKLOG_ROOT / slug


def _require_package_dir(root: Path, slug: str) -> Path:
    packages = discover_packages(root)
    package_slugs = {package.slug for package in packages}
    if slug not in package_slugs:
        available = ", ".join(package.slug for package in packages) or "none"
        raise ToolError(
            "\n".join(
                [
                    f"unknown backlog package: {slug}",
                    f"expected package under {BACKLOG_ROOT}/ with README.md and prompt files.",
                    f"available packages: {available}",
                ]
            ),
            code=1,
        )
    return _package_dir(root, slug)


def _task_label(copy_ready_path: Path | None, verify_ready_path: Path | None) -> str:
    source = copy_ready_path or verify_ready_path
    return source.stem if source is not None else "task"


def _task_from_paths(number: int, copy_ready_path: Path | None, verify_ready_path: Path | None) -> BacklogTask:
    return BacklogTask(
        number=number,
        label=_task_label(copy_ready_path, verify_ready_path),
        copy_ready_path=copy_ready_path,
        verify_ready_path=verify_ready_path,
    )


def _tasks_from_readme_table(package_dir: Path) -> list[BacklogTask]:
    readme = package_dir / "README.md"
    tasks: list[BacklogTask] = []
    seen_rows: set[tuple[str | None, str | None]] = set()

    for line in readme.read_text(encoding="utf-8").splitlines():
        if not line.lstrip().startswith("|"):
            continue
        prompt_links = PROMPT_LINK_PATTERN.findall(line)
        if not prompt_links:
            continue

        copy_ready_path: Path | None = None
        verify_ready_path: Path | None = None
        copy_ready_key: str | None = None
        verify_ready_key: str | None = None
        for prompt_link in prompt_links:
            if prompt_link.startswith("copy-ready/") and copy_ready_path is None:
                copy_ready_key = prompt_link
                copy_ready_path = package_dir / prompt_link
            if prompt_link.startswith("verify-ready/") and verify_ready_path is None:
                verify_ready_key = prompt_link
                verify_ready_path = package_dir / prompt_link

        row_key = (copy_ready_key, verify_ready_key)
        if row_key in seen_rows:
            continue
        seen_rows.add(row_key)
        tasks.append(_task_from_paths(len(tasks) + 1, copy_ready_path, verify_ready_path))

    return tasks


def _tasks_from_filename_sort(package_dir: Path) -> list[BacklogTask]:
    copy_ready_files = {path.name: path for path in _prompt_files(package_dir, "copy-ready")}
    verify_ready_files = {path.name: path for path in _prompt_files(package_dir, "verify-ready")}
    filenames = sorted(set(copy_ready_files) | set(verify_ready_files))
    return [
        _task_from_paths(
            number=index,
            copy_ready_path=copy_ready_files.get(filename),
            verify_ready_path=verify_ready_files.get(filename),
        )
        for index, filename in enumerate(filenames, start=1)
    ]


def discover_package_tasks(package_dir: Path) -> list[BacklogTask]:
    """Return stable 1-based tasks for one backlog package.

    README prompt table order is the package-level source of truth. Packages
    without a prompt table fall back to sorted prompt filenames.
    """

    readme_tasks = _tasks_from_readme_table(package_dir)
    if readme_tasks:
        return readme_tasks
    return _tasks_from_filename_sort(package_dir)


def _format_task_path(path: Path | None, package_dir: Path) -> str:
    if path is None:
        return "(missing)"
    return str(path.relative_to(package_dir))


def _format_task_index(package_dir: Path, tasks: list[BacklogTask]) -> str:
    rows = [
        "",
        "## Task Index",
        "",
        "Task numbers follow the package README table order. Packages without a README prompt table fall back to sorted prompt filenames.",
        "",
        "Use `./dev backlog show <package> --task N --mode copy|verify` to print a specific prompt.",
        "",
        "N | copy-ready | verify-ready",
        "---: | --- | ---",
    ]
    rows.extend(
        f"{task.number} | `{_format_task_path(task.copy_ready_path, package_dir)}` | `{_format_task_path(task.verify_ready_path, package_dir)}`"
        for task in tasks
    )
    return "\n".join(rows) + "\n"


def run_backlog_list(root: Path) -> int:
    packages = discover_packages(root)
    if not packages:
        raise ToolError(
            "\n".join(
                [
                    f"no backlog prompt packages found under {BACKLOG_ROOT}/.",
                    "expected shape: tasks/backlog/prompts/<package>/{README.md,copy-ready/*.md,verify-ready/*.md}",
                ]
            ),
            code=1,
        )
    print(_format_packages(packages))
    return 0


def run_backlog_show(root: Path, args: Namespace) -> int:
    package_dir = _require_package_dir(root, args.package)
    readme = package_dir / "README.md"
    tasks = discover_package_tasks(package_dir)

    if args.task is None:
        readme_text = readme.read_text(encoding="utf-8")
        sys.stdout.write(readme_text)
        if not readme_text.endswith("\n"):
            sys.stdout.write("\n")
        sys.stdout.write(_format_task_index(package_dir, tasks))
        return 0

    if args.mode not in PROMPT_MODES:
        raise ToolError("./dev backlog show <package> --task N requires --mode copy|verify.", code=2)
    if args.task < 1 or args.task > len(tasks):
        available = f"1-{len(tasks)}" if tasks else "none"
        raise ToolError(f"task {args.task} is out of range for package {args.package}; available task numbers: {available}.", code=1)

    task = tasks[args.task - 1]
    prompt_path = task.copy_ready_path if args.mode == "copy" else task.verify_ready_path
    prompt_dir_name = PROMPT_MODES[args.mode]
    if prompt_path is None or not prompt_path.is_file():
        expected = prompt_path or package_dir / prompt_dir_name / f"{task.label}.md"
        raise ToolError(
            f"missing {prompt_dir_name} prompt for package {args.package} task {args.task}: {_relative_display(expected, root)}",
            code=1,
        )

    sys.stdout.write(prompt_path.read_text(encoding="utf-8"))
    return 0


def run_backlog_command(root: Path, args: Namespace) -> int:
    """Run a read-only backlog browser command."""

    if args.backlog_command == "list":
        return run_backlog_list(root)
    if args.backlog_command == "show" and args.task is not None and args.mode is None:
        raise ToolError("./dev backlog show <package> --task N requires --mode copy|verify.", code=2)
    if args.backlog_command == "show" and args.mode is not None and args.task is None:
        raise ToolError("./dev backlog show <package> --mode copy|verify requires --task N.", code=2)
    if args.backlog_command == "show":
        return run_backlog_show(root, args)
    raise ToolError(f"unsupported backlog command: {_command_name(args)}", code=2)
