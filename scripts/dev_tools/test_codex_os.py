"""Regression tests for Codex Operating System developer tools."""

from __future__ import annotations

from argparse import Namespace
from datetime import datetime, timezone
import contextlib
import io
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

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
        "output": None,
        "recommend_validation": False,
    }
    values.update(extra)
    return Namespace(**values)


class CodexOsToolsTest(unittest.TestCase):
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
                        title="Codex OS v2",
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
            self.assertIn("Codex OS resume", stdout.getvalue())

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


if __name__ == "__main__":
    unittest.main()
