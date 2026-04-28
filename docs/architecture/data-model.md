# 数据模型

> AreaMatrix 的元数据全部存储在资料库内的 SQLite 单文件 `<repo>/.areamatrix/index.db` 中。本文给出完整 schema、CRUD SQL、关键索引的 EXPLAIN 输出、容量预估方法论。
>
> 阅读时长：约 14 分钟。

---

## 数据存储位置

| 数据 | 位置 | 形式 |
|---|---|---|
| 用户文件 | `<repo>/...` | 标准文件，可来自新建目录或已有目录 |
| 元数据 / 改动日志 | `<repo>/.areamatrix/index.db` | SQLite |
| 用户配置 | `~/Library/Application Support/AreaMatrix/config.json` | JSON |
| 分类规则 | `<repo>/.areamatrix/classifier.yaml` | YAML |
| 自动概览 | `<repo>/.areamatrix/generated/*.md`，可选 `<repo>/AREAMATRIX.md` | Markdown |
| 临时事务区 | `<repo>/.areamatrix/staging/` | 标准文件 |
| 应用日志 | `~/Library/Logs/AreaMatrix/*.log` | 文本 |
| change_log 归档 | `<repo>/.areamatrix/archives/changes-YYYY-MM.jsonl` | 文本 |

DB 放在资料库内（而不是 `~/Library/Application Support/`）的理由：

- 用户**带走资料库时元数据一起带走**
- iCloud 同步资料库时元数据自动同步
- 删除资料库 = 完整清理（不留垃圾）

---

## SQLite 配置

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 268435456;
PRAGMA cache_size = -65536;
PRAGMA busy_timeout = 5000;
```

| Pragma | 选择理由 |
|---|---|
| `journal_mode = WAL` | 读写并发更好；崩溃恢复 |
| `foreign_keys = ON` | SQLite 默认关闭，必须显式打开 |
| `synchronous = NORMAL` | 配合 WAL 已足够安全；FULL 模式过于保守 |
| `temp_store = MEMORY` | 临时表/索引放内存，提速 |
| `mmap_size = 256MB` | 大库下显著降低 IO |
| `cache_size = -65536` | 64MB page cache（负数为 KB） |
| `busy_timeout = 5000` | 写并发自动等待 5s 而非立即返回 SQLITE_BUSY |

---

## 完整 Schema

```sql
-- core/src/db/schema.sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;

CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  original_name TEXT NOT NULL,
  current_name TEXT NOT NULL,
  category TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  hash_sha256 TEXT NOT NULL,
  storage_mode TEXT NOT NULL CHECK (storage_mode IN ('moved', 'copied', 'indexed')),
  source_path TEXT,
  imported_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('staging', 'active', 'deleted'))
);

CREATE INDEX IF NOT EXISTS idx_files_category_active
  ON files(category, imported_at DESC)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_files_hash_active
  ON files(hash_sha256)
  WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_files_status ON files(status);
CREATE INDEX IF NOT EXISTS idx_files_imported_at ON files(imported_at DESC);

