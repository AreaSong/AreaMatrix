//! AreaMatrix platform-neutral core library.

// UniFFI 0.28 generated scaffolding currently trips this lint.
#![allow(clippy::empty_line_after_doc_comments)]

uniffi::include_scaffolding!("area_matrix");

pub mod api;
pub mod classify;
pub mod config;
pub mod db;
pub mod domain;
pub mod error;
mod icloud_conflicts;
mod note;
pub mod overview;
mod recovery;
mod repair;
mod repo_entries;
mod repo_init;
mod repo_path;
mod repo_scan;
pub mod search;
pub mod storage;
pub mod sync;
mod tags;
pub mod tree;
pub mod undo;

pub use api::*;
pub use domain::*;
pub use error::{
    map_core_error, CoreError, CoreResult, ErrorKind, ErrorMapping, ErrorMappingInput,
    ErrorRecoverability, ErrorSeverity,
};
pub use search::*;
pub use tags::{
    add_tag, batch_add_tags, list_tags, remove_tag, BatchMutationItemResult, BatchMutationReport,
    BatchMutationStatus, TagRecord, TagSet,
};
pub use undo::{
    list_undo_actions, undo_action, UndoActionRecord, UndoActionResult, UndoActionStatus,
};
