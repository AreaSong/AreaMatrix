use std::path::{Path, PathBuf};

use crate::{
    db, repo_path, CoreError, CoreResult, ManualRescanPreviewReport, ReindexReport, ScanSession,
    ScanSessionKind, ScanSessionStatus,
};

use super::{
    files::collect_scan_files,
    preview::preview_from_plan,
    report::{empty_report, report_from_session},
    runner::{run_adopt_scan, run_filesystem_scan},
    types::ScanMode,
};

pub(crate) fn start_adopt_scan(repo_path: &Path) -> CoreResult<()> {
    let scan_session_id = db::create_scan_session(repo_path, ScanSessionKind::Adopt)?;
    run_adopt_scan(repo_path, scan_session_id, None)
}

pub(crate) fn reindex_from_filesystem(repo_path: String) -> CoreResult<ReindexReport> {
    let repo = initialized_repo_path(&repo_path)?;
    ensure_no_running_reindex(&repo)?;
    let scan_session_id = db::create_scan_session(&repo, ScanSessionKind::Reindex)?;
    run_filesystem_scan(&repo, scan_session_id, None, ScanMode::Reindex, true)?;
    let finished = db::scan_session_by_id(&repo, scan_session_id)?;
    Ok(report_from_session(&finished))
}

pub(crate) fn preview_manual_rescan(repo_path: String) -> CoreResult<ManualRescanPreviewReport> {
    let repo = initialized_repo_path(&repo_path)?;
    ensure_no_running_reindex_read_only(&repo)?;
    let plan = collect_scan_files(&repo, None)?;
    preview_from_plan(&repo, &plan)
}

pub(crate) fn get_latest_scan_session(repo_path: String) -> CoreResult<Option<ScanSession>> {
    let repo = initialized_repo_path(&repo_path)?;
    db::latest_scan_session(&repo)
}

pub(crate) fn resume_scan_session(
    repo_path: String,
    scan_session_id: i64,
) -> CoreResult<ReindexReport> {
    let repo = initialized_repo_path(&repo_path)?;
    let session = db::scan_session_by_id(&repo, scan_session_id)?;
    if session.status == ScanSessionStatus::Completed {
        return Ok(empty_report(scan_session_id));
    }
    if session.status == ScanSessionStatus::Running {
        return Err(CoreError::conflict("manual rescan already running"));
    }
    if session.kind == ScanSessionKind::Reindex {
        ensure_no_other_running_reindex(&repo, scan_session_id)?;
    }
    let scan_mode = ScanMode::from_kind(&session.kind);

    db::mark_scan_session_running_for_resume(&repo, scan_session_id)?;
    run_filesystem_scan(
        &repo,
        scan_session_id,
        session.last_path.as_deref(),
        scan_mode,
        session.kind == ScanSessionKind::Reindex,
    )?;
    let finished = db::scan_session_by_id(&repo, scan_session_id)?;
    Ok(report_from_session(&finished))
}

fn initialized_repo_path(repo_path: &str) -> CoreResult<PathBuf> {
    if repo_path.is_empty() {
        return Err(CoreError::invalid_path("invalid path"));
    }
    repo_path::validate_initialized_repo_path(repo_path.to_owned())?;
    Ok(PathBuf::from(repo_path))
}

fn ensure_no_running_reindex(repo_path: &Path) -> CoreResult<()> {
    if db::has_running_reindex_session(repo_path)? {
        return Err(CoreError::conflict("manual rescan already running"));
    }
    Ok(())
}

fn ensure_no_running_reindex_read_only(repo_path: &Path) -> CoreResult<()> {
    if db::has_running_reindex_session_read_only(repo_path)? {
        return Err(CoreError::conflict("manual rescan already running"));
    }
    Ok(())
}

fn ensure_no_other_running_reindex(repo_path: &Path, scan_session_id: i64) -> CoreResult<()> {
    if db::has_running_reindex_session_excluding(repo_path, Some(scan_session_id))? {
        return Err(CoreError::conflict("manual rescan already running"));
    }
    Ok(())
}
