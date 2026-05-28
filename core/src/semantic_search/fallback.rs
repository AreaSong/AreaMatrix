use super::{SemanticSearchFallbackReason, SemanticSearchRoute};

pub(super) struct SearchFallback {
    pub(super) reason: SemanticSearchFallbackReason,
    pub(super) message: &'static str,
    pub(super) privacy_rule_id: Option<String>,
}

impl SearchFallback {
    pub(super) fn ai_disabled() -> Self {
        Self::new(SemanticSearchFallbackReason::AiDisabled, "AI is off")
    }

    pub(super) fn feature_disabled() -> Self {
        Self::new(
            SemanticSearchFallbackReason::FeatureDisabled,
            "Semantic search feature is off",
        )
    }

    pub(super) fn provider() -> Self {
        Self::new(
            SemanticSearchFallbackReason::ProviderUnavailable,
            "Semantic search provider is unavailable",
        )
    }

    pub(super) fn privacy(rule_id: String) -> Self {
        Self {
            reason: SemanticSearchFallbackReason::PrivacyRule,
            message: "Semantic search input was skipped by privacy policy",
            privacy_rule_id: Some(rule_id),
        }
    }

    pub(super) fn index_not_ready() -> Self {
        Self::new(
            SemanticSearchFallbackReason::SemanticIndexNotReady,
            "Semantic index is not ready",
        )
    }

    pub(super) fn call_log() -> Self {
        Self::new(
            SemanticSearchFallbackReason::CallLogUnavailable,
            "Semantic search call log is unavailable",
        )
    }

    fn new(reason: SemanticSearchFallbackReason, message: &'static str) -> Self {
        Self {
            reason,
            message,
            privacy_rule_id: None,
        }
    }
}

pub(super) struct BuildFallback {
    pub(super) reason: SemanticSearchFallbackReason,
    pub(super) message: &'static str,
    pub(super) route: Option<SemanticSearchRoute>,
}

impl BuildFallback {
    pub(super) fn ai_disabled() -> Self {
        Self::new(SemanticSearchFallbackReason::AiDisabled, "AI is off")
    }

    pub(super) fn feature_disabled() -> Self {
        Self::new(
            SemanticSearchFallbackReason::FeatureDisabled,
            "Semantic search feature is off",
        )
    }

    pub(super) fn provider() -> Self {
        Self::new(
            SemanticSearchFallbackReason::ProviderUnavailable,
            "Semantic search provider is unavailable",
        )
    }

    pub(super) fn no_input(route: SemanticSearchRoute) -> Self {
        Self {
            reason: SemanticSearchFallbackReason::NoEligibleInput,
            message: "No files are eligible for semantic indexing",
            route: Some(route),
        }
    }

    pub(super) fn call_log(total_count: i64) -> (Self, i64) {
        (
            Self::new(
                SemanticSearchFallbackReason::CallLogUnavailable,
                "Semantic search call log is unavailable",
            ),
            total_count,
        )
    }

    fn new(reason: SemanticSearchFallbackReason, message: &'static str) -> Self {
        Self {
            reason,
            message,
            route: None,
        }
    }
}
