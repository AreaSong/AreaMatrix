"""Self-check suite for the Python AreaMatrix task loop."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Callable, Sequence

from scripts.dev_tools.checks import run_skills_check
from scripts.dev_tools.discussion import discussion_artifacts, validate_discussion_artifacts
from scripts.dev_tools.changes import write_artifacts
from scripts.dev_tools.workflow_init import init_artifacts

from . import git as git_helpers
from .actions import ACTIONS, COMMAND_ALIASES, MENUS, SHORTCUT_ALIASES, validate_actions
from .dev_config import config_path, save_lang_mode, saved_lang_mode
from .i18n import load_catalog, validate_catalogs
from .lifecycle import validate_lifecycle_snapshot
from . import state


class CheckFailure(RuntimeError):
    pass


PHASE4_STAGE_CLOSEOUT_LABELS = {"4-1/task-143", "4-2/task-79", "4-3/task-165"}
COPY_READY_FULL_GATE_BOUNDARY = "不得自行升级到 `cargo test --workspace`"
COPY_READY_NO_WORKSPACE_FALLBACK = "不要用 `cargo test --workspace` 兜底"


def log(message: str) -> None:
    print(f"[task-loop-check] {message}")


def root_executable(root: Path, name: str) -> str:
    path = root / name
    return str(path if path.exists() else name)


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def assert_json(path: Path, predicate: Callable[[dict[str, object]], bool], label: str) -> None:
    data = read_json(path)
    if not predicate(data):
        raise CheckFailure(f"json assertion failed: {label} ({path})")


def assert_contains(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise CheckFailure(f"missing text for {label}: {needle}")


def assert_not_contains(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise CheckFailure(f"unexpected text for {label}: {needle}")


def assert_not_exists(path: Path, label: str) -> None:
    if path.exists():
        raise CheckFailure(f"unexpected path exists for {label}: {path}")


def assert_exists(path: Path, label: str) -> None:
    if not path.exists():
        raise CheckFailure(f"missing path for {label}: {path}")


def export_label(path: Path) -> str:
    batch, number = path.stem.rsplit("-task-", 1)
    return f"{batch}/task-{number}"


def exported_validation_block(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    marker = "## 任务要求的验证"
    start = text.find(marker)
    if start < 0:
        return ""
    fence_start = text.find("```bash", start)
    if fence_start < 0:
        return text[start : start + 400]
    fence_end = text.find("```", fence_start + len("```bash"))
    return text[fence_start:fence_end] if fence_end >= 0 else text[fence_start : fence_start + 400]


class Harness:
    def __init__(self, root: Path, tmp: Path) -> None:
        self.root = root
        self.tmp = tmp
        self.python = os.environ.get("PYTHON_BIN", "python3")
        self.task_loop = root_executable(root, "task-loop")
        self.dev = root_executable(root, "dev")

    def run(
        self,
        argv: Sequence[str],
        *,
        env: dict[str, str] | None = None,
        cwd: Path | None = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        merged = os.environ.copy()
        merged.setdefault("DEV_LANG", "mixed")
        merged.setdefault("PYTHONPYCACHEPREFIX", str(self.tmp / "python-pycache"))
        if env:
            merged.update(env)
        proc = subprocess.run(
            list(argv),
            cwd=cwd or self.root,
            env=merged,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if check and proc.returncode != 0:
            raise CheckFailure(
                f"command failed ({proc.returncode}): {list(argv)}\n"
                f"stdout:\n{proc.stdout}\n"
                f"stderr:\n{proc.stderr}"
            )
        return proc

    def temp_env(self, prefix: str, extra: dict[str, str] | None = None) -> dict[str, str]:
        base = self.tmp / prefix
        env = {
            "ROOT_DIR": str(self.root),
            "PROGRESS_FILE": str(base / "progress.json"),
            "LOG_ROOT": str(base / "logs"),
            "RUN_SUMMARY_ROOT": str(base / "runs"),
            "PROGRESS_BACKUP_ROOT": str(base / "backups"),
            "LOCK_DIR": str(base / "lock"),
            "CONTROL_DIR": str(base / "control"),
            "CONSOLE_LOG_ROOT": str(base / "console"),
        }
        if extra:
            env.update(extra)
        return env

    def task_loop_run(
        self,
        prefix: str,
        args: Sequence[str],
        *,
        extra_env: dict[str, str] | None = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return self.run([self.task_loop, *args], env=self.temp_env(prefix, extra_env), check=check)

    def dev_run(
        self,
        prefix: str,
        args: Sequence[str],
        *,
        extra_env: dict[str, str] | None = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        return self.run([self.dev, *args], env=self.temp_env(prefix, extra_env), check=check)


def init_temp_git_repo(repo: Path) -> None:
    repo.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "branch", "-M", "main"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "task-loop-check@example.invalid"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "AreaMatrix Task Loop Check"], cwd=repo, check=True)
    (repo / ".gitignore").write_text(
        ".codex/task-loop-lock/\n.codex/task-loop-tmp/\n.codex/task-loop-control/\n",
        encoding="utf-8",
    )
    (repo / "README.md").write_text("baseline\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "initial"], cwd=repo, check=True)


def add_prompt_fixture(repo: Path, labels: Sequence[str]) -> None:
    for label in labels:
        phase = f"phase-{label.split('-', 1)[0]}"
        task_name = label.replace("/task-", "-task-")
        copy_file = repo / "tasks/prompts/_shared/copy-ready" / phase / f"{task_name}.md"
        verify_file = repo / "tasks/prompts/_shared/verify-ready" / phase / f"{task_name}.md"
        copy_file.parent.mkdir(parents=True, exist_ok=True)
        verify_file.parent.mkdir(parents=True, exist_ok=True)
        copy_file.write_text(f"# copy {label}\n风险等级：`Medium`\n", encoding="utf-8")
        verify_file.write_text(f"# verify {label}\n", encoding="utf-8")


def write_live_lock(lock_dir: Path, run_id: str, operation: str = "run") -> None:
    lock_dir.mkdir(parents=True, exist_ok=True)
    (lock_dir / "pid").write_text(f"{os.getpid()}\n", encoding="utf-8")
    (lock_dir / "run_id").write_text(f"{run_id}\n", encoding="utf-8")
    (lock_dir / "operation").write_text(f"{operation}\n", encoding="utf-8")
    (lock_dir / "started_at").write_text("now\n", encoding="utf-8")


def write_live_activity(lock_dir: Path, tmp: Path) -> None:
    output_file = tmp / "live-activity.log"
    output_file.write_text("running\n", encoding="utf-8")
    state.write_lock_activity(
        lock_dir,
        {
            "status": "running",
            "stage": "copy",
            "task_label": "0-1/task-01",
            "task_name": "0-1-task-01",
            "attempt": 1,
            "pid": os.getpid(),
            "prompt_file": str(tmp / "copy.md"),
            "output_file": str(output_file),
            "command": "codex exec -m gpt-5.5 --full-auto -",
            "started_at": state.utc_now(),
        },
    )


def check_static(h: Harness) -> None:
    log("static checks")
    files = sorted((h.root / "scripts/task_loop").glob("*.py")) + sorted((h.root / "scripts/dev_tools").glob("*.py"))
    h.run([h.python, "-m", "py_compile", *[str(path) for path in files]])
    static_errors = validate_catalogs() + validate_actions() + validate_lifecycle_snapshot(h.root)
    if static_errors:
        raise CheckFailure("static registry/catalog validation failed:\n" + "\n".join(static_errors))
    for action_id in MENUS["home"].action_ids:
        if action_id not in ACTIONS:
            raise CheckFailure(f"home menu action is not registered: {action_id}")
    for menu in MENUS.values():
        for action_id in menu.action_ids:
            if action_id not in ACTIONS:
                raise CheckFailure(f"menu action is not registered: {menu.id}:{action_id}")
    for alias, action_id in {**COMMAND_ALIASES, **SHORTCUT_ALIASES}.items():
        if action_id not in ACTIONS:
            raise CheckFailure(f"action alias is not registered: {alias}->{action_id}")
    for command in ["lifecycle", "live-queue", "tools", "lang", "shortcuts"]:
        if command not in COMMAND_ALIASES:
            raise CheckFailure(f"missing dev console command alias: {command}")
    help_lines = load_catalog("mixed").get("help.lines", [])
    if not isinstance(help_lines, list):
        raise CheckFailure("help.lines catalog entry must be a list")
    for line in help_lines:
        if not isinstance(line, str):
            continue
        parts = line.strip().split()
        if len(parts) < 2 or parts[0] != "./dev" or parts[1].startswith("-"):
            continue
        if parts[1] not in COMMAND_ALIASES:
            raise CheckFailure(f"help command is not registered: {parts[1]}")
    pref_root = h.tmp / "dev-config-root"
    save_lang_mode(pref_root, "zh")
    if saved_lang_mode(pref_root) != "zh":
        raise CheckFailure("dev config did not persist zh language mode")
    assert_exists(config_path(pref_root), "dev console local config")


def check_repo_health(h: Harness) -> None:
    log("repo health")
    if run_skills_check(h.root) != 0:
        raise CheckFailure("skill health failed")
    h.run([h.python, "tasks/prompts/_shared/prompt_pipeline.py", "doctor"])
    check_exported_prompt_validation_strategy(h)


def check_exported_prompt_validation_strategy(h: Harness) -> None:
    log("exported prompt validation strategy")
    for root in [h.root / "tasks/prompts/_shared/copy-ready", h.root / "tasks/prompts/_shared/verify-ready"]:
        phase4_dir = root / "phase-4"
        for path in sorted(phase4_dir.glob("*.md")):
            text = path.read_text(encoding="utf-8")
            if root.name == "copy-ready":
                if COPY_READY_FULL_GATE_BOUNDARY not in text:
                    raise CheckFailure(f"copy-ready prompt lost full-gate boundary: {path.relative_to(h.root)}")
                if COPY_READY_NO_WORKSPACE_FALLBACK not in text:
                    raise CheckFailure(f"copy-ready prompt lost no-workspace-fallback rule: {path.relative_to(h.root)}")
            label = export_label(path)
            validation = exported_validation_block(path)
            if not validation:
                raise CheckFailure(f"missing exported validation block: {path.relative_to(h.root)}")
            if label in PHASE4_STAGE_CLOSEOUT_LABELS:
                if "./dev check all" not in validation:
                    raise CheckFailure(f"phase-4 closeout prompt lost broad validation: {path.relative_to(h.root)}")
                continue
            expected = f"./dev check task {label}"
            if expected not in validation:
                raise CheckFailure(f"phase-4 exported prompt missing task validation {expected}: {path.relative_to(h.root)}")
            if "./dev check all" in validation:
                raise CheckFailure(f"phase-4 exported prompt uses broad validation for atomic task: {path.relative_to(h.root)}")


def check_template_changes(h: Harness) -> None:
    log("template change tracking")
    doctor = h.run([h.dev, "changes", "doctor"]).stdout
    assert_contains(doctor, "v-template change doctor: OK", "changes doctor")
    preview = h.run([h.dev, "changes", "preview"]).stdout
    assert_contains(preview, "v-template change preview", "changes preview header")
    assert_contains(preview, "preview only; no prompt files are generated", "changes preview no writes")
    assert_contains(preview, "template-docs-contract", "changes preview feature")
    generated = h.run([h.dev, "changes", "generate"]).stdout
    assert_contains(generated, "v-template generated prompt drafts", "changes generate header")
    assert_contains(generated, "preview only; no files written", "changes generate no writes")
    assert_contains(generated, "workflow/versions/v-template/drafts/template-docs-contract/manifest.md", "changes generate manifest path")
    assert_contains(generated, "template-docs-contract/docs-baseline", "changes generate semantic task")
    assert_contains(generated, "VERIFY_RESULT: PASS", "changes generate verify prompt")

    feature_only = h.run([h.dev, "changes", "generate", "--feature", "template-docs-contract"]).stdout
    assert_contains(feature_only, "template-docs-contract/docs-baseline", "changes generate feature filter include")
    assert_not_contains(feature_only, "template-execution-contract/queue-candidate", "changes generate feature filter exclude")

    draft_out = h.tmp / "template-drafts"
    first_write = h.run([h.dev, "changes", "generate", "--write", "--out-dir", str(draft_out)]).stdout
    assert_contains(first_write, "v-template change generate: wrote draft files", "changes generate write")
    assert_exists(draft_out / "template-docs-contract/manifest.md", "changes generate manifest write")
    assert_exists(draft_out / "template-docs-contract/docs-baseline.copy.md", "changes generate copy write")
    assert_exists(draft_out / "template-docs-contract/docs-baseline.verify.md", "changes generate verify write")

    second_write = h.run([h.dev, "changes", "generate", "--write", "--out-dir", str(draft_out)], check=False)
    if second_write.returncode == 0:
        raise CheckFailure("template draft overwrite unexpectedly succeeded without --force")
    assert_contains(second_write.stdout + second_write.stderr, "use --force to overwrite", "changes generate overwrite guard")

    force_write = h.run([h.dev, "changes", "generate", "--write", "--force", "--out-dir", str(draft_out)]).stdout
    assert_contains(force_write, "v-template change generate: wrote draft files", "changes generate force write")

    bad_force = h.run([h.dev, "changes", "generate", "--force"], check=False)
    if bad_force.returncode == 0:
        raise CheckFailure("template draft generate unexpectedly accepted --force without --write")
    assert_contains(bad_force.stdout + bad_force.stderr, "--force requires --write", "changes generate force guard")


def check_versioned_workflow(h: Harness) -> None:
    log("versioned workflow tracking")
    doctor = h.run([h.dev, "workflow", "doctor"]).stdout
    assert_contains(doctor, "workflow doctor: OK", "workflow doctor")
    assert_contains(doctor, "discussion v-template: template-reference", "workflow template discussion")
    assert_contains(doctor, "local queue v-template: template-reference", "workflow template local queue")
    assert_contains(doctor, "live mapping v-template: configured (phase-5/5-1)", "workflow template live mapping")
    assert_contains(doctor, "middle-layer v-template: required", "workflow template middle layer")

    status = h.run([h.dev, "workflow", "status"]).stdout
    assert_contains(status, "v1-mvp: live-running", "workflow status v1")
    assert_contains(status, "v-template: template-reference", "workflow status template")
    assert_contains(status, "discussion: v-template: managed template reference", "workflow status discussion")
    assert_contains(status, "local_queue: template-reference", "workflow status local queue")
    assert_contains(status, "live_mapping: configured (phase-5/5-1)", "workflow status live mapping")
    assert_contains(status, "projection: blocked as expected for template reference", "workflow status template projection note")
    assert_contains(status, "closeout: blocked as expected for template reference", "workflow status template closeout note")
    assert_contains(status, "must not promote to tasks/prompts/**", "workflow promote gate")

    template_check = h.run([h.dev, "workflow", "check-template"]).stdout
    assert_contains(template_check, "workflow check-template: OK", "workflow check-template")
    assert_contains(template_check, "[check-template] promotion apply preview: OK", "workflow check-template promotion preview")

    init_preview = h.run([h.dev, "workflow", "init", "--version", "v3"]).stdout
    assert_contains(init_preview, "Workflow version init", "workflow init preview")
    assert_contains(init_preview, "mode: preview only; no files written", "workflow init no write")
    assert_contains(init_preview, "workflow/versions/v3/version.yaml", "workflow init version path")
    assert_contains(init_preview, "local_queue:", "workflow init local queue")
    assert_contains(init_preview, "live_mapping: pending", "workflow init live mapping pending")
    bad_name = h.run([h.dev, "workflow", "init", "--version", "bad-name"], check=False)
    if bad_name.returncode == 0:
        raise CheckFailure("workflow init unexpectedly accepted bad version name")
    assert_contains(bad_name.stdout + bad_name.stderr, "version must look like v2", "workflow init version guard")
    bad_v1 = h.run([h.dev, "workflow", "init", "--version", "v1-mvp"], check=False)
    if bad_v1.returncode == 0:
        raise CheckFailure("workflow init unexpectedly accepted v1-mvp")
    assert_contains(bad_v1.stdout + bad_v1.stderr, "cannot create v1-mvp", "workflow init v1 guard")

    version_out = h.tmp / "v3-version"
    init_write = h.run([h.dev, "workflow", "init", "--version", "v3", "--write", "--out-dir", str(version_out)]).stdout
    assert_contains(init_write, "workflow init: wrote files", "workflow init write")
    assert_exists(version_out / "version.yaml", "workflow init version yaml")
    assert_exists(version_out / "discussion/docs-discussion.md", "workflow init docs discussion")
    assert_exists(version_out / "discussion/middle-layer-discussion.md", "workflow init middle discussion")
    assert_exists(version_out / "discussion/decisions.yaml", "workflow init decisions")
    for layer in ["changes", "plans", "drafts", "queue", "promotion"]:
        assert_exists(version_out / layer / "README.md", f"workflow init {layer} README")
    second_init_write = h.run([h.dev, "workflow", "init", "--version", "v3", "--write", "--out-dir", str(version_out)], check=False)
    if second_init_write.returncode == 0:
        raise CheckFailure("workflow init overwrite unexpectedly succeeded without --force")
    assert_contains(second_init_write.stdout + second_init_write.stderr, "use --force to overwrite", "workflow init overwrite guard")
    h.run([h.dev, "workflow", "init", "--version", "v3", "--write", "--force", "--out-dir", str(version_out)])
    bad_init_force = h.run([h.dev, "workflow", "init", "--version", "v3", "--force"], check=False)
    if bad_init_force.returncode == 0:
        raise CheckFailure("workflow init unexpectedly accepted --force without --write")
    assert_contains(bad_init_force.stdout + bad_init_force.stderr, "--force requires --write", "workflow init force guard")

    init_discussion_errors = validate_discussion_artifacts(h.root, "v3", version_out / "discussion")
    if not any("allow_changes must be true" in error for error in init_discussion_errors):
        raise CheckFailure(f"workflow init did not create blocked discussion gate: {init_discussion_errors}")
    approved_version = h.tmp / "approved-v3-version"
    write_artifacts(init_artifacts(h.root, "v3", None, str(approved_version)), force=False, label="test workflow init file")
    (approved_version / "discussion/decisions.yaml").write_text(
        """version: v3
