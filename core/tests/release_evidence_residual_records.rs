const CHECKLIST: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/release-checklist.md");
const ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/icloud-placeholder-smoke-evidence.md");
const RELEASE_GATE_REVIEW_TASK05: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/release-gate-review-task05.md");
const DISTRIBUTION_SIGNING_NOTARIZATION: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md");
const FINAL_TAG_RELEASE_EVIDENCE: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/final-tag-release-evidence.md");
const ALPHA_FEEDBACK_ROUTE: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/alpha-feedback-route.md");
const RELEASE_NOTES_010: &str =
    include_str!("../../workflow/versions/v1-mvp/evidence/release-notes/release-notes-0.1.0.md");
const V1_RESIDUALS: &str = include_str!("../../workflow/versions/v1-mvp/residuals/residuals.yaml");
const V1_RELEASE_RESIDUALS: &str =
    include_str!("../../workflow/versions/v1-mvp/residuals/release-evidence.md");
const GLOBAL_RESIDUALS_README: &str = include_str!("../../workflow/residuals/README.md");
const GLOBAL_RESIDUALS_YAML: &str = include_str!("../../workflow/residuals/residuals.yaml");
const TASK_RESIDUAL_INDEX: &str = include_str!("../../tasks/indexes/residuals.md");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected release evidence residual record to contain `{needle}`"
    );
}

#[test]
fn distribution_signing_record_stays_blocked_until_real_evidence_exists() {
    assert_contains(CHECKLIST, "distribution-signing-notarization.md");
    assert_contains(CHECKLIST, "`preflight_json.status: BLOCKED`");
    assert_contains(CHECKLIST, "`closes_residual: false`");
    assert_contains(CHECKLIST, "`release_gate: block_if_any_pending_or_blocked`");

    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "当前结论：**不关闭 `v1-rl-003`**",
    );
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "schema_version: 1");
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "mode: distribution_signing_notarization_record",
    );
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "residual_id: v1-rl-003");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "preflight_json:");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "artifact_probe:");
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "mode: distribution_artifact_probe",
    );
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "probe_status: pending");
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "distribution_requirements_status: blocked",
    );
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "status_semantics: probe.status captured is not a distribution pass",
    );
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "status: BLOCKED");
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "Developer ID Application identity",
    );
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "notarytool keychain profile",
    );
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "codesign_developer_id_team:",
    );
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "notarytool_submission:");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "log_url: null");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "stapler_app:");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "formal_dmg:");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "sha256: null");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "stapler_dmg:");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "spctl_assess:");
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "clean_mac_first_launch:");
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "gatekeeper_result: pending",
    );
    assert_contains(DISTRIBUTION_SIGNING_NOTARIZATION, "closes_residual: false");
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "release_gate: block_if_any_pending_or_blocked",
    );
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "任何 ad-hoc signed `.app`",
    );
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "只有上述字段全部为真实 `pass` / `accepted`",
    );
    assert_contains(
        DISTRIBUTION_SIGNING_NOTARIZATION,
        "`distribution_requirements.status` 在正式证据不足时仍为 `blocked`",
    );
}

