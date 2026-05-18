use std::fs;

use area_matrix_core::{
    preview_classifier_rule_impact, CoreError, RuleImpactConflictKind, RuleImpactMatchReason,
    RuleImpactStatus,
};
use pretty_assertions::assert_eq;

#[path = "support/classifier_impact_preview.rs"]
mod classifier_impact_preview_support;

use classifier_impact_preview_support::{
    initialized_repo, insert_indexed_file, insert_repo_file, path_string, remove_category_request,
    remove_extension_request, remove_keyword_request, request, request_without_move, sample,
    sample_status, snapshot, write_classifier_with_finance_rules,
    write_classifier_with_priority_overlap,
};

#[test]
fn classifier_impact_preview_implementation_reads_metadata_and_has_no_side_effects() {
    let repo = initialized_repo();
    let keyword_id = insert_repo_file(repo.path(), "docs/clientx-report.txt", "docs");
    let extension_id = insert_repo_file(repo.path(), "docs/archive.csv", "docs");
    let both_id = insert_repo_file(repo.path(), "docs/合同x.csv", "docs");
    let already_id = insert_repo_file(repo.path(), "finance/clientx-paid.txt", "finance");
    insert_repo_file(repo.path(), "docs/readme.txt", "docs");
    let before = snapshot(repo.path());

    let report = preview_classifier_rule_impact(path_string(repo.path()), request())
        .expect("preview impact");

    assert_eq!(report.request, request());
    assert_eq!(report.affected_file_count, 4);
    assert_eq!(report.will_update_count, 3);
    assert_eq!(report.already_correct_count, 1);
    assert_eq!(report.needs_review_count, 0);
    assert_eq!(report.conflict_count, 0);
    assert!(report.can_apply);
    assert_eq!(report.apply_blocked_reason, None);
    assert_eq!(
        sample_status(&report, keyword_id),
        RuleImpactStatus::WillUpdate
    );
    assert_eq!(
        sample_status(&report, extension_id),
        RuleImpactStatus::WillUpdate
    );
    assert_eq!(
        sample_status(&report, both_id),
        RuleImpactStatus::WillUpdate
    );
    assert_eq!(
        sample_status(&report, already_id),
        RuleImpactStatus::AlreadyCorrect
    );

    let both = report
        .samples
        .iter()
        .find(|sample| sample.file_id == both_id)
        .expect("both-match sample exists");
    assert_eq!(
        both.match_reasons,
        vec![
            RuleImpactMatchReason::Keyword,
            RuleImpactMatchReason::Extension
        ]
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_implementation_uses_full_matcher_priority_for_rule_draft() {
    let repo = initialized_repo();
    write_classifier_with_priority_overlap(repo.path());
    let protected_id = insert_repo_file(repo.path(), "docs/clientx-report.txt", "docs");
    let before = snapshot(repo.path());

    let report = preview_classifier_rule_impact(path_string(repo.path()), request_without_move())
        .expect("preview priority-aware impact");

    assert_eq!(report.affected_file_count, 1);
    assert_eq!(report.will_update_count, 0);
    assert_eq!(report.already_correct_count, 1);
    assert_eq!(report.conflict_count, 0);
    let sample = sample(&report, protected_id);
    assert_eq!(sample.new_category, "docs");
    assert_eq!(sample.status, RuleImpactStatus::AlreadyCorrect);
    assert_eq!(sample.match_reasons, vec![RuleImpactMatchReason::Keyword]);
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_implementation_surfaces_missing_index_only_and_conflicts() {
    let repo = initialized_repo();
    let indexed_root = tempfile::tempdir().expect("create indexed source root");
    let indexed_id = insert_indexed_file(
        repo.path(),
        &indexed_root.path().join("clientx-indexed.txt"),
        "docs",
    );
    let missing_id = insert_repo_file(repo.path(), "docs/clientx-missing.txt", "docs");
    fs::remove_file(repo.path().join("docs/clientx-missing.txt")).expect("remove backing file");
    let conflict_id = insert_repo_file(repo.path(), "docs/clientx-conflict.txt", "docs");
    fs::create_dir_all(repo.path().join("finance")).expect("create finance dir");
    fs::write(
        repo.path().join("finance/clientx-conflict.txt"),
        b"existing target",
    )
    .expect("write conflicting target");
    let before = snapshot(repo.path());

    let report = preview_classifier_rule_impact(path_string(repo.path()), request())
        .expect("preview impact");

    assert_eq!(report.affected_file_count, 3);
    assert_eq!(report.will_update_count, 0);
    assert_eq!(report.already_correct_count, 0);
    assert_eq!(report.needs_review_count, 1);
    assert_eq!(report.conflict_count, 2);
    assert!(report.needs_review);
    assert!(!report.can_apply);
    assert_eq!(
        sample_status(&report, indexed_id),
        RuleImpactStatus::IndexOnly
    );
    assert_eq!(
        sample_status(&report, missing_id),
        RuleImpactStatus::Missing
    );
    assert_eq!(
        sample_status(&report, conflict_id),
        RuleImpactStatus::Conflict
    );
    assert!(report
        .conflicts
        .iter()
        .any(|conflict| conflict.kind == RuleImpactConflictKind::MissingFile));
    assert!(report.conflicts.iter().any(|conflict| conflict.kind
        == RuleImpactConflictKind::NameConflict
        && conflict.conflicting_path.as_deref() == Some("finance/clientx-conflict.txt")));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_implementation_honors_move_preference_for_conflict_dry_run() {
    let repo = initialized_repo();
    let conflict_id = insert_repo_file(repo.path(), "docs/clientx-conflict.txt", "docs");
    fs::create_dir_all(repo.path().join("finance")).expect("create finance dir");
    fs::write(
        repo.path().join("finance/clientx-conflict.txt"),
        b"existing target",
    )
    .expect("write conflicting target");
    let before = snapshot(repo.path());

    let metadata_only =
        preview_classifier_rule_impact(path_string(repo.path()), request_without_move())
            .expect("preview without move conflict dry-run");

    assert_eq!(metadata_only.affected_file_count, 1);
    assert_eq!(metadata_only.will_update_count, 1);
    assert_eq!(metadata_only.conflict_count, 0);
    assert!(metadata_only.can_apply);
    assert_eq!(
        sample_status(&metadata_only, conflict_id),
        RuleImpactStatus::WillUpdate
    );

    let move_aware = preview_classifier_rule_impact(path_string(repo.path()), request())
        .expect("preview with move conflict dry-run");

    assert_eq!(move_aware.affected_file_count, 1);
    assert_eq!(move_aware.will_update_count, 0);
    assert_eq!(move_aware.conflict_count, 1);
    assert!(!move_aware.can_apply);
    assert_eq!(
        sample_status(&move_aware, conflict_id),
        RuleImpactStatus::Conflict
    );
    assert!(move_aware.conflicts.iter().any(|conflict| conflict.kind
        == RuleImpactConflictKind::NameConflict
        && conflict.conflicting_path.as_deref() == Some("finance/clientx-conflict.txt")));
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_implementation_warns_for_broad_rules_and_limits_samples() {
    let repo = initialized_repo();
    for index in 0..25 {
        insert_repo_file(repo.path(), &format!("docs/clientx-{index:02}.txt"), "docs");
    }

    let report = preview_classifier_rule_impact(path_string(repo.path()), request())
        .expect("preview impact");

    assert_eq!(report.affected_file_count, 25);
    assert_eq!(report.will_update_count, 25);
    assert!(report.warning_required);
    assert!(report.warning.is_some());
    assert_eq!(report.sample_limit, 50);
    assert_eq!(report.samples.len(), 25);
}

#[test]
fn classifier_impact_preview_implementation_rejects_invalid_config_and_metadata() {
    let repo = initialized_repo();
    fs::write(
        repo.path().join(".areamatrix/classifier.yaml"),
        "version: 1\ndefault: missing\ncategories:\n  - slug: finance\n",
    )
    .expect("write invalid classifier config");

    assert!(matches!(
        preview_classifier_rule_impact(path_string(repo.path()), request()),
        Err(CoreError::Config { .. })
    ));

    let plain_dir = tempfile::tempdir().expect("create plain directory");
    assert!(matches!(
        preview_classifier_rule_impact(path_string(plain_dir.path()), request()),
        Err(CoreError::Db { .. })
    ));
}

#[test]
fn classifier_impact_preview_implementation_previews_removed_keyword_and_extension() {
    let repo = initialized_repo();
    write_classifier_with_finance_rules(repo.path());
    let keyword_id = insert_repo_file(repo.path(), "finance/clientx-paid.txt", "finance");
    let extension_id = insert_repo_file(repo.path(), "finance/archive.csv", "finance");
    let both_id = insert_repo_file(repo.path(), "finance/合同x.csv", "finance");
    let before = snapshot(repo.path());

    let keyword_report =
        preview_classifier_rule_impact(path_string(repo.path()), remove_keyword_request("clientx"))
            .expect("preview keyword removal");

    assert_eq!(keyword_report.affected_file_count, 1);
    assert_eq!(keyword_report.will_update_count, 1);
    assert_eq!(keyword_report.samples[0].file_id, keyword_id);
    assert_eq!(keyword_report.samples[0].new_category, "docs");
    assert_eq!(
        keyword_report.samples[0].match_reasons,
        vec![RuleImpactMatchReason::Keyword]
    );

    let extension_report =
        preview_classifier_rule_impact(path_string(repo.path()), remove_extension_request("csv"))
            .expect("preview extension removal");

    assert_eq!(extension_report.affected_file_count, 2);
    assert_eq!(extension_report.will_update_count, 1);
    assert_eq!(extension_report.already_correct_count, 1);
    let extension_sample = sample(&extension_report, extension_id);
    assert_eq!(extension_sample.new_category, "inbox");
    assert_eq!(
        extension_sample.match_reasons,
        vec![RuleImpactMatchReason::Extension]
    );
    assert_eq!(
        sample_status(&extension_report, both_id),
        RuleImpactStatus::AlreadyCorrect
    );
    assert_eq!(snapshot(repo.path()), before);
}

#[test]
fn classifier_impact_preview_implementation_previews_category_removal_replacement_gate() {
    let repo = initialized_repo();
    write_classifier_with_finance_rules(repo.path());
    let replaced_id = insert_repo_file(repo.path(), "finance/clientx-paid.txt", "finance");
    insert_repo_file(repo.path(), "docs/readme.txt", "docs");
    let before = snapshot(repo.path());

    let missing_replacement =
        preview_classifier_rule_impact(path_string(repo.path()), remove_category_request(None))
            .expect("preview category removal without replacement");

    assert_eq!(missing_replacement.affected_file_count, 1);
    assert_eq!(missing_replacement.will_update_count, 0);
    assert_eq!(missing_replacement.needs_review_count, 1);
    assert!(!missing_replacement.can_apply);
    assert_eq!(
        missing_replacement.apply_blocked_reason.as_deref(),
        Some("replacement category is required before Apply")
    );
    assert_eq!(
        missing_replacement.samples[0].match_reasons,
        vec![RuleImpactMatchReason::Category]
    );

    let with_replacement = preview_classifier_rule_impact(
        path_string(repo.path()),
        remove_category_request(Some("docs")),
    )
    .expect("preview category removal with replacement");

    assert_eq!(with_replacement.affected_file_count, 1);
    assert_eq!(with_replacement.will_update_count, 1);
    assert!(with_replacement.can_apply);
    assert_eq!(with_replacement.samples[0].file_id, replaced_id);
    assert_eq!(with_replacement.samples[0].new_category, "docs");
    assert_eq!(snapshot(repo.path()), before);
}
