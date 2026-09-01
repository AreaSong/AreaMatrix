use std::{fs, path::Path};

use area_matrix_core::{
    init_repo, recover_on_startup, CoreResult, OverviewOutput, RepoInitMode, RepoInitOptions,
    RepositoryLocalePolicy,
};
use rusqlite::{params, Connection};
use serde_json::json;
use sha2::{Digest, Sha256};

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create repository");
    init_repo(
        path_string(repo.path()),
        RepoInitOptions {
            mode: RepoInitMode::CreateEmpty,
            create_default_categories: false,
            overview_output: OverviewOutput::GeneratedOnly,
            locale_policy: RepositoryLocalePolicy::FollowInterface,
            content_locale: area_matrix_core::ContentLocale::En,
        },
    )
    .expect("initialize repository");
    repo
}

fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn insert_file(repo: &Path, path: &str, category: &str, content: &[u8]) -> i64 {
    let absolute = repo.join(path);
    fs::create_dir_all(absolute.parent().expect("file parent")).expect("create file parent");
    fs::write(&absolute, content).expect("write file");
    let name = Path::new(path)
        .file_name()
        .and_then(|value| value.to_str())
        .expect("file name");
    let connection = Connection::open(repo.join(".areamatrix/index.db")).expect("open db");
    connection
        .execute(
            "INSERT INTO files (
                path, original_name, current_name, category, size_bytes,
                hash_sha256, storage_mode, origin, imported_at, updated_at, status
             ) VALUES (?1, ?2, ?2, ?3, ?4, ?5, 'copied', 'imported', 100, 100, 'active')",
            params![path, name, category, content.len() as i64, hash(content)],
        )
        .expect("insert file");
    connection.last_insert_rowid()
}

struct JournalInput<'a> {
    old_path: &'a str,
    new_path: &'a str,
    old_category: &'a str,
    new_category: &'a str,
    content: &'a [u8],
    sidecar: Option<(&'a str, &'a str, &'a [u8])>,
}

fn write_journal(repo: &Path, file_id: i64, input: JournalInput<'_>) -> std::path::PathBuf {
    let old_name = Path::new(input.old_path)
        .file_name()
        .and_then(|value| value.to_str())
        .expect("old name");
    let new_name = Path::new(input.new_path)
        .file_name()
        .and_then(|value| value.to_str())
        .expect("new name");
    let sidecar_json = input.sidecar.map(|(old, new, bytes)| {
        json!({
            "original_relative": old,
            "current_relative": new,
            "hash_sha256": hash(bytes),
        })
    });
    let value = json!({
        "version": 1,
        "operation": "batch_change_category",
        "file_id": file_id,
        "original_relative": input.old_path,
        "current_relative": input.new_path,
        "original_db_path": input.old_path,
        "current_db_path": input.new_path,
        "original_name": old_name,
        "current_name": new_name,
        "original_category": input.old_category,
        "current_category": input.new_category,
        "file_hash_sha256": hash(input.content),
        "sidecar": sidecar_json,
        "planned_directory_relative": Path::new(input.new_path)
            .parent()
            .and_then(Path::to_str),
        "created_directory_identity": null,
    });
    let directory = repo.join(".areamatrix/staging/batch");
    fs::create_dir_all(&directory).expect("create journal directory");
    let path = directory.join(format!("{file_id}.json"));
    fs::write(&path, serde_json::to_vec(&value).expect("encode journal")).expect("write journal");
    path
}

fn recover(repo: &Path) -> CoreResult<()> {
    recover_on_startup(path_string(repo)).map(|_| ())
}

