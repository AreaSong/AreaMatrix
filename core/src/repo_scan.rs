//! Filesystem scan support for adopting existing repositories.

mod files;
mod ignore;
mod preview;
mod report;
mod runner;
mod session;
mod types;

pub(crate) use session::{
    get_latest_scan_session, preview_manual_rescan, reindex_from_filesystem, resume_scan_session,
    start_adopt_scan,
};
