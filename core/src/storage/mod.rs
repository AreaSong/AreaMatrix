//! File storage operations.

mod dedup;
mod destination;
mod hash;
mod import;
mod rename;
mod replacement_trash;
mod safe_move;
mod staging_row;
mod validate;

pub(crate) use import::import_file;
pub(crate) use rename::rename_file;