#[test]
fn recovery_rolls_back_main_and_sidecar_when_db_is_still_old() {
    let repository = repo();
    let content = b"main bytes";
    let note = b"note bytes";
    let file_id = insert_file(repository.path(), "finance/report.pdf", "finance", content);
    fs::write(repository.path().join("finance/report.pdf.md"), note).expect("write note");
    fs::create_dir_all(repository.path().join("docs")).expect("create target directory");
    fs::rename(
        repository.path().join("finance/report.pdf"),
        repository.path().join("docs/report.pdf"),
    )
    .expect("simulate main move");
    fs::rename(
        repository.path().join("finance/report.pdf.md"),
        repository.path().join("docs/report.pdf.md"),
    )
    .expect("simulate sidecar move");
    let journal = write_journal(
        repository.path(),
        file_id,
        JournalInput {
            old_path: "finance/report.pdf",
            new_path: "docs/report.pdf",
            old_category: "finance",
            new_category: "docs",
            content,
            sidecar: Some(("finance/report.pdf.md", "docs/report.pdf.md", note)),
        },
    );

    recover(repository.path()).expect("recover old database state");

    assert_eq!(
        fs::read(repository.path().join("finance/report.pdf")).expect("restored main"),
        content
    );
    assert_eq!(
        fs::read(repository.path().join("finance/report.pdf.md")).expect("restored sidecar"),
        note
    );
    assert!(!repository.path().join("docs/report.pdf").exists());
    assert!(!journal.exists());
}

#[test]
fn recovery_handles_main_move_before_sidecar_move() {
    let repository = repo();
    let content = b"main bytes";
    let note = b"note bytes";
    let file_id = insert_file(repository.path(), "finance/report.pdf", "finance", content);
    fs::write(repository.path().join("finance/report.pdf.md"), note).expect("write note");
    fs::create_dir_all(repository.path().join("docs")).expect("create target directory");
    fs::rename(
        repository.path().join("finance/report.pdf"),
        repository.path().join("docs/report.pdf"),
    )
    .expect("simulate main move");
    let journal = write_journal(
        repository.path(),
        file_id,
        JournalInput {
            old_path: "finance/report.pdf",
            new_path: "docs/report.pdf",
            old_category: "finance",
            new_category: "docs",
            content,
            sidecar: Some(("finance/report.pdf.md", "docs/report.pdf.md", note)),
        },
    );

    recover(repository.path()).expect("recover partial move");

    assert!(repository.path().join("finance/report.pdf").exists());
    assert!(repository.path().join("finance/report.pdf.md").exists());
    assert!(!repository.path().join("docs/report.pdf").exists());
    assert!(!journal.exists());
}

#[test]
fn recovery_keeps_user_recreated_source_and_manifest() {
    let repository = repo();
    let content = b"main bytes";
    let file_id = insert_file(repository.path(), "finance/report.pdf", "finance", content);
    fs::create_dir_all(repository.path().join("docs")).expect("create target directory");
    fs::rename(
        repository.path().join("finance/report.pdf"),
        repository.path().join("docs/report.pdf"),
    )
    .expect("simulate main move");
    fs::write(
        repository.path().join("finance/report.pdf"),
        b"user replacement",
    )
    .expect("recreate source");
    let journal = write_journal(
        repository.path(),
        file_id,
        JournalInput {
            old_path: "finance/report.pdf",
            new_path: "docs/report.pdf",
            old_category: "finance",
            new_category: "docs",
            content,
            sidecar: None,
        },
    );

    recover(repository.path()).expect("recover with user replacement");

    assert_eq!(
        fs::read(repository.path().join("finance/report.pdf")).expect("read user replacement"),
        b"user replacement"
    );
    assert!(repository.path().join("docs/report.pdf").exists());
    assert!(journal.exists());
}

#[test]
fn recovery_cleans_manifest_after_database_commit() {
    let repository = repo();
    let content = b"main bytes";
    let file_id = insert_file(repository.path(), "finance/report.pdf", "finance", content);
    fs::create_dir_all(repository.path().join("docs")).expect("create target directory");
    fs::rename(
        repository.path().join("finance/report.pdf"),
        repository.path().join("docs/report.pdf"),
    )
    .expect("simulate main move");
    Connection::open(repository.path().join(".areamatrix/index.db"))
        .expect("open db")
        .execute(
            "UPDATE files SET path = 'docs/report.pdf', current_name = 'report.pdf',
             category = 'docs' WHERE id = ?1",
            [file_id],
        )
        .expect("commit database state");
    let journal = write_journal(
        repository.path(),
        file_id,
        JournalInput {
            old_path: "finance/report.pdf",
            new_path: "docs/report.pdf",
            old_category: "finance",
            new_category: "docs",
            content,
            sidecar: None,
        },
    );

    recover(repository.path()).expect("recover committed state");

    assert!(repository.path().join("docs/report.pdf").exists());
    assert!(!journal.exists());
}