status: ready
allow_changes: true
exact_docs:
  - docs/README.md
decisions:
  - id: docs-scope
    status: accepted
    summary: Use docs README as a placeholder source for the test version.
open_questions: []
blockers: []
risk_boundaries:
  - Do not write live tasks/prompts from discussion.
next_layers:
  changes: allowed
  plans: blocked
  drafts: blocked
  queue: blocked
  promotion: blocked
""",
        encoding="utf-8",
    )
    approved_version_errors = validate_discussion_artifacts(h.root, "v3", approved_version / "discussion")
    if approved_version_errors:
        raise CheckFailure(f"workflow init approved discussion failed: {approved_version_errors}")

    bad_template_init = h.run([h.dev, "workflow", "init", "--version", "v-template"], check=False)
    if bad_template_init.returncode == 0:
        raise CheckFailure("workflow init unexpectedly accepted v-template")
    assert_contains(bad_template_init.stdout + bad_template_init.stderr, "cannot recreate v-template", "workflow init template guard")

    discuss_doctor = h.run([h.dev, "workflow", "discuss", "--version", "v-template", "doctor"]).stdout
    assert_contains(discuss_doctor, "workflow discuss doctor: OK", "workflow discuss template doctor")
    assert_contains(discuss_doctor, "managed template reference", "workflow discuss template reference")
    discuss_preview = h.run([h.dev, "workflow", "discuss", "--version", "v-template", "preview"]).stdout
    assert_contains(discuss_preview, "Workflow discussion preview", "workflow discuss preview")
    assert_contains(discuss_preview, "template-reference", "workflow discuss preview template")

    discussion_out = h.tmp / "workflow-discussion"
    discussion_init = h.run(
        [h.dev, "workflow", "discuss", "--version", "v3", "init", "--write", "--out-dir", str(discussion_out)]
    ).stdout
    assert_contains(discussion_init, "workflow discuss init: wrote files", "workflow discuss init write")
    assert_exists(discussion_out / "docs-discussion.md", "workflow discussion docs file")
    assert_exists(discussion_out / "middle-layer-discussion.md", "workflow discussion middle file")
    assert_exists(discussion_out / "decisions.yaml", "workflow discussion decisions file")
    second_discussion_init = h.run(
        [h.dev, "workflow", "discuss", "--version", "v3", "init", "--write", "--out-dir", str(discussion_out)],
        check=False,
    )
    if second_discussion_init.returncode == 0:
        raise CheckFailure("workflow discussion overwrite unexpectedly succeeded without --force")
    assert_contains(
        second_discussion_init.stdout + second_discussion_init.stderr,
        "use --force to overwrite",
        "workflow discussion overwrite guard",
    )
    h.run([h.dev, "workflow", "discuss", "--version", "v3", "init", "--write", "--force", "--out-dir", str(discussion_out)])
    bad_discussion_force = h.run([h.dev, "workflow", "discuss", "--version", "v3", "init", "--force"], check=False)
    if bad_discussion_force.returncode == 0:
        raise CheckFailure("workflow discussion init unexpectedly accepted --force without --write")
    assert_contains(bad_discussion_force.stdout + bad_discussion_force.stderr, "--force requires --write", "workflow discussion force guard")

    blocked_discussion = h.tmp / "blocked-discussion"
    write_artifacts(discussion_artifacts(h.root, "v3", str(blocked_discussion)), force=False, label="test discussion file")
    blocked_errors = validate_discussion_artifacts(h.root, "v3", blocked_discussion)
    if not any("allow_changes must be true" in error for error in blocked_errors):
        raise CheckFailure(f"workflow discussion did not reject unapproved decisions: {blocked_errors}")
    if not any("unresolved blocker" in error for error in blocked_errors):
        raise CheckFailure(f"workflow discussion did not reject unresolved blockers: {blocked_errors}")
    approved_discussion = h.tmp / "approved-discussion"
    write_artifacts(discussion_artifacts(h.root, "v3", str(approved_discussion)), force=False, label="test discussion file")
    (approved_discussion / "decisions.yaml").write_text(
        """version: v3
