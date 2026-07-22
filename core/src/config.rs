//! Repository configuration defaults and conversion helpers.

use std::sync::atomic::{AtomicU8, Ordering};

use crate::{OverviewOutput, RepoConfig, StorageMode};

const DEFAULT_LOCALE: &str = "zh-Hans";
const INTERFACE_LOCALE_ZH_HANS: u8 = 0;
const INTERFACE_LOCALE_EN: u8 = 1;

static APP_INTERFACE_LOCALE: AtomicU8 = AtomicU8::new(INTERFACE_LOCALE_ZH_HANS);

pub(crate) fn set_app_interface_locale(locale: &str) -> crate::CoreResult<()> {
    let value = match locale.trim().replace('_', "-").to_ascii_lowercase() {
        normalized if normalized == "zh" || normalized.starts_with("zh-") => {
            INTERFACE_LOCALE_ZH_HANS
        }
        normalized if normalized == "en" => INTERFACE_LOCALE_EN,
        _ => return Err(crate::CoreError::config("unsupported app interface locale")),
    };
    APP_INTERFACE_LOCALE.store(value, Ordering::Release);
    Ok(())
}

pub(crate) fn resolve_content_locale(locale: &str) -> &'static str {
    let normalized = locale.trim().replace('_', "-").to_ascii_lowercase();
    if normalized == "system" {
        return current_app_interface_locale();
    }
    if normalized == "zh" || normalized.starts_with("zh-") {
        return "zh-Hans";
    }
    "en"
}

fn current_app_interface_locale() -> &'static str {
    match APP_INTERFACE_LOCALE.load(Ordering::Acquire) {
        INTERFACE_LOCALE_ZH_HANS => "zh-Hans",
        _ => "en",
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
    use super::{resolve_content_locale, set_app_interface_locale};

    #[test]
    fn content_locale_follows_interface_only_for_system_selection() {
        set_app_interface_locale("en").expect("set English interface locale");
        assert_eq!(resolve_content_locale("system"), "en");
        assert_eq!(resolve_content_locale("zh-Hans"), "zh-Hans");

        set_app_interface_locale("zh-Hant").expect("normalize Chinese interface locale");
        assert_eq!(resolve_content_locale("system"), "zh-Hans");
        assert_eq!(resolve_content_locale("en"), "en");
        assert!(set_app_interface_locale("fr").is_err());
    }
}
