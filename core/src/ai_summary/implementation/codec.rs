use crate::{CoreError, CoreResult};

use super::super::{AiSummaryInputField, AiSummaryRoute};

pub(super) fn used_context_json(fields: &[AiSummaryInputField]) -> CoreResult<String> {
    serde_json::to_string(&field_names(fields))
        .map_err(|_| CoreError::internal("AI summary context metadata is invalid"))
}

pub(super) fn summary_route_to_db(route: &AiSummaryRoute) -> String {
    match route {
        AiSummaryRoute::Local => "local",
        AiSummaryRoute::Remote => "remote",
    }
    .to_owned()
}

fn field_names(fields: &[AiSummaryInputField]) -> Vec<&'static str> {
    fields
        .iter()
        .map(|field| match field {
            AiSummaryInputField::FileName => "filename",
            AiSummaryInputField::RepoRelativePath => "repo_relative_path",
            AiSummaryInputField::ExtractedTextExcerpt => "extracted_text_excerpt",
            AiSummaryInputField::ExistingAiSummary => "ai_summary",
            AiSummaryInputField::NoteSummary => "note_summary",
            AiSummaryInputField::TagCategoryContext => "tag_category_context",
        })
        .collect()
}