CREATE TABLE IF NOT EXISTS change_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_id INTEGER,
  action TEXT NOT NULL CHECK (action IN (
    'imported','renamed','moved','edited_note',
    'deleted','restored','external_modified'
  )),
  detail_json TEXT NOT NULL,
  occurred_at INTEGER NOT NULL,
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_changelog_time ON change_log(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_file ON change_log(file_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_action ON change_log(action, occurred_at DESC);

CREATE TABLE IF NOT EXISTS notes (
  file_id INTEGER PRIMARY KEY,
  content_md TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tags (
  file_id INTEGER NOT NULL,
  tag TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (file_id, tag),
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag);

CREATE TABLE IF NOT EXISTS fs_event_cursor (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  last_event_id INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS repo_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

INSERT OR IGNORE INTO schema_version (version, applied_at)
VALUES (1, strftime('%s', 'now'));
```

---

## 表关系图

```mermaid
erDiagram
    files ||--o{ change_log : "logs"
    files ||--o| notes : "annotates"
    files ||--o{ tags : "tagged"
    files {
        int id PK
        string path UK
        string original_name
        string current_name
        string category
        int size_bytes
        string hash_sha256
        string storage_mode
        string source_path
        int imported_at
        int updated_at
        int deleted_at
        string status
    }
    change_log {
        int id PK
        int file_id FK
        string action
        string detail_json
        int occurred_at
    }
    notes {
        int file_id PK_FK
        string content_md
        int updated_at
    }
    tags {
        int file_id PK_FK
        string tag PK
        int added_at
    }
    fs_event_cursor {
        int id PK
        int last_event_id
        int updated_at
    }
    repo_config {
        string key PK
        string value
        int updated_at
    }
    schema_version {
        int version PK
        int applied_at
    }
```

---

## CRUD SQL（按表）

### files: INSERT (staging)

```sql
INSERT INTO files (
  path, original_name, current_name, category,
  size_bytes, hash_sha256, storage_mode, source_path,
  imported_at, updated_at, status
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'staging');
```

### files: 提升为 active

```sql
UPDATE files
   SET path = ?, current_name = ?, status = 'active', updated_at = ?
 WHERE id = ?;
```

### files: SELECT by path

```sql
SELECT id, path, original_name, current_name, category,
       size_bytes, hash_sha256, storage_mode, source_path,
       imported_at, updated_at, deleted_at, status
  FROM files
 WHERE path = ? AND status != 'staging'
 LIMIT 1;
```

### files: SELECT by hash (active)

```sql
SELECT id, path, current_name, category, size_bytes
  FROM files
 WHERE hash_sha256 = ? AND status = 'active'
 LIMIT 1;
```

### files: list active in category

```sql
SELECT id, path, current_name, size_bytes, hash_sha256, imported_at
  FROM files
 WHERE category = ? AND status = 'active'
 ORDER BY imported_at DESC
 LIMIT ? OFFSET ?;
```

### files: rename / move (combined UPDATE)

```sql
UPDATE files
   SET path = ?, current_name = ?, category = ?, updated_at = ?
 WHERE id = ?;
```

### files: 软删除

```sql
UPDATE files
   SET status = 'deleted', deleted_at = ?, updated_at = ?
 WHERE id = ?;
```

### files: 物理删除（仅 staging 行）

```sql
DELETE FROM files WHERE id = ? AND status = 'staging';
```

### files: 列出 staging 行（recovery 用）

```sql
SELECT id, path FROM files WHERE status = 'staging';
```

### files: 分类总览

```sql
SELECT
  category,
  COUNT(*) AS file_count,
  SUM(size_bytes) AS total_bytes,
  MAX(imported_at) AS latest_import
FROM files
WHERE status = 'active'
GROUP BY category
ORDER BY category;
```

### files: 跨分类时间窗

```sql
SELECT id, path, category, imported_at
  FROM files
 WHERE status = 'active'
   AND imported_at >= ?
   AND imported_at < ?
 ORDER BY imported_at DESC
 LIMIT ? OFFSET ?;
```

### change_log: INSERT

```sql
INSERT INTO change_log (file_id, action, detail_json, occurred_at)
VALUES (?, ?, ?, ?);
```

### change_log: SELECT 单文件历史

```sql
SELECT id, action, detail_json, occurred_at
  FROM change_log
 WHERE file_id = ?
 ORDER BY occurred_at DESC
 LIMIT ?;
```

### change_log: SELECT 近期跨文件

```sql
SELECT cl.id, cl.file_id, cl.action, cl.detail_json, cl.occurred_at,
       f.path, f.category
  FROM change_log cl
  LEFT JOIN files f ON f.id = cl.file_id
 WHERE cl.occurred_at >= ?
 ORDER BY cl.occurred_at DESC
 LIMIT ?;
```

### change_log: GC（按时间）

```sql
DELETE FROM change_log
 WHERE occurred_at < ?
   AND id NOT IN (SELECT id FROM change_log ORDER BY occurred_at DESC LIMIT ?);
```

### notes: UPSERT

```sql
INSERT INTO notes (file_id, content_md, updated_at)
VALUES (?, ?, ?)
ON CONFLICT(file_id) DO UPDATE SET
  content_md = excluded.content_md,
  updated_at = excluded.updated_at;
```

### notes: SELECT

```sql
SELECT content_md, updated_at FROM notes WHERE file_id = ?;
```

### tags: 批量加标签

```sql
INSERT OR IGNORE INTO tags (file_id, tag, added_at)
VALUES (?, ?, ?), (?, ?, ?), (?, ?, ?);
```

### tags: 按标签查文件

```sql
SELECT f.id, f.path, f.current_name, f.category
  FROM tags t
  JOIN files f ON f.id = t.file_id
 WHERE t.tag = ? AND f.status = 'active'
 ORDER BY t.added_at DESC
 LIMIT ?;
```

### fs_event_cursor: 读

```sql
SELECT last_event_id FROM fs_event_cursor WHERE id = 1;
```

### fs_event_cursor: 写

```sql
INSERT INTO fs_event_cursor (id, last_event_id, updated_at)
VALUES (1, ?, ?)
ON CONFLICT(id) DO UPDATE SET
  last_event_id = excluded.last_event_id,
  updated_at = excluded.updated_at;
```

---

## 关键查询的 EXPLAIN QUERY PLAN

数据集：files 表 10 万行（active 9 万、deleted 9 千、staging 1 千）。

### Q1：按 path 查（应走 UNIQUE index）

```sql
EXPLAIN QUERY PLAN
SELECT id, current_name FROM files WHERE path = 'docs/contract.pdf';
```

输出：

```text
SEARCH files USING INDEX sqlite_autoindex_files_1 (path=?)
```

性能：< 0.1 ms。`sqlite_autoindex_files_1` 是 `path UNIQUE` 自动建的索引。

### Q2：按 hash 查 active（应走 partial index）

```sql
EXPLAIN QUERY PLAN
SELECT id, path FROM files WHERE hash_sha256 = ? AND status = 'active';
```

输出：

```text
SEARCH files USING INDEX idx_files_hash_active (hash_sha256=?)
```

性能：< 0.5 ms。`partial index` 只覆盖 active 行（约 90% 行），但查询提速明显。

### Q3：分类列表（应走 partial composite index）

```sql
EXPLAIN QUERY PLAN
SELECT id, current_name FROM files
WHERE category = 'docs' AND status = 'active'
ORDER BY imported_at DESC LIMIT 200;
```

输出：

```text
SEARCH files USING INDEX idx_files_category_active (category=?)
```

`(category, imported_at DESC)` 复合索引同时覆盖 WHERE 和 ORDER BY，无 sort 步骤。性能：< 5 ms。

### Q4：分类总览（GROUP BY）

```sql
EXPLAIN QUERY PLAN
SELECT category, COUNT(*), SUM(size_bytes)
FROM files WHERE status = 'active' GROUP BY category;
```

输出：

```text
SCAN files USING INDEX idx_files_category_active
USE TEMP B-TREE FOR GROUP BY
```

性能：10 万行约 30 ms（必须扫整索引）。MVP 可接受；大库下加物化视图。

### Q5：单文件 change_log 历史

```sql
EXPLAIN QUERY PLAN
SELECT action, detail_json, occurred_at FROM change_log
WHERE file_id = 42 ORDER BY occurred_at DESC LIMIT 100;
```

输出：

```text
SEARCH change_log USING INDEX idx_changelog_file (file_id=?)
```

`(file_id, occurred_at DESC)` 复合索引；性能 < 1 ms。

### Q6：近 7 天跨文件改动

```sql
EXPLAIN QUERY PLAN
SELECT cl.action, cl.detail_json, cl.occurred_at, f.path
FROM change_log cl LEFT JOIN files f ON f.id = cl.file_id
WHERE cl.occurred_at >= ? ORDER BY cl.occurred_at DESC LIMIT 200;
```

输出：

```text
SEARCH cl USING INDEX idx_changelog_time (occurred_at>?)
SEARCH f USING INTEGER PRIMARY KEY (rowid=?)
```

性能：< 10 ms（30 天 5 万条 change_log）。

### Q7：full table scan（应避免）

```sql
EXPLAIN QUERY PLAN
SELECT * FROM files WHERE current_name LIKE '%2026%';
```

输出：

```text
SCAN files
```

10 万行约 100 ms。Stage 2 起加 FTS5 全文搜索表：

```sql
CREATE VIRTUAL TABLE files_fts USING fts5(
  current_name, original_name, content='files', content_rowid='id'
);
```

---

## 容量预估方法论

### 单行字节数估算

| 表 | 平均行字节 | 来源 |
|---|---|---|
| `files` | 320 字节 | 见下表 |
| `change_log` | 280 字节 | id+file_id+action+detail_json(200)+timestamp |
| `notes` | 1024 字节 | 平均 1KB markdown |
| `tags` | 64 字节 | id+tag(16)+timestamp |

`files` 单行细节：

| 字段 | 平均字节 |
|---|---|
| id | 8 |
| path | 60 (含路径) |
| original_name | 32 |
| current_name | 32 |
| category | 12 |
| size_bytes | 8 |
| hash_sha256 | 64 (hex 字符串) |
| storage_mode | 8 |
| source_path | 60 (NULL or 含路径) |
| imported_at + updated_at + deleted_at | 24 |
| status | 8 |
| 行开销 + 索引 | ~40 |
| **合计** | **~320** |

### 不同规模

| 文件数 | files 大小 | change_log 估算 | notes (10% 文件有) | 总 DB 大小 | mmap 命中率 |
|---|---|---|---|---|---|
| 1,000 | 320 KB | 1 MB (≈ 4× 改动) | 100 KB | ~1.5 MB | 100% |
| 10,000 | 3.2 MB | 10 MB | 1 MB | ~15 MB | 100% |
| 100,000 | 32 MB | 100 MB | 10 MB | ~150 MB | 大部分 |
| 1,000,000 | 320 MB | 1 GB | 100 MB | ~1.5 GB | 部分 |

### 性能预期

| 操作 | 1k 文件 | 10k | 100k | 1M |
|---|---|---|---|---|
| 按 path 查（UNIQUE index） | < 0.1 ms | < 0.1 ms | < 0.1 ms | < 0.5 ms |
| 按 hash 查（partial index） | < 0.5 ms | < 0.5 ms | < 0.5 ms | < 2 ms |
| 列分类（200 条） | < 1 ms | < 2 ms | < 5 ms | < 20 ms |
| 分类总览（GROUP BY） | < 1 ms | < 5 ms | < 30 ms | < 300 ms |
| 单文件历史 | < 0.5 ms | < 1 ms | < 1 ms | < 5 ms |
| 全表扫描（无索引 LIKE） | < 5 ms | < 30 ms | < 300 ms | 数秒 |

### vacuum / analyze 节奏

```sql
ANALYZE;       -- 每月一次自动跑（统计信息）
VACUUM;        -- 删 deleted 行 > 30% 时手动跑（重整页）
```

`VACUUM` 期间需独占锁，不在用户活跃时跑。

---

## 关键不变量

| 不变量 | SQL 表达 | 校验时机 |
|---|---|---|
| INV-D1 同 path 唯一 active | `path UNIQUE` | INSERT |
| INV-D2 staging 行不可见 | 用户查询带 `WHERE status = 'active'` | 编码规范 |
| INV-D3 软删除保留历史 | `deleted_at` + change_log | INSERT change_log |
| INV-D4 schema 版本可追溯 | schema_version 单调 | migration |
| INV-D5 change_log action 在枚举内 | CHECK 约束 | INSERT |
| INV-D6 storage_mode 在枚举内 | CHECK 约束 | INSERT |
| INV-D7 status 在枚举内 | CHECK 约束 | INSERT/UPDATE |

`fsck` 命令（Stage 2）跑：

```sql
SELECT id FROM files WHERE status = 'active' AND deleted_at IS NOT NULL;
SELECT id FROM files WHERE hash_sha256 NOT GLOB '[0-9a-f]*' OR LENGTH(hash_sha256) != 64;
SELECT cl.id FROM change_log cl LEFT JOIN files f ON f.id = cl.file_id
  WHERE cl.action != 'deleted' AND cl.file_id IS NOT NULL AND f.id IS NULL;
```

---

## Migration 策略

### 文件布局

```text
core/src/db/
├── schema.sql              # v1 完整 schema
└── migrations/
    ├── m_002_add_xxx.sql
    ├── m_003_xxx.sql
    └── ...
```

### 启动时检查

```rust
fn run_migrations(conn: &mut rusqlite::Connection) -> CoreResult<()> {
    let current: i64 = conn.query_row(
        "SELECT COALESCE(MAX(version), 0) FROM schema_version",
        [], |r| r.get(0)
    )?;

    let latest: i64 = LATEST_VERSION;
    for v in (current + 1)..=latest {
        let sql = match v {
            2 => include_str!("migrations/m_002_add_xxx.sql"),
            _ => continue,
        };
        let tx = conn.transaction()?;
        tx.execute_batch(sql)?;
        tx.execute(
            "INSERT INTO schema_version (version, applied_at) VALUES (?1, strftime('%s', 'now'))",
            rusqlite::params![v],
        )?;
        tx.commit()?;
        tracing::info!("applied migration v{}", v);
    }
    Ok(())
}
```

详见 [migration.md](migration.md)。

---

## 备份与恢复

### 自动备份

应用启动时如果检测到 `index.db` 存在：

- 创建 `.areamatrix/index.db.bak.<timestamp>`（保留最近 5 份）
- 每次 migration 前额外创建 `.areamatrix/index.db.pre-v<N>.bak`

### 手动恢复

```bash
cp <repo>/.areamatrix/index.db.bak.<timestamp> <repo>/.areamatrix/index.db
```

### 完全重建

应用提供「从文件系统重新索引」按钮：

- 扫描 `<repo>/`，跳过 `.areamatrix/` 与可忽略目录，对每个用户文件计算 hash 并 INSERT 到 files
- change_log 全部丢失

> 完全重建会丢失改动历史，但用户的文件本身永远不会丢。这是产品级的"真相在文件系统"承诺的体现。

---

## 100 万文件以上的考量

100 万文件以上是 Stage 4 才考虑，超出 MVP 范围。需要的改造：

- files 表分片（按 category 或时间分区）
- 全文搜索切换到独立服务（不在 SQLite）
- 增量备份策略
- WAL checkpoint 自动调度

---

## Related

- [overview.md](overview.md)
- [transactional-import.md](transactional-import.md)
- [source-of-truth.md](source-of-truth.md)
- [migration.md](migration.md)
- [../modules/storage.md](../modules/storage.md)
- [../modules/change-log.md](../modules/change-log.md)
