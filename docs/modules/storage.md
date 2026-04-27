# 模块：文件存储（storage）

> 负责所有文件级写操作：事务式导入、移动 / 复制 / 索引、SHA256、冲突重命名、软删除、外部变化处理。
>
> 阅读时长：约 6 分钟。

---

## 职责

| 子模块 | 文件 | 职责 |
|---|---|---|
| ops | `core/src/storage/ops.rs` | import_file 主流程、状态机 |
| hash | `core/src/storage/hash.rs` | SHA256 计算 |
| conflict | `core/src/storage/conflict.rs` | 同名冲突时追加 `_1`、`_2` |
| recovery | `core/src/storage/recovery.rs` | 启动时清 staging |
| reindex | `core/src/storage/reindex.rs` | 从文件系统重建索引 |

---

## 关键 API

```rust
pub fn import_file(
    repo: &Path,
    src: &Path,
    options: ImportOptions,
) -> CoreResult<FileEntry>;

pub fn delete_file(repo: &Path, file_id: i64, hard: bool) -> CoreResult<()>;

pub fn rename_file(repo: &Path, file_id: i64, new_name: &str) -> CoreResult<FileEntry>;

pub fn move_to_category(repo: &Path, file_id: i64, new_category: &str) -> CoreResult<FileEntry>;

pub fn recover_on_startup(repo: &Path) -> CoreResult<RecoveryReport>;

pub fn reindex_from_filesystem(repo: &Path) -> CoreResult<ReindexReport>;
```

详见 [../api/core-api.md](../api/core-api.md)。

---

## import_file 完整流程

详见 [../architecture/transactional-import.md](../architecture/transactional-import.md)。简短版：

```mermaid
flowchart LR
    A[1 复制/移动到 staging] --> B[2 算 hash]
    B --> C{3 hash 重复?}
    C -->|是| D[按 strategy 处理]
    C -->|否| E[4 classify]
    E --> F[5 解决冲突文件名]
    F --> G[6 BEGIN TX]
    G --> H[INSERT staging row]
    H --> I[rename staging → final]
    I --> J[UPDATE active]
    J --> K[INSERT change_log]
    K --> L[COMMIT]
    L --> M[7 重新生成 README]
```

---

## hash 模块

```rust
// core/src/storage/hash.rs
use sha2::{Digest, Sha256};
use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;

pub fn sha256_file(path: &Path) -> std::io::Result<String> {
    let f = File::open(path)?;
    let mut reader = BufReader::with_capacity(64 * 1024, f);
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 { break; }
        hasher.update(&buf[..n]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}
```

### 流式 + 复制并发优化（Stage 2）

复制和 hash 可同步进行，省一次完整 IO：

```rust
pub fn copy_and_hash(src: &Path, dst: &Path) -> std::io::Result<String> {
    let mut reader = BufReader::with_capacity(64 * 1024, File::open(src)?);
    let mut writer = BufWriter::with_capacity(64 * 1024, File::create(dst)?);
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 { break; }
        writer.write_all(&buf[..n])?;
        hasher.update(&buf[..n]);
    }
    writer.flush()?;
    Ok(format!("{:x}", hasher.finalize()))
}
```

---

## conflict 模块（同名冲突）

`docs/contract.pdf` 已存在 → 新文件命名为 `contract_1.pdf` → `_2`...

```rust
// core/src/storage/conflict.rs
use std::path::{Path, PathBuf};

pub fn resolve_target(category_dir: &Path, filename: &str) -> std::io::Result<PathBuf> {
    let candidate = category_dir.join(filename);
    if !candidate.exists() {
        return Ok(candidate);
    }
    let stem = std::path::Path::new(filename).file_stem()
        .and_then(|s| s.to_str()).unwrap_or(filename);
    let ext = std::path::Path::new(filename).extension()
        .and_then(|s| s.to_str()).map(|e| format!(".{}", e)).unwrap_or_default();

    for i in 1..1000 {
        let new_name = format!("{}_{}{}", stem, i, ext);
        let path = category_dir.join(&new_name);
        if !path.exists() {
            return Ok(path);
        }
    }
    Err(std::io::Error::new(
        std::io::ErrorKind::AlreadyExists,
        "exceeded 1000 conflict suffix attempts"
    ))
}
```

### 注意

- 1000 次上限是防御无限循环（实际场景中 _999 不会出现）
- 使用 `file_stem` / `extension` 处理多层扩展（如 `archive.tar.gz` → stem=`archive.tar`, ext=`gz`）

---

## delete_file

软删除（默认）：DB UPDATE status='deleted'，文件移到 `~/.Trash`：

```rust
pub fn delete_file(repo: &Path, file_id: i64, hard: bool) -> CoreResult<()> {
    let entry = db::with_repo(repo, |c| db::get_file(&c.unchecked_transaction()?, file_id))?;
    let abs_path = repo.join(&entry.path);

    if hard {
        std::fs::remove_file(&abs_path)?;
    } else {
        // 移到 macOS 废纸篓
        trash::delete(&abs_path).map_err(|e| CoreError::Io(e.to_string()))?;
    }

    db::with_repo(repo, |conn| -> CoreResult<()> {
        let tx = conn.transaction()?;
        db::soft_delete(&tx, file_id)?;
        db::insert_change(&tx, file_id, ChangeAction::Deleted,
            json!({"hard": hard, "by": "user"}))?;
        tx.commit()?;
        Ok(())
    })?;

    crate::readme::regenerate_for_category(repo, &entry.category)?;
    Ok(())
}
```

