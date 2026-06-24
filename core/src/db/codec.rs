use crate::{CoreError, CoreResult, FileOrigin, OverviewOutput, StorageMode};

pub(crate) fn storage_mode_to_db(mode: &StorageMode) -> &'static str {
    match mode {
        StorageMode::Moved => "moved",
        StorageMode::Copied => "copied",
        StorageMode::Indexed => "indexed",
    }
}

pub(crate) fn storage_mode_from_db(value: &str) -> CoreResult<StorageMode> {
    match value {
        "moved" | "Moved" => Ok(StorageMode::Moved),
        "copied" | "Copied" => Ok(StorageMode::Copied),
        "indexed" | "Indexed" => Ok(StorageMode::Indexed),
        _ => Err(CoreError::config("configuration error")),
    }
}

pub(crate) fn origin_from_db(value: &str) -> CoreResult<FileOrigin> {
    match value {
        "imported" | "Imported" => Ok(FileOrigin::Imported),
        "adopted" | "Adopted" => Ok(FileOrigin::Adopted),
        "external" | "External" => Ok(FileOrigin::External),
        _ => Err(CoreError::db("database error")),
    }
}

pub(crate) fn overview_output_to_db(output: &OverviewOutput) -> &'static str {
    match output {
        OverviewOutput::GeneratedOnly => "generated_only",
        OverviewOutput::RootAreaMatrixFile => "root_areamatrix_file",
    }
}

pub(crate) fn overview_output_from_db(value: &str) -> CoreResult<OverviewOutput> {
    match value {
        "generated_only" | "GeneratedOnly" => Ok(OverviewOutput::GeneratedOnly),
        "root_areamatrix_file" | "RootAreaMatrixFile" => Ok(OverviewOutput::RootAreaMatrixFile),
        _ => Err(CoreError::config("configuration error")),
    }
}

pub(crate) fn bool_to_db(value: bool) -> &'static str {
    if value {
        "true"
    } else {
        "false"
    }
}

pub(crate) fn bool_from_db(value: &str) -> CoreResult<bool> {
    match value {
        "true" => Ok(true),
        "false" => Ok(false),
        _ => Err(CoreError::config("configuration error")),
    }
}
