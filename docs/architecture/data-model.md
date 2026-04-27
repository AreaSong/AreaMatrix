# 数据模型

> AreaMatrix 的元数据全部存储在 SQLite 单文件 `~/AreaMatrix/.areamatrix/index.db` 中。本文给出 schema、索引、迁移策略、查询模式、不变量。
>
> 阅读时长：约 8 分钟。

---

## 数据存储位置

| 数据 | 位置 | 形式 |
|---|---|---|
| 用户文件 | `~/AreaMatrix/<category>/...` | 标准文件 |
| 元数据 / 改动日志 | `~/AreaMatrix/.areamatrix/index.db` | SQLite |
| 用户配置 | `~/Library/Application Support/AreaMatrix/config.json` | JSON |
| 分类规则 | `~/AreaMatrix/.areamatrix/classifier.yaml` | YAML |
| 临时事务区 | `~/AreaMatrix/.areamatrix/staging/` | 标准文件 |
| 应用日志 | `~/Library/Logs/AreaMatrix/*.log` | 文本 |

为什么 DB 放在 `.areamatrix/`（资料库内）而不是 `~/Library/Application Support/`：
- 让用户**带走资料库时元数据一起带走**
- iCloud 同步资料库时元数据自动同步
- 删除资料库 = 完整清理（不留垃圾）

---

## SQLite 配置

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;
PRAGMA mmap_size = 268435456;  -- 256MB
```

| Pragma | 选择理由 |
|---|---|
| `journal_mode = WAL` | 读写并发更好；崩溃恢复 |
| `foreign_keys = ON` | SQLite 默认关闭，必须显式打开 |
| `synchronous = NORMAL` | 配合 WAL 已足够安全；FULL 模式过于保守 |
| `temp_store = MEMORY` | 临时表/索引放内存，提速 |
| `mmap_size = 256MB` | 大库下显著降低 IO（个人文件库不会真用满 256MB） |

---

## 完整 Schema

文件位置：`core/src/db/schema.sql`

```sql
-- ============================================================
-- AreaMatrix SQLite Schema v1
-- ============================================================

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;

-- ------------------------------------------------------------
-- schema_version
-- 用于 migration 检测
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL  -- unix epoch seconds
);

-- ------------------------------------------------------------
-- files
-- 资料库中每个文件的元数据
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 资料库相对路径，唯一索引
  -- 形如 "docs/contract.pdf"
  path TEXT NOT NULL UNIQUE,

  -- 用户拖入时的原始文件名
  original_name TEXT NOT NULL,

  -- 当前在资料库中的文件名（可能被分类引擎重命名过）
  current_name TEXT NOT NULL,

  -- 分类英文 slug (docs / code / ...)
  category TEXT NOT NULL,

  -- 字节数
  size_bytes INTEGER NOT NULL,

  -- 内容 SHA256，去重和外部修改识别用
  hash_sha256 TEXT NOT NULL,

  -- 'moved' | 'copied' | 'indexed'
  storage_mode TEXT NOT NULL CHECK (storage_mode IN ('moved', 'copied', 'indexed')),

  -- index 模式时记录原始路径；其他模式可为 NULL
  source_path TEXT,

  -- unix epoch seconds
  imported_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,

  -- 软删除时间戳；NULL = 未删除
  deleted_at INTEGER,

  -- 事务过渡状态：导入中、已落位、已删除
  -- 'staging' 状态的行不应出现在用户视图
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('staging', 'active', 'deleted'))
);

CREATE INDEX IF NOT EXISTS idx_files_category ON files(category) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_files_hash ON files(hash_sha256) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_files_status ON files(status);
CREATE INDEX IF NOT EXISTS idx_files_imported_at ON files(imported_at DESC);

