use crate::{AiPrivacyDecision, AiPrivacyEvaluationReport};

pub(super) fn privacy_blocks(report: &AiPrivacyEvaluationReport) -> bool {
    report.decision != AiPrivacyDecision::Allowed
}

pub(super) fn matched_rule_id(report: &AiPrivacyEvaluationReport) -> Option<String> {
    report
        .matched_rules
        .first()
        .map(|rule| rule.rule_id.clone())
}
