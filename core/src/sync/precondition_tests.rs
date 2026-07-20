use std::fs;

use super::plans::{revalidate_planned_filesystem_state, FilesystemExpectation};
use crate::CoreError;

fn assert_conflict(result: crate::CoreResult<()>, expected_path: &str) {
    match result {
        Err(CoreError::Conflict { path }) => assert_eq!(path, expected_path),
        Err(error) => panic!("expected path conflict, got {error:?}"),
        Ok(()) => panic!("stale filesystem expectation must not pass"),
    }
}

#[test]
fn revalidate_planned_filesystem_state_rejects_changed_snapshot() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let relative_path = "docs/item.txt";
    let path = repo.path().join(relative_path);
    fs::create_dir_all(path.parent().expect("file parent")).expect("create file parent");
    fs::write(&path, b"changed").expect("write changed file fixture");
    let expectation = FilesystemExpectation::Snapshot {
        path: relative_path.to_owned(),
        size_bytes: 8,
        hash_sha256: "stale-hash".to_owned(),
    };

    assert_conflict(
        revalidate_planned_filesystem_state(repo.path(), &[expectation]),
        relative_path,
    );
}

#[test]
fn revalidate_planned_filesystem_state_rejects_reappeared_removed_path() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let relative_path = "docs/reappeared.txt";
    let path = repo.path().join(relative_path);
    fs::create_dir_all(path.parent().expect("file parent")).expect("create file parent");
    fs::write(path, b"reappeared").expect("write reappeared file fixture");
    let expectation = FilesystemExpectation::Absent {
        path: relative_path.to_owned(),
    };

    assert_conflict(
        revalidate_planned_filesystem_state(repo.path(), &[expectation]),
        relative_path,
    );
}

#[test]
fn revalidate_planned_filesystem_state_rejects_reappeared_rename_source() {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
    let source_path = "docs/source.txt";
    let target_path = "docs/target.txt";
    fs::create_dir_all(repo.path().join("docs")).expect("create file parent");
    fs::write(repo.path().join(source_path), b"source").expect("write source file fixture");
    fs::write(repo.path().join(target_path), b"target").expect("write target file fixture");
    let expectation = FilesystemExpectation::Rename {
        source_path: source_path.to_owned(),
        target_path: target_path.to_owned(),
        size_bytes: 6,
        hash_sha256: "unused-while-source-exists".to_owned(),
    };

    assert_conflict(
        revalidate_planned_filesystem_state(repo.path(), &[expectation]),
        source_path,
    );
}
