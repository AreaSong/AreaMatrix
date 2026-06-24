pub(crate) const DOMAIN_RS: &str = concat!(
    include_str!("../../src/domain.rs"),
    include_str!("../../src/domain/classify.rs"),
    include_str!("../../src/domain/file.rs"),
    include_str!("../../src/domain/icloud.rs"),
    include_str!("../../src/domain/import.rs"),
    include_str!("../../src/domain/query.rs"),
    include_str!("../../src/domain/recovery.rs"),
    include_str!("../../src/domain/repository.rs"),
    include_str!("../../src/domain/scan.rs"),
    include_str!("../../src/domain/sync.rs"),
);
