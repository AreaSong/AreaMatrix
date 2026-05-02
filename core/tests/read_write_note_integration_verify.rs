use std::{
    fs,
    path::{Path, PathBuf},
};

use area_matrix_core::{
    get_file, import_file, init_repo, list_changes, read_note, write_note, ChangeFilter, CoreError,
    DuplicateStrategy, ImportDestination, ImportOptions, OverviewOutput, RepoInitMode,
    RepoInitOptions, StorageMode,
};
use pretty_assertions::assert_eq;
use rusqlite::{params, Connection};
use serde_json::Value;

const CAPABILITY_SPEC: &str =
    include_str!("../../docs/core/capability-specs/stage-1-mvp/C1-14-read-write-note.md");
const CONTROL_MAP: &str = include_str!("../../docs/architecture/mvp-control-map.md");
const CORE_API: &str = include_str!("../../docs/api/core-api.md");
const API_RS: &str = include_str!("../src/api.rs");
const DB_NOTE_RS: &str = include_str!("../src/db/note.rs");
const NOTE_RS: &str = include_str!("../src/note.rs");
const S1_14_DETAIL_NOTE: &str =
    include_str!("../../docs/ux/page-specs/stage-1-mvp/S1-14-detail-note.md");
const UDL: &str = include_str!("../area_matrix.udl");

fn assert_contains(haystack: &str, needle: &str) {
    assert!(
        haystack.contains(needle),
        "expected document or source to contain `{needle}`"
    );
}

fn path_string(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn initialized_repo() -> tempfile::TempDir {
    let repo = tempfile::tempdir().expect("create temporary repository directory");
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

fn source_file(name: &str, content: &[u8]) -> (tempfile::TempDir, PathBuf) {
    let source_root = tempfile::tempdir().expect("create source directory");
    let source_path = source_root.path().join(name);
    fs::write(&source_path, content).expect("write source file");
    (source_root, source_path)
}

fn copied_options() -> ImportOptions {
    ImportOptions {
        mode: StorageMode::Copied,
        destination: ImportDestination::SelectedDirectory,
        target_directory: Some("finance/2026".to_owned()),
        override_category: None,
        override_filename: Some("q1-contract.pdf".to_owned()),
        duplicate_strategy: DuplicateStrategy::Skip,
    }
}

fn edited_note_filter(file_id: i64) -> ChangeFilter {
    ChangeFilter {
        file_id: Some(file_id),
        category: None,
        action: Some("edited_note".to_owned()),
        since: None,
        until: None,
        limit: 10,
        offset: 0,
    }
}

fn open_db(repo: &Path) -> Connection {
    Connection::open(repo.join(".areamatrix/index.db")).expect("open repository database")
}

fn note_content(repo: &Path, file_id: i64) -> Option<String> {
    open_db(repo)
        .query_row(
            "SELECT content_md FROM notes WHERE file_id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .ok()
}

fn sidecar_path(repo: &Path, relative_path: &str) -> PathBuf {
    repo.join(format!("{relative_path}.md"))
}

fn edited_note_count(repo: &Path, file_id: i64) -> i64 {
    open_db(repo)
        .query_row(
            "SELECT COUNT(*) FROM change_log
             WHERE file_id = ?1 AND action = 'edited_note'",
            params![file_id],
            |row| row.get(0),
        )
        .expect("count edited_note change-log rows")
}

#[test]
fn read_write_note_integration_verify_docs_api_udl_and_s1_14_consumer_stay_aligned() {
    for fragment in [
        "C1-14 read-write-note",
        "- S1-14 detail-note",
        "- `read_note(repo_path, file_id) -> string?`",
        "- `write_note(repo_path, file_id, content_md)`",
        "- `notes` upsert。",
        "- `change_log.action = edited_note`。",
        "- 写入同目录伴生 `.md` 文件。",
        "DB `notes`、`change_log` 与伴生 `.md` 文件必须保持一致",
        "- 无笔记返回 `nil`。",
        "- 笔记写失败不应破坏旧内容。",
        "- 富文本编辑、双向链接、Markdown 预览增强属于 Stage 2+。",
    ] {
        assert_contains(CAPABILITY_SPEC, fragment);
    }

    for fragment in [
        "| S1-14 | detail-note | C1-14 | `read_note`, `write_note` | `notes`, `change_log` | sidecar `.md` | FileNotFound, Io | `2-3/task-07` | Real Core |",
        "不可 mock：路径校验、init/adopt、导入、重复检测、同名冲突、详情、日志、笔记、Tree、recovery、错误映射。",
        "Core 能力若未在本矩阵出现，默认不得提前进入 Stage 1 实现。",
    ] {
        assert_contains(CONTROL_MAP, fragment);
    }

    for fragment in [
        "string? read_note(string repo_path, i64 file_id);",
        "void write_note(string repo_path, i64 file_id, string content_md);",
        "FileNotFound(string path);",
        "PermissionDenied(string path);",
        "Io(string message);",
        "Db(string message);",
    ] {
        assert_contains(CORE_API, fragment);
        assert_contains(UDL, fragment);
    }

    for fragment in [
        "### `read_note(repoPath, fileId) throws -> String?`",
        "### `write_note(repoPath, fileId, contentMd) throws`",
        "DB `notes` 表",
        "物理文件 `<filename>.md`",
        "`InFlightTracker` 标记避免 watcher",
        "Stage 1 先用 `get_file` + `list_changes` + `read_note` 组合",
    ] {
        assert_contains(CORE_API, fragment);
    }

    for fragment in [
        "保存失败不能清空用户输入",
        "Core `read_note(repoPath, fileId)`。",
        "Core `write_note(repoPath, fileId, contentMd)`。",
        "停止输入约 800ms 后保存",
        "文件缺失：允许查看已有笔记；禁用写入",
        "Preview 未实现时不影响 Stage 1 验收。",
    ] {
        assert_contains(S1_14_DETAIL_NOTE, fragment);
    }

    for fragment in [
        "C1-14 exposes this read-only query",
        "This API must not create note rows",
        "C1-14 writes exactly one note",
        "The app layer owns `InFlightTracker`",
        "Failed writes must preserve the previous note",
    ] {
        assert_contains(API_RS, fragment);
    }

    for fragment in [
        "validate_previous_sidecar",
        "SidecarRollback::capture",
        "write_sidecar_atomically",
        "SidecarWritePolicy::CreateNew",
        "persist_temp_without_replace",
        "rollback.restore()?",
    ] {
        assert_contains(NOTE_RS, fragment);
    }

    for fragment in [
        "INSERT INTO notes",
        "ON CONFLICT(file_id) DO UPDATE",
        "INSERT INTO change_log",
        "'edited_note'",
        "tx.commit()",
    ] {
        assert_contains(DB_NOTE_RS, fragment);
    }
}

#[test]
fn read_write_note_integration_verify_real_detail_note_round_trip_has_no_mock_gap() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("contract.pdf", b"contract bytes");
    let source_before = fs::read(&source).expect("read source before note flow");

    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import file for detail-note integration");
    let target_before =
        fs::read(repo.path().join(&imported.path)).expect("read target before note");
    let content = "# 客户A 2026 Q1 合同\n\n- 处理状态：已核对金额".to_owned();

    assert_eq!(read_note(path_string(repo.path()), imported.id), Ok(None));
    let detail = get_file(path_string(repo.path()), imported.id).expect("get detail context");
    assert_eq!(detail.id, imported.id);

    write_note(path_string(repo.path()), imported.id, content.clone()).expect("write note");

    assert_eq!(
        read_note(path_string(repo.path()), imported.id),
        Ok(Some(content.clone()))
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), &imported.path)).expect("read sidecar note"),
        content
    );
    assert_eq!(
        note_content(repo.path(), imported.id).as_deref(),
        Some(content.as_str())
    );

    let changes = list_changes(path_string(repo.path()), edited_note_filter(imported.id))
        .expect("list notes");
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].file_id, Some(imported.id));
    assert_eq!(changes[0].action, "edited_note");
    let detail_json: Value =
        serde_json::from_str(&changes[0].detail_json).expect("parse edited_note detail");
    assert_eq!(detail_json["length_before"], 0);
    assert_eq!(detail_json["length_after"], content.chars().count() as i64);
    assert_eq!(detail_json["by"], "user");

    assert_eq!(
        fs::read(&source).expect("read source after note flow"),
        source_before
    );
    assert_eq!(
        fs::read(repo.path().join(&imported.path)).expect("read target after note flow"),
        target_before
    );
}

