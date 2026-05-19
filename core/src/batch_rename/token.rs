use sha2::{Digest, Sha256};

use crate::{BatchRenameDateSource, BatchRenameMode, BatchRenameRule};

use super::plan::BatchRenamePlanItem;

pub(super) fn preview_token(
    file_ids: &[i64],
    rule: &BatchRenameRule,
    items: &[BatchRenamePlanItem],
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"area-matrix:c2-10:preview:v1");
    feed_rule(&mut hasher, rule);
    for file_id in file_ids {
        hasher.update(file_id.to_le_bytes());
    }
    for item in items {
        item.feed_preview_token(&mut hasher);
    }
    format!("preview:batch-rename:{:x}", hasher.finalize())
}

fn feed_rule(hasher: &mut Sha256, rule: &BatchRenameRule) {
    hasher.update(rename_mode_token(&rule.mode));
    feed_optional(hasher, rule.prefix.as_deref());
    feed_optional(hasher, rule.date_source.as_ref().map(date_source_token));
    feed_optional(hasher, rule.date_format.as_deref());
    feed_optional(hasher, rule.separator.as_deref());
    feed_i64(hasher, rule.start_number);
    feed_i64(hasher, rule.padding);
    feed_optional(hasher, rule.find.as_deref());
    feed_optional(hasher, rule.replacement.as_deref());
    hasher.update(if rule.case_sensitive {
        b"\x01"
    } else {
        b"\x00"
    });
}

fn rename_mode_token(mode: &BatchRenameMode) -> &'static [u8] {
    match mode {
        BatchRenameMode::Prefix => b"prefix",
        BatchRenameMode::DatePrefix => b"date_prefix",
        BatchRenameMode::KeepBaseSequence => b"keep_base_sequence",
        BatchRenameMode::ReplaceText => b"replace_text",
    }
}

fn date_source_token(source: &BatchRenameDateSource) -> &'static str {
    match source {
        BatchRenameDateSource::Imported => "imported",
        BatchRenameDateSource::Modified => "modified",
        BatchRenameDateSource::Today => "today",
    }
}

fn feed_optional(hasher: &mut Sha256, value: Option<&str>) {
    match value {
        Some(value) => {
            hasher.update(b"\x01");
            hasher.update(value.as_bytes());
        }
        None => hasher.update(b"\x00"),
    }
}

fn feed_i64(hasher: &mut Sha256, value: Option<i64>) {
    match value {
        Some(value) => {
            hasher.update(b"\x01");
            hasher.update(value.to_le_bytes());
        }
        None => hasher.update(b"\x00"),
    }
}
