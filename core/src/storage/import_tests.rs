use std::fs;

use super::*;

#[test]
fn resolve_name_conflict_persist_refuses_raced_final_without_overwrite() {
    let dir = tempfile::tempdir().expect("create import tempdir");
    let staging = dir.path().join("staging-file");
    let final_path = dir.path().join("final.pdf");
    fs::write(&staging, b"new content").expect("write staging file");
    fs::write(&final_path, b"raced content").expect("write raced final file");

    let result = persist_staging_to_final(&staging, &final_path);

    assert!(matches!(result, Err(CoreError::Conflict { .. })));
    assert_eq!(
        fs::read(&staging).expect("staging remains recoverable"),
        b"new content"
    );
    assert_eq!(
        fs::read(&final_path).expect("raced final remains unmodified"),
        b"raced content"
    );
}