#[test]
fn read_write_note_integration_verify_missing_file_allows_read_but_rejects_write() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("contract.pdf", b"contract bytes");
    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import file for missing-file note flow");
    let content = "saved note".to_owned();

    write_note(path_string(repo.path()), imported.id, content.clone()).expect("write note");
    fs::remove_file(repo.path().join(&imported.path)).expect("remove target file");

    assert_eq!(
        read_note(path_string(repo.path()), imported.id),
        Ok(Some(content.clone()))
    );
    assert!(matches!(
        write_note(
            path_string(repo.path()),
            imported.id,
            "new draft".to_owned()
        ),
        Err(CoreError::FileNotFound { .. })
    ));

    assert_eq!(
        read_note(path_string(repo.path()), imported.id),
        Ok(Some(content.clone()))
    );
    assert_eq!(
        fs::read_to_string(sidecar_path(repo.path(), &imported.path))
            .expect("read preserved sidecar note"),
        content
    );
    assert_eq!(
        note_content(repo.path(), imported.id).as_deref(),
        Some(content.as_str())
    );
    assert_eq!(edited_note_count(repo.path(), imported.id), 1);
}

#[test]
fn read_write_note_integration_verify_unconfirmed_sidecar_is_not_overwritten() {
    let repo = initialized_repo();
    let (_source_root, source) = source_file("contract.pdf", b"contract bytes");
    let imported = import_file(
        path_string(repo.path()),
        path_string(&source),
        copied_options(),
    )
    .expect("import file for unconfirmed sidecar check");
    let sidecar = sidecar_path(repo.path(), &imported.path);
    fs::write(&sidecar, "user-authored sidecar").expect("write unconfirmed sidecar");

    let result = write_note(path_string(repo.path()), imported.id, "new note".to_owned());

    assert_eq!(
        result,
        Err(CoreError::permission_denied("permission denied"))
    );
    assert_eq!(
        fs::read_to_string(&sidecar).expect("read preserved user sidecar"),
        "user-authored sidecar"
    );
    assert_eq!(read_note(path_string(repo.path()), imported.id), Ok(None));
    assert_eq!(note_content(repo.path(), imported.id), None);
    assert_eq!(edited_note_count(repo.path(), imported.id), 0);
}