status: ready
allow_changes: true
exact_docs:
  - docs/README.md
decisions:
  - id: docs-scope
    status: accepted
    summary: Use docs README as a placeholder source for the test discussion.
open_questions: []
blockers: []
risk_boundaries:
  - Do not write live tasks/prompts from discussion.
next_layers:
  changes: allowed
  plans: blocked
  drafts: blocked
  queue: blocked
  promotion: blocked
""",
        encoding="utf-8",
    )
    approved_errors = validate_discussion_artifacts(h.root, "v3", approved_discussion)
    if approved_errors:
        raise CheckFailure(f"workflow discussion approved fixture failed: {approved_errors}")
    (approved_discussion / "decisions.yaml").write_text(
        """version: v3
status: ready
allow_changes: true
exact_docs:
  - docs/missing-discussion-source.md
decisions:
  - id: docs-scope
    status: accepted
    summary: Bad doc path test.
open_questions: []
blockers: []
risk_boundaries:
  - Do not write live tasks/prompts from discussion.
next_layers:
  changes: allowed
""",
        encoding="utf-8",
    )
    missing_doc_errors = validate_discussion_artifacts(h.root, "v3", approved_discussion)
    if not any("Exact Docs path does not exist" in error for error in missing_doc_errors):
        raise CheckFailure(f"workflow discussion did not reject missing Exact Docs: {missing_doc_errors}")

    plan = h.run([h.dev, "workflow", "plan", "--version", "v-template", "--feature", "template-docs-contract"]).stdout
    assert_contains(plan, "Workflow plans", "workflow plan header")
    assert_contains(plan, "Docs Change Ledger", "workflow plan ledger")
    assert_contains(plan, "17-30", "workflow plan line range")
    assert_contains(plan, "Code Impact", "workflow plan code impact")
    assert_contains(plan, "blocked while `v1-mvp` is `live-running`", "workflow plan v1 block")

    queue = h.run([h.dev, "workflow", "queue", "--version", "v-template", "--feature", "template-docs-contract"]).stdout
    assert_contains(queue, "Workflow queue candidates", "workflow queue header")
    assert_contains(queue, "depends_on: []", "workflow queue empty deps")
    assert_contains(queue, "live_queue_blocked: true", "workflow queue live block")

    promote = h.run([h.dev, "workflow", "promote", "--version", "v-template", "--preview"]).stdout
    assert_contains(promote, "Workflow promotion preview", "workflow promote header")
    assert_contains(promote, "promotion blocked: v-template is a template reference", "workflow promote template block")
    assert_contains(promote, "target_kind: preview-only", "workflow promote target kind")
    assert_contains(promote, "writes_live_queue: false", "workflow promote writes live false")
    assert_contains(promote, "template_reference: true", "workflow promote template reference")
    assert_contains(promote, "apply_allowed: false", "workflow promote apply false")
    assert_contains(promote, "Future live paths below are previews only", "workflow promote future path warning")
    assert_contains(promote, "template-docs-contract/docs-baseline", "workflow promote semantic task")
    assert_contains(promote, "5-1/task-01", "workflow promote live label")
    assert_contains(promote, "tasks/prompts/phase-5/5-1-template-reference/task-01-docs-baseline.md", "workflow promote task path")
    assert_contains(promote, "tasks/prompts/_shared/manifests/phase-5.md", "workflow promote manifest path")
    assert_contains(promote, "tasks/prompts/_shared/copy-ready/phase-5/5-1-task-01.md", "workflow promote copy-ready path")
    assert_contains(promote, "Live queue: not modified", "workflow promote no live writes")

    promote_feature = h.run([h.dev, "workflow", "promote", "--version", "v-template", "--feature", "template-docs-contract", "--preview"]).stdout
    assert_contains(promote_feature, "template-docs-contract/docs-baseline", "workflow promote feature include")
    assert_not_contains(promote_feature, "template-execution-contract/queue-candidate", "workflow promote feature exclude")

    baseline_default = h.run([h.dev, "workflow", "baseline", "doctor"]).stdout
    assert_contains(baseline_default, "workflow baseline doctor: OK", "workflow baseline default doctor")
    assert_contains(baseline_default, "version: v-template", "workflow baseline default version")
    project_default = h.run([h.dev, "workflow", "project", "doctor"]).stdout
    assert_contains(project_default, "workflow project doctor: OK", "workflow project default doctor")
    assert_contains(project_default, "blocked as expected for template reference", "workflow project template note")
    closeout_default = h.run([h.dev, "workflow", "closeout", "doctor"]).stdout
    assert_contains(closeout_default, "workflow closeout doctor: OK", "workflow closeout default doctor")
    assert_contains(closeout_default, "blocked as expected for template reference", "workflow closeout template note")

    apply_preview = h.run([h.dev, "workflow", "promote", "--version", "v-template", "apply", "--preview"]).stdout
    assert_contains(apply_preview, "Workflow promotion apply preview", "workflow apply preview header")
    assert_contains(apply_preview, "target_kind: apply-preview", "workflow apply preview target kind")
    assert_contains(apply_preview, "writes_live_queue: false", "workflow apply preview no writes")
    assert_contains(apply_preview, "template_reference: true", "workflow apply preview template")
    assert_contains(apply_preview, "apply_allowed: false", "workflow apply preview blocked")
    apply_write = h.run([h.dev, "workflow", "promote", "--version", "v-template", "apply", "--write"], check=False)
    if apply_write.returncode == 0:
        raise CheckFailure("workflow promote apply --write unexpectedly accepted v-template")
    assert_contains(apply_write.stdout + apply_write.stderr, "template reference and cannot apply", "workflow apply write template guard")

    plan_out = h.tmp / "workflow-plans"
    first_plan_write = h.run([h.dev, "workflow", "plan", "--version", "v-template", "--write", "--out-dir", str(plan_out)]).stdout
    assert_contains(first_plan_write, "workflow plan: wrote files", "workflow plan write")
    assert_exists(plan_out / "template-docs-contract.plan.md", "workflow plan file")
    second_plan_write = h.run([h.dev, "workflow", "plan", "--version", "v-template", "--write", "--out-dir", str(plan_out)], check=False)
    if second_plan_write.returncode == 0:
        raise CheckFailure("workflow plan overwrite unexpectedly succeeded without --force")
    assert_contains(second_plan_write.stdout + second_plan_write.stderr, "use --force to overwrite", "workflow plan overwrite guard")
    h.run([h.dev, "workflow", "plan", "--version", "v-template", "--write", "--force", "--out-dir", str(plan_out)])
    bad_plan_force = h.run([h.dev, "workflow", "plan", "--version", "v-template", "--force"], check=False)
    if bad_plan_force.returncode == 0:
        raise CheckFailure("workflow plan unexpectedly accepted --force without --write")
    assert_contains(bad_plan_force.stdout + bad_plan_force.stderr, "--force requires --write", "workflow plan force guard")

    queue_out = h.tmp / "workflow-queue"
    first_queue_write = h.run([h.dev, "workflow", "queue", "--version", "v-template", "--write", "--out-dir", str(queue_out)]).stdout
    assert_contains(first_queue_write, "workflow queue: wrote files", "workflow queue write")
    assert_exists(queue_out / "template-docs-contract/queue.yaml", "workflow queue yaml")
    assert_exists(queue_out / "template-docs-contract/queue.md", "workflow queue markdown")
    second_queue_write = h.run([h.dev, "workflow", "queue", "--version", "v-template", "--write", "--out-dir", str(queue_out)], check=False)
    if second_queue_write.returncode == 0:
        raise CheckFailure("workflow queue overwrite unexpectedly succeeded without --force")
    assert_contains(second_queue_write.stdout + second_queue_write.stderr, "use --force to overwrite", "workflow queue overwrite guard")
    h.run([h.dev, "workflow", "queue", "--version", "v-template", "--write", "--force", "--out-dir", str(queue_out)])
    bad_queue_force = h.run([h.dev, "workflow", "queue", "--version", "v-template", "--force"], check=False)
    if bad_queue_force.returncode == 0:
        raise CheckFailure("workflow queue unexpectedly accepted --force without --write")
    assert_contains(bad_queue_force.stdout + bad_queue_force.stderr, "--force requires --write", "workflow queue force guard")

    promotion_out = h.tmp / "workflow-promotion"
    first_promotion_write = h.run([h.dev, "workflow", "promote", "--version", "v-template", "--write", "--out-dir", str(promotion_out)]).stdout
    assert_contains(first_promotion_write, "workflow promote: wrote preview files", "workflow promote write")
    assert_contains(first_promotion_write, "promotion blocked: v-template is a template reference", "workflow promote write gate")
    assert_exists(promotion_out / "promotion.yaml", "workflow promotion yaml")
    assert_exists(promotion_out / "promotion.md", "workflow promotion markdown")
    second_promotion_write = h.run([h.dev, "workflow", "promote", "--version", "v-template", "--write", "--out-dir", str(promotion_out)], check=False)
    if second_promotion_write.returncode == 0:
        raise CheckFailure("workflow promotion overwrite unexpectedly succeeded without --force")
    assert_contains(second_promotion_write.stdout + second_promotion_write.stderr, "use --force to overwrite", "workflow promotion overwrite guard")
    h.run([h.dev, "workflow", "promote", "--version", "v-template", "--write", "--force", "--out-dir", str(promotion_out)])
    bad_promotion_force = h.run([h.dev, "workflow", "promote", "--version", "v-template", "--force"], check=False)
    if bad_promotion_force.returncode == 0:
        raise CheckFailure("workflow promote unexpectedly accepted --force without --write")
    assert_contains(bad_promotion_force.stdout + bad_promotion_force.stderr, "--force requires --write", "workflow promote force guard")


def check_real_status(h: Harness) -> None:
    log("real status is readable")
    status = h.run([h.task_loop, "status"]).stdout
    assert_contains(status, "stale_in_progress:", "task-loop status stale count")
    assert_contains(status, "drain_requested:", "task-loop status drain")
    dev_status = h.run([h.dev, "--lang", "mixed", "status"]).stdout
    assert_contains(dev_status, "AreaMatrix Dev Console", "dev status dashboard header")
    assert_contains(dev_status, "当前局势", "dev status situation")
    assert_contains(dev_status, "推荐行动链", "dev status recommendation chain")
    assert_contains(dev_status, "进度概览", "dev status progress overview")
    assert_contains(dev_status, "lang mixed", "dev status language mode")
    assert_contains(dev_status, "v1-mvp live queue", "dev status v1 overview")
    dev_status_zh = h.run([h.dev, "status", "--lang", "zh", "--once", "--color", "never"]).stdout
    assert_contains(dev_status_zh, "语言 zh | 快照", "dev status zh header")
    status_help_en = h.run([h.dev, "status", "--lang", "en", "--help"]).stdout
    assert_contains(status_help_en, "Usage: ./dev status", "dev status en help usage")
    assert_contains(status_help_en, "Language mode; overrides DEV_LANG", "dev status en help lang")
    status_help_zh = h.run([h.dev, "status", "--lang", "zh", "--help"]).stdout
    assert_contains(status_help_zh, "用法: ./dev status", "dev status zh help usage")
    assert_contains(status_help_zh, "显示语言；覆盖 DEV_LANG", "dev status zh help lang")
    dev_verbose = h.run([h.dev, "--lang", "mixed", "status", "--verbose"]).stdout
    assert_contains(dev_verbose, "AreaMatrix Dev Console", "dev verbose status header")
    assert_contains(dev_verbose, "进程快照", "dev verbose process snapshot")
    preflight = h.dev_run("dev-preflight", ["preflight"]).stdout
    assert_contains(preflight, "Preflight", "dev preflight header")

    status_root = h.tmp / "status-live-activity"
    write_live_lock(status_root / "lock", "status-live-activity")
    write_live_activity(status_root / "lock", status_root)
    write_json(status_root / "progress.json", {"version": 1, "tasks": {}})
    live_status = h.task_loop_run("status-live-activity", ["status"]).stdout
    assert_contains(live_status, "live_activity: copy task=0-1/task-01 attempt=1 status=running", "live activity headline")
    assert_contains(live_status, "live_activity_elapsed:", "live activity elapsed")
    assert_contains(live_status, "live_activity_pid:", "live activity pid")
    assert_contains(live_status, "live_activity_log_state: exists", "live activity log state")
    assert_contains(live_status, "live_activity_command: codex exec -m gpt-5.5 --full-auto -", "live activity command")


def check_dev_home(h: Harness) -> None:
    log("dev home dashboard and color controls")
    home = h.run([h.dev, "--lang", "mixed", "--once"], env={"DEV_COLOR": "always", "NO_COLOR": ""}).stdout
    assert_contains(home, "\033[", "dev home default color")
    assert_contains(home, "AreaMatrix Dev Console", "dev home dashboard header")
    assert_contains(home, "当前局势", "dev home situation")
    assert_contains(home, "current task:", "dev home current task")
    assert_contains(home, "原因：", "dev home reasons")
    assert_contains(home, "推荐行动链", "dev home action chain")
    assert_contains(home, "verify PASS 后", "dev home guide after")
    assert_contains(home, "进度概览", "dev home progress overview")
    assert_contains(home, "v1-mvp live queue", "dev home v1 card")
    assert_contains(home, "v-template reference", "dev home template card")
    assert_contains(home, "去哪里看更多", "dev home navigation")
    assert_contains(home, "recommended guide", "dev home recommended guide")
    assert_contains(home, "lifecycle map", "dev home lifecycle map")
    assert_contains(home, "live queue details", "dev home live queue details")
    assert_contains(home, "shortcuts", "dev home shortcuts action")
    assert_contains(home, "当前语言: mixed", "dev home language mode")
    assert_contains(home, "输入 lang 持久切换", "dev home language switch hint")
    assert_contains(home, "输入 ? 查看全部快捷键", "dev home shortcut help hint")
    assert_contains(home, "Enter 只显示完整状态，不启动任务", "dev home enter is status only")
    assert_not_contains(home, "任务快捷操作", "dev home should not show full shortcut list")
    assert_not_contains(home, "clear-stale", "dev home hides dangerous clear-stale")
    assert_not_contains(home, "reset-progress", "dev home hides dangerous reset-progress")
    assert_not_contains(home, "/Applications/Codex.app/Contents/Resources/codex exec", "dev home folded process command")

    no_color = h.run([h.dev, "--color", "never", "--once"]).stdout
    assert_not_contains(no_color, "\033[", "dev home color never")
    assert_contains(no_color, "去哪里看更多", "dev home no-color navigation")

    zh_home = h.run([h.dev, "--lang", "zh", "--once", "--color", "never"]).stdout
    assert_contains(zh_home, "语言 zh | 快照", "dev home zh header")
    assert_contains(zh_home, "当前局势", "dev home zh situation")
    assert_contains(zh_home, "推荐行动链", "dev home zh guide")
    assert_contains(zh_home, "进度概览", "dev home zh progress")
    assert_contains(zh_home, "快捷键", "dev home zh shortcut action")
    assert_not_contains(zh_home, "Primary Actions", "dev home zh no english title")

    en_home = h.run([h.dev, "--lang", "en", "--once", "--color", "never"]).stdout
    assert_contains(en_home, "lang en", "dev home en language mode")
    assert_contains(en_home, "Current Situation", "dev home en situation")
    assert_contains(en_home, "Recommended Action Chain", "dev home en guide")
    assert_contains(en_home, "Progress Overview", "dev home en progress")
    assert_contains(en_home, "Where To See More", "dev home en navigation")
    assert_contains(en_home, "type lang to persist", "dev home en language switch hint")
    assert_contains(en_home, "Enter shows full status only", "dev home en enter is status only")
    assert_not_contains(en_home, "主要入口", "dev home en no chinese title")

    en_help = h.run([h.dev, "--lang", "en", "help"]).stdout
    assert_contains(en_help, "Quick Model:", "dev help en title")
    assert_contains(en_help, "Live queue:", "dev help en live queue")
    zh_help = h.run([h.dev, "--lang", "zh", "help"]).stdout
    assert_contains(zh_help, "常用理解：", "dev help zh title")
    assert_contains(zh_help, "Live queue：", "dev help zh live queue")
    assert_contains(zh_help, "./dev lifecycle", "dev help lifecycle command")

    env_color_never = h.run([h.dev, "--once"], env={"DEV_COLOR": "never"}).stdout
    assert_not_contains(env_color_never, "\033[", "dev home DEV_COLOR never")

    env_no_color = h.run([h.dev, "--once"], env={"NO_COLOR": "1"}).stdout
    assert_not_contains(env_no_color, "\033[", "dev home NO_COLOR")

    status_color = h.run([h.dev, "status", "--once", "--color", "always"], env={"NO_COLOR": ""}).stdout
    assert_contains(status_color, "\033[", "dev status color always")

    processes = h.run([h.dev, "processes"]).stdout
    assert_contains(processes, "进程快照", "dev processes header")
    assert_contains(processes, "host codex exec", "dev processes full section")
    lifecycle = h.run([h.dev, "--lang", "mixed", "lifecycle"]).stdout
    assert_contains(lifecycle, "Lifecycle Wizard", "dev lifecycle command")
    assert_contains(lifecycle, "v1-mvp live-running", "dev lifecycle v1")
    assert_contains(lifecycle, "v-template template-reference", "dev lifecycle template")
    live_queue = h.run([h.dev, "--lang", "mixed", "live-queue"]).stdout
    assert_contains(live_queue, "Live Queue", "dev live queue command")
    assert_contains(live_queue, "maintenance / danger", "dev live queue maintenance")
    tools = h.run([h.dev, "--lang", "mixed", "tools"]).stdout
    assert_contains(tools, "workflow / 工程检查", "dev tools command")
    lang = h.run([h.dev, "--lang", "mixed", "lang"]).stdout
    assert_contains(lang, "本地偏好文件", "dev lang config path")
    shortcuts = h.run([h.dev, "--lang", "mixed", "shortcuts"]).stdout
    assert_contains(shortcuts, "1", "dev shortcuts command")
    assert_contains(shortcuts, "recommended guide", "dev shortcuts recommended")


def check_dev_console(h: Harness) -> None:
    log("dev recovery hints use stable action names")
    prefix = h.tmp / "dev-hints"
    write_live_lock(prefix / "lock", "dev-hints-run")
    write_json(
        prefix / "progress.json",
        {
            "version": 1,
            "tasks": {
                "0-1/task-01": {
                    "attempts": 1,
                    "copy_log": "/tmp/missing-copy.log",
                    "note": "fake stale",
                    "run_id": "missing-run",
                    "status": "in_progress",
                    "verify_log": "/tmp/missing-verify.log",
                },
                "0-1/task-02": {"note": "fake failed", "status": "failed"},
                "0-2/task-01": {"note": "fake blocked", "status": "blocked"},
            },
        },
    )
    hints = h.dev_run("dev-hints", ["--lang", "mixed", "status"]).stdout
    assert_contains(hints, "AreaMatrix Dev Console", "dev hints dashboard")
    assert_contains(hints, "推荐行动链", "dev hints recommendation")
    assert_contains(hints, "./dev drain", "dev live drain command")
    assert_contains(hints, "进度概览", "dev hints progress context")

    verbose_hints = h.dev_run("dev-hints", ["--lang", "mixed", "status", "--verbose"]).stdout
    assert_contains(verbose_hints, "从 stale 任务继续", "dev stale action")
    assert_contains(verbose_hints, "./dev resume-stale", "dev stale command")
    assert_contains(verbose_hints, "从 failed 任务继续", "dev failed action")
    assert_contains(verbose_hints, "./dev resume-failed", "dev failed command")
    assert_contains(verbose_hints, "一键优雅收尾", "dev drain action")

    log("dev console preview does not execute")
    preview = h.dev_run(
        "dev-preview",
        ["preview"],
        extra_env={"DEV_SH_EXECUTION_MODE": "foreground", "DEV_SH_GIT_CHECKPOINT": "off", "DEV_SH_MAX_TASKS": "1"},
    ).stdout
    assert_contains(preview, "未执行。", "dev preview no execution")
    assert_contains(preview, "--max-tasks 1", "dev preview max tasks")
    assert_not_exists(h.tmp / "dev-preview/progress.json", "dev preview progress")

    log("dev console temp dry-run avoids real progress")
    temp_dry = h.dev_run("dev-temp-dry-run", ["dry-run"], extra_env={"DEV_SH_MAX_TASKS": "1"}).stdout
    assert_contains(temp_dry, "临时 dry-run 完成，真实 progress/logs 未修改。", "dev temp dry-run")
    assert_not_exists(h.tmp / "dev-temp-dry-run/progress.json", "dev temp dry-run configured progress")

    log("dev console dry-run foreground command choices")
    h.dev_run(
        "dev-foreground",
        ["start"],
        extra_env={
            "DEV_SH_EXECUTION_MODE": "foreground",
            "DEV_SH_GIT_CHECKPOINT": "off",
            "DEV_SH_MAX_TASKS": "1",
            "DEV_SH_DRY_RUN": "1",
            "DEV_SH_DRY_RUN_RESULT": "PASS",
        },
    )
    assert_json(
        h.tmp / "dev-foreground/progress.json",
        lambda data: data["tasks"]["0-1/task-01"]["status"] == "completed",  # type: ignore[index]
        "dev foreground completed",
    )

    log("dev console dry-run background command choices")
    background = h.dev_run(
        "dev-background",
        ["start"],
        extra_env={
            "DEV_SH_EXECUTION_MODE": "background",
            "DEV_SH_GIT_CHECKPOINT": "off",
            "DEV_SH_MAX_TASKS": "1",
            "DEV_SH_DRY_RUN": "1",
            "DEV_SH_DRY_RUN_RESULT": "PASS",
            "DEV_SH_STOP_AFTER": "0-1/task-01",
        },
    ).stdout
    assert_contains(background, "已后台启动：pid=", "dev background start")
    assert_contains(background, "--stop-after 0-1/task-01", "dev background stop target")
    progress = h.tmp / "dev-background/progress.json"
    for _ in range(50):
        if progress.exists():
            data = read_json(progress)
            entry = data.get("tasks", {}).get("0-1/task-01", {})  # type: ignore[union-attr]
            if isinstance(entry, dict) and entry.get("status") == "completed":
                break
        time.sleep(0.1)
    assert_json(progress, lambda data: data["tasks"]["0-1/task-01"]["status"] == "completed", "dev background completed")  # type: ignore[index]
    if not list((h.tmp / "dev-background/console").glob("*.log")):
        raise CheckFailure("dev background console log missing")

    log("dev console blocks duplicate live runner")
    write_live_lock(h.tmp / "dev-live/lock", "live-run")
    live = h.dev_run(
        "dev-live",
        ["start"],
        extra_env={
            "DEV_SH_EXECUTION_MODE": "foreground",
            "DEV_SH_GIT_CHECKPOINT": "off",
            "DEV_SH_MAX_TASKS": "1",
            "DEV_SH_DRY_RUN": "1",
        },
        check=False,
    )
    if live.returncode == 0:
        raise CheckFailure("dev console unexpectedly allowed duplicate live runner")
    assert_contains(live.stdout + live.stderr, "已有 live runner，已阻止启动第二个 runner", "dev live guard")


def check_runner_core(h: Harness) -> None:
    log("drain request requires a live runner")
    no_drain = h.task_loop_run("drain-no-runner", ["drain"], check=False)
    if no_drain.returncode == 0:
        raise CheckFailure("drain request unexpectedly succeeded without a live runner")
    assert_contains(no_drain.stdout + no_drain.stderr, "no live task loop lock found", "drain no live runner")

    log("dry-run PASS writes temp progress, logs, summary, and index")
    h.task_loop_run("pass", ["run", "--dry-run", "--phase", "phase-0", "--max-tasks", "1"], extra_env={"DRY_RUN_RESULT": "PASS", "MAX_RETRIES": "1"})
    assert_json(h.tmp / "pass/progress.json", lambda data: data["tasks"]["0-1/task-01"]["status"] == "completed", "pass progress")  # type: ignore[index]
    summary = next((h.tmp / "pass/runs").rglob("summary.json"))
    assert_json(summary, lambda data: data["status"] == "completed" and data["totals"]["completed_in_run"] == 1, "pass summary")  # type: ignore[index]
    assert_json(h.tmp / "pass/runs/index.json", lambda data: data["runs"][0]["status"] == "completed", "pass index")  # type: ignore[index]
    assert_not_exists(h.tmp / "pass/lock", "pass lock release")

    log("runner validates explicit start and stop targets before execution")
    start_guard = h.task_loop_run("start-target-guard", ["run", "--dry-run", "--phase", "phase-0", "--start-from", "2-1/task-19", "--max-tasks", "1"], check=False)
    if start_guard.returncode == 0:
        raise CheckFailure("start target outside selected phase unexpectedly succeeded")
    assert_contains(start_guard.stdout + start_guard.stderr, "START_FROM label is not runnable in selected phases", "start guard")
    assert_not_exists(h.tmp / "start-target-guard/progress.json", "start guard progress")
    stop_guard = h.task_loop_run("stop-target-guard", ["run", "--dry-run", "--phase", "phase-0", "--stop-after", "9-9/task-99", "--max-tasks", "1"], check=False)
    if stop_guard.returncode == 0:
        raise CheckFailure("missing stop target unexpectedly succeeded")
    assert_contains(stop_guard.stdout + stop_guard.stderr, "STOP_AFTER label is not runnable in selected phases", "stop guard")
    assert_not_exists(h.tmp / "stop-target-guard/progress.json", "stop guard progress")

    log("drain request stops after current task")
    drain_repo = h.tmp / "drain-repo"
    add_prompt_fixture(drain_repo, ["0-1/task-01", "0-1/task-02"])
    drain_env = {
        "ROOT_DIR": str(drain_repo),
        "PROGRESS_FILE": str(h.tmp / "drain/progress.json"),
        "LOG_ROOT": str(h.tmp / "drain/logs"),
        "RUN_SUMMARY_ROOT": str(h.tmp / "drain/runs"),
        "PROGRESS_BACKUP_ROOT": str(h.tmp / "drain/backups"),
        "LOCK_DIR": str(h.tmp / "drain/lock"),
        "CONTROL_DIR": str(h.tmp / "drain/control"),
    }
    write_live_lock(h.tmp / "drain/lock", "drain-run")
    request = h.run([h.task_loop, "drain"], env={**drain_env, "RUN_ID": "drain-request"})
    assert_contains(request.stdout, "request drain for live runner", "drain request")
    shutil.rmtree(h.tmp / "drain/lock")
    run = h.run(
        [h.task_loop, "run", "--dry-run", "--phase", "phase-0"],
        env={**drain_env, "RUN_ID": "drain-run", "DRY_RUN_RESULT": "PASS", "MAX_RETRIES": "1"},
    )
    assert_json(
        h.tmp / "drain/progress.json",
        lambda data: data["tasks"]["0-1/task-01"]["status"] == "completed" and "0-1/task-02" not in data["tasks"],  # type: ignore[index]
        "drain progress",
    )
    assert_json(h.tmp / "drain/runs/drain-run/summary.json", lambda data: data["status"] == "drained", "drain summary")
    assert_not_exists(h.tmp / "drain/control/drain.request", "drain request cleared")
    assert_contains(run.stdout, "drain requested; stop after completed task=0-1/task-01", "drain stop log")

    log("stale status and clear use only temp progress")
    write_json(
        h.tmp / "stale/progress.json",
        {
            "version": 1,
            "tasks": {
                "0-1/task-01": {
                    "attempts": 1,
                    "copy_log": "/tmp/missing-copy.log",
                    "note": "fake stale",
                    "risk": "Medium",
                    "run_id": "missing-run",
                    "status": "in_progress",
                    "verify_log": "/tmp/missing-verify.log",
                }
            },
        },
    )
    stale_status = h.task_loop_run("stale", ["status"]).stdout
    assert_contains(stale_status, "stale_in_progress: 1", "stale status")
    h.task_loop_run("stale", ["clear-stale"])
    assert_json(h.tmp / "stale/progress.json", lambda data: data["tasks"] == {}, "clear stale")  # type: ignore[index]
    if not list((h.tmp / "stale/backups").glob("progress-before-clear-stale-*.json")):
        raise CheckFailure("clear-stale backup missing")

    log("resume-stale FAIL does not mark completed")
    write_json(
        h.tmp / "resume/progress.json",
        {
            "version": 1,
            "tasks": {
                "0-1/task-01": {
                    "attempts": 1,
                    "copy_log": "/tmp/missing-copy.log",
                    "note": "fake stale",
                    "risk": "Medium",
                    "run_id": "missing-run",
                    "status": "in_progress",
                    "verify_log": "/tmp/missing-verify.log",
                }
            },
        },
    )
    resume = h.task_loop_run(
        "resume",
        ["resume-stale", "--dry-run", "--phase", "phase-0"],
        extra_env={"DRY_RUN_RESULT": "FAIL", "DRY_RUN_MAX_ATTEMPTS": "1", "MAX_RETRIES": "1"},
        check=False,
    )
    if resume.returncode == 0:
        raise CheckFailure("resume-stale FAIL path unexpectedly succeeded")
    assert_json(h.tmp / "resume/progress.json", lambda data: data["tasks"]["0-1/task-01"]["status"] == "failed", "resume failed")  # type: ignore[index]
    resume_summary = next((h.tmp / "resume/runs").rglob("summary.json"))
    assert_json(resume_summary, lambda data: data["status"] == "failed" and data["totals"]["retries"] == 1, "resume summary")  # type: ignore[index]

    log("live lock blocks second runner")
    write_live_lock(h.tmp / "lockcase/lock", "fake-run")
    lockcase = h.task_loop_run("lockcase", ["run", "--dry-run", "--phase", "phase-0", "--max-tasks", "1"], check=False)
    if lockcase.returncode == 0:
        raise CheckFailure("lock conflict unexpectedly allowed a second runner")
    assert_contains(lockcase.stdout + lockcase.stderr, "task loop lock is held by live pid", "lock conflict")


def check_git_helpers(h: Harness) -> None:
    log("git helper preflight and checkpoint")
    git_repo = h.tmp / "git-helper"
    init_temp_git_repo(git_repo)
    preflight = git_helpers.preflight(git_repo, "commit", "auto", "origin", True, "check001")
    if preflight.get("status") != "ok" or not str(preflight.get("branch", "")).startswith("codex/areamatrix-task-loop-check001"):
        raise CheckFailure(f"bad git preflight: {preflight}")
    if git_helpers.current_branch(git_repo) != "codex/areamatrix-task-loop-check001":
        raise CheckFailure("auto branch was not created")
    progress = git_repo / "tasks/prompts/_shared/progress.json"
    summary = git_repo / ".codex/task-loop-runs/check001/summary.json"
    write_json(progress, {"version": 1, "tasks": {"0-1/task-01": {"status": "completed"}}})
    write_json(summary, {"version": 1, "tasks": {"0-1/task-01": {"status": "completed"}}})
    (git_repo / "implemented.txt").write_text("implemented\n", encoding="utf-8")
    evidence = git_helpers.checkpoint(
        git_repo,
        "commit",
        "origin",
        True,
        "0-1/task-01",
        "phase-0",
        "0-1-task-01",
        1,
        "check001",
        str(git_repo / ".codex/task-loop-logs/check001/phase-0/copy.log"),
        str(git_repo / ".codex/task-loop-logs/check001/phase-0/verify.log"),
        progress,
        summary,
    )
    if evidence.get("status") != "committed" or len(str(evidence.get("commit", ""))) < 7:
        raise CheckFailure(f"bad git checkpoint evidence: {evidence}")
    assert_json(progress, lambda data: data["tasks"]["0-1/task-01"]["git_checkpoint_status"] == "committed", "git checkpoint progress")  # type: ignore[index]
    if git_helpers.status_short(git_repo):
        raise CheckFailure("git checkpoint left dirty worktree")

    dirty_repo = h.tmp / "git-dirty"
    init_temp_git_repo(dirty_repo)
    (dirty_repo / "README.md").write_text("baseline\ndirty\n", encoding="utf-8")
    try:
        git_helpers.preflight(dirty_repo, "commit", "auto", "origin", True, "dirty")
    except git_helpers.GitError as exc:
        assert_contains(str(exc), "requires a clean worktree", "dirty preflight")
    else:
        raise CheckFailure("dirty git preflight unexpectedly succeeded")

    push_fail_repo = h.tmp / "git-push-fail"
    init_temp_git_repo(push_fail_repo)
    subprocess.run(["git", "checkout", "-q", "-b", "codex/push-fail"], cwd=push_fail_repo, check=True)
    push_progress = push_fail_repo / "tasks/prompts/_shared/progress.json"
    push_summary = push_fail_repo / ".codex/task-loop-runs/pushfail/summary.json"
    write_json(push_progress, {"version": 1, "tasks": {"0-1/task-01": {"status": "completed"}}})
    write_json(push_summary, {"version": 1, "tasks": {"0-1/task-01": {"status": "completed"}}})
    (push_fail_repo / "push-fail.txt").write_text("push fail\n", encoding="utf-8")
    try:
        git_helpers.checkpoint(
            push_fail_repo,
            "push",
            "missing",
            True,
            "0-1/task-01",
            "phase-0",
            "0-1-task-01",
            1,
            "pushfail",
            "",
            "",
            push_progress,
            push_summary,
        )
    except git_helpers.GitError:
        pass
    else:
        raise CheckFailure("push failure checkpoint unexpectedly succeeded")
    assert_json(push_progress, lambda data: data["tasks"]["0-1/task-01"]["git_checkpoint_status"] == "git_push_failed", "push failure progress")  # type: ignore[index]
    if git_helpers.status_short(push_fail_repo):
        raise CheckFailure("push failure checkpoint left dirty worktree")


def check_runner_git_checkpoint(h: Harness) -> None:
    log("runner git checkpoint with fake codex in temp repo")
    runner_repo = h.tmp / "runner-git"
    init_temp_git_repo(runner_repo)
    add_prompt_fixture(runner_repo, ["0-1/task-01"])
    subprocess.run(["git", "add", "."], cwd=runner_repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "add prompt fixtures"], cwd=runner_repo, check=True)
    fake_codex = h.tmp / "fake-codex"
    fake_codex.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
if [ -n "${FAKE_CODEX_ARGS_LOG:-}" ]; then
  mkdir -p "$(dirname "$FAKE_CODEX_ARGS_LOG")"
  printf '%s\\n' "$*" >> "$FAKE_CODEX_ARGS_LOG"
fi
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    --cd)
      cd "$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
input="$(cat)"
mkdir -p "$(dirname "$out")"
sleep "${FAKE_CODEX_SLEEP_SECONDS:-0}"
if printf '%s' "$input" | grep -q 'VERIFY_RESULT'; then
  printf '验收通过\\nVERIFY_RESULT: PASS\\n' > "$out"
else
  printf 'copy ok\\n' > "$out"
fi
""",
        encoding="utf-8",
    )
    fake_codex.chmod(0o755)
    result = h.run(
        [h.task_loop, "run", "--phase", "phase-0", "--max-tasks", "1"],
        env={
            "ROOT_DIR": str(runner_repo),
            "PROGRESS_FILE": str(runner_repo / "tasks/prompts/_shared/progress.json"),
            "LOG_ROOT": str(runner_repo / ".codex/task-loop-logs"),
            "RUN_SUMMARY_ROOT": str(runner_repo / ".codex/task-loop-runs"),
            "PROGRESS_BACKUP_ROOT": str(runner_repo / ".codex/task-loop-progress-backups"),
            "LOCK_DIR": str(runner_repo / ".codex/task-loop-lock"),
            "CONTROL_DIR": str(runner_repo / ".codex/task-loop-control"),
            "CODEX_BIN": str(fake_codex),
            "FAKE_CODEX_ARGS_LOG": str(h.tmp / "fake-codex-args.log"),
            "GIT_CHECKPOINT": "commit",
            "GIT_BRANCH_POLICY": "auto",
            "RISK_POLICY": "allow",
            "MAX_RETRIES": "1",
            "ACTIVITY_HEARTBEAT_SECONDS": "1",
            "FAKE_CODEX_SLEEP_SECONDS": "2",
        },
    )
    assert_contains(result.stdout, "live activity heartbeat", "runner prints live activity heartbeat")
    assert_contains(result.stdout, "current task | stage=copy | task=0-1/task-01", "runner live task status line")
    assert_contains(result.stdout, "  live log:", "runner live log section")
    assert_contains(result.stdout, "    state:", "runner live log state")
    assert_contains(result.stdout, "current command | heartbeat=1s | command_elapsed=", "runner live command status line")
    assert_contains(result.stdout, " | command=", "runner live command text")
    progress = runner_repo / "tasks/prompts/_shared/progress.json"
    assert_json(
        progress,
        lambda data: data["tasks"]["0-1/task-01"]["status"] == "completed" and len(data["tasks"]["0-1/task-01"].get("git_commit", "")) >= 7,  # type: ignore[index]
        "runner git progress",
    )
    fake_args = (h.tmp / "fake-codex-args.log").read_text(encoding="utf-8")
    if fake_args.count("-s danger-full-access") != 2:
        raise CheckFailure(f"runner did not use danger-full-access for both codex exec calls:\n{fake_args}")
    assert_not_contains(fake_args, "-s read-only", "runner fake codex args no read-only sandbox")
    assert_not_contains(fake_args, "-s workspace-write", "runner fake codex args no workspace-write sandbox")
    if git_helpers.status_short(runner_repo):
        raise CheckFailure("runner git checkpoint left dirty worktree")
    if not git_helpers.current_branch(runner_repo).startswith("codex/areamatrix-task-loop-"):
        raise CheckFailure("runner did not auto-create task branch")


