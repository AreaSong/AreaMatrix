use std::path::Path;

use rusqlite::{params, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::{CoreError, CoreResult, TagRecord, TagSet};

use super::open_repo_connection;

const RECENT_TAG_LIMIT: i64 = 10;

pub(crate) fn add_tag_row(repo_path: &Path, file_id: i64, tag: &str) -> CoreResult<TagSet> {
    mutate_tag_relation(repo_path, file_id, tag, TagMutation::Add)
}

pub(crate) fn remove_tag_row(repo_path: &Path, file_id: i64, tag: &str) -> CoreResult<TagSet> {
    mutate_tag_relation(repo_path, file_id, tag, TagMutation::Remove)
}

pub(crate) fn list_tag_set(repo_path: &Path, file_id: i64) -> CoreResult<TagSet> {
    let connection = open_repo_connection(repo_path)?;
    ensure_active_file(&connection, file_id)?;
    load_tag_set(
        &connection,
        file_id,
        current_tag_updated_at(&connection, file_id)?,
    )
}

enum TagMutation {
    Add,
    Remove,
}

impl TagMutation {
    fn kind(&self) -> &'static str {
        match self {
            Self::Add => "tag_added",
            Self::Remove => "tag_removed",
        }
    }

    fn detail(&self, tag: &str, changed: bool) -> Value {
        json!({
            "kind": self.kind(),
            "tag": tag,
            "changed": changed,
            "by": "user",
        })
    }
}

fn mutate_tag_relation(
    repo_path: &Path,
    file_id: i64,
    tag: &str,
    mutation: TagMutation,
) -> CoreResult<TagSet> {
    let mut connection = open_repo_connection(repo_path)?;
    let tx = connection
        .transaction()
        .map_err(|error| CoreError::db(error.to_string()))?;
    ensure_active_file(&tx, file_id)?;
    let occurred_at = chrono::Utc::now().timestamp();
    let changed = match mutation {
        TagMutation::Add => insert_tag_relation(&tx, file_id, tag, occurred_at)?,
        TagMutation::Remove => delete_tag_relation(&tx, file_id, tag)?,
    };
    if changed {
        insert_tag_change(&tx, file_id, &mutation.detail(tag, changed), occurred_at)?;
    }
    let fallback_updated_at = if changed {
        occurred_at
    } else {
        current_tag_updated_at(&tx, file_id)?
    };
    let tag_set = load_tag_set(&tx, file_id, fallback_updated_at)?;
    tx.commit()
        .map_err(|error| CoreError::db(error.to_string()))?;
    Ok(tag_set)
}

fn insert_tag_relation(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    tag: &str,
    occurred_at: i64,
) -> CoreResult<bool> {
    tx.execute(
        "INSERT OR IGNORE INTO tags (file_id, tag, added_at)
         VALUES (?1, ?2, ?3)",
        params![file_id, tag, occurred_at],
    )
    .map(|changed| changed == 1)
    .map_err(|error| CoreError::db(error.to_string()))
}

fn delete_tag_relation(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    tag: &str,
) -> CoreResult<bool> {
    tx.execute(
        "DELETE FROM tags WHERE file_id = ?1 AND tag = ?2",
        params![file_id, tag],
    )
    .map(|changed| changed == 1)
    .map_err(|error| CoreError::db(error.to_string()))
}

fn insert_tag_change(
    tx: &rusqlite::Transaction<'_>,
    file_id: i64,
    detail: &Value,
    occurred_at: i64,
) -> CoreResult<()> {
    let detail_json =
        serde_json::to_string(detail).map_err(|error| CoreError::internal(error.to_string()))?;
    tx.execute(
        "INSERT INTO change_log (file_id, action, detail_json, occurred_at)
         VALUES (?1, 'external_modified', ?2, ?3)",
        params![file_id, detail_json, occurred_at],
    )
    .map(|_| ())
    .map_err(|error| CoreError::db(error.to_string()))
}

fn ensure_active_file(connection: &rusqlite::Connection, file_id: i64) -> CoreResult<()> {
    let exists = connection
        .query_row(
            "SELECT 1 FROM files WHERE id = ?1 AND status = 'active'",
            params![file_id],
            |_| Ok(()),
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))?;
    exists.ok_or_else(|| CoreError::file_not_found(format!("file:{file_id}")))
}

