"""Regression tests for workflow template hardening gates."""

from __future__ import annotations

import contextlib
import io
import shutil
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

from scripts.dev_tools.changes import parse_yaml_subset
from scripts.dev_tools.workflow import run_workflow_doctor, validate_queue_gate
from scripts.dev_tools.workflow_baseline import build_baseline_entries, validate_baseline
from scripts.dev_tools.changes import FeatureRecord
from scripts.dev_tools.promotion import (
    PromotionConfig,
    build_promotion_tasks,
    promotion_apply_artifacts,
    validate_apply,
    validate_promotion_preview_config,
)
from scripts.dev_tools.workflow_projection import validate_closeout, validate_projection
from scripts.dev_tools.workflow_states import ARTIFACT_STATUSES


ROOT = Path(__file__).resolve().parents[2]


def copy_tree(src: Path, dst: Path) -> None:
    if src.is_dir():
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)


class WorkflowHardeningTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for rel in [
            "workflow",
            "scripts/dev_tools",
            "scripts/task_loop",
            "workflow/versions/v1-mvp/execution/_shared",
        ]:
            copy_tree(ROOT / rel, self.root / rel)
        for rel in ["scripts/__init__.py"]:
            source = ROOT / rel
            if source.exists():
                copy_tree(source, self.root / rel)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_artifact_status_model_rejects_old_values(self) -> None:
        for status in ["candidate", "planned", "archived", "partial", "approved"]:
            self.assertNotIn(status, ARTIFACT_STATUSES)

    def test_queue_doctor_rejects_legacy_candidate_status(self) -> None:
        queue = self.root / "workflow/versions/v-template/queue/template-docs-contract/queue.yaml"
        queue.write_text(queue.read_text(encoding="utf-8").replace("status: ready", "status: candidate", 1), encoding="utf-8")

        errors, _ = validate_queue_gate(self.root, "v-template")

        self.assertTrue(any("status must be one of" in error for error in errors), errors)

    def test_workflow_doctor_rejects_missing_late_lifecycle_templates(self) -> None:
        for name in ["approval.yaml", "apply.yaml", "projection.yaml", "closeout.yaml"]:
            (self.root / "workflow/templates" / name).unlink()

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = run_workflow_doctor(self.root, Namespace())

        self.assertNotEqual(code, 0)
        output = stdout.getvalue()
        self.assertIn("missing workflow template", output)
        self.assertIn("approval.yaml", output)
        self.assertIn("closeout.yaml", output)

    def test_baseline_doctor_rejects_hash_drift(self) -> None:
        baseline = self.root / "workflow/versions/v-template/baseline/docs.yaml"
        text = baseline.read_text(encoding="utf-8")
        baseline.write_text(text.replace("sha256: '", "sha256: '0000", 1), encoding="utf-8")

        errors, _ = validate_baseline(self.root, "v-template", require_file=True)

        self.assertTrue(any("docs drift detected" in error for error in errors), errors)

    def test_baseline_includes_exact_doc_without_change_entry(self) -> None:
        decisions = self.root / "workflow/versions/v-template/discussion/decisions.yaml"
        text = decisions.read_text(encoding="utf-8")
        decisions.write_text(
            text.replace(
                "  - workflow/pipeline.md\n",
                "  - workflow/pipeline.md\n  - workflow/README.md\n",
                1,
            ),
            encoding="utf-8",
        )

        errors, entries = build_baseline_entries(self.root, "v-template")

        self.assertEqual(errors, [])
        readme_entries = [entry for entry in entries if entry.file == "workflow/README.md"]
        self.assertEqual(len(readme_entries), 1)
        self.assertEqual(readme_entries[0].source, "discussion:exact_docs")

    def test_projection_and_closeout_reject_legacy_partial_status(self) -> None:
        projection = self.root / "workflow/versions/v-template/projection/projection.yaml"
        projection.write_text(projection.read_text(encoding="utf-8").replace("status: blocked", "status: partial", 1), encoding="utf-8")
        closeout = self.root / "workflow/versions/v-template/closeout/closeout.yaml"
        closeout.write_text(closeout.read_text(encoding="utf-8").replace("status: blocked", "status: partial", 1), encoding="utf-8")

        projection_errors, _ = validate_projection(self.root, "v-template", require_file=True)
        closeout_errors, _ = validate_closeout(self.root, "v-template", require_file=True)

        self.assertTrue(any("status must be one of" in error for error in projection_errors), projection_errors)
        self.assertTrue(any("status must be one of" in error for error in closeout_errors), closeout_errors)

    def test_promotion_preview_shape_declares_no_live_writes(self) -> None:
        promotion = self.root / "workflow/versions/v-template/promotion/promotion.yaml"
        data = parse_yaml_subset(promotion.read_text(encoding="utf-8"), promotion)

        self.assertEqual(data.get("target_kind"), "preview-only")
        self.assertIs(data.get("writes_live_queue"), False)
        self.assertIs(data.get("template_reference"), True)
        self.assertIs(data.get("apply_allowed"), False)

    def test_real_version_rejects_placeholder_target_queue(self) -> None:
        errors = validate_promotion_preview_config(
            "fixture: promotion_preview",
            {"target_queue": "workflow/versions/<version>/execution", "live_mapping": "pending"},
            "v2",
        )

        self.assertTrue(any("workflow/versions/v2/execution" in error for error in errors), errors)

    def test_promotion_apply_is_version_local_and_bootstraps_runtime(self) -> None:
        config = PromotionConfig("workflow/versions/v2/execution", "phase-0", "0-1", "v2-planning", 1)
        change = self.root / "workflow/versions/v-template/changes/template-contracts.yaml"
        data = parse_yaml_subset(change.read_text(encoding="utf-8"), change)
        record = FeatureRecord(change, data["id"], data["features"][0])

        tasks = build_promotion_tasks(self.root, "v2", config, [record], "None")
        errors = validate_apply(self.root, "v2", tasks)
        artifacts = promotion_apply_artifacts(self.root, "v2", tasks)
        by_path = {artifact.path.resolve().relative_to(self.root.resolve()).as_posix(): artifact.content for artifact in artifacts}

        self.assertEqual(errors, [])
        self.assertIn("workflow/versions/v2/execution/_shared/prompt_pipeline.py", by_path)
        self.assertIn("workflow/versions/v2/execution/_shared/progress.json", by_path)
        self.assertIn('"tasks": {}', by_path["workflow/versions/v2/execution/_shared/progress.json"])
        self.assertNotIn("4-3/task-165", by_path["workflow/versions/v2/execution/_shared/progress.json"])


if __name__ == "__main__":
    unittest.main()
