"""Regression tests for Codex Operating System developer tools."""

from __future__ import annotations

from argparse import Namespace
from datetime import datetime, timezone
import contextlib
import io
import json
import os
import sqlite3
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.dev_tools.cli import _build_parser, _normalize_codex_os_common_args
from scripts.dev_tools.codex_os import (
    ThreadRecord,
    classify_thread,
    run_codex_os_command,
)


def create_state_db(path: Path) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            cwd TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            archived INTEGER NOT NULL,
            preview TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE agent_jobs (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            status TEXT NOT NULL
        );
        CREATE TABLE agent_job_items (
            job_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            assigned_thread_id TEXT,
            status TEXT NOT NULL,
            PRIMARY KEY (job_id, item_id)
        );
        CREATE TABLE thread_spawn_edges (
            parent_thread_id TEXT NOT NULL,
            child_thread_id TEXT NOT NULL PRIMARY KEY,
            status TEXT NOT NULL
        );
        """
    )
    now = int(datetime(2026, 6, 29, tzinfo=timezone.utc).timestamp())
    rows = [
        ("active-recent", "Fix active task", "/repo", now - 3600, now - 3600, 0, "recent"),
        ("old-greeting", "你好", "/repo", now - 80 * 86400, now - 80 * 86400, 0, "hello"),
        ("risk", "Mission-Critical migration review", "/repo", now - 80 * 86400, now - 80 * 86400, 0, "risk"),
        ("archived", "Archived task", "/repo", now - 80 * 86400, now - 80 * 86400, 1, "done"),
        ("edge-parent", "Parent with child", "/repo", now - 80 * 86400, now - 80 * 86400, 0, "edge"),
        ("edge-child", "Child worker", "/repo", now - 80 * 86400, now - 80 * 86400, 0, "edge"),
    ]
    conn.executemany(
        "INSERT INTO threads (id, title, cwd, created_at, updated_at, archived, preview) VALUES (?, ?, ?, ?, ?, ?, ?)",
        rows,
    )
    conn.execute(
        "INSERT INTO thread_spawn_edges (parent_thread_id, child_thread_id, status) VALUES (?, ?, ?)",
        ("edge-parent", "edge-child", "open"),
    )
    conn.execute("INSERT INTO agent_jobs (id, name, status) VALUES (?, ?, ?)", ("job-1", "example", "running"))
    conn.execute(
        "INSERT INTO agent_job_items (job_id, item_id, assigned_thread_id, status) VALUES (?, ?, ?, ?)",
        ("job-1", "item-1", "active-recent", "running"),
    )
    conn.commit()
    conn.close()


def args(command: str, state_db: Path, runtime_dir: Path, **extra: object) -> Namespace:
    values = {
        "codex_os_command": command,
        "state_db": str(state_db),
        "runtime_dir": str(runtime_dir),
        "project": None,
        "limit": 20,
        "json": False,
        "write": False,
        "registry_command": None,
        "force": False,
        "task_id": None,
        "project_name": None,
        "lane": None,
        "status": None,
        "owner_thread": None,
        "handoff_file": None,
        "next_action": None,
        "validation": None,
        "archive_recommendation": None,
        "risk_level": None,
        "confirmation_status": None,
        "evidence_file": None,
        "closeout_file": None,
        "evidence_note": None,
        "closeout_note": None,
        "validation_status": None,
        "automation_scope": None,
        "strict": False,
        "write_dashboard": False,
        "task_command": None,
        "title": None,
        "path": [],
        "changed": False,
        "profile": "standard",
        "execute": False,
        "timeout": 600,
        "from_latest_validation": False,
        "close_when_pass": False,
        "ops": False,
        "compact": False,
        "action_items": False,
        "output": None,
        "recommend_validation": False,
    }
    values.update(extra)
    return Namespace(**values)


class CodexOsToolsTest(unittest.TestCase):
    def test_codex_os_common_args_work_before_or_after_subcommand(self) -> None:
        parser = _build_parser()
        parent_args = parser.parse_args(
            [
                "codex-os",
                "--state-db",
                "parent.sqlite",
                "--runtime-dir",
                "parent-runtime",
                "start-flow",
                "--task-id",
                "AM-ARGS",
            ]
        )
        _normalize_codex_os_common_args(parent_args)
        self.assertEqual(parent_args.state_db, "parent.sqlite")
        self.assertEqual(parent_args.runtime_dir, "parent-runtime")

        child_args = parser.parse_args(
            [
                "codex-os",
                "start-flow",
                "--state-db",
                "child.sqlite",
                "--runtime-dir",
                "child-runtime",
                "--task-id",
                "AM-ARGS",
            ]
        )
        _normalize_codex_os_common_args(child_args)
        self.assertEqual(child_args.state_db, "child.sqlite")
        self.assertEqual(child_args.runtime_dir, "child-runtime")

    def test_codex_os_parser_recognizes_aggregate_flow_and_new_modes(self) -> None:
        parser = _build_parser()
        flow = parser.parse_args(
            [
                "codex-os",
                "flow",
                "--task-id",
                "AM-PARSER",
                "--changed",
                "--profile",
                "full",
                "--execute",
                "--close-when-pass",
                "--ops",
            ]
        )
        _normalize_codex_os_common_args(flow)
        self.assertEqual(flow.codex_os_command, "flow")
        self.assertEqual(flow.profile, "full")
        self.assertTrue(flow.execute)
        self.assertTrue(flow.close_when_pass)
        self.assertTrue(flow.ops)

        latest = parser.parse_args(["codex-os", "close-flow", "--task-id", "AM-PARSER", "--status", "Done", "--from-latest-validation"])
        _normalize_codex_os_common_args(latest)
        self.assertTrue(latest.from_latest_validation)

        ops = parser.parse_args(["codex-os", "ops-flow", "--action-items", "--json"])
        _normalize_codex_os_common_args(ops)
        self.assertTrue(ops.action_items)
        self.assertTrue(ops.json)

        go = parser.parse_args(["codex-os", "go", "--title", "Parser go", "--apply", "--profile", "auto"])
        _normalize_codex_os_common_args(go)
        self.assertEqual(go.codex_os_command, "go")
        self.assertTrue(go.apply)
        self.assertEqual(go.profile, "auto")

        done = parser.parse_args(["codex-os", "done", "--task-id", "AM-PARSER"])
        _normalize_codex_os_common_args(done)
        self.assertEqual(done.codex_os_command, "done")

        now = parser.parse_args(["codex-os", "now", "--task-id", "AM-PARSER", "--json"])
        _normalize_codex_os_common_args(now)
        self.assertEqual(now.codex_os_command, "now")
        self.assertTrue(now.json)

    def test_classify_thread_marks_archive_candidate_and_risk_review(self) -> None:
        now = datetime(2026, 6, 29, tzinfo=timezone.utc)
        old = int(datetime(2026, 3, 1, tzinfo=timezone.utc).timestamp())
        greeting = ThreadRecord("1", "你好", "/repo", old, old, False, "", False, False)
        risk = ThreadRecord("2", "Mission-Critical migration", "/repo", old, old, False, "", False, False)
        edge = ThreadRecord("3", "Old but open", "/repo", old, old, False, "", True, False)
        prompt = ThreadRecord("4", "# Verify-ready Prompt: 4-3/task-165", "/repo", old, old, False, "", False, False)

        self.assertEqual(classify_thread(greeting, now).bucket, "Archive Candidate")
        self.assertEqual(classify_thread(risk, now).bucket, "Risk Review")
        self.assertEqual(classify_thread(edge, now).bucket, "Active")
        self.assertEqual(classify_thread(prompt, now).bucket, "Archive Candidate")

    def test_thread_health_writes_json_without_mutating_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = run_codex_os_command(
                    root,
                    args("thread-health", state_db, runtime, write=True, json=True, limit=5),
                )

            self.assertEqual(code, 0)
            data = json.loads((runtime / "thread-health.json").read_text(encoding="utf-8"))
            self.assertEqual(data["total_threads"], 6)
            self.assertEqual(data["bucket_counts"]["Active"], 3)
            self.assertEqual(data["bucket_counts"]["Archive Candidate"], 1)
            self.assertIn("thread-health.json", stdout.getvalue())

            conn = sqlite3.connect(state_db)
            archived_count = conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 1").fetchone()[0]
            conn.close()
            self.assertEqual(archived_count, 1)

    def test_registry_init_status_dashboard_and_doctor(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            (root / ".codex/references").mkdir(parents=True)
            (root / ".codex/templates").mkdir(parents=True)
            for relative in [
                ".codex/README.md",
                ".codex/references/index.md",
                ".codex/references/codex-operating-system.md",
                ".codex/templates/codex-intake-template.md",
                ".codex/templates/codex-handoff-template.md",
                ".codex/templates/codex-evidence-template.md",
                ".codex/templates/codex-closeout-template.md",
                ".codex/templates/task-registry.example.json",
            ]:
                text = "{}\n" if relative.endswith(".json") else "fixture\n"
                (root / relative).write_text(text, encoding="utf-8")

            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="status")),
                0,
            )
            self.assertEqual(run_codex_os_command(root, args("dashboard", state_db, runtime, write=True)), 0)
            self.assertTrue((runtime / "dashboard.md").is_file())
            self.assertTrue((runtime / "health-report.md").is_file())
            self.assertEqual(run_codex_os_command(root, args("doctor", state_db, runtime)), 0)

    def test_registry_add_list_update_and_archive_candidates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )

            add_args = args(
                "registry",
                state_db,
                runtime,
                registry_command="add",
                task_id="AM-1",
                project_name="AreaMatrix",
                lane="Change",
                status="Ready",
                owner_thread="",
                handoff_file="tasks/active/demo/HANDOFF.md",
                next_action="Read handoff.",
                validation="./dev codex-os doctor",
                archive_recommendation="keep",
                write=True,
            )
            self.assertEqual(run_codex_os_command(root, add_args), 0)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(root, args("registry", state_db, runtime, registry_command="list")),
                    0,
                )
            self.assertIn("AM-1", stdout.getvalue())

            update_args = args(
                "registry",
                state_db,
                runtime,
                registry_command="update",
                task_id="AM-1",
                lane=None,
                status="Verifying",
                owner_thread=None,
                handoff_file=None,
                next_action="Run validation.",
                validation=None,
                archive_recommendation=None,
                write=True,
            )
            self.assertEqual(run_codex_os_command(root, update_args), 0)
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            self.assertEqual(registry["tasks"][0]["status"], "Verifying")
            self.assertEqual(registry["tasks"][0]["next_action"], "Run validation.")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(root, args("archive-candidates", state_db, runtime, limit=10, json=False)),
                    0,
                )
            self.assertIn("Archive candidates", stdout.getvalue())
            self.assertIn("你好", stdout.getvalue())

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(root, args("archive-candidates", state_db, runtime, limit=10, json=True)),
                    0,
                )
            archive_json = json.loads(stdout.getvalue())
            self.assertEqual(archive_json["policy"], "recommendations only; no archive action is performed")
            self.assertIn("bucket_counts", archive_json)
            self.assertIn("archive_candidates", archive_json)

    def test_intake_prints_template_with_lane_and_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = root / ".codex/runtime/codex-os"
            template = root / ".codex/templates/codex-intake-template.md"
            template.parent.mkdir(parents=True)
            template.write_text("Lane: Quick | Change | Mission-Critical | Explore | Review | Ops\nTask ID: <task-id>\n", encoding="utf-8")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = run_codex_os_command(
                    root,
                    args("intake", root / "missing.sqlite", runtime, lane="Change", task_id="AM-1"),
                )

            self.assertEqual(code, 0)
            self.assertIn("Lane: Change", stdout.getvalue())
            self.assertIn("Task ID: AM-1", stdout.getvalue())

    def test_closeout_prints_template_with_task_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = root / ".codex/runtime/codex-os"
            template = root / ".codex/templates/codex-closeout-template.md"
            template.parent.mkdir(parents=True)
            template.write_text("Task: <task-id>\n", encoding="utf-8")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = run_codex_os_command(
                    root,
                    args("closeout", root / "missing.sqlite", runtime, task_id="AM-1"),
                )

            self.assertEqual(code, 0)
            self.assertEqual(stdout.getvalue(), "Task: AM-1\n")

    def test_preflight_strict_fails_for_done_task_without_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-2",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Done",
                        validation="./dev check codex-os",
                        write=True,
                    ),
                ),
                0,
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = run_codex_os_command(root, args("preflight", state_db, runtime, task_id="AM-2", strict=True))

            self.assertEqual(code, 1)
            self.assertIn("Done task has no evidence or closeout reference", stdout.getvalue())

    def test_task_transitions_preview_and_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-3",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Ready",
                        write=True,
                    ),
                ),
                0,
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(root, args("task", state_db, runtime, task_command="start", task_id="AM-3")),
                    0,
                )
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            self.assertEqual(registry["tasks"][0]["status"], "Ready")
            self.assertIn("Add --write", stdout.getvalue())

            self.assertEqual(
                run_codex_os_command(
                    root,
                    args("task", state_db, runtime, task_command="start", task_id="AM-3", write=True),
                ),
                0,
            )
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            self.assertEqual(registry["tasks"][0]["status"], "Running")

    def test_finish_done_requires_evidence_and_writes_optional_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-4",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Verifying",
                        write=True,
                    ),
                ),
                0,
            )

            with self.assertRaises(Exception):
                run_codex_os_command(
                    root,
                    args(
                        "finish",
                        state_db,
                        runtime,
                        task_id="AM-4",
                        status="Done",
                        validation="./dev check codex-os: PASS",
                    ),
                )

            with self.assertRaises(Exception) as dry_finish:
                run_codex_os_command(
                    root,
                    args(
                        "finish",
                        state_db,
                        runtime,
                        task_id="AM-4",
                        status="Done",
                        validation="./dev check codex-os: SKIPPED; result: NOT-READY",
                        evidence_note="unit-test evidence",
                    ),
                )
            self.assertIn("fresh PASS/OK", str(dry_finish.exception))

            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "finish",
                        state_db,
                        runtime,
                        task_id="AM-4",
                        status="Done",
                        validation="./dev check codex-os: PASS",
                        evidence_note="unit-test evidence",
                        closeout_note="unit-test closeout",
                        archive_recommendation="review",
                        write=True,
                    ),
                ),
                0,
            )
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            task = registry["tasks"][0]
            self.assertEqual(task["status"], "Done")
            self.assertEqual(task["validation_status"], "Pass")
            self.assertEqual(task["archive_recommendation"], "review")
            self.assertEqual(task["evidence_note"], "unit-test evidence")
            self.assertIn("finished_at", task)

            conn = sqlite3.connect(state_db)
            archived_count = conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 1").fetchone()[0]
            conn.close()
            self.assertEqual(archived_count, 1)

    def test_finish_blocked_requires_next_action(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-5",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Running",
                        write=True,
                    ),
                ),
                0,
            )

            with self.assertRaises(Exception):
                run_codex_os_command(root, args("finish", state_db, runtime, task_id="AM-5", status="Blocked"))
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "finish",
                        state_db,
                        runtime,
                        task_id="AM-5",
                        status="Blocked",
                        next_action="Wait for user confirmation.",
                        write=True,
                    ),
                ),
                0,
            )
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            self.assertEqual(registry["tasks"][0]["status"], "Blocked")
            self.assertEqual(registry["tasks"][0]["validation_status"], "Blocked")

    def test_recommend_validation_uses_changed_paths_without_running_commands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            runtime = root / ".codex/runtime/codex-os"
            (root / ".git").mkdir()
            (root / "scripts/dev_tools").mkdir(parents=True)
            (root / "scripts/dev_tools/codex_os.py").write_text("fixture\n", encoding="utf-8")
            subprocess_args = args(
                "recommend-validation",
                root / "missing.sqlite",
                runtime,
                path=["scripts/dev_tools/codex_os.py"],
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_codex_os_command(root, subprocess_args), 0)

            output = stdout.getvalue()
            self.assertIn("recommendation only", output)
            self.assertIn("python3 -m compileall -q scripts/dev_tools scripts/task_loop", output)
            self.assertIn("python3 -m unittest scripts.dev_tools.test_codex_os", output)
            self.assertIn("./dev check diff", output)

    def test_template_write_backfills_task_reference(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            template = root / ".codex/templates/codex-evidence-template.md"
            template.parent.mkdir(parents=True)
            template.write_text("任务 ID: <task-id>\n", encoding="utf-8")
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-6",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Running",
                        write=True,
                    ),
                ),
                0,
            )

            output = root / ".codex/runtime/codex-os/evidence/AM-6.md"
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args("evidence", state_db, runtime, task_id="AM-6", output=str(output), write=True),
                ),
                0,
            )
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            self.assertEqual(registry["tasks"][0]["evidence_file"], ".codex/runtime/codex-os/evidence/AM-6.md")
            self.assertEqual(output.read_text(encoding="utf-8"), "任务 ID: AM-6\n")

    def test_template_output_refuses_workflow_execution_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            template = root / ".codex/templates/codex-evidence-template.md"
            template.parent.mkdir(parents=True)
            template.write_text("任务 ID: <task-id>\n", encoding="utf-8")

            blocked_outputs = (
                Path("workflow/versions/v9/execution/evidence.md"),
                Path("workflow/versions/v9/discussion/../execution/evidence.md"),
                root / "workflow/versions/v9/execution/evidence.md",
                Path(tmp).parent / "outside/workflow/versions/v9/execution/evidence.md",
            )
            for output in blocked_outputs:
                with self.assertRaises(Exception) as caught:
                    run_codex_os_command(
                        root,
                        args("evidence", state_db, runtime, task_id="AM-6", output=str(output), write=True),
                    )
                self.assertIn("must not write workflow/versions", str(caught.exception))

    def test_preflight_strict_blocks_high_risk_without_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-7",
                        project_name="AreaMatrix",
                        lane="Mission-Critical",
                        status="Ready",
                        validation="./dev check codex-os",
                        risk_level="High",
                        confirmation_status="Required",
                        write=True,
                    ),
                ),
                0,
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = run_codex_os_command(root, args("preflight", state_db, runtime, task_id="AM-7", strict=True))

            self.assertEqual(code, 1)
            self.assertIn("manual confirmation", stdout.getvalue())

    def test_new_resume_lifecycle_and_registry_strict_audit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )

            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "new",
                        state_db,
                        runtime,
                        task_id="AM-8",
                        title="Codex OS flow",
                        lane="Change",
                        status="Ready",
                        path=["scripts/dev_tools/codex_os.py"],
                        recommend_validation=True,
                        write=True,
                    ),
                ),
                0,
            )
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            self.assertIn("test_codex_os", registry["tasks"][0]["validation"])

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_codex_os_command(root, args("resume", state_db, runtime, task_id="AM-8")), 0)
            resume_output = stdout.getvalue()
            self.assertIn("Codex OS resume", resume_output)
            self.assertIn("python3 -m unittest scripts.dev_tools.test_codex_os", resume_output)
            self.assertIn("./dev check codex-os", resume_output)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_codex_os_command(root, args("lifecycle", state_db, runtime, task_id="AM-8")), 0)
            self.assertIn("task start", stdout.getvalue())

            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="update",
                        task_id="AM-8",
                        status="Done",
                        write=True,
                    ),
                ),
                0,
            )
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="status", strict=True)),
                1,
            )

    def test_subagent_plan_recommends_read_only_roles(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-9",
                        project_name="AreaMatrix",
                        lane="Mission-Critical",
                        status="Ready",
                        risk_level="High",
                        write=True,
                    ),
                ),
                0,
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(root, args("subagent-plan", state_db, runtime, task_id="AM-9", json=True)),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertTrue(data["subagents_recommended"])
            self.assertEqual(data["write_owner"], "Main Agent")
            self.assertEqual(data["input_paths"], [])
            self.assertIn("recommendation only", data["policy"])
            self.assertIn("Risk Reviewer", [role["role"] for role in data["roles"]])
            for role in data["roles"]:
                self.assertEqual(role["mode"], "read-only")
                self.assertIn("Modify files", role["forbidden_actions"])
                self.assertIn("copy_ready_prompt", role)
                self.assertIn("只阅读和归纳", role["copy_ready_prompt"])

    def test_start_flow_creates_and_starts_task_with_flow_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "start-flow",
                            state_db,
                            runtime,
                            task_id="AM-FLOW-1",
                            title="Flow task",
                            lane="Change",
                            path=["scripts/dev_tools/codex_os.py"],
                            write=True,
                            json=True,
                        ),
                    ),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertEqual(data["flow"], "start-flow")
            self.assertEqual(data["action"], "created_and_started")
            self.assertIn(data["result"], {"PASS", "WARN"})
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            task = registry["tasks"][0]
            self.assertEqual(task["task_id"], "AM-FLOW-1")
            self.assertEqual(task["status"], "Running")
            self.assertEqual(task["validation_status"], "Recommended")
            self.assertTrue((runtime / "start-flow.json").is_file())

    def test_start_flow_blocks_high_risk_without_confirmation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = run_codex_os_command(
                    root,
                    args(
                        "start-flow",
                        state_db,
                        runtime,
                        task_id="AM-FLOW-2",
                        title="Risky task",
                        lane="Mission-Critical",
                        risk_level="High",
                        confirmation_status="Required",
                        write=True,
                        strict=True,
                        json=True,
                    ),
                )

            self.assertEqual(code, 1)
            data = json.loads(stdout.getvalue())
            self.assertEqual(data["result"], "FAIL")
            self.assertEqual(data["action"], "blocked_by_preflight")
            self.assertIn("manual confirmation", json.dumps(data["preflight"], ensure_ascii=False))

    def test_start_flow_infers_lane_and_risk_from_natural_language_title(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "start-flow",
                            state_db,
                            runtime,
                            task_id="AM-NL",
                            title="Mission-Critical migration safety review",
                            write=False,
                            json=True,
                        ),
                    ),
                    0,
                )
            data = json.loads(stdout.getvalue())
            self.assertEqual(data["task"]["lane"], "Mission-Critical")
            self.assertEqual(data["task"]["risk_level"], "Mission-Critical")
            self.assertEqual(data["task"]["confirmation_status"], "Required")

    def test_run_validation_defaults_to_dry_run_and_can_write_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-FLOW-3",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Running",
                        validation="./dev check codex-os",
                        write=True,
                    ),
                ),
                0,
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "run-validation",
                            state_db,
                            runtime,
                            task_id="AM-FLOW-3",
                            path=["scripts/dev_tools/codex_os.py"],
                            write=True,
                            json=True,
                            execute=False,
                        ),
                    ),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertEqual(data["result"], "NOT-READY")
            self.assertFalse(data["execute"])
            self.assertTrue(all(item["result"] == "SKIPPED" for item in data["results"]))
            self.assertTrue(data["not_run"])
            self.assertIn("residual_prompt", data)
            self.assertIn("dirty_worktree_scope", data)
            self.assertIn("--execute --write", data["next_commands"][0])
            self.assertIn("report_path", data)
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            task = registry["tasks"][0]
            self.assertEqual(task["validation_status"], "Not-Ready")
            self.assertIn("validation_report_file", task)

    def test_run_validation_executes_compileall_recommendation_without_shell_globs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            (root / "scripts/dev_tools").mkdir(parents=True)
            (root / "scripts/task_loop").mkdir(parents=True)
            (root / "scripts/dev_tools/example.py").write_text("VALUE = 1\n", encoding="utf-8")
            (root / "scripts/task_loop/example.py").write_text("VALUE = 2\n", encoding="utf-8")
            dev = root / "dev"
            dev.write_text("#!/bin/sh\n[ \"$1 $2\" = \"check diff\" ] && exit 0\nexit 1\n", encoding="utf-8")
            dev.chmod(dev.stat().st_mode | stat.S_IXUSR)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-FLOW-3C",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Running",
                        validation="PYTHONDONTWRITEBYTECODE=1 python3 -m compileall -q scripts/dev_tools scripts/task_loop",
                        write=True,
                    ),
                ),
                0,
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "run-validation",
                            state_db,
                            runtime,
                            task_id="AM-FLOW-3C",
                            path=["notes/example.txt"],
                            execute=True,
                            json=True,
                        ),
                    ),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertEqual(data["result"], "PASS")
            self.assertIn("fingerprint", data)
            self.assertIn("digest", data["fingerprint"])
            compileall_results = [item for item in data["results"] if "python3 -m compileall" in item["command"]]
            self.assertEqual(len(compileall_results), 1)
            self.assertEqual(compileall_results[0]["result"], "PASS")

    def test_run_validation_reports_unrelated_dirty_paths_when_explicit_paths_are_supplied(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init"], cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            (root / "owned.txt").write_text("owned\n", encoding="utf-8")
            (root / "other.txt").write_text("other\n", encoding="utf-8")
            subprocess.run(["git", "add", "owned.txt", "other.txt"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-m", "init"], cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            (root / "owned.txt").write_text("owned changed\n", encoding="utf-8")
            (root / "other.txt").write_text("other changed\n", encoding="utf-8")
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args("run-validation", state_db, runtime, path=["owned.txt"], json=True),
                    ),
                    0,
                )
            data = json.loads(stdout.getvalue())
            self.assertIn("owned.txt", data["dirty_worktree_scope"]["covered_dirty_paths"])
            self.assertIn("other.txt", data["dirty_worktree_scope"]["unrelated_dirty_paths"])

    def test_run_validation_profiles_select_minimal_standard_and_full(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)

            outputs: dict[str, dict[str, object]] = {}
            for profile in ("minimal", "standard", "full", "auto"):
                stdout = io.StringIO()
                with contextlib.redirect_stdout(stdout):
                    self.assertEqual(
                        run_codex_os_command(
                            root,
                            args(
                                "run-validation",
                                state_db,
                                runtime,
                                task_id="AM-PROFILE",
                                path=["scripts/dev_tools/codex_os_automation.py"],
                                profile=profile,
                                json=True,
                            ),
                        ),
                        0,
                    )
                outputs[profile] = json.loads(stdout.getvalue())

            self.assertEqual(outputs["minimal"]["profile"], "minimal")
            self.assertEqual(outputs["standard"]["profile"], "standard")
            self.assertEqual(outputs["full"]["profile"], "full")
            self.assertEqual(outputs["auto"]["requested_profile"], "auto")
            self.assertEqual(outputs["auto"]["resolved_profile"], "full")
            self.assertEqual(outputs["auto"]["profile"], "full")
            self.assertLessEqual(len(outputs["minimal"]["selected_commands"]), len(outputs["standard"]["selected_commands"]))
            self.assertGreaterEqual(len(outputs["full"]["selected_commands"]), len(outputs["standard"]["selected_commands"]))
            self.assertIn("./dev check secrets", outputs["full"]["selected_commands"])
            self.assertIn("./dev check task-loop", outputs["full"]["selected_commands"])
            self.assertIn("./dev check task-loop", outputs["auto"]["selected_commands"])

    def test_run_validation_blocks_write_style_dev_commands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-FLOW-3B",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Running",
                        validation="./dev workflow init --version v9 --write",
                        write=True,
                    ),
                ),
                0,
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                code = run_codex_os_command(
                    root,
                    args(
                        "run-validation",
                        state_db,
                        runtime,
                        task_id="AM-FLOW-3B",
                        execute=True,
                        json=True,
                    ),
                )

            self.assertEqual(code, 1)
            data = json.loads(stdout.getvalue())
            self.assertEqual(data["result"], "BLOCKED")
            self.assertIn("read-only ./dev validation", data["results"][0]["note"])

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "run-validation",
                            state_db,
                            runtime,
                            task_id="AM-FLOW-3B",
                            execute=True,
                            write=True,
                            json=True,
                        ),
                    ),
                    1,
                )
            knowledge = json.loads((runtime / "failure-knowledge.json").read_text(encoding="utf-8"))
            self.assertTrue(knowledge["records"])
            self.assertEqual(knowledge["records"][-1]["result"], "BLOCKED")

    def test_flow_aggregates_start_and_validation_without_closing_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            dev = root / "dev"
            dev.write_text("#!/bin/sh\n[ \"$1\" = \"check\" ] && exit 0\nexit 1\n", encoding="utf-8")
            dev.chmod(dev.stat().st_mode | stat.S_IXUSR)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "flow",
                            state_db,
                            runtime,
                            task_id="AM-AGG",
                            title="Aggregate flow",
                            lane="Change",
                            path=[".codex/README.md"],
                            profile="minimal",
                            execute=True,
                            write=True,
                            json=True,
                        ),
                    ),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertEqual(data["flow"], "flow")
            self.assertEqual(data["validation"]["result"], "PASS")
            self.assertEqual(data["action"], "ready-to-close")
            self.assertIn("--from-latest-validation", data["next_commands"][0])
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            self.assertEqual(registry["tasks"][0]["status"], "Running")
            self.assertFalse((runtime / "close-flow.json").exists())

    def test_flow_close_when_pass_uses_latest_validation_and_finishes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            (root / ".codex/templates").mkdir(parents=True)
            (root / ".codex/templates/codex-evidence-template.md").write_text("Evidence <task-id>\n", encoding="utf-8")
            (root / ".codex/templates/codex-closeout-template.md").write_text("Closeout <task-id>\n", encoding="utf-8")
            dev = root / "dev"
            dev.write_text("#!/bin/sh\n[ \"$1\" = \"check\" ] && exit 0\nexit 1\n", encoding="utf-8")
            dev.chmod(dev.stat().st_mode | stat.S_IXUSR)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "flow",
                            state_db,
                            runtime,
                            task_id="AM-AGG-DONE",
                            title="Aggregate close flow",
                            lane="Change",
                            path=[".codex/README.md"],
                            profile="minimal",
                            execute=True,
                            close_when_pass=True,
                            write=True,
                            json=True,
                        ),
                    ),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertEqual(data["action"], "closed")
            self.assertEqual(data["close_flow"]["result"], "UPDATED")
            self.assertTrue(data["close_flow"]["from_latest_validation"])
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            self.assertEqual(registry["tasks"][0]["status"], "Done")
            self.assertTrue((runtime / "close-flow.json").is_file())

    def test_go_done_todo_and_now_wrappers_use_safe_existing_flows(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init"], cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            (root / "dev").write_text("#!/bin/sh\n[ \"$1\" = \"check\" ] && exit 0\nexit 1\n", encoding="utf-8")
            (root / "dev").chmod((root / "dev").stat().st_mode | stat.S_IXUSR)
            subprocess.run(["git", "add", "dev"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-m", "init"], cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "go",
                            state_db,
                            runtime,
                            task_id="AM-GO",
                            title="Go wrapper",
                            lane="Change",
                            path=[".codex/README.md"],
                            apply=True,
                            json=True,
                        ),
                    ),
                    0,
                )
            data = json.loads(stdout.getvalue())
            self.assertEqual(data["flow"], "flow")
            self.assertEqual(data["validation"]["result"], "PASS")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_codex_os_command(root, args("now", state_db, runtime, task_id="AM-GO", json=True)), 0)
            now = json.loads(stdout.getvalue())
            self.assertIn("can_close", now)
            self.assertTrue(now["validation_ready"])
            self.assertIn("completion_confidence", now)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_codex_os_command(root, args("done", state_db, runtime, task_id="AM-GO", json=True)), 0)
            done = json.loads(stdout.getvalue())
            self.assertEqual(done["flow"], "close-flow")
            self.assertEqual(done["result"], "UPDATED")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(run_codex_os_command(root, args("todo", state_db, runtime, action_items=True, json=True, limit=10)), 0)
            todo = json.loads(stdout.getvalue())
            self.assertEqual(todo["flow"], "ops-flow")
            self.assertIn("review_cards", todo)
            self.assertIn("manual_review_queue", todo["weekly"])

    def test_codex_os_refuses_workflow_execution_runtime_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            create_state_db(state_db)
            runtime = root / "workflow/versions/v9/execution"

            with self.assertRaises(Exception) as caught:
                run_codex_os_command(
                    root,
                    args(
                        "start-flow",
                        state_db,
                        runtime,
                        task_id="AM-FLOW-BLOCK",
                        title="Blocked runtime",
                        lane="Change",
                        write=True,
                    ),
                )

            self.assertIn("must not write workflow/versions", str(caught.exception))

            relative_runtimes = (
                Path("workflow/versions/v9/execution"),
                Path("workflow/versions/v9/execution/runtime"),
                Path("workflow/versions/v9/discussion/../execution/runtime"),
                Path(tmp).parent / "outside/workflow/versions/v9/execution/runtime",
            )
            for relative_runtime in relative_runtimes:
                with self.assertRaises(Exception) as relative:
                    run_codex_os_command(
                        root,
                        args(
                            "ops-flow",
                            state_db,
                            relative_runtime,
                            write=True,
                        ),
                    )
                self.assertIn("must not write workflow/versions", str(relative.exception))

            normalized_runtime = root / "workflow/versions/v9/discussion/../execution/runtime"
            with self.assertRaises(Exception) as normalized:
                run_codex_os_command(
                    root,
                    args(
                        "ops-flow",
                        state_db,
                        normalized_runtime,
                        write=True,
                    ),
                )
            self.assertIn("must not write workflow/versions", str(normalized.exception))

    def test_repair_plan_uses_diagnose_and_validation_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-FLOW-4",
                        project_name="AreaMatrix",
                        lane="Mission-Critical",
                        status="Running",
                        risk_level="High",
                        confirmation_status="Required",
                        write=True,
                    ),
                ),
                0,
            )
            report = {
                "results": [
                    {
                        "command": "./dev check codex-os",
                        "result": "FAIL",
                        "note": "fixture failure",
                    }
                ]
            }
            report_path = runtime / "validation/failed.json"
            report_path.parent.mkdir(parents=True)
            report_path.write_text(json.dumps(report), encoding="utf-8")

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "repair-plan",
                            state_db,
                            runtime,
                            task_id="AM-FLOW-4",
                            validation_report=str(report_path),
                            json=True,
                        ),
                    ),
                    0,
                )

            data = json.loads(stdout.getvalue())
            categories = [step["category"] for step in data["steps"]]
            self.assertIn("manual-confirmation", categories)
            self.assertIn("validation", categories)
            self.assertIn("failure_knowledge", data)

    def test_repair_plan_flags_dry_run_coverage_and_failure_knowledge(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)), 0)
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-REPAIR-COVERAGE",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Running",
                        validation="./dev check codex-os",
                        write=True,
                    ),
                ),
                0,
            )
            report_path = runtime / "validation/dry.json"
            report_path.parent.mkdir(parents=True)
            report_path.write_text(
                json.dumps(
                    {
                        "flow": "run-validation",
                        "task_id": "AM-REPAIR-COVERAGE",
                        "execute": False,
                        "result": "NOT-READY",
                        "results": [{"command": "./dev check codex-os", "result": "SKIPPED", "exit_code": None}],
                        "not_run": [{"command": "./dev check codex-os", "reason": "dry-run", "blocks_done": True}],
                        "validation_summary": "./dev check codex-os: SKIPPED",
                    }
                ),
                encoding="utf-8",
            )
            (runtime / "failure-knowledge.json").write_text(
                json.dumps(
                    {
                        "records": [
                            {
                                "recorded_at": "2026-06-29T00:00:00Z",
                                "task_id": "AM-OLD",
                                "command": "./dev check codex-os",
                                "result": "FAIL",
                                "note": "old failure",
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "repair-plan",
                            state_db,
                            runtime,
                            task_id="AM-REPAIR-COVERAGE",
                            validation_report=str(report_path),
                            json=True,
                        ),
                    ),
                    0,
                )
            data = json.loads(stdout.getvalue())
            categories = [step["category"] for step in data["steps"]]
            self.assertIn("unrun-checks", categories)
            self.assertTrue(data["failure_knowledge"])

    def test_close_flow_writes_evidence_closeout_and_finishes_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            (root / ".codex/templates").mkdir(parents=True)
            (root / ".codex/templates/codex-evidence-template.md").write_text("Evidence <task-id>\n", encoding="utf-8")
            (root / ".codex/templates/codex-closeout-template.md").write_text("Closeout <task-id>\n", encoding="utf-8")
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-FLOW-5",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Verifying",
                        validation="./dev check codex-os",
                        write=True,
                    ),
                ),
                0,
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "close-flow",
                            state_db,
                            runtime,
                            task_id="AM-FLOW-5",
                            status="Done",
                            validation="./dev check codex-os: PASS",
                            archive_recommendation="review",
                            write=True,
                            json=True,
                        ),
                    ),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertEqual(data["result"], "UPDATED")
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            task = registry["tasks"][0]
            self.assertEqual(task["status"], "Done")
            self.assertEqual(task["validation_status"], "Pass")
            self.assertTrue((root / task["evidence_file"]).is_file())
            self.assertTrue((root / task["closeout_file"]).is_file())
            self.assertTrue((root / task["handoff_file"]).is_file())
            self.assertIn("completion_confidence", data)
            self.assertIn("handoff_summary_file", data)

    def test_close_flow_done_rejects_recommended_or_dry_run_validation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(
                run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)),
                0,
            )
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-FLOW-6",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Verifying",
                        validation="./dev check codex-os",
                        write=True,
                    ),
                ),
                0,
            )

            with self.assertRaises(Exception) as missing:
                run_codex_os_command(
                    root,
                    args("close-flow", state_db, runtime, task_id="AM-FLOW-6", status="Done", write=True),
                )
            self.assertIn("explicit fresh --validation", str(missing.exception))

            with self.assertRaises(Exception) as dry_run:
                run_codex_os_command(
                    root,
                    args(
                        "close-flow",
                        state_db,
                        runtime,
                        task_id="AM-FLOW-6",
                        status="Done",
                        validation="./dev check codex-os: SKIPPED; result: NOT-READY",
                        write=True,
                    ),
                )
            self.assertIn("fresh PASS/OK", str(dry_run.exception))

    def test_close_flow_can_use_latest_executed_pass_validation_for_same_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            (root / ".codex/templates").mkdir(parents=True)
            (root / ".codex/templates/codex-evidence-template.md").write_text("Evidence <task-id>\n", encoding="utf-8")
            (root / ".codex/templates/codex-closeout-template.md").write_text("Closeout <task-id>\n", encoding="utf-8")
            self.assertEqual(run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)), 0)
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-LATEST",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Verifying",
                        write=True,
                    ),
                ),
                0,
            )
            report_path = runtime / "validation/latest-pass.json"
            report_path.parent.mkdir(parents=True)
            report_path.write_text(
                json.dumps(
                    {
                        "generated_at": "2026-06-29T00:00:00Z",
                        "flow": "run-validation",
                        "task_id": "AM-LATEST",
                        "profile": "standard",
                        "execute": True,
                        "result": "PASS",
                        "results": [{"command": "./dev check codex-os", "result": "PASS", "exit_code": 0}],
                        "validation_summary": "./dev check codex-os: PASS",
                    }
                ),
                encoding="utf-8",
            )

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args(
                            "close-flow",
                            state_db,
                            runtime,
                            task_id="AM-LATEST",
                            status="Done",
                            from_latest_validation=True,
                            write=True,
                            json=True,
                        ),
                    ),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertTrue(data["from_latest_validation"])
            self.assertEqual(data["latest_validation_report"]["result"], "PASS")
            registry = json.loads((runtime / "task-registry.json").read_text(encoding="utf-8"))
            task = registry["tasks"][0]
            self.assertEqual(task["status"], "Done")
            self.assertEqual(task["validation"], "./dev check codex-os: PASS")

    def test_close_flow_latest_validation_rejects_dry_run_fail_and_wrong_task(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)), 0)
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-STRICT",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Verifying",
                        write=True,
                    ),
                ),
                0,
            )
            validation_dir = runtime / "validation"
            validation_dir.mkdir(parents=True)
            fixtures = [
                ("wrong.json", "AM-OTHER", True, "PASS", [{"command": "./dev check codex-os", "result": "PASS", "exit_code": 0}], "./dev check codex-os: PASS"),
                ("dry.json", "AM-STRICT", False, "NOT-READY", [{"command": "./dev check codex-os", "result": "SKIPPED", "exit_code": None}], "./dev check codex-os: SKIPPED"),
                ("fail.json", "AM-STRICT", True, "FAIL", [{"command": "./dev check codex-os", "result": "FAIL", "exit_code": 1}], "./dev check codex-os: FAIL"),
            ]
            for name, task_id, execute, result, results, summary in fixtures:
                (validation_dir / name).write_text(
                    json.dumps(
                        {
                            "flow": "run-validation",
                            "task_id": task_id,
                            "execute": execute,
                            "result": result,
                            "results": results,
                            "validation_summary": summary,
                        }
                    ),
                    encoding="utf-8",
                )

            with self.assertRaises(Exception) as caught:
                run_codex_os_command(
                    root,
                    args("close-flow", state_db, runtime, task_id="AM-STRICT", status="Done", from_latest_validation=True, write=True),
                )
            self.assertIn("latest validation report", str(caught.exception))
            self.assertIn("FAIL", str(caught.exception))

    def test_close_flow_latest_validation_rejects_older_pass_after_new_fail(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)), 0)
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-REGRESSED",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Verifying",
                        write=True,
                    ),
                ),
                0,
            )
            validation_dir = runtime / "validation"
            validation_dir.mkdir(parents=True)
            pass_path = validation_dir / "a-pass.json"
            pass_path.write_text(
                json.dumps(
                    {
                        "flow": "run-validation",
                        "task_id": "AM-REGRESSED",
                        "execute": True,
                        "result": "PASS",
                        "results": [{"command": "./dev check codex-os", "result": "PASS", "exit_code": 0}],
                        "validation_summary": "./dev check codex-os: PASS",
                    }
                ),
                encoding="utf-8",
            )
            fail_path = validation_dir / "z-fail.json"
            fail_path.write_text(
                json.dumps(
                    {
                        "flow": "run-validation",
                        "task_id": "AM-REGRESSED",
                        "execute": True,
                        "result": "FAIL",
                        "results": [{"command": "./dev check codex-os", "result": "FAIL", "exit_code": 1}],
                        "validation_summary": "./dev check codex-os: FAIL",
                    }
                ),
                encoding="utf-8",
            )
            pass_path.touch()
            os.utime(pass_path, (1_000_000, 1_000_000))
            os.utime(fail_path, (1_000_010, 1_000_010))

            with self.assertRaises(Exception) as caught:
                run_codex_os_command(
                    root,
                    args("close-flow", state_db, runtime, task_id="AM-REGRESSED", status="Done", from_latest_validation=True, write=True),
                )
            self.assertIn("latest validation report", str(caught.exception))
            self.assertIn("FAIL", str(caught.exception))

    def test_close_flow_latest_validation_rejects_stale_fingerprint(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            subprocess.run(["git", "init"], cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=root, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=root, check=True)
            (root / "dev").write_text("#!/bin/sh\n[ \"$1\" = \"check\" ] && exit 0\nexit 1\n", encoding="utf-8")
            (root / "dev").chmod((root / "dev").stat().st_mode | stat.S_IXUSR)
            (root / "tracked.txt").write_text("before\n", encoding="utf-8")
            subprocess.run(["git", "add", "tracked.txt", "dev"], cwd=root, check=True)
            subprocess.run(["git", "commit", "-m", "init"], cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)), 0)
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-STALE",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Verifying",
                        validation="./dev check codex-os",
                        write=True,
                    ),
                ),
                0,
            )
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(
                        root,
                        args("run-validation", state_db, runtime, task_id="AM-STALE", path=["tracked.txt"], execute=True, write=True, json=True),
                    ),
                    0,
                )
            (root / "tracked.txt").write_text("after\n", encoding="utf-8")

            with self.assertRaises(Exception) as caught:
                run_codex_os_command(
                    root,
                    args("close-flow", state_db, runtime, task_id="AM-STALE", status="Done", from_latest_validation=True, write=True),
                )
            self.assertIn("stale", str(caught.exception))

    def test_close_flow_latest_validation_rejects_empty_results(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)), 0)
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-EMPTY",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Verifying",
                        write=True,
                    ),
                ),
                0,
            )
            validation_dir = runtime / "validation"
            validation_dir.mkdir(parents=True)
            (validation_dir / "empty.json").write_text(
                json.dumps(
                    {
                        "flow": "run-validation",
                        "task_id": "AM-EMPTY",
                        "execute": True,
                        "result": "PASS",
                        "results": [],
                        "validation_summary": "./dev check codex-os: PASS",
                    }
                ),
                encoding="utf-8",
            )

            with self.assertRaises(Exception) as caught:
                run_codex_os_command(
                    root,
                    args("close-flow", state_db, runtime, task_id="AM-EMPTY", status="Done", from_latest_validation=True, write=True),
                )
            self.assertIn("no command results", str(caught.exception))

    def test_ops_flow_is_advisory_and_does_not_archive_threads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            conn = sqlite3.connect(state_db)
            titles_before = conn.execute("SELECT id, title FROM threads ORDER BY id").fetchall()
            conn.close()

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(root, args("ops-flow", state_db, runtime, write=True, json=True, limit=10)),
                    0,
                )

            data = json.loads(stdout.getvalue())
            self.assertEqual(data["flow"], "ops-flow")
            self.assertIn("advisory", data["policy"])
            self.assertTrue((runtime / "ops-flow.json").is_file())
            conn = sqlite3.connect(state_db)
            archived_count = conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 1").fetchone()[0]
            titles_after = conn.execute("SELECT id, title FROM threads ORDER BY id").fetchall()
            conn.close()
            self.assertEqual(archived_count, 1)
            self.assertEqual(titles_after, titles_before)

    def test_ops_flow_action_items_are_advisory_and_persist_full_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            state_db = root / "state.sqlite"
            runtime = root / ".codex/runtime/codex-os"
            create_state_db(state_db)
            self.assertEqual(run_codex_os_command(root, args("registry", state_db, runtime, registry_command="init", write=True)), 0)
            self.assertEqual(
                run_codex_os_command(
                    root,
                    args(
                        "registry",
                        state_db,
                        runtime,
                        registry_command="add",
                        task_id="AM-OPS",
                        project_name="AreaMatrix",
                        lane="Change",
                        status="Done",
                        write=True,
                    ),
                ),
                0,
            )
            conn = sqlite3.connect(state_db)
            titles_before = conn.execute("SELECT id, title FROM threads ORDER BY id").fetchall()
            conn.close()

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(
                    run_codex_os_command(root, args("ops-flow", state_db, runtime, write=True, json=False, action_items=True, limit=10)),
                    0,
                )

            self.assertIn("Action Items", stdout.getvalue())
            data = json.loads((runtime / "ops-flow.json").read_text(encoding="utf-8"))
            self.assertIn("archive_review", data)
            self.assertIn("weekly", data)
            self.assertTrue(data["action_items"])
            self.assertTrue(all("recommended_command" in item for item in data["action_items"]))
            self.assertTrue(all("preview_command" in item for item in data["action_items"]))
            self.assertTrue(all("decision_options" in item for item in data["action_items"]))
            self.assertTrue(data["review_cards"])
            self.assertTrue(all("review_checklist" in card for card in data["review_cards"]))
            conn = sqlite3.connect(state_db)
            archived_count = conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 1").fetchone()[0]
            titles_after = conn.execute("SELECT id, title FROM threads ORDER BY id").fetchall()
            conn.close()
            self.assertEqual(archived_count, 1)
            self.assertEqual(titles_after, titles_before)


if __name__ == "__main__":
    unittest.main()
