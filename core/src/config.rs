//! Repository configuration defaults and conversion helpers.

use crate::{OverviewOutput, RepoConfig, StorageMode};

const DEFAULT_LOCALE: &str = "system";

pub(crate) fn validate_content_locale(locale: &str) -> crate::CoreResult<&'static str> {
    match locale.trim() {
        "zh-Hans" => Ok("zh-Hans"),
        "en" => Ok("en"),
        _ => Err(crate::CoreError::config("unsupported content locale")),
    }
}

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
        enable_extension_rules: true,
        enable_keyword_rules: true,
        fallback_to_inbox: true,
        allow_replace_during_import: false,
    }
}

#[cfg(test)]
mod tests {
    use super::{default_repo_config, validate_content_locale};
    use crate::OverviewOutput;

    #[test]
    fn content_locale_accepts_only_resolved_contract_values() {
        assert_eq!(validate_content_locale("zh-Hans").unwrap(), "zh-Hans");
        assert_eq!(validate_content_locale("en").unwrap(), "en");
        assert!(validate_content_locale("system").is_err());
        assert!(validate_content_locale("zh-Hant").is_err());
    }

    #[test]
    fn new_repository_defaults_to_follow_interface() {
        let config = default_repo_config("/tmp/repo".to_owned(), OverviewOutput::GeneratedOnly);
        assert_eq!(config.locale, "system");
    }
}
