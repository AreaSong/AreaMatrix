mod codec;
mod files;
mod session;
mod types;

use super::{
    open_repo_connection, open_repo_read_connection, origin_from_db, storage_mode_from_db,
};

use codec::{kind_to_db, scan_session_from_row, status_to_db};
pub(crate) use files::{
    active_scan_file_snapshots, active_scan_file_snapshots_read_only, upsert_adopted_file,
    upsert_reindexed_file,
};
pub(crate) use session::{
    create_scan_session, finish_scan_session, has_running_reindex_session,
    has_running_reindex_session_excluding, has_running_reindex_session_read_only,
    latest_scan_session, mark_scan_session_running_for_resume, scan_session_by_id,
    update_scan_session_progress,
};
pub(crate) use types::{FileIndexInput, ScanFileChange, ScanFileSnapshot};