-- ------------------------------------------------------------
-- change_log
-- 不可变的事件日志，每个改动一条记录
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS change_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  -- 关联文件，被删除后置 NULL（保留日志）
  file_id INTEGER,

  -- imported / renamed / moved / edited_note / deleted / external_modified / restored
  action TEXT NOT NULL,

  -- 结构化细节，JSON：{"from": "...", "to": "...", "by": "user|external"}
  detail_json TEXT,

  -- unix epoch seconds
  occurred_at INTEGER NOT NULL,

  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_changelog_time ON change_log(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_file ON change_log(file_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_changelog_action ON change_log(action);

-- ------------------------------------------------------------
-- notes
-- 用户为某文件写的伴生笔记
-- 与磁盘 <filename>.md 双向同步
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notes (
  file_id INTEGER PRIMARY KEY,
  content_md TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- tags
-- 跨分类的 cross-cutting 标签（Stage 2 起激活，schema 提前预留）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tags (
  file_id INTEGER NOT NULL,
  tag TEXT NOT NULL,
  added_at INTEGER NOT NULL,
  PRIMARY KEY (file_id, tag),
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag);

-- ------------------------------------------------------------
-- fs_event_cursor
-- 持久化 FSEventStream 的 event id，供启动时差量重放
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fs_event_cursor (
  id INTEGER PRIMARY KEY CHECK (id = 1),  -- 单行表
  last_event_id INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 初始化版本
INSERT OR IGNORE INTO schema_version (version, applied_at) VALUES (1, strftime('%s', 'now'));
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
    schema_version {
        int version PK
        int applied_at
    }
```

---

## 关键不变量

| 不变量 | SQL 表达 |
|---|---|
| INV-D1 同 path 唯一 active 文件 | `path` UNIQUE 约束 |
| INV-D2 hash 唯一 active | 应用层在 import 前查询 + 业务约束（不加 UNIQUE 索引以允许 staging/deleted 行） |
| INV-D3 staging 行不可见 | 所有用户查询带 `WHERE status = 'active'` |
| INV-D4 软删除保留历史 | `deleted_at` 字段 + change_log 的 deleted 条目 |
| INV-D5 schema 版本可追溯 | schema_version 表每次 migration 插入新行 |

---

## 常用查询模式

### 1. 列出某分类的所有 active 文件

```sql
SELECT id, path, current_name, size_bytes, imported_at
FROM files
WHERE category = ?1 AND status = 'active'
ORDER BY imported_at DESC;
```

### 2. 检测 hash 重复

```sql
SELECT id, path
FROM files
WHERE hash_sha256 = ?1 AND status = 'active'
LIMIT 1;
```

### 3. 文件的改动时间线

```sql
SELECT action, detail_json, occurred_at
FROM change_log
WHERE file_id = ?1
ORDER BY occurred_at DESC
LIMIT 100;
```

### 4. 资料库总览（根 README 用）

```sql
SELECT
  category,
  COUNT(*) AS file_count,
  SUM(size_bytes) AS total_bytes,
  MAX(imported_at) AS latest_import
FROM files
WHERE status = 'active'
GROUP BY category;
```

### 5. 近 7 天跨分类改动

```sql
SELECT cl.action, cl.detail_json, cl.occurred_at, f.path, f.category
FROM change_log cl
LEFT JOIN files f ON cl.file_id = f.id
WHERE cl.occurred_at >= strftime('%s', 'now', '-7 days')
ORDER BY cl.occurred_at DESC
LIMIT 200;
```

### 6. 软删除一个文件

```sql
BEGIN;
UPDATE files SET status = 'deleted', deleted_at = strftime('%s', 'now')
WHERE id = ?1;
INSERT INTO change_log (file_id, action, detail_json, occurred_at)
VALUES (?1, 'deleted', ?2, strftime('%s', 'now'));
COMMIT;
```

### 7. 重命名（外部修改）

```sql
BEGIN;
UPDATE files SET path = ?1, current_name = ?2, updated_at = strftime('%s', 'now')
WHERE id = ?3;
INSERT INTO change_log (file_id, action, detail_json, occurred_at)
VALUES (?3, 'external_modified', json_object('rename_from', ?4, 'rename_to', ?1), strftime('%s', 'now'));
COMMIT;
```

---

## Migration 策略

### 原则

- 每次 schema 变更 = 一次 migration
- migration 文件只追加不修改（已发布的不能改）
- migration 在应用启动时检查 + 自动应用

### 文件布局

```
core/src/db/
├── schema.sql              # v1 完整 schema（首次安装用）
└── migrations/
    ├── m_002_add_xxx.sql   # 增量
    ├── m_003_xxx.sql
    └── ...
```

### 启动时检查

```rust
fn run_migrations(conn: &mut Connection) -> CoreResult<()> {
    let current: i64 = conn.query_row(
        "SELECT MAX(version) FROM schema_version",
        [],
        |row| row.get(0)
    ).unwrap_or(0);

    let latest = LATEST_VERSION;  // 编译期常量
    for v in (current + 1)..=latest {
        let sql = include_str!(...);  // 按 v 选择
        let tx = conn.transaction()?;
        tx.execute_batch(sql)?;
        tx.execute(
            "INSERT INTO schema_version (version, applied_at) VALUES (?1, strftime('%s', 'now'))",
            [v]
        )?;
        tx.commit()?;
        tracing::info!("applied migration v{}", v);
    }
    Ok(())
}
```

### 兼容性原则

- **MAJOR 版本变更**才允许破坏性 schema 变更
- MINOR / PATCH 版本只能加列、加表、加索引（不删不改）
- 删列 / 改列必须做 v->v+1 的迁移：新建临时表 → 复制 → 替换

---

## 备份与恢复

### 自动备份

- 应用启动时如果检测到 `index.db` 存在，先创建 `.areamatrix/index.db.bak.<timestamp>`（保留最近 5 份）
- 每次 migration 前自动备份

### 手动恢复

```bash
# 用户场景：DB 损坏
cp ~/AreaMatrix/.areamatrix/index.db.bak.<timestamp> ~/AreaMatrix/.areamatrix/index.db
```

### 完全重建

```bash
# 极端场景：DB 完全损坏，从文件系统重建索引
# 应用提供「从文件系统重新索引」按钮
# 实现：扫描 ~/AreaMatrix/，对每个文件计算 hash 并 INSERT 到 files；change_log 全部丢失
```

> 注意：完全重建会**丢失改动历史**，但用户的文件本身永远不会丢。这是产品级的"真相在文件系统"承诺的体现。

---

## 容量预期

| 文件数 | DB 大小（估算） | 性能 |
|---|---|---|
| 1,000 | ~500KB | 任何查询 < 1ms |
| 10,000 | ~5MB | 任何查询 < 5ms |
| 100,000 | ~50MB | 索引查询 < 20ms，全表扫描 < 200ms |
| 1,000,000 | ~500MB | 索引查询 < 50ms，需要重新审视架构 |

100 万文件以上是 Stage 4 才考虑的场景，超出 MVP 范围。

---

## Related

- [overview.md](overview.md)
- [transactional-import.md](transactional-import.md)
- [source-of-truth.md](source-of-truth.md)
- [../modules/storage.md](../modules/storage.md)
- [../modules/change-log.md](../modules/change-log.md)
