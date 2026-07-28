//! Public functions exposed through the UniFFI boundary.

mod ai;
mod batch;
mod classifier;
mod conflicts;
mod core_contract;
mod file_actions;
mod history;
mod observability;
mod queries;
mod repository;
mod syncing;
mod tags;

pub use ai::*;
pub use batch::*;
pub use classifier::*;
pub use conflicts::*;
pub use core_contract::*;
pub use file_actions::*;
pub use history::*;
pub use observability::*;
pub use queries::*;
pub use repository::*;
pub use syncing::*;
pub use tags::*;
