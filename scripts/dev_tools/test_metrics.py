"""Regression tests for local build feedback metrics."""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path

from scripts.dev_tools.metrics import (
    CARGO_LOCK_METRICS_FILE,
    CORE_SDK_METRICS_FILE,
    FEEDBACK_METRICS_FILE,
    METRICS_MAX_RECORDS,
    build_metrics_summary,
    feedback_metrics_summary,
    record_feedback_metric,
    record_metric,
    run_build_metrics,
)


class BuildMetricsTest(unittest.TestCase):
    def test_feedback_summary_reports_nearest_rank_percentiles_and_readiness(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for duration in range(1, 21):
                self.assertTrue(
                    record_feedback_metric(
                        root,
                        path="canvas",
                        cohort="ui-catalog-canvas-warm",
                        duration_seconds=float(duration),
                    )
                )
            summary = feedback_metrics_summary(root)
            cohort = summary["paths"]["canvas"]["cohorts"]["ui-catalog-canvas-warm"]
            self.assertEqual(cohort["p50_seconds"], 10.5)
            self.assertEqual(cohort["p95_seconds"], 19.0)
            self.assertTrue(cohort["baseline_ready"])
            self.assertTrue(summary["paths"]["canvas"]["baseline_ready"])
            self.assertTrue((root / ".build/metrics" / FEEDBACK_METRICS_FILE).is_file())

    def test_legacy_mixed_feedback_never_becomes_a_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / ".build/metrics/developer-feedback.jsonl"
            path.parent.mkdir(parents=True)
            records = [
                {
                    "schema_version": 1,
                    "recorded_at": datetime.now(timezone.utc).isoformat(),
                    "path": "build",
                    "status": "success",
                    "duration_seconds": float(duration),
                }
                for duration in range(1, 21)
            ]
            path.write_text("\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8")

            summary = feedback_metrics_summary(root)
            legacy = summary["paths"]["build"]["cohorts"]["legacy-mixed"]
            self.assertEqual(legacy["successful_sample_count"], 20)
            self.assertFalse(legacy["baseline_ready"])
            self.assertFalse(summary["paths"]["build"]["baseline_ready"])

    def test_record_schema_contains_stable_diagnostic_dimensions(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)

            self.assertTrue(
                record_metric(
                    root,
                    CARGO_LOCK_METRICS_FILE,
                    {"kind": "cargo_lock", "operation": "test", "hold_seconds": 0.25},
                )
            )

            record = json.loads(
                (root / ".build/metrics/cargo-lock.jsonl").read_text(encoding="utf-8")
            )
            self.assertEqual(
                {
                    "recorded_at",
                    "kind",
                    "operation",
                    "status",
                    "duration_seconds",
                    "fingerprint",
                    "toolchain",
                    "arch",
                }
                - record.keys(),
                set(),
            )
            self.assertEqual(record["duration_seconds"], 0.25)

    def test_recording_prunes_old_records_and_caps_file_size(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / ".build/metrics/core-sdk.jsonl"
            path.parent.mkdir(parents=True)
            now = datetime.now(timezone.utc)
            old = (now - timedelta(days=31)).isoformat().replace("+00:00", "Z")
            recent = now.isoformat().replace("+00:00", "Z")
            records = [
                json.dumps({"schema_version": 1, "recorded_at": old, "index": -1}),
                *(
                    json.dumps({"schema_version": 1, "recorded_at": recent, "index": index})
                    for index in range(METRICS_MAX_RECORDS)
                ),
            ]
            path.write_text("\n".join(records) + "\n", encoding="utf-8")

            self.assertTrue(
                record_metric(root, CORE_SDK_METRICS_FILE, {"kind": "core_sdk", "operation": "build"})
            )

            retained = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
            self.assertEqual(len(retained), METRICS_MAX_RECORDS)
            self.assertNotIn(-1, {record.get("index") for record in retained})
            self.assertNotIn(0, {record.get("index") for record in retained})

    def test_summary_calculates_cache_and_lock_contention_rates(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.assertTrue(
                record_metric(
                    root,
                    CORE_SDK_METRICS_FILE,
                    {
                        "kind": "core_sdk",
                        "operation": "build",
                        "status": 0,
                        "cache": "hit",
                        "lane": "sdk",
                        "lock_wait_seconds": 0.0,
                    },
                )
            )
            self.assertTrue(
                record_metric(
                    root,
                    CORE_SDK_METRICS_FILE,
                    {
                        "kind": "core_sdk",
                        "operation": "build",
                        "status": 0,
                        "cache": "miss",
                        "lane": "sdk",
                        "lock_wait_seconds": 0.125,
                    },
                )
            )
            self.assertTrue(
                record_metric(
                    root,
                    CORE_SDK_METRICS_FILE,
                    {
                        "kind": "core_sdk",
                        "operation": "verify",
                        "status": 0,
                        "cache": "verify",
                        "lane": "sdk",
                    },
                )
            )
            self.assertTrue(
                record_metric(
                    root,
                    CARGO_LOCK_METRICS_FILE,
                    {"kind": "cargo_lock", "lane": "sdk", "operation": "first", "wait_seconds": 0.0},
                )
            )
            self.assertTrue(
                record_metric(
                    root,
                    CARGO_LOCK_METRICS_FILE,
                    {"kind": "cargo_lock", "lane": "sdk", "operation": "second", "wait_seconds": 0.2},
                )
            )

            summary = build_metrics_summary(root)

            self.assertEqual(summary["core_sdk"]["sample_count"], 2)
            self.assertEqual(summary["core_sdk"]["cache_hit_rate_percent"], 50.0)
            self.assertEqual(summary["cargo_lock"]["contended_sample_count"], 1)
            self.assertEqual(summary["cargo_lock"]["contention_rate_percent"], 50.0)

    def test_invalid_records_are_reported_without_blocking_summary(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / ".build/metrics/core-sdk.jsonl"
            path.parent.mkdir(parents=True)
            path.write_text("not-json\n", encoding="utf-8")

            summary = build_metrics_summary(root)

            self.assertEqual(summary["invalid_record_count"], 1)
            self.assertEqual(summary["core_sdk"]["sample_count"], 0)

    def test_invalid_records_fail_only_in_strict_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / ".build/metrics/core-sdk.jsonl"
            path.parent.mkdir(parents=True)
            path.write_text("not-json\n", encoding="utf-8")

            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(run_build_metrics(root), 0)
                self.assertEqual(run_build_metrics(root, strict=True), 1)

            self.assertIn("WARNING invalid_record_count=1", output.getvalue())

    def test_json_output_is_machine_readable(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(run_build_metrics(Path(temp), json_output=True), 0)

            payload = json.loads(output.getvalue())
            self.assertEqual(payload["mode"], "build_metrics")
            self.assertIn("core_sdk", payload)
