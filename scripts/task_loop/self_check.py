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
from . import state


class CheckFailure(RuntimeError):
    pass


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


def check_static(h: Harness) -> None:
    log("static checks")
    files = sorted((h.root / "scripts/task_loop").glob("*.py")) + sorted((h.root / "scripts/dev_tools").glob("*.py"))
    h.run([h.python, "-m", "py_compile", *[str(path) for path in files]])


def check_repo_health(h: Harness) -> None:
    log("repo health")
    if run_skills_check(h.root) != 0:
        raise CheckFailure("skill health failed")
    h.run([h.python, "tasks/prompts/_shared/prompt_pipeline.py", "doctor"])


def check_v2_changes(h: Harness) -> None:
    log("v2 change tracking")
    doctor = h.run([h.dev, "changes", "doctor"]).stdout
    assert_contains(doctor, "v2 change doctor: OK", "changes doctor")
    preview = h.run([h.dev, "changes", "preview"]).stdout
    assert_contains(preview, "V2 change preview", "changes preview header")
    assert_contains(preview, "preview only; no prompt files are generated", "changes preview no writes")
    assert_contains(preview, "v2-search-query", "changes preview feature")
    generated = h.run([h.dev, "changes", "generate"]).stdout
    assert_contains(generated, "V2 generated prompt drafts", "changes generate header")
    assert_contains(generated, "preview only; no files written", "changes generate no writes")
    assert_contains(generated, "workflow/versions/v2/drafts/v2-search-query/manifest.md", "changes generate manifest path")
    assert_contains(generated, "v2-search-query/docs-contract", "changes generate semantic task")
    assert_contains(generated, "VERIFY_RESULT: PASS", "changes generate verify prompt")

    feature_only = h.run([h.dev, "changes", "generate", "--feature", "v2-search-query"]).stdout
    assert_contains(feature_only, "v2-search-query/docs-contract", "changes generate feature filter include")
    assert_not_contains(feature_only, "v2-search-filters/filter-contract", "changes generate feature filter exclude")

    draft_out = h.tmp / "v2-drafts"
    first_write = h.run([h.dev, "changes", "generate", "--write", "--out-dir", str(draft_out)]).stdout
    assert_contains(first_write, "v2 change generate: wrote draft files", "changes generate write")
    assert_exists(draft_out / "v2-search-query/manifest.md", "changes generate manifest write")
    assert_exists(draft_out / "v2-search-query/docs-contract.copy.md", "changes generate copy write")
    assert_exists(draft_out / "v2-search-query/docs-contract.verify.md", "changes generate verify write")

    second_write = h.run([h.dev, "changes", "generate", "--write", "--out-dir", str(draft_out)], check=False)
    if second_write.returncode == 0:
        raise CheckFailure("v2 draft overwrite unexpectedly succeeded without --force")
    assert_contains(second_write.stdout + second_write.stderr, "use --force to overwrite", "changes generate overwrite guard")

    force_write = h.run([h.dev, "changes", "generate", "--write", "--force", "--out-dir", str(draft_out)]).stdout
    assert_contains(force_write, "v2 change generate: wrote draft files", "changes generate force write")

    bad_force = h.run([h.dev, "changes", "generate", "--force"], check=False)
    if bad_force.returncode == 0:
        raise CheckFailure("v2 draft generate unexpectedly accepted --force without --write")
    assert_contains(bad_force.stdout + bad_force.stderr, "--force requires --write", "changes generate force guard")


