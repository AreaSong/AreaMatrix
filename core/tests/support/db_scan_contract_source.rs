pub(crate) const DB_SCAN_RS: &str = concat!(
    include_str!("../../src/db/scan.rs"),
    include_str!("../../src/db/scan/codec.rs"),
    include_str!("../../src/db/scan/files.rs"),
    include_str!("../../src/db/scan/session.rs"),
    include_str!("../../src/db/scan/types.rs"),
);
