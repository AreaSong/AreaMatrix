pub(crate) const AI_SUMMARY_IMPL_RS: &str = concat!(
    include_str!("../../src/ai_summary/implementation.rs"),
    include_str!("../../src/ai_summary/implementation/codec.rs"),
    include_str!("../../src/ai_summary/implementation/common.rs"),
    include_str!("../../src/ai_summary/implementation/draft.rs"),
    include_str!("../../src/ai_summary/implementation/generation.rs"),
    include_str!("../../src/ai_summary/implementation/metadata.rs"),
    include_str!("../../src/ai_summary/implementation/privacy.rs"),
    include_str!("../../src/ai_summary/implementation/route.rs"),
);
