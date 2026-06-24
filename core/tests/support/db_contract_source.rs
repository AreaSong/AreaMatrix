pub(crate) const DB_RS: &str = concat!(
    include_str!("../../src/db/mod.rs"),
    include_str!("../../src/db/codec.rs"),
    include_str!("../../src/db/connection.rs"),
    include_str!("../../src/db/read_models.rs"),
    include_str!("../../src/db/repo_config.rs"),
    include_str!("../../src/db/schema.rs"),
);
