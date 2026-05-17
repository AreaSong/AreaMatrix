use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    import_file, init_repo, BatchRenameDateSource, BatchRenameMode, BatchRenameRule,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use rusqlite::{params, Connection};

pub(crate) fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

pub(crate) fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
        },
    )
    .expect("initialize repository");
    repo
}

pub(crate) fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

pub(crate) fn import_fixture(
    repo: &Path,
    mode: StorageMode,
    filename: &str,
    source_name: &str,
    content: &[u8],
) -> area_matrix_core::FileEntry {
    let (_source_root, source) = source_file(source_name, content);
    import_file(
        path_string(repo),
        path_string(&source),
        import_options(mode, filename),
    )
    .expect("import fixture")
}

pub(crate) fn import_options(mode: StorageMode, filename: &str) -> ImportOptions {
    ImportOptions {
        mode,
        destination: ImportDestination::AutoClassify,
        target_directory: None,
        override_category: Some("finance".to_owned()),
        override_filename: Some(filename.to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

pub(crate) fn prefix_rule(prefix: &str) -> BatchRenameRule {
    BatchRenameRule {
        mode: BatchRenameMode::Prefix,
        prefix: Some(prefix.to_owned()),
        date_source: None,
        date_format: None,
        separator: None,
        start_number: None,
        padding: None,
        find: None,
        replacement: None,
        case_sensitive: false,
    }
}

pub(crate) fn sequence_rule() -> BatchRenameRule {
    BatchRenameRule {
        mode: BatchRenameMode::KeepBaseSequence,
        prefix: None,
        date_source: None,
        date_format: None,
        separator: Some("_".to_owned()),
        start_number: Some(1),
        padding: Some(2),
        find: None,
        replacement: None,
        case_sensitive: false,
    }
}

pub(crate) fn date_rule() -> BatchRenameRule {
    BatchRenameRule {
        mode: BatchRenameMode::DatePrefix,
        prefix: None,
        date_source: Some(BatchRenameDateSource::Imported),
        date_format: Some("yyyy-MM-dd".to_owned()),
        separator: Some("_".to_owned()),
        start_number: None,
        padding: None,
        find: None,
        replacement: None,
        case_sensitive: false,
    }
}

pub(crate) fn replace_rule(find: &str, replacement: &str, case_sensitive: bool) -> BatchRenameRule {
    BatchRenameRule {
        mode: BatchRenameMode::ReplaceText,
        prefix: None,
        date_source: None,
        date_format: None,
        separator: None,
        start_number: None,
        padding: None,
        find: Some(find.to_owned()),
        replacement: Some(replacement.to_owned()),
        case_sensitive,
    }
}

pub(crate) fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

pub(crate) fn indexed_file(repo: &Path, external_path: &Path, category: &str) -> i64 {
    let current_name = external_path
        .file_name()
        .and_then(|name| name.to_str())
        .expect("fixture has file name");
    let path = path_string(external_path);
    let connection = open_db(repo);
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, source_path,
                imported_at, updated_at, status
             ) VALUES (
                ?1, ?2, ?2, ?3, 13,
                ?4, 'indexed', 'imported', ?1,
                100, 100, 'active'
             )",
            params![
                path,
                current_name,
                category,
                format!("{:064x}", path_string(external_path).len()),
            ],
        )
        .expect("insert indexed file row");
    connection.last_insert_rowid()
}

pub(crate) fn file_row(repo: &Path, file_id: i64) -> (String, String, String) {
    open_db(repo)
        .query_row(
            "SELECT path, current_name, category FROM files WHERE id = ?1",
            params![file_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read file row")
}

pub(crate) fn renamed_details(repo: &Path) -> Vec<serde_json::Value> {
    let connection = open_db(repo);
    let mut statement = connection
        .prepare("SELECT detail_json FROM change_log WHERE action = 'renamed' ORDER BY id")
        .expect("prepare renamed changes query");
    statement
        .query_map([], |row| {
            let detail: String = row.get(0)?;
            Ok(serde_json::from_str(&detail).expect("change detail is json"))
        })
        .expect("query renamed changes")
        .map(|row| row.expect("read renamed change detail"))
        .collect()
}
