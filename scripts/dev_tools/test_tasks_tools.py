"""Regression tests for read-only lightweight task developer tools."""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

from scripts.dev_tools.common import ToolError
from scripts.dev_tools.tasks import discover_lightweight_tasks, run_tasks_command, validate_lightweight_tasks


def write_file(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def file_snapshot(root: Path) -> dict[str, str]:
    return {
        str(path.relative_to(root)): path.read_text(encoding="utf-8")
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def task_yaml(task_id: int, slug: str, *, status: str = "todo", layer: str = "frontend", location: str = "apps/macos") -> str:
    return f"""id: {task_id}
slug: {slug}
title: {slug.replace("-", " ").title()}
status: {status}
priority: p2
kind: feature
risk: low

scope:
  layer: {layer}
  area: {location}
  feature: settings

paths:
  touch:
    - {location}/
  forbid:
    - workflow/versions/*/execution/

validation:
  - ./dev check

created: 2026-06-18
updated: 2026-06-18
owner: tasks
"""


def write_task(root: Path, base: str, task_id: int, slug: str, *, status: str = "todo", layer: str = "frontend") -> None:
    prefix = f"{base}/{task_id}.{slug}"
    write_file(root, f"{prefix}/task.yaml", task_yaml(task_id, slug, status=status, layer=layer))
    write_file(root, f"{prefix}/task.md", f"# Task {task_id}\n\nDo {slug}.\n")
    write_file(root, f"{prefix}/verify.md", f"# Verify {task_id}\n")
    write_file(root, f"{prefix}/evidence.md", f"# Evidence {task_id}\n")


def assert_forbidden_state_absent(test: unittest.TestCase, root: Path) -> None:
    for relative in [
        "workflow/versions/v1-mvp/execution",
        "workflow/versions/v1-mvp/evidence/task-loop-runs",
        ".codex/runtime/task-loop/logs",
        ".codex/task-loop-runs",
        ".codex/runtime/task-loop/lock",
        ".codex/runtime/task-loop/control",
    ]:
        test.assertFalse((root / relative).exists(), f"unexpected live state path created: {relative}")


class LightweightTasksToolsTest(unittest.TestCase):
    def _status_args(self) -> Namespace:
        return Namespace(tasks_command="status", task_id=None, task=False, verify=False, evidence=False)

    def _list_args(self) -> Namespace:
        return Namespace(tasks_command="list", task_id=None, task=False, verify=False, evidence=False)

    def _doctor_args(self) -> Namespace:
        return Namespace(tasks_command="doctor", task_id=None, task=False, verify=False, evidence=False)

    def _create_args(
        self,
        *,
        title: str = "Add Settings Button",
        slug: str | None = None,
        write: bool = False,
        validation: list[str] | None = None,
    ) -> Namespace:
        return Namespace(
            tasks_command="create",
            task_id=None,
            task=False,
            verify=False,
            evidence=False,
            title=title,
            slug=slug,
            priority="p2",
            kind="feature",
            risk="low",
            layer="frontend",
            area="apps/macos",
            feature="settings",
            touch=[],
            forbid=[],
            validation=validation or ["./dev check"],
            date="2026-06-18",
            write=write,
        )

    def _complete_args(self, task_id: int, *, write: bool = False, confirm_pass: bool = False) -> Namespace:
        return Namespace(
            tasks_command="complete",
            task_id=task_id,
            task=False,
            verify=False,
            evidence=False,
            date="2026-06-18",
            write=write,
            confirm_pass=confirm_pass,
        )

    def _show_args(self, task_id: int, *, task: bool = False, verify: bool = False, evidence: bool = False) -> Namespace:
        return Namespace(tasks_command="show", task_id=task_id, task=task, verify=verify, evidence=evidence)

    def test_discover_lightweight_tasks_reads_active_and_done(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 2, "fix-sidebar-color", status="blocked", layer="frontend")
            write_task(root, "tasks/done/2026", 1, "add-settings-button", status="done", layer="scripts")

            tasks = discover_lightweight_tasks(root)

            self.assertEqual([task.id for task in tasks], [1, 2])
            self.assertEqual(tasks[0].location, "done/2026")
            self.assertEqual(tasks[1].location, "active")
            self.assertEqual(tasks[1].status, "blocked")

    def test_status_prints_summary_active_done_and_backlog(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button", status="verify_ready")
            write_task(root, "tasks/active", 2, "fix-sidebar-color", status="blocked")
            write_task(root, "tasks/done/2026", 3, "update-docs-layout", status="done", layer="docs")
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "copy\n")
            write_file(root, "tasks/backlog/prompts/beta/README.md", "# Beta Package\n\n- status: closed\n")
            write_file(root, "tasks/backlog/prompts/beta/copy-ready/task-01.md", "copy\n")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._status_args()), 0)

            output = stdout.getvalue()
            self.assertIn("Lightweight tasks\n", output)
            self.assertIn("- active: 2\n", output)
            self.assertIn("- done: 1\n", output)
            self.assertIn("- blocked: 1\n", output)
            self.assertIn("- verify_ready: 1\n", output)
            self.assertIn("- backlog prompt packages: 2\n", output)
            self.assertIn("- backlog open: 1\n", output)
            self.assertIn("- backlog closed: 1\n", output)
            self.assertIn("1 | 1.add-settings-button | active | verify_ready", output)
            self.assertIn("3 | 3.update-docs-layout | done/2026 | done", output)

    def test_list_prints_stable_table(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._list_args()), 0)

            self.assertIn("Lightweight tasks (active and done)", stdout.getvalue())
            self.assertIn("1 | 1.add-settings-button | active | todo | p2 | feature | frontend | apps/macos | settings", stdout.getvalue())

    def test_doctor_passes_valid_structure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")
            write_task(root, "tasks/done/2026", 2, "done-task", status="done")
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "copy\n")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._doctor_args()), 0)

            output = stdout.getvalue()
            self.assertIn("lightweight tasks doctor: OK", output)
            self.assertIn("- active: 1", output)
            self.assertIn("- done: 1", output)
            self.assertIn("- backlog prompt packages: 1", output)
            self.assertIn("- backlog open: 1", output)
            self.assertIn("- backlog closed: 0", output)

    def test_doctor_reports_structure_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button", status="done")
            (root / "tasks/active/1.add-settings-button/verify.md").unlink()
            write_task(root, "tasks/done/current", 2, "bad-year", status="todo")
            write_file(root, "tasks/active/not-number/task.yaml", "id: 3\nslug: not-number\nstatus: todo\n")

            errors = validate_lightweight_tasks(root)

            self.assertTrue(any("missing required task file" in error for error in errors), errors)
            self.assertTrue(any("active task status must be one of" in error for error in errors), errors)
            self.assertTrue(any("done archive directory must be YYYY" in error for error in errors), errors)
            self.assertTrue(any("done task status must be one of" in error for error in errors), errors)
            self.assertTrue(any("task directory must use <number>.<slug>" in error for error in errors), errors)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._doctor_args()), 1)
            self.assertIn("lightweight tasks doctor: FAILED", stdout.getvalue())

    def test_doctor_reports_invalid_classification_values(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")
            yaml_path = root / "tasks/active/1.add-settings-button/task.yaml"
            text = yaml_path.read_text(encoding="utf-8")
            text = text.replace("priority: p2", "priority: p9")
            text = text.replace("kind: feature", "kind: random")
            text = text.replace("risk: low", "risk: huge")
            text = text.replace("layer: frontend", "layer: random")
            yaml_path.write_text(text, encoding="utf-8")

            errors = validate_lightweight_tasks(root)

            self.assertTrue(any("priority must be one of" in error for error in errors), errors)
            self.assertTrue(any("kind must be one of" in error for error in errors), errors)
            self.assertTrue(any("risk must be one of" in error for error in errors), errors)
            self.assertTrue(any("scope.layer must be one of" in error for error in errors), errors)

    def test_create_preview_is_read_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            before = file_snapshot(root)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._create_args()), 0)

            output = stdout.getvalue()
            self.assertEqual(file_snapshot(root), before)
            self.assertIn("Lightweight task create preview", output)
            self.assertIn("tasks/active/1.add-settings-button/", output)
            self.assertIn("Add --write to create this task", output)

    def test_create_write_creates_standard_active_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/done/2026", 1, "old-task", status="done")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._create_args(write=True)), 0)

            task_dir = root / "tasks/active/2.add-settings-button"
            self.assertTrue(task_dir.is_dir())
            for file_name in ["task.yaml", "task.md", "verify.md", "evidence.md"]:
                self.assertTrue((task_dir / file_name).is_file(), file_name)
            yaml_text = (task_dir / "task.yaml").read_text(encoding="utf-8")
            self.assertIn("id: 2\n", yaml_text)
            self.assertIn("slug: add-settings-button\n", yaml_text)
            self.assertIn("status: todo\n", yaml_text)
            self.assertIn("scope:\n  layer: frontend\n  area: apps/macos\n  feature: settings\n", yaml_text)
            self.assertIn("workflow/versions/*/execution/", yaml_text)
            self.assertIn("./dev check", yaml_text)
            self.assertIn("created lightweight task: tasks/active/2.add-settings-button/", stdout.getvalue())
            self.assertFalse((root / "workflow/versions/v1-mvp/execution").exists())

            self.assertEqual(validate_lightweight_tasks(root), [])

    def test_create_rejects_unhealthy_existing_tasks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button", status="done")

            with self.assertRaises(ToolError) as ctx:
                run_tasks_command(root, self._create_args(write=True))

            self.assertEqual(ctx.exception.code, 1)
            self.assertIn("run ./dev tasks doctor", str(ctx.exception))
            self.assertFalse((root / "tasks/active/2.add-settings-button").exists())

    def test_complete_preview_is_read_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button", status="verify_ready")
            before = file_snapshot(root)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._complete_args(1)), 0)

            output = stdout.getvalue()
            self.assertEqual(file_snapshot(root), before)
            self.assertIn("Lightweight task complete preview", output)
            self.assertIn("tasks/active/1.add-settings-button/", output)
            self.assertIn("tasks/done/2026/1.add-settings-button/", output)

    def test_complete_write_requires_confirm_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button", status="verify_ready")

            with self.assertRaises(ToolError) as ctx:
                run_tasks_command(root, self._complete_args(1, write=True))

            self.assertEqual(ctx.exception.code, 2)
            self.assertIn("--confirm-pass", str(ctx.exception))
            self.assertTrue((root / "tasks/active/1.add-settings-button").is_dir())

    def test_complete_write_archives_active_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button", status="verify_ready")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._complete_args(1, write=True, confirm_pass=True)), 0)

            active_dir = root / "tasks/active/1.add-settings-button"
            done_dir = root / "tasks/done/2026/1.add-settings-button"
            self.assertFalse(active_dir.exists())
            self.assertTrue(done_dir.is_dir())
            yaml_text = (done_dir / "task.yaml").read_text(encoding="utf-8")
            self.assertIn("status: done\n", yaml_text)
            self.assertIn("updated: 2026-06-18\n", yaml_text)
            self.assertIn("archived lightweight task: tasks/done/2026/1.add-settings-button/", stdout.getvalue())
            self.assertEqual(validate_lightweight_tasks(root), [])

    def test_complete_rejects_done_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/done/2026", 1, "done-task", status="done")

            with self.assertRaises(ToolError) as ctx:
                run_tasks_command(root, self._complete_args(1, write=True, confirm_pass=True))

            self.assertEqual(ctx.exception.code, 1)
            self.assertIn("unknown active lightweight task id", str(ctx.exception))

    def test_show_prints_detail_and_task_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._show_args(1)), 0)

            output = stdout.getvalue()
            self.assertIn("Task 1: add-settings-button", output)
            self.assertIn("- scope: frontend / apps/macos / settings", output)
            self.assertIn("--- task.md ---", output)
            self.assertIn("# Task 1", output)

    def test_show_can_print_task_verify_or_evidence_raw(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")

            for flag_name, expected in [("task", "# Task 1\n\nDo add-settings-button.\n"), ("verify", "# Verify 1\n"), ("evidence", "# Evidence 1\n")]:
                stdout = io.StringIO()
                args = self._show_args(1, **{flag_name: True})
                with contextlib.redirect_stdout(stdout):
                    self.assertEqual(run_tasks_command(root, args), 0)
                self.assertEqual(stdout.getvalue(), expected)

    def test_show_finds_done_task_by_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/done/2026", 4, "done-task", status="done")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_tasks_command(root, self._show_args(4)), 0)

            self.assertIn("- location: done/2026", stdout.getvalue())

    def test_status_is_read_only_for_repo_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")
            write_file(root, "workflow/versions/v1-mvp/execution/_shared/progress.json", "{}\n")
            before = file_snapshot(root)

            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(run_tasks_command(root, self._doctor_args()), 0)
                self.assertEqual(run_tasks_command(root, self._status_args()), 0)
                self.assertEqual(run_tasks_command(root, self._list_args()), 0)
                self.assertEqual(run_tasks_command(root, self._show_args(1)), 0)

            self.assertEqual(file_snapshot(root), before)

    def test_tasks_commands_do_not_create_live_queue_or_task_loop_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")

            assert_forbidden_state_absent(self, root)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(run_tasks_command(root, self._doctor_args()), 0)
                self.assertEqual(run_tasks_command(root, self._status_args()), 0)
                self.assertEqual(run_tasks_command(root, self._list_args()), 0)
                self.assertEqual(run_tasks_command(root, self._show_args(1, task=True)), 0)
                self.assertEqual(run_tasks_command(root, self._show_args(1, verify=True)), 0)
                self.assertEqual(run_tasks_command(root, self._show_args(1, evidence=True)), 0)

            assert_forbidden_state_absent(self, root)

    def test_show_rejects_unknown_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")

            with self.assertRaises(ToolError) as ctx:
                run_tasks_command(root, self._show_args(2))

            self.assertEqual(ctx.exception.code, 1)
            self.assertIn("unknown lightweight task id: 2", str(ctx.exception))
            self.assertIn("available task ids: 1", str(ctx.exception))

    def test_rejects_duplicate_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")
            write_task(root, "tasks/done/2026", 1, "old-settings-button", status="done")

            with self.assertRaises(ToolError) as ctx:
                discover_lightweight_tasks(root)

            self.assertIn("duplicate lightweight task id 1", str(ctx.exception))

    def test_rejects_yaml_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")
            yaml_path = root / "tasks/active/1.add-settings-button/task.yaml"
            yaml_path.write_text(yaml_path.read_text(encoding="utf-8").replace("slug: add-settings-button", "slug: wrong"), encoding="utf-8")

            with self.assertRaises(ToolError) as ctx:
                discover_lightweight_tasks(root)

            self.assertIn("slug must match directory slug add-settings-button", str(ctx.exception))

    def test_show_rejects_multiple_file_flags(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_task(root, "tasks/active", 1, "add-settings-button")

            with self.assertRaises(ToolError) as ctx:
                run_tasks_command(root, self._show_args(1, task=True, verify=True))

            self.assertEqual(ctx.exception.code, 2)
            self.assertIn("only one of --task, --verify, or --evidence", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
