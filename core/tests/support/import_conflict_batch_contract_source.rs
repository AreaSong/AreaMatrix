pub(crate) const IMPORT_CONFLICT_BATCH_RS: &str = concat!(
    include_str!("../../src/import_conflict_batch.rs"),
    include_str!("../../src/import_conflict_batch/path.rs"),
    include_str!("../../src/import_conflict_batch/plan.rs"),
    include_str!("../../src/import_conflict_batch/token.rs"),
    include_str!("../../src/import_conflict_batch/apply.rs"),
    include_str!("../../src/import_conflict_batch/apply/detail.rs"),
    include_str!("../../src/import_conflict_batch/apply/execution.rs"),
    include_str!("../../src/import_conflict_batch/apply/item.rs"),
    include_str!("../../src/import_conflict_batch/apply/replace.rs"),
    include_str!("../../src/import_conflict_batch/apply/result.rs"),
    include_str!("../../src/import_conflict_batch/apply/rollback.rs"),
);