#[test]
fn icloud_placeholder_smoke_record_stays_blocked_until_real_manual_smoke() {
    assert_contains(CHECKLIST, "icloud-placeholder-smoke-evidence.md");
    assert_contains(CHECKLIST, "`metadata_probe.status: pending`");
    assert_contains(CHECKLIST, "`ui_retry.status: pending`");
    assert_contains(CHECKLIST, "`db_row_result: pending`");
    assert_contains(CHECKLIST, "`smoke_evidence_gate: BLOCKED`");
    assert_contains(
        CHECKLIST,
        "`./dev release icloud-placeholder-smoke-audit --json`",
    );

    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "当前结论：**不关闭 `v1-rl-002`**",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "schema_version: 1");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "mode: icloud_placeholder_smoke_record",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "residual_id: v1-rl-002");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "manual_evidence_id: M-02",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "smoke_audit:");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "command: ./dev release icloud-placeholder-smoke-audit --json",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "smoke_evidence_gate: BLOCKED",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "audit_side_effects:");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "icloud_download_attempted: false",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "network_attempted: false",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "metadata_probe:");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "mode: icloud_placeholder_metadata_probe",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "path_redaction: true");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "raw_path_fields_present: false",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "download_attempted: false",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "file_content_read_attempted: false",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "file_write_attempted: false",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "db_write_attempted: false",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "project_write_attempted: false",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "areamatrix_metadata_write_attempted: false",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "environment:");
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "icloud_drive: blocked");
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "icloud_account: pending");
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "ui_retry:");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "action: Download & retry",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "repo_and_db_evidence:");
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "db_row_result: pending");
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "user_file_invariants:");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "placeholder_marker_not_silently_deleted: pending",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "no_readme_or_areamatrix_overwrite: pending",
    );
    assert_contains(ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE, "closes_residual: false");
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "blocked_until_real_icloud_download_retry_and_db_evidence_pass",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "任何合成 `.icloud` marker",
    );
    assert_contains(
        ICLOUD_PLACEHOLDER_SMOKE_EVIDENCE,
        "只有所有字段都是真实 `pass`",
    );
}

#[test]
fn residual_indexes_reference_structured_release_records_without_closing_them() {
    assert_contains(
        V1_RESIDUALS,
        "workflow/versions/v1-mvp/evidence/icloud-placeholder-smoke-evidence.md",
    );
    assert_contains(
        V1_RESIDUALS,
        "workflow/versions/v1-mvp/evidence/release-gate-review-task05.md",
    );
    assert_contains(V1_RESIDUALS, "metadata_probe, UI retry, DB row evidence");
    assert_contains(
        V1_RESIDUALS,
        "workflow/versions/v1-mvp/evidence/distribution-signing-notarization.md",
    );
    assert_contains(
        V1_RESIDUALS,
        "workflow/versions/v1-mvp/evidence/final-tag-release-evidence.md",
    );
    assert_contains(
        V1_RESIDUALS,
        "workflow/versions/v1-mvp/evidence/alpha-feedback-route.md",
    );
    assert_contains(V1_RESIDUALS, "closes_residual=false");
    assert_contains(V1_RESIDUALS, "release_gate=block_if_any_pending");
    assert_contains(V1_RELEASE_RESIDUALS, "icloud-placeholder-smoke-evidence.md");
    assert_contains(V1_RELEASE_RESIDUALS, "release-gate-review-task05.md");
    assert_contains(V1_RELEASE_RESIDUALS, "distribution-signing-notarization.md");
    assert_contains(V1_RELEASE_RESIDUALS, "final-tag-release-evidence.md");
    assert_contains(V1_RELEASE_RESIDUALS, "alpha-feedback-route.md");
    assert_contains(
        CHECKLIST,
        "[v1 release residuals](../residuals/release-evidence.md)",
    );
    assert_contains(
        CHECKLIST,
        "[global residual ledger](../../../residuals/README.md)",
    );
    assert_contains(
        CHECKLIST,
        "[task-facing residual index](../../../../tasks/indexes/residuals.md)",
    );
    assert_contains(
        GLOBAL_RESIDUALS_README,
        "iCloud placeholder smoke record 和只读 metadata helper 已存在",
    );
    assert_contains(GLOBAL_RESIDUALS_YAML, "updated: \"2026-07-29\"");
    assert_contains(
        GLOBAL_RESIDUALS_YAML,
        "source: workflow/versions/v1-mvp/residuals/residuals.yaml",
    );
    assert_contains(GLOBAL_RESIDUALS_YAML, "status: mixed-blocked");
    assert_contains(GLOBAL_RESIDUALS_YAML, "blocked-external");
    assert_contains(GLOBAL_RESIDUALS_YAML, "blocked-decision");
    assert_contains(GLOBAL_RESIDUALS_YAML, "deferred");
    assert_contains(GLOBAL_RESIDUALS_YAML, "accepted-exception");
    assert_contains(
        GLOBAL_RESIDUALS_README,
        "Developer ID signing / notarization 结构化 record 已存在",
    );
    assert_contains(GLOBAL_RESIDUALS_README, "final tag record 已存在");
    assert_contains(
        GLOBAL_RESIDUALS_README,
        "Alpha feedback issue template 和 route evidence 已存在",
    );
    assert_contains(
        GLOBAL_RESIDUALS_README,
        "release-gate review record 已结构化",
    );
    assert_contains(TASK_RESIDUAL_INDEX, "iCloud smoke record 已结构化");
    assert_contains(TASK_RESIDUAL_INDEX, "release-gate review record 已结构化");
    assert_contains(TASK_RESIDUAL_INDEX, "分发签名 / 公证 record 已结构化");
    assert_contains(TASK_RESIDUAL_INDEX, "final tag record 已结构化");
    assert_contains(
        TASK_RESIDUAL_INDEX,
        "Alpha feedback issue template 和 route evidence 已存在",
    );
}

