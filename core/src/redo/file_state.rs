use rusqlite::{params, OptionalExtension};

use crate::{CoreError, CoreResult};

#[derive(Debug)]
pub(super) struct FileDbState {
    pub(super) path: String,
    pub(super) current_name: String,
    pub(super) category: String,
    pub(super) status: String,
}

pub(super) fn load_file_state(
    connection: &rusqlite::Connection,
    file_id: i64,
) -> CoreResult<Option<FileDbState>> {
    connection
        .query_row(
            "SELECT path, current_name, category, status
               FROM files
              WHERE id = ?1",
            params![file_id],
            |row| {
                Ok(FileDbState {
                    path: row.get(0)?,
                    current_name: row.get(1)?,
                    category: row.get(2)?,
                    status: row.get(3)?,
                })
            },
        )
        .optional()
        .map_err(|error| CoreError::db(error.to_string()))
}

pub(super) fn ensure_single_row_changed(changed: usize, file_id: i64) -> CoreResult<()> {
    if changed == 1 {
        Ok(())
    } else {
        Err(CoreError::file_not_found(format!("file:{file_id}")))
    }
}
