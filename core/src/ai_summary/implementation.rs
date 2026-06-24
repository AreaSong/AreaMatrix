mod codec;
mod common;
mod draft;
mod generation;
mod metadata;
mod privacy;
mod route;

pub(super) use generation::generate_ai_summary;
pub(super) use metadata::{clear_ai_summary, save_ai_summary};
