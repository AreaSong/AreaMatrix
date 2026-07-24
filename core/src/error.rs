//! Shared error and error-mapping contract types for the AreaMatrix core.

mod conversions;
mod core_error;
mod mapping;
mod templates;
mod types;

pub use core_error::CoreError;
pub type CoreResult<T> = Result<T, CoreError>;
pub use mapping::map_core_error;
pub use types::{
    ErrorArgument, ErrorKind, ErrorMapping, ErrorMappingInput, ErrorRecoverability, ErrorSeverity,
};
