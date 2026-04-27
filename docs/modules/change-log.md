# 模块：改动日志（change_log）

> 所有文件级动作都被记录到 SQLite `change_log` 表。详情面板的「改动」Tab、根 README 的「近期改动」段都从这里来。
>
> 阅读时长：约 4 分钟。

---

## 设计原则

1. **append-only**：change_log 永不更新已存在的记录，只 INSERT
2. **结构化但灵活**：`detail_json` 字段存任意 schema 的 JSON
3. **不阻塞**：写日志失败不能让主操作失败（但要打 tracing 警告）
4. **永久保留**：MVP 不做日志清理；Stage 2 起加用户可控的保留策略
5. **DB 损坏不丢用户文件**：日志只是元信息，丢失无伤大雅

---

## 动作类型

```rust
pub enum ChangeAction {
    Imported,           // 导入
    Renamed,            // 应用内重命名
    Moved,              // 跨分类移动
    EditedNote,         // 笔记编辑
    Deleted,            // 软删除
    Restored,           // 从软删除恢复
    ExternalModified,   // 外部修改（含外部 rename / 内容改动）
}
```

| Action | by 字段可选值 | 典型 detail_json |
|---|---|---|
| Imported | "user" | `{"source": "/path/to/orig", "mode": "copied"}` |
| Renamed | "user" | `{"from": "a.pdf", "to": "b.pdf"}` |
| Moved | "user" | `{"from_category": "docs", "to_category": "code"}` |
| EditedNote | "user" / "external" | `{"length_before": 100, "length_after": 200}` |
| Deleted | "user" / "external" / "startup_reconcile" | `{"hard": false}` |
| Restored | "user" / "external" | `{}` |
| ExternalModified | "external" | `{"kind": "rename", "from": "...", "to": "..."}` |

---

## 写入 API（内部）

文件：`core/src/db/changes.rs`

```rust
pub fn insert(
    tx: &Transaction,
    file_id: i64,
    action: ChangeAction,
    detail: serde_json::Value,
) -> CoreResult<i64> {
    let action_str = action.as_str();
    let detail_str = serde_json::to_string(&detail)?;
    let now = chrono::Utc::now().timestamp();
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, ?2, ?3, ?4)",
        rusqlite::params![file_id, action_str, detail_str, now],
    )?;
    Ok(tx.last_insert_rowid())
}
```

调用方：

- storage::ops 在事务内 INSERT
- sync::handle_* 在事务内 INSERT
- 笔记编辑、删除、移动等所有写入路径

---

## 读取 API（外部）

```rust
pub fn list_changes(
    repo: &Path,
    filter: ChangeFilter,
) -> CoreResult<Vec<ChangeLogEntry>>;

pub struct ChangeFilter {
    pub file_id: Option<i64>,
    pub action: Option<String>,
    pub since: Option<i64>,
    pub limit: i64,  // 默认 100
}
```

```rust
pub fn list_changes(repo: &Path, filter: ChangeFilter) -> CoreResult<Vec<ChangeLogEntry>> {
    db::with_repo(repo, |conn| {
        let mut sql = String::from(
            "SELECT id, file_id, action, detail_json, occurred_at FROM change_log WHERE 1=1"
        );
        let mut params: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();
        if let Some(fid) = filter.file_id {
            sql.push_str(" AND file_id = ?");
            params.push(Box::new(fid));
        }
        if let Some(action) = filter.action {
            sql.push_str(" AND action = ?");
            params.push(Box::new(action));
        }
        if let Some(since) = filter.since {
            sql.push_str(" AND occurred_at >= ?");
            params.push(Box::new(since));
        }
        sql.push_str(" ORDER BY occurred_at DESC LIMIT ?");
        params.push(Box::new(filter.limit.max(1)));

        let mut stmt = conn.prepare(&sql)?;
        let params_refs: Vec<&dyn rusqlite::ToSql> = params.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(params_refs.as_slice(), |row| {
            Ok(ChangeLogEntry {
                id: row.get(0)?,
                file_id: row.get(1)?,
                action: row.get::<_, String>(2)?.into(),
                detail_json: row.get(3)?,
                occurred_at: row.get(4)?,
            })
        })?;
        rows.collect::<Result<_, _>>().map_err(Into::into)
    })
}
```

