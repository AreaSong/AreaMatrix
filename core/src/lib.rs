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
pub mod overview;
pub mod storage;
pub mod sync;
pub mod tree;

pub use api::*;
pub use domain::*;
pub use error::{CoreError, CoreResult};
