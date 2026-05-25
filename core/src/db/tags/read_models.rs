use rusqlite::{params, Row};

use crate::{CoreError, CoreResult, TagRecord, TagSet};

use super::RECENT_TAG_LIMIT;

pub(super) fn load_tag_set(
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
