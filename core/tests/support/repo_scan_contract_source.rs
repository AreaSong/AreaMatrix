pub(crate) const REPO_SCAN_RS: &str = concat!(
    include_str!("../../src/repo_scan.rs"),
    include_str!("../../src/repo_scan/files.rs"),
    include_str!("../../src/repo_scan/ignore.rs"),
    include_str!("../../src/repo_scan/preview.rs"),
    include_str!("../../src/repo_scan/report.rs"),
    include_str!("../../src/repo_scan/runner.rs"),
    include_str!("../../src/repo_scan/session.rs"),
    include_str!("../../src/repo_scan/types.rs"),
);
