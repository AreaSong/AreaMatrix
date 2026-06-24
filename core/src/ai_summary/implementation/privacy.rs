use super::super::AiSummaryGenerationRequest;

pub(super) fn privacy_blocks(
    config_ref: &Option<String>,
    request: &AiSummaryGenerationRequest,
) -> bool {
    let reference = request.privacy_policy_ref.as_ref().or(config_ref.as_ref());
    reference.is_some_and(|value| {
        let normalized = value.to_ascii_lowercase();
        normalized.contains("block")
            || normalized.contains("deny")
            || normalized.contains("private")
    })
}

pub(super) fn privacy_rule_id(request: &AiSummaryGenerationRequest) -> Option<String> {
    request
        .privacy_policy_ref
        .as_ref()
        .map(|value| format!("rule:{value}"))
}
