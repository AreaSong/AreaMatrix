//! File storage operations.

mod dedup;
mod destination;
mod hash;
mod import;
mod safe_move;
mod validate;

pub(crate) use import::import_file;
