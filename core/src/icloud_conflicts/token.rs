use sha2::{Digest, Sha256};

use crate::{CoreError, CoreResult, ICloudConflictVersionRole};

use super::types::{ConflictBinding, VersionState};

const TOKEN_VERSION: &str = "icloud-preview-v1";

pub(super) fn preview_token(
    binding: &ConflictBinding,
    versions: &[VersionState],
) -> CoreResult<String> {
    let mut hasher = Sha256::new();
    feed(&mut hasher, TOKEN_VERSION);
    feed(&mut hasher, &binding.repository_identity);
    feed(&mut hasher, &binding.conflict_id);

    let mut ordered = versions.iter().collect::<Vec<_>>();
    ordered.sort_by_key(|version| (role_rank(&version.role), version.relative_path.as_str()));
    feed(&mut hasher, &ordered.len().to_string());
    for version in ordered {
        feed(&mut hasher, role_name(&version.role));
        feed(&mut hasher, &version.relative_path);
        feed(&mut hasher, &version.hash_sha256);
        feed(&mut hasher, &version.size_bytes.to_string());
        feed(&mut hasher, &version.modified_at.to_string());
        feed(&mut hasher, &version.modified_at_nanos.to_string());
        feed(&mut hasher, &version.file_identity);
        feed(&mut hasher, &version.ancestor_identity);
    }
    Ok(format!("{TOKEN_VERSION}:{:x}", hasher.finalize()))
}

pub(super) fn ensure_token_matches(expected: &str, actual: &str) -> CoreResult<()> {
    if expected.trim().is_empty() || !constant_time_equal(expected.as_bytes(), actual.as_bytes()) {
        return Err(CoreError::conflict("stale conflict preview"));
    }
    Ok(())
}

fn feed(hasher: &mut Sha256, value: &str) {
    hasher.update((value.len() as u64).to_be_bytes());
    hasher.update(value.as_bytes());
}

fn role_rank(role: &ICloudConflictVersionRole) -> u8 {
    match role {
        ICloudConflictVersionRole::Original => 0,
        ICloudConflictVersionRole::ConflictedCopy => 1,
    }
}

fn role_name(role: &ICloudConflictVersionRole) -> &'static str {
    match role {
        ICloudConflictVersionRole::Original => "original",
        ICloudConflictVersionRole::ConflictedCopy => "conflicted-copy",
    }
}

fn constant_time_equal(left: &[u8], right: &[u8]) -> bool {
    let mut difference = (left.len() ^ right.len()) as u8;
    let max_len = left.len().max(right.len());
    for index in 0..max_len {
        let lhs = left.get(index).copied().unwrap_or(0);
        let rhs = right.get(index).copied().unwrap_or(0);
        difference |= lhs ^ rhs;
    }
    difference == 0
}

#[cfg(test)]
mod tests {
    use super::constant_time_equal;

    #[test]
    fn constant_time_comparison_requires_equal_length_and_bytes() {
        assert!(constant_time_equal(b"abc", b"abc"));
        assert!(!constant_time_equal(b"abc", b"abd"));
        assert!(!constant_time_equal(b"abc", b"ab"));
    }
}
