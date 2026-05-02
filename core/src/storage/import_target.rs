use std::path::Path;

use crate::{classify, CoreResult, ImportDestination, ImportOptions};

use super::validate;

pub(super) struct ImportTarget {
    pub(super) relative_dir: String,
    pub(super) category: String,
}

pub(super) fn resolve_import_target(
    repo: &Path,
    repo_path: &str,
    original_name: &str,
    options: &ImportOptions,
) -> CoreResult<ImportTarget> {
    match options.destination {
        ImportDestination::AutoClassify => auto_classify_target(repo_path, original_name, options),
        ImportDestination::SelectedDirectory => selected_directory_target(options),
        ImportDestination::Category => category_target(repo, options),
    }
}

fn auto_classify_target(
    repo_path: &str,
    original_name: &str,
    options: &ImportOptions,
) -> CoreResult<ImportTarget> {
    let category = match &options.override_category {
        Some(category) => category.clone(),
        None => {
            classify::predict_category(repo_path.to_owned(), original_name.to_owned())?.category
        }
    };
    validate::category_slug(&category)?;
    Ok(ImportTarget {
        relative_dir: category.clone(),
        category,
    })
}

fn selected_directory_target(options: &ImportOptions) -> CoreResult<ImportTarget> {
    let directory = options
        .target_directory
        .as_deref()
        .ok_or(crate::CoreError::InvalidPath)?;
    validate::relative_directory(directory)?;
    let category = validate::top_level_category(directory)?;
    Ok(ImportTarget {
        relative_dir: directory.to_owned(),
        category,
    })
}

fn category_target(repo: &Path, options: &ImportOptions) -> CoreResult<ImportTarget> {
    let category = options
        .override_category
        .as_deref()
        .ok_or(crate::CoreError::InvalidPath)?;
    validate::category_slug(category)?;
    let relative_dir = repo
        .join(category)
        .strip_prefix(repo)
        .map_err(|_| crate::CoreError::InvalidPath)?
        .to_string_lossy()
        .into_owned();
    Ok(ImportTarget {
        relative_dir,
        category: category.to_owned(),
    })
}