def check_versioned_workflow(h: Harness) -> None:
    log("versioned workflow tracking")
    doctor = h.run([h.dev, "workflow", "doctor"]).stdout
    assert_contains(doctor, "workflow doctor: OK", "workflow doctor")
    assert_contains(doctor, "v1 gate: queue-only for v2", "workflow v1 gate")
    assert_contains(doctor, "discussion v2: compatibility-exemption", "workflow discussion exemption")
    assert_contains(doctor, "local queue v2: phase-0/0-1/task-01", "workflow local queue")
    assert_contains(doctor, "live mapping v2: configured (phase-5/5-1)", "workflow live mapping")

    status = h.run([h.dev, "workflow", "status"]).stdout
    assert_contains(status, "v1-mvp: live-running", "workflow status v1")
    assert_contains(status, "v2: planning", "workflow status v2")
    assert_contains(status, "discussion: v2: existing-instance compatibility exemption", "workflow status discussion")
    assert_contains(status, "local_queue: phase-0/0-1/task-01", "workflow status local queue")
    assert_contains(status, "live_mapping: configured (phase-5/5-1)", "workflow status live mapping")
    assert_contains(status, "must not promote to tasks/prompts/**", "workflow promote gate")

    init_preview = h.run([h.dev, "workflow", "init", "--version", "v3"]).stdout
    assert_contains(init_preview, "Workflow version init", "workflow init preview")
    assert_contains(init_preview, "mode: preview only; no files written", "workflow init no write")
    assert_contains(init_preview, "workflow/versions/v3/version.yaml", "workflow init version path")
    assert_contains(init_preview, "local_queue:", "workflow init local queue")
    assert_contains(init_preview, "live_mapping: pending", "workflow init live mapping pending")
    bad_name = h.run([h.dev, "workflow", "init", "--version", "bad-name"], check=False)
    if bad_name.returncode == 0:
        raise CheckFailure("workflow init unexpectedly accepted bad version name")
    assert_contains(bad_name.stdout + bad_name.stderr, "version must look like v3", "workflow init version guard")
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
status: approved
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

    discuss_doctor = h.run([h.dev, "workflow", "discuss", "--version", "v2", "doctor"]).stdout
    assert_contains(discuss_doctor, "workflow discuss doctor: OK", "workflow discuss v2 doctor")
    assert_contains(discuss_doctor, "compatibility exemption", "workflow discuss v2 exemption")
    discuss_preview = h.run([h.dev, "workflow", "discuss", "--version", "v2", "preview"]).stdout
    assert_contains(discuss_preview, "Workflow discussion preview", "workflow discuss preview")
    assert_contains(discuss_preview, "compatibility-exemption", "workflow discuss preview exemption")

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
status: approved
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
status: approved
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

    plan = h.run([h.dev, "workflow", "plan", "--version", "v2", "--feature", "v2-search-query"]).stdout
    assert_contains(plan, "Workflow plans", "workflow plan header")
    assert_contains(plan, "Docs Change Ledger", "workflow plan ledger")
    assert_contains(plan, "23-31", "workflow plan line range")
    assert_contains(plan, "Code Impact", "workflow plan code impact")
    assert_contains(plan, "blocked while `v1-mvp` is `live-running`", "workflow plan v1 block")

    queue = h.run([h.dev, "workflow", "queue", "--version", "v2", "--feature", "v2-search-query"]).stdout
    assert_contains(queue, "Workflow queue candidates", "workflow queue header")
    assert_contains(queue, "depends_on: []", "workflow queue empty deps")
    assert_contains(queue, "live_queue_blocked: true", "workflow queue live block")

    promote = h.run([h.dev, "workflow", "promote", "--version", "v2", "--preview"]).stdout
    assert_contains(promote, "Workflow promotion preview", "workflow promote header")
    assert_contains(promote, "promotion blocked: v1-mvp is live-running", "workflow promote v1 block")
    assert_contains(promote, "v2-search-query/docs-contract", "workflow promote semantic task")
    assert_contains(promote, "5-1/task-01", "workflow promote live label")
    assert_contains(promote, "tasks/prompts/phase-5/5-1-v2-search/task-01-docs-contract.md", "workflow promote task path")
    assert_contains(promote, "tasks/prompts/_shared/manifests/phase-5.md", "workflow promote manifest path")
    assert_contains(promote, "tasks/prompts/_shared/copy-ready/phase-5/5-1-task-01.md", "workflow promote copy-ready path")
    assert_contains(promote, "Live queue: not modified", "workflow promote no live writes")

    promote_feature = h.run([h.dev, "workflow", "promote", "--version", "v2", "--feature", "v2-search-query", "--preview"]).stdout
    assert_contains(promote_feature, "v2-search-query/docs-contract", "workflow promote feature include")
    assert_not_contains(promote_feature, "v2-search-filters/filter-contract", "workflow promote feature exclude")

    plan_out = h.tmp / "workflow-plans"
    first_plan_write = h.run([h.dev, "workflow", "plan", "--version", "v2", "--write", "--out-dir", str(plan_out)]).stdout
    assert_contains(first_plan_write, "workflow plan: wrote files", "workflow plan write")
    assert_exists(plan_out / "v2-search-query.plan.md", "workflow plan file")
    second_plan_write = h.run([h.dev, "workflow", "plan", "--version", "v2", "--write", "--out-dir", str(plan_out)], check=False)
    if second_plan_write.returncode == 0:
        raise CheckFailure("workflow plan overwrite unexpectedly succeeded without --force")
    assert_contains(second_plan_write.stdout + second_plan_write.stderr, "use --force to overwrite", "workflow plan overwrite guard")
    h.run([h.dev, "workflow", "plan", "--version", "v2", "--write", "--force", "--out-dir", str(plan_out)])
    bad_plan_force = h.run([h.dev, "workflow", "plan", "--version", "v2", "--force"], check=False)
    if bad_plan_force.returncode == 0:
        raise CheckFailure("workflow plan unexpectedly accepted --force without --write")
    assert_contains(bad_plan_force.stdout + bad_plan_force.stderr, "--force requires --write", "workflow plan force guard")

    queue_out = h.tmp / "workflow-queue"
    first_queue_write = h.run([h.dev, "workflow", "queue", "--version", "v2", "--write", "--out-dir", str(queue_out)]).stdout
    assert_contains(first_queue_write, "workflow queue: wrote files", "workflow queue write")
    assert_exists(queue_out / "v2-search-query/queue.yaml", "workflow queue yaml")
    assert_exists(queue_out / "v2-search-query/queue.md", "workflow queue markdown")
    second_queue_write = h.run([h.dev, "workflow", "queue", "--version", "v2", "--write", "--out-dir", str(queue_out)], check=False)
    if second_queue_write.returncode == 0:
        raise CheckFailure("workflow queue overwrite unexpectedly succeeded without --force")
    assert_contains(second_queue_write.stdout + second_queue_write.stderr, "use --force to overwrite", "workflow queue overwrite guard")
    h.run([h.dev, "workflow", "queue", "--version", "v2", "--write", "--force", "--out-dir", str(queue_out)])
    bad_queue_force = h.run([h.dev, "workflow", "queue", "--version", "v2", "--force"], check=False)
    if bad_queue_force.returncode == 0:
        raise CheckFailure("workflow queue unexpectedly accepted --force without --write")
    assert_contains(bad_queue_force.stdout + bad_queue_force.stderr, "--force requires --write", "workflow queue force guard")

    promotion_out = h.tmp / "workflow-promotion"
    first_promotion_write = h.run([h.dev, "workflow", "promote", "--version", "v2", "--write", "--out-dir", str(promotion_out)]).stdout
    assert_contains(first_promotion_write, "workflow promote: wrote preview files", "workflow promote write")
    assert_contains(first_promotion_write, "promotion blocked: v1-mvp is live-running", "workflow promote write gate")
    assert_exists(promotion_out / "promotion.yaml", "workflow promotion yaml")
    assert_exists(promotion_out / "promotion.md", "workflow promotion markdown")
    second_promotion_write = h.run([h.dev, "workflow", "promote", "--version", "v2", "--write", "--out-dir", str(promotion_out)], check=False)
    if second_promotion_write.returncode == 0:
        raise CheckFailure("workflow promotion overwrite unexpectedly succeeded without --force")
    assert_contains(second_promotion_write.stdout + second_promotion_write.stderr, "use --force to overwrite", "workflow promotion overwrite guard")
    h.run([h.dev, "workflow", "promote", "--version", "v2", "--write", "--force", "--out-dir", str(promotion_out)])
    bad_promotion_force = h.run([h.dev, "workflow", "promote", "--version", "v2", "--force"], check=False)
    if bad_promotion_force.returncode == 0:
        raise CheckFailure("workflow promote unexpectedly accepted --force without --write")
    assert_contains(bad_promotion_force.stdout + bad_promotion_force.stderr, "--force requires --write", "workflow promote force guard")