#[test]
fn final_tag_record_stays_blocked_until_release_gates_and_tag_push() {
    assert_contains(CHECKLIST, "final-tag-release-evidence.md");
    assert_contains(CHECKLIST, "`release_candidate.commit: pending`");
    assert_contains(CHECKLIST, "`final_tag.created: false`");
    assert_contains(CHECKLIST, "`final_tag.pushed: false`");

    assert_contains(
        FINAL_TAG_RELEASE_EVIDENCE,
        "当前结论：**不关闭 `v1-rl-004`**",
    );
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "schema_version: 1");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "mode: final_tag_release_record");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "residual_id: v1-rl-004");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "status: blocked");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "closes_residual: false");
    assert_contains(
        FINAL_TAG_RELEASE_EVIDENCE,
        "block_until_all_release_gates_closed_and_final_tag_pushed",
    );
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "release_candidate:");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "commit: null");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "required_gates:");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "v1_rl_002_icloud_placeholder:");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "v1_rl_003_distribution:");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "v1_rl_006_feedback_route:");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "final_tag:");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "created: false");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "pushed: false");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "github_release_url: null");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "artifact_dmg_sha256: null");
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "readiness_audit:");
    assert_contains(
        FINAL_TAG_RELEASE_EVIDENCE,
        "command: ./dev release final-tag-readiness-audit --json --remote",
    );
    assert_contains(
        FINAL_TAG_RELEASE_EVIDENCE,
        "pre_tag_release_evidence_gate: BLOCKED",
    );
    assert_contains(FINAL_TAG_RELEASE_EVIDENCE, "tag_prerequisite_gate: BLOCKED");
    assert_contains(
        FINAL_TAG_RELEASE_EVIDENCE,
        "ready_to_create_formal_tag: false",
    );
    assert_contains(
        FINAL_TAG_RELEASE_EVIDENCE,
        "preview tag is a formal release tag",
    );
    assert_contains(
        FINAL_TAG_RELEASE_EVIDENCE,
        "本文件只记录最终 tag 的前置条件和关闭字段",
    );
}

