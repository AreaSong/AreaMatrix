//! Repository configuration defaults and conversion helpers.

use crate::{OverviewOutput, RepoConfig, StorageMode};

const DEFAULT_LOCALE: &str = "zh-Hans";

pub(crate) fn default_repo_config(
    repo_path: String,
    overview_output: OverviewOutput,
) -> RepoConfig {
    RepoConfig {
        repo_path,
        default_mode: StorageMode::Copied,
        overview_output,
        ai_enabled: false,
        locale: DEFAULT_LOCALE.to_owned(),
        icloud_warn: true,
    }
}