def check_real_status(h: Harness) -> None:
    log("real status is readable")
    status = h.run([h.task_loop, "status"]).stdout
    assert_contains(status, "stale_in_progress:", "task-loop status stale count")
    assert_contains(status, "drain_requested:", "task-loop status drain")
    dev_status = h.run([h.dev, "status"]).stdout
    assert_contains(dev_status, "AreaMatrix Task Loop", "dev status dashboard header")
    assert_contains(dev_status, "下一步建议", "dev status dashboard suggestions")
    assert_contains(dev_status, "详细长输出：./dev status --verbose", "dev status verbose hint")
    dev_verbose = h.run([h.dev, "status", "--verbose"]).stdout
    assert_contains(dev_verbose, "AreaMatrix Task Loop 控制台", "dev verbose status header")
    assert_contains(dev_verbose, "进程快照", "dev verbose process snapshot")
    preflight = h.dev_run("dev-preflight", ["preflight"]).stdout
    assert_contains(preflight, "Preflight", "dev preflight header")


def check_dev_home(h: Harness) -> None:
    log("dev home dashboard and color controls")
    home = h.run([h.dev, "--once"], env={"DEV_COLOR": "always", "NO_COLOR": ""}).stdout
    assert_contains(home, "\033[", "dev home default color")
    assert_contains(home, "AreaMatrix Task Loop", "dev home dashboard header")
    assert_contains(home, "快捷键", "dev home shortcuts")
    assert_contains(home, "other codex=", "dev home folded process count")
    assert_not_contains(home, "/Applications/Codex.app/Contents/Resources/codex exec", "dev home folded process command")

    no_color = h.run([h.dev, "--color", "never", "--once"]).stdout
    assert_not_contains(no_color, "\033[", "dev home color never")
    assert_contains(no_color, "快捷键", "dev home no-color shortcuts")

    env_color_never = h.run([h.dev, "--once"], env={"DEV_COLOR": "never"}).stdout
    assert_not_contains(env_color_never, "\033[", "dev home DEV_COLOR never")

    env_no_color = h.run([h.dev, "--once"], env={"NO_COLOR": "1"}).stdout
    assert_not_contains(env_no_color, "\033[", "dev home NO_COLOR")

    status_color = h.run([h.dev, "status", "--once", "--color", "always"], env={"NO_COLOR": ""}).stdout
    assert_contains(status_color, "\033[", "dev status color always")

    processes = h.run([h.dev, "processes"]).stdout
    assert_contains(processes, "进程快照", "dev processes header")
    assert_contains(processes, "host codex exec", "dev processes full section")


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
    hints = h.dev_run("dev-hints", ["status"]).stdout
    assert_contains(hints, "从 stale 任务继续", "dev stale action")
    assert_contains(hints, "./dev resume-stale", "dev stale command")
    assert_contains(hints, "从 failed 任务继续", "dev failed action")
    assert_contains(hints, "./dev resume-failed", "dev failed command")
    assert_contains(hints, "一键优雅收尾", "dev drain action")
    assert_contains(hints, "./dev drain", "dev drain command")

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
if printf '%s' "$input" | grep -q 'VERIFY_RESULT'; then
  printf '验收通过\\nVERIFY_RESULT: PASS\\n' > "$out"
else
  printf 'copy ok\\n' > "$out"
fi
""",
        encoding="utf-8",
    )
    fake_codex.chmod(0o755)
    h.run(
        [h.task_loop, "run", "--phase", "phase-0", "--max-tasks", "1"],
        env={
            "ROOT_DIR": str(runner_repo),
            "CODEX_BIN": str(fake_codex),
            "RISK_POLICY": "allow",
            "MAX_RETRIES": "1",
        },
    )
    progress = runner_repo / "tasks/prompts/_shared/progress.json"
    assert_json(
        progress,
        lambda data: data["tasks"]["0-1/task-01"]["status"] == "completed" and len(data["tasks"]["0-1/task-01"].get("git_commit", "")) >= 7,  # type: ignore[index]
        "runner git progress",
    )
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
            check_v2_changes(harness)
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
                print(f"[task-loop-check] kept temp dir: {tmp}")
                return 1
            return 1
        if keep:
            preserved = root / ".codex/task-loop-tmp" / tmp.name
            preserved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(tmp, preserved, dirs_exist_ok=True)
            print(f"[task-loop-check] kept temp dir: {preserved}")
        log("OK")
        return 0
