//! File storage operations.

pub(crate) mod dedup;
mod delete;
mod destination;
mod hash;
mod import;
mod import_target;
mod move_to_category;
mod rename;
mod replacement_trash;
mod safe_move;
mod staging_row;
mod validate;

pub(crate) use delete::{delete_file, remove_index_entry};
pub(crate) use import::import_file;
pub(crate) use move_to_category::{move_to_category, preview_move_to_category};
pub(crate) use rename::rename_file;
pub(crate) use replacement_trash::move_to_user_trash;
pub(crate) use safe_move::move_recoverable_file;