#[test]
fn alpha_feedback_route_record_stays_blocked_until_release_decision() {
    assert_contains(CHECKLIST, "alpha-feedback-route.md");
    assert_contains(CHECKLIST, "`status: blocked`");
    assert_contains(CHECKLIST, "`closes_residual: false`");
    assert_contains(CHECKLIST, "`release_gate: block_if_any_pending`");

    assert_contains(ALPHA_FEEDBACK_ROUTE, "当前结论：**不关闭 `v1-rl-006`**");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "schema_version: 1");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "mode: alpha_feedback_release_decision_record",
    );
    assert_contains(ALPHA_FEEDBACK_ROUTE, "residual_id: v1-rl-006");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "release: v0.1.0");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "status: blocked");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "closes_residual: false");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "release_gate: block_if_any_pending");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "alpha_feedback_release_decision:");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "trusted_tester_list:");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "source: null");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "tester_count: null");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "`trusted_tester_list.tester_count` 必须是大于 0 的整数",
    );
    assert_contains(ALPHA_FEEDBACK_ROUTE, "announcement:");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "url: null");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "feedback_route:");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "secondary: null");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "triage_owner:");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "owner: null");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "response_slo: null");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "decision_audit:");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "command: ./dev release alpha-feedback-decision-audit --json",
    );
    assert_contains(ALPHA_FEEDBACK_ROUTE, "status: BLOCKED");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "issue_template: PASS");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "discussion_links: PASS");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "decision_gate: BLOCKED");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "closes_residual: false");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "decision_side_effects:");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "github_discussion_created: false");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "testers_invited: false");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "announcement_published: false");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "feedback_owner_assigned: false");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "feedback_route_marked_ready: false");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "does_not_prove:");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "trusted tester list exists");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "formal announcement or Discussion exists",
    );
    assert_contains(ALPHA_FEEDBACK_ROUTE, "feedback route is final");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "triage owner has accepted responsibility",
    );
    assert_contains(ALPHA_FEEDBACK_ROUTE, "v1-rl-006 is closed");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "formal alpha release readiness");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "trusted_tester_list.status: pending");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "announcement.status: pending");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "feedback_route.status: pending");
    assert_contains(ALPHA_FEEDBACK_ROUTE, "triage_owner.status: pending");
    assert_contains(
        ALPHA_FEEDBACK_ROUTE,
        "decision_audit.decision_gate: BLOCKED",
    );
}

#[test]
fn task05_release_gate_review_record_stays_deferred_without_task_loop_pass() {
    assert_contains(CHECKLIST, "release-gate-review-task05.md");
    assert_contains(CHECKLIST, "`task_loop_evidence.verify_result_pass: false`");
    assert_contains(
        CHECKLIST,
        "`tracked_incomplete_summaries_excluded_from_pass: 5`",
    );
    assert_contains(
        CHECKLIST,
        "`review_audit.release_evidence_review_gate: BLOCKED`",
    );
    assert_contains(
        CHECKLIST,
        "`./dev release task05-release-review-audit --json`",
    );

    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "当前结论：**不关闭 `v1-ref-003-1-task-05`**",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "schema_version: 1");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "mode: release_gate_review_task05_record",
    );
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "residual_id: v1-ref-003-1-task-05",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "task_label: 3-1/task-05");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "status: deferred");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "closes_residual: false");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "release_gate: deferred_to_formal_release_evidence_review",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "review_audit:");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "command: ./dev release task05-release-review-audit --json",
    );
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "release_evidence_review_gate: BLOCKED",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "task_loop_boundary_gate: PASS");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "forbidden_repair_gate: PASS");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "audit_side_effects:");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "progress_json_rewritten: false");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "task_loop_logs_rewritten: false",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "run_summaries_rewritten: false");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "git_checkpoint_backfilled: false",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "commit_created: false");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "tag_created: false");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "github_release_created: false");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "completed_task_loop_run_id: null",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "verify_result_pass: false");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "copy_log_archived: false");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "verify_log_archived: false");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "tracked_incomplete_summaries_excluded_from_pass: 5",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "run_id: 20260509_125521");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "run_id: 20260510_004410");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "run_id: 20260510_134208");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "run_id: 20260510_184848");
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "run_id: 20260510_223424");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "progress_json_rewrite_attempted: false",
    );
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "task_loop_log_rewrite_attempted: false",
    );
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "run_summary_rewrite_attempted: false",
    );
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "git_checkpoint_backfill_attempted: false",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "tag_or_release_created: false");
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "task-loop VERIFY_RESULT PASS exists",
    );
    assert_contains(
        RELEASE_GATE_REVIEW_TASK05,
        "release evidence blockers are closed",
    );
    assert_contains(RELEASE_GATE_REVIEW_TASK05, "formal alpha release readiness");
    assert_contains(RELEASE_NOTES_010, "`v1-ref-003-1-task-05`");
    assert_contains(RELEASE_NOTES_010, "fresh formal release evidence review");
    assert_contains(RELEASE_NOTES_010, "task-loop `VERIFY_RESULT: PASS`");
    assert_contains(RELEASE_NOTES_010, "5 个 tracked incomplete summaries");
}