fn load_tag_set(
    connection: &rusqlite::Connection,
    file_id: i64,
    fallback_updated_at: i64,
) -> CoreResult<TagSet> {
    let selected_tags = selected_tag_values(connection, file_id)?;
    let file_tags = file_tag_records(connection, file_id)?;
    let available_tags = available_tag_records(connection)?;
    let recent_tags = recent_tag_records(connection)?;
    let updated_at = file_tags
        .iter()
        .chain(available_tags.iter())
        .map(|record| record.updated_at)
        .max()
        .map(|record_updated_at| record_updated_at.max(fallback_updated_at))
        .unwrap_or(fallback_updated_at);

    Ok(TagSet {
        file_id,
        file_tags,
        available_tags: mark_selected(available_tags, &selected_tags),
        recent_tags: mark_selected(recent_tags, &selected_tags),
        updated_at,
    })
}

fn selected_tag_values(connection: &rusqlite::Connection, file_id: i64) -> CoreResult<Vec<String>> {
    let mut statement = connection
        .prepare("SELECT tag FROM tags WHERE file_id = ?1 ORDER BY lower(tag) ASC, tag ASC")
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![file_id], |row| row.get(0))
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn file_tag_records(connection: &rusqlite::Connection, file_id: i64) -> CoreResult<Vec<TagRecord>> {
    let mut statement = connection
        .prepare(
            "SELECT t.tag, COUNT(active.file_id) AS file_count, MAX(active.added_at) AS updated_at
               FROM tags t
               JOIN tags active ON active.tag = t.tag
               JOIN files f ON f.id = active.file_id AND f.status = 'active'
              WHERE t.file_id = ?1
              GROUP BY t.tag
              ORDER BY lower(t.tag) ASC, t.tag ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![file_id], |row| tag_record_from_row(row, true))
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn available_tag_records(connection: &rusqlite::Connection) -> CoreResult<Vec<TagRecord>> {
    let mut statement = connection
        .prepare(
            "SELECT t.tag, COUNT(t.file_id) AS file_count, MAX(t.added_at) AS updated_at
               FROM tags t
               JOIN files f ON f.id = t.file_id AND f.status = 'active'
              GROUP BY t.tag
              ORDER BY lower(t.tag) ASC, t.tag ASC",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map([], |row| tag_record_from_row(row, false))
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn recent_tag_records(connection: &rusqlite::Connection) -> CoreResult<Vec<TagRecord>> {
    let mut statement = connection
        .prepare(
            "SELECT t.tag, COUNT(t.file_id) AS file_count, MAX(t.added_at) AS updated_at
               FROM tags t
               JOIN files f ON f.id = t.file_id AND f.status = 'active'
              GROUP BY t.tag
              ORDER BY updated_at DESC, lower(t.tag) ASC, t.tag ASC
              LIMIT ?1",
        )
        .map_err(|error| CoreError::db(error.to_string()))?;
    let rows = statement
        .query_map(params![RECENT_TAG_LIMIT], |row| {
            tag_record_from_row(row, false)
        })
        .map_err(|error| CoreError::db(error.to_string()))?;
    rows.collect::<Result<Vec<_>, _>>()
        .map_err(|error| CoreError::db(error.to_string()))
}

fn tag_record_from_row(row: &Row<'_>, selected: bool) -> rusqlite::Result<TagRecord> {
    let tag: String = row.get(0)?;
    Ok(TagRecord {
        value: tag.clone(),
        label: tag,
        file_count: row.get(1)?,
        selected,
        disabled: false,
        updated_at: row.get(2)?,
    })
}

fn mark_selected(mut records: Vec<TagRecord>, selected_tags: &[String]) -> Vec<TagRecord> {
    for record in &mut records {
        record.selected = selected_tags.iter().any(|tag| tag == &record.value);
    }
    records
}

fn current_tag_updated_at(connection: &rusqlite::Connection, file_id: i64) -> CoreResult<i64> {
    connection
        .query_row(
            "SELECT COALESCE(MAX(added_at), 0) FROM tags WHERE file_id = ?1",
            params![file_id],
            |row| row.get(0),
        )
        .map_err(|error| CoreError::db(error.to_string()))
}
