pub(crate) const ERROR_RS: &str = concat!(
    include_str!("../../src/error.rs"),
    include_str!("../../src/error/conversions.rs"),
    include_str!("../../src/error/core_error.rs"),
    include_str!("../../src/error/mapping.rs"),
    include_str!("../../src/error/templates.rs"),
    include_str!("../../src/error/types.rs"),
);