def check_git_ignore(h: Harness) -> None:
    log("git ignore policy")
    ignored = [
        ".codex/task-loop-lock/foo",
        ".codex/task-loop-control/drain.request",
        ".codex/task-loop-tmp/foo",
        ".codex/task-loop-console/foo.log",
        ".codex/dev-console/config.json",
    ]
    tracked = [
        "tasks/prompts/_shared/progress.json",
        ".codex/task-loop-runs/index.json",
        ".codex/task-loop-runs/example/summary.json",
        ".codex/task-loop-progress-backups/progress-before-reset-example.json",
        ".codex/task-loop-logs/example/phase-0/example.log",
    ]
    for item in ignored:
        proc = h.run(["git", "check-ignore", "-q", item], check=False)
        if proc.returncode != 0:
            raise CheckFailure(f"expected ignored: {item}")
    for item in tracked:
        proc = h.run(["git", "check-ignore", "-q", item], check=False)
        if proc.returncode == 0:
            raise CheckFailure(f"expected tracked/not ignored: {item}")


def run_check(root_dir: Path) -> int:
    root = root_dir.resolve()
    keep = os.environ.get("KEEP_TASK_LOOP_CHECK_TMP") == "1"
    with tempfile.TemporaryDirectory(prefix="areamatrix-task-loop-check-") as tmp_name:
        tmp = Path(tmp_name)
        harness = Harness(root, tmp)
        try:
            check_static(harness)
            check_repo_health(harness)
            check_template_changes(harness)
            check_versioned_workflow(harness)
            check_real_status(harness)
            check_dev_home(harness)
            check_dev_console(harness)
            check_runner_core(harness)
            check_git_helpers(harness)
            check_runner_git_checkpoint(harness)
            check_git_ignore(harness)
        except CheckFailure as exc:
            print(f"[task-loop-check] FAIL: {exc}")
            print(f"[task-loop-check] temp dir: {tmp}")
            if keep:
                preserved = root / ".codex/task-loop-tmp" / tmp.name
                preserved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(tmp, preserved, dirs_exist_ok=True)
                print(f"[task-loop-check] kept temp dir: {preserved}")
                return 1
            return 1
        if keep:
            preserved = root / ".codex/task-loop-tmp" / tmp.name
            preserved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(tmp, preserved, dirs_exist_ok=True)
            print(f"[task-loop-check] kept temp dir: {preserved}")
        log("OK")
        return 0
