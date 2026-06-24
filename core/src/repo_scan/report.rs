use crate::{ReindexReport, ScanSession};

pub(super) fn empty_report(scan_session_id: i64) -> ReindexReport {
    ReindexReport {
        scan_session_id: Some(scan_session_id),
        inserted: 0,
        updated: 0,
        missing: 0,
        conflicts: 0,
        unreadable: 0,
        unknown: 0,
        skipped: 0,
        errors: Vec::new(),
    }
}

pub(super) fn report_from_session(session: &ScanSession) -> ReindexReport {
    ReindexReport {
        scan_session_id: Some(session.id),
        inserted: session.inserted,
        updated: session.updated,
        missing: session.missing,
        conflicts: session.conflicts,
        unreadable: session.unreadable,
        unknown: session.unknown,
        skipped: session.skipped,
        errors: session.errors.clone(),
    }
}