依赖 `trash` crate（跨平台废纸篓）。

---

## rename_file

```rust
pub fn rename_file(repo: &Path, file_id: i64, new_name: &str) -> CoreResult<FileEntry> {
    validate_filename(new_name)?;  // 不允许 / \ : * ? " < > |

    let entry = db::with_repo(repo, |c| db::get_file(&c.unchecked_transaction()?, file_id))?;
    let old_abs = repo.join(&entry.path);
    let category_dir = old_abs.parent().unwrap();

    let new_abs = crate::storage::conflict::resolve_target(category_dir, new_name)?;
    let new_relative = new_abs.strip_prefix(repo).unwrap();

    std::fs::rename(&old_abs, &new_abs)?;

    db::with_repo(repo, |conn| -> CoreResult<()> {
        let tx = conn.transaction()?;
        db::update_path(&tx, file_id, &new_relative.to_string_lossy(), new_name)?;
        db::insert_change(&tx, file_id, ChangeAction::Renamed,
            json!({"from": entry.current_name, "to": new_name}))?;
        tx.commit()?;
        Ok(())
    })?;

    crate::readme::regenerate_for_category(repo, &entry.category)?;
    db::with_repo(repo, |c| db::get_file(&c.unchecked_transaction()?, file_id))
}
```

---

## move_to_category

跨分类移动 = 跨目录 rename + UPDATE category。文件物理位置变化通过 InFlightTracker 标记防外部循环：

```rust
pub fn move_to_category(repo: &Path, file_id: i64, new_category: &str) -> CoreResult<FileEntry> {
    let entry = db::get_file_by_id(repo, file_id)?;
    let old_abs = repo.join(&entry.path);
    let new_dir = repo.join(new_category);
    std::fs::create_dir_all(&new_dir)?;
    let new_abs = crate::storage::conflict::resolve_target(&new_dir, &entry.current_name)?;
    let new_rel = new_abs.strip_prefix(repo).unwrap();

    std::fs::rename(&old_abs, &new_abs)?;

    db::with_repo(repo, |conn| -> CoreResult<()> {
        let tx = conn.transaction()?;
        db::update_path_and_category(&tx, file_id,
            &new_rel.to_string_lossy(), new_category)?;
        db::insert_change(&tx, file_id, ChangeAction::Moved,
            json!({"from_category": entry.category, "to_category": new_category}))?;
        tx.commit()?;
        Ok(())
    })?;

    crate::readme::regenerate_for_category(repo, &entry.category)?;
    crate::readme::regenerate_for_category(repo, new_category)?;
    Ok(db::get_file_by_id(repo, file_id)?)
}
```

---

## reindex_from_filesystem

```rust
pub fn reindex_from_filesystem(repo: &Path) -> CoreResult<ReindexReport> {
    let mut report = ReindexReport::default();
    let walker = walkdir::WalkDir::new(repo)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| !is_areamatrix_internal(e));  // 跳过 .areamatrix/

    for entry in walker {
        let entry = match entry {
            Ok(e) => e,
            Err(e) => { report.errors.push(e.to_string()); continue; }
        };
        if !entry.file_type().is_file() { continue; }

        let abs = entry.path();
        let rel = abs.strip_prefix(repo).unwrap();
        let path_str = rel.to_string_lossy().to_string();

        if is_areamatrix_internal_path(&path_str) { continue; }
        if is_readme_or_companion_md(&path_str) { continue; }

        let hash = match crate::storage::hash::sha256_file(abs) {
            Ok(h) => h,
            Err(e) => { report.errors.push(e.to_string()); continue; }
        };
        let size = entry.metadata()?.len() as i64;

        match db::find_by_path(repo, &path_str)? {
            Some(existing) if existing.hash_sha256 == hash => {
                report.skipped += 1;
            },
            Some(existing) => {
                db::update_hash(repo, existing.id, &hash, size)?;
                report.updated += 1;
            },
            None => {
                let category = top_level_dir(&path_str)
                    .unwrap_or_else(|| "inbox".to_string());
                let original_name = abs.file_name().unwrap().to_string_lossy().to_string();
                db::insert_active(repo, NewFile {
                    path: path_str,
                    original_name: original_name.clone(),
                    current_name: original_name,
                    category,
                    size_bytes: size,
                    hash_sha256: hash,
                    storage_mode: StorageMode::Indexed,
                    source_path: None,
                    imported_at: chrono::Utc::now().timestamp(),
                })?;
                report.inserted += 1;
            },
        }
    }
    Ok(report)
}
```

---

## 测试

| 测试 | 文件 |
|---|---|
| import 三种模式 | `core/tests/import_modes_test.rs` |
| hash 重复策略 | `core/tests/dedup_test.rs` |
| 冲突重命名 | `core/tests/conflict_test.rs` |
| 中断恢复 | `core/tests/recovery_test.rs` |
| reindex | `core/tests/reindex_test.rs` |

---

## Related

- [../architecture/transactional-import.md](../architecture/transactional-import.md)
- [../architecture/data-model.md](../architecture/data-model.md)
- [classify.md](classify.md)
- [readme-gen.md](readme-gen.md)