---

## UI 展示

详情面板「改动」Tab：

```
2026-04-26 14:32  imported (来源: /Users/.../Downloads/contract.pdf, mode: Copied)
2026-04-25 09:11  renamed (合同.pdf → 契约.pdf)
2026-04-25 09:12  external_modified (rename: 契约.pdf → 契约_2026Q1.pdf)
```

UI 把 detail_json 解构展示。Stage 1 用简单字符串拼接，Stage 2 加结构化展示组件。

---

## detail_json 约定

为了让 UI / README 解析方便，约定每个 action 的 detail_json schema：

```json
// imported
{"source": "/abs/path", "mode": "moved|copied|indexed", "by": "user"}

// renamed
{"from": "old.pdf", "to": "new.pdf", "by": "user"}

// moved
{"from_category": "docs", "to_category": "code", "by": "user"}

// edited_note
{"length_before": 100, "length_after": 200, "by": "user"}

// deleted
{"hard": false, "by": "user|external|startup_reconcile"}

// restored
{"reason": "user|external_recreated", "by": "..."}

// external_modified
{
  "kind": "rename|move|content",
  "from": "...",   // 可选
  "to": "...",     // 可选
  "by": "external"
}
```

---

## 不变量

| 不变量 | 说明 |
|---|---|
| INV-CL1 | `change_log.occurred_at` 单调（同一线程内插入时间戳单调） |
| INV-CL2 | 文件软删除后，关联日志 file_id 仍指向 files.id（不级联删除） |
| INV-CL3 | files 物理删除时，change_log.file_id 置 NULL（FK ON DELETE SET NULL） |

---

## 保留策略

| Stage | 策略 |
|---|---|
| 1 (MVP) | 永久保留 |
| 2 | 设置中加"保留近 N 天/M 条"开关，超出归档为只读 |
| 3 | 自动归档为 JSONL 文件 `.areamatrix/archives/changes-YYYYMM.jsonl` 后从 DB 删除 |

10 万次操作 ≈ 50MB SQLite 数据，单机用户大概 1-2 年才到这个量级。MVP 不优化。

---

## 写入失败的处理

事务内 INSERT change_log 失败 → 整个 import 事务回滚（保证不变量）。

如果 change_log 表本身损坏（极小概率）：

- 启动时 schema 检查会发现
- 应用提示用户："改动历史损坏，可继续使用，但历史记录可能不完整。建议从备份恢复或重新索引。"

---

## 测试

```rust
#[test]
fn import_creates_imported_log() {
    let repo = setup_test_repo();
    let entry = import_file(&repo, &source, opts).unwrap();
    let changes = list_changes(&repo, ChangeFilter {
        file_id: Some(entry.id),
        action: None, since: None, limit: 10,
    }).unwrap();
    assert_eq!(changes.len(), 1);
    assert_eq!(changes[0].action, ChangeAction::Imported);
}

#[test]
fn rename_logs_from_to() {
    let repo = setup_test_repo();
    let entry = import_file(&repo, &src, opts).unwrap();
    rename_file(&repo, entry.id, "new_name.pdf").unwrap();
    let changes = list_changes(&repo, ChangeFilter {
        file_id: Some(entry.id),
        action: Some("renamed".into()),
        since: None, limit: 10,
    }).unwrap();
    let detail: serde_json::Value = serde_json::from_str(&changes[0].detail_json).unwrap();
    assert_eq!(detail["from"], src.file_name().unwrap().to_string_lossy().as_ref());
    assert_eq!(detail["to"], "new_name.pdf");
}

#[test]
fn external_modified_logs() {
    let repo = setup_test_repo_with_file();
    // 模拟外部 rename
    let event = ExternalEvent { /* ... */ };
    sync_external_changes(&repo, vec![event]).unwrap();
    let changes = list_changes(&repo, ChangeFilter {
        file_id: None,
        action: Some("external_modified".into()),
        since: None, limit: 10,
    }).unwrap();
    assert!(!changes.is_empty());
}
```

---

## Related

- [../architecture/data-model.md](../architecture/data-model.md)
- [storage.md](storage.md)
- [readme-gen.md](readme-gen.md)
