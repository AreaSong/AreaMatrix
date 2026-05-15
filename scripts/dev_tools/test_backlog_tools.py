"""Regression tests for read-only backlog developer tools."""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

from scripts.dev_tools.backlog import discover_package_tasks, discover_packages, run_backlog_command
from scripts.dev_tools.common import ToolError


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


def assert_forbidden_state_absent(test: unittest.TestCase, root: Path) -> None:
    for relative in [
        "tasks/prompts",
        ".codex/task-loop-logs",
        ".codex/task-loop-runs",
        ".codex/task-loop-lock",
        ".codex/task-loop-control",
    ]:
        test.assertFalse((root / relative).exists(), f"unexpected live state path created: {relative}")


class BacklogToolsTest(unittest.TestCase):
    def _list_args(self) -> Namespace:
        return Namespace(backlog_command="list", package=None, task=None, mode=None)

    def _show_args(self, package: str, task: int | None = None, mode: str | None = None) -> Namespace:
        return Namespace(backlog_command="show", package=package, task=task, mode=mode)

    def test_discover_packages_returns_slug_sorted_counts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(root, "tasks/backlog/prompts/zeta/README.md", "# Zeta Package\n")
            write_file(root, "tasks/backlog/prompts/zeta/copy-ready/task-02.md", "copy\n")
            write_file(root, "tasks/backlog/prompts/zeta/verify-ready/task-02.md", "verify\n")
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "copy\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-02.md", "copy\n")
            write_file(root, "tasks/backlog/prompts/no-readme/copy-ready/task-01.md", "copy\n")
            write_file(root, "tasks/backlog/prompts/no-prompts/README.md", "# No Prompts\n")

            packages = discover_packages(root)

            self.assertEqual([package.slug for package in packages], ["alpha", "zeta"])
            self.assertEqual(packages[0].title, "Alpha Package")
            self.assertEqual(packages[0].task_count, 2)
            self.assertEqual(packages[0].copy_ready_count, 2)
            self.assertEqual(packages[0].verify_ready_count, 0)
            self.assertEqual(packages[1].task_count, 1)
            self.assertEqual(packages[1].copy_ready_count, 1)
            self.assertEqual(packages[1].verify_ready_count, 1)

    def test_list_prints_stable_markdown_table(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(root, "tasks/backlog/prompts/zeta/README.md", "# Zeta Package\n")
            write_file(root, "tasks/backlog/prompts/zeta/copy-ready/task-02.md", "copy\n")
            write_file(root, "tasks/backlog/prompts/zeta/verify-ready/task-02.md", "verify\n")
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "copy\n")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_backlog_command(root, self._list_args()), 0)

            self.assertEqual(
                stdout.getvalue(),
                "\n".join(
                    [
                        "Backlog prompt packages (sorted by slug)",
                        "slug | title | tasks | copy-ready | verify-ready",
                        "--- | --- | ---: | ---: | ---:",
                        "alpha | Alpha Package | 1 | 1 | 0",
                        "zeta | Zeta Package | 1 | 1 | 1",
                    ]
                )
                + "\n",
            )

    def test_list_is_read_only_for_repo_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "copy\n")
            write_file(root, "tasks/prompts/_shared/progress.json", "{}\n")
            before = file_snapshot(root)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_backlog_command(root, self._list_args()), 0)

            self.assertEqual(file_snapshot(root), before)
            self.assertIn("alpha | Alpha Package | 1 | 1 | 0", stdout.getvalue())

    def test_empty_package_root_returns_clear_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "tasks/backlog/prompts").mkdir(parents=True)

            with self.assertRaises(ToolError) as ctx:
                run_backlog_command(root, self._list_args())

            self.assertEqual(ctx.exception.code, 1)
            self.assertIn("no backlog prompt packages found", str(ctx.exception))

    def test_show_package_prints_readme_and_task_index(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(
                root,
                "tasks/backlog/prompts/alpha/README.md",
                "\n".join(
                    [
                        "# Alpha Package",
                        "",
                        "| 顺序 | Copy-ready | Verify-ready | 目的 |",
                        "|---|---|---|---|",
                        "| 1 | `copy-ready/task-02.md` | `verify-ready/task-02.md` | second first |",
                        "| 2 | `copy-ready/task-01.md` | `verify-ready/task-01.md` | first second |",
                    ]
                )
                + "\n",
            )
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy 1\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-02.md", "# Copy 2\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-01.md", "# Verify 1\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-02.md", "# Verify 2\n")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_backlog_command(root, self._show_args("alpha")), 0)

            output = stdout.getvalue()
            self.assertIn("# Alpha Package\n", output)
            self.assertIn("## Task Index\n", output)
            self.assertIn("1 | `copy-ready/task-02.md` | `verify-ready/task-02.md`", output)
            self.assertIn("2 | `copy-ready/task-01.md` | `verify-ready/task-01.md`", output)
            self.assertIn("--task N --mode copy|verify", output)

    def test_task_mapping_prefers_readme_table_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_dir = root / "tasks/backlog/prompts/alpha"
            write_file(
                root,
                "tasks/backlog/prompts/alpha/README.md",
                "\n".join(
                    [
                        "# Alpha Package",
                        "",
                        "| 顺序 | Copy-ready | Verify-ready | 目的 |",
                        "|---|---|---|---|",
                        "| 1 | `copy-ready/task-02.md` | `verify-ready/task-02.md` | second first |",
                        "| 2 | `copy-ready/task-01.md` | `verify-ready/task-01.md` | first second |",
                    ]
                )
                + "\n",
            )
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy 1\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-02.md", "# Copy 2\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-01.md", "# Verify 1\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-02.md", "# Verify 2\n")

            tasks = discover_package_tasks(package_dir)

            self.assertEqual([task.copy_ready_path.name for task in tasks], ["task-02.md", "task-01.md"])
            self.assertEqual([task.verify_ready_path.name for task in tasks], ["task-02.md", "task-01.md"])

    def test_task_mapping_falls_back_to_filename_sort(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            package_dir = root / "tasks/backlog/prompts/alpha"
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-02.md", "# Copy 2\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-02.md", "# Verify 2\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy 1\n")

            tasks = discover_package_tasks(package_dir)

            self.assertEqual([task.copy_ready_path.name for task in tasks], ["task-01.md", "task-02.md"])
            self.assertIsNone(tasks[0].verify_ready_path)
            self.assertEqual(tasks[1].verify_ready_path.name, "task-02.md")

    def test_show_task_prints_copy_ready_prompt_raw(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(
                root,
                "tasks/backlog/prompts/alpha/README.md",
                "| 1 | `copy-ready/task-01.md` | `verify-ready/task-01.md` | one |\n",
            )
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy Prompt\n\nBody\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-01.md", "# Verify Prompt\n")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_backlog_command(root, self._show_args("alpha", task=1, mode="copy")), 0)

            self.assertEqual(stdout.getvalue(), "# Copy Prompt\n\nBody\n")

    def test_show_task_prints_verify_ready_prompt_raw(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(
                root,
                "tasks/backlog/prompts/alpha/README.md",
                "| 1 | `copy-ready/task-01.md` | `verify-ready/task-01.md` | one |\n",
            )
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy Prompt\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-01.md", "# Verify Prompt\n\nBody\n")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_backlog_command(root, self._show_args("alpha", task=1, mode="verify")), 0)

            self.assertEqual(stdout.getvalue(), "# Verify Prompt\n\nBody\n")

    def test_show_requires_mode_when_task_is_specified(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy\n")

            with self.assertRaises(ToolError) as ctx:
                run_backlog_command(root, self._show_args("alpha", task=1))

            self.assertEqual(ctx.exception.code, 2)
            self.assertIn("--mode copy|verify", str(ctx.exception))

    def test_show_rejects_mode_without_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy\n")

            with self.assertRaises(ToolError) as ctx:
                run_backlog_command(root, self._show_args("alpha", mode="copy"))

            self.assertEqual(ctx.exception.code, 2)
            self.assertIn("requires --task N", str(ctx.exception))

    def test_show_rejects_unknown_package(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy\n")

            with self.assertRaises(ToolError) as ctx:
                run_backlog_command(root, self._show_args("missing"))

            self.assertEqual(ctx.exception.code, 1)
            self.assertIn("unknown backlog package: missing", str(ctx.exception))
            self.assertIn("available packages: alpha", str(ctx.exception))

    def test_show_rejects_out_of_range_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(root, "tasks/backlog/prompts/alpha/README.md", "# Alpha Package\n")
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy\n")

            with self.assertRaises(ToolError) as ctx:
                run_backlog_command(root, self._show_args("alpha", task=2, mode="copy"))

            self.assertEqual(ctx.exception.code, 1)
            self.assertIn("task 2 is out of range", str(ctx.exception))
            self.assertIn("available task numbers: 1-1", str(ctx.exception))

    def test_show_rejects_missing_prompt_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(
                root,
                "tasks/backlog/prompts/alpha/README.md",
                "| 1 | `copy-ready/task-01.md` | `verify-ready/task-01.md` | one |\n",
            )
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy\n")

            with self.assertRaises(ToolError) as ctx:
                run_backlog_command(root, self._show_args("alpha", task=1, mode="verify"))

            self.assertEqual(ctx.exception.code, 1)
            self.assertIn("missing verify-ready prompt", str(ctx.exception))
            self.assertIn("tasks/backlog/prompts/alpha/verify-ready/task-01.md", str(ctx.exception))

    def test_show_task_is_read_only_for_repo_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(
                root,
                "tasks/backlog/prompts/alpha/README.md",
                "| 1 | `copy-ready/task-01.md` | `verify-ready/task-01.md` | one |\n",
            )
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-01.md", "# Verify\n")
            write_file(root, "tasks/prompts/_shared/progress.json", "{}\n")
            before = file_snapshot(root)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_backlog_command(root, self._show_args("alpha", task=1, mode="copy")), 0)

            self.assertEqual(file_snapshot(root), before)
            self.assertEqual(stdout.getvalue(), "# Copy\n")

    def test_backlog_commands_do_not_create_live_queue_or_task_loop_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_file(
                root,
                "tasks/backlog/prompts/alpha/README.md",
                "| 1 | `copy-ready/task-01.md` | `verify-ready/task-01.md` | one |\n",
            )
            write_file(root, "tasks/backlog/prompts/alpha/copy-ready/task-01.md", "# Copy\n")
            write_file(root, "tasks/backlog/prompts/alpha/verify-ready/task-01.md", "# Verify\n")

            assert_forbidden_state_absent(self, root)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(run_backlog_command(root, self._list_args()), 0)
                self.assertEqual(run_backlog_command(root, self._show_args("alpha")), 0)
                self.assertEqual(run_backlog_command(root, self._show_args("alpha", task=1, mode="copy")), 0)
                self.assertEqual(run_backlog_command(root, self._show_args("alpha", task=1, mode="verify")), 0)

            assert_forbidden_state_absent(self, root)


if __name__ == "__main__":
    unittest.main()
