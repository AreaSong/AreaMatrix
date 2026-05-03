//! File storage operations.

mod dedup;
mod delete;
mod destination;
mod hash;
mod import;
mod import_target;
mod rename;
mod replacement_trash;
mod safe_move;
mod staging_row;
mod validate;

pub(crate) use delete::{delete_file, remove_index_entry};
pub(crate) use import::import_file;
pub(crate) use rename::rename_file;
