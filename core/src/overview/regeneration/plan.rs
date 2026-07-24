use std::{
    collections::{BTreeMap, BTreeSet},
    fs, io,
    path::Path,
};

use sha2::{Digest, Sha256};

use crate::{
    classifier_rule_editor::list_classifier_category_slugs, db, ContentLocale, CoreError,
    CoreResult, OverviewOutput,
};

use crate::overview::{
    map_io_error, node_document, root_document, root_entry_content, root_managed_block,
    validate_node_slug, GENERATED_DIR, NODE_OVERVIEW_LIMIT, NODE_RECENT_DAYS, RECENT_LIMIT,
    ROOT_RECENT_DAYS,
};

use super::{
    OverviewLanguageState, OverviewLanguageStatus, OverviewRegenerationReason, PlanPayload,
    RenderedTarget,
};

const TOKEN_DOMAIN: &[u8] = b"AreaMatrix overview regeneration plan v1\0";

pub(super) fn render_targets(
    repo: &Path,
    locale: &ContentLocale,
    output: OverviewOutput,
) -> CoreResult<Vec<RenderedTarget>> {
    let mut categories = list_classifier_category_slugs(repo)?;
    categories.sort();
    categories.dedup();
    let existing = db::list_overview_node_summaries(repo)?;
    let summary_map = existing
        .into_iter()
        .map(|summary| (summary.slug.clone(), summary))
        .collect::<BTreeMap<_, _>>();
    let summaries = categories
        .iter()
        .map(|slug| {
            summary_map.get(slug).map_or_else(
                || db::OverviewNodeSummary {
                    slug: slug.clone(),
                    file_count: 0,
                    total_bytes: 0,
                    last_imported_at: 0,
                },
                |value| db::OverviewNodeSummary {
                    slug: value.slug.clone(),
                    file_count: value.file_count,
                    total_bytes: value.total_bytes,
                    last_imported_at: value.last_imported_at,
                },
            )
        })
        .collect::<Vec<_>>();
    let mut targets = Vec::new();
    for slug in &categories {
        validate_node_slug(slug)?;
        let files = db::list_overview_node_files(repo, slug, NODE_OVERVIEW_LIMIT)?;
        let recent =
            db::list_overview_recent_changes(repo, Some(slug), NODE_RECENT_DAYS, RECENT_LIMIT)?;
        targets.push(rendered_target(
            repo,
            format!("{GENERATED_DIR}/nodes/{slug}.md"),
            "generated",
            Some(node_document(slug, locale.as_str(), &files, &recent).into_bytes()),
        )?);
    }
    add_obsolete_node_targets(repo, &categories, &mut targets)?;
    let recent = db::list_overview_recent_changes(repo, None, ROOT_RECENT_DAYS, RECENT_LIMIT)?;
    targets.push(rendered_target(
        repo,
        format!("{GENERATED_DIR}/root.md"),
        "generated",
        Some(root_document(locale.as_str(), &summaries, &recent).into_bytes()),
    )?);
    if output == OverviewOutput::RootAreaMatrixFile {
        let managed = root_managed_block(locale.as_str(), &summaries, &recent);
        targets.push(rendered_target(
            repo,
            "AREAMATRIX.md".to_owned(),
            "managed_root",
            Some(root_entry_content(repo, locale.as_str(), &managed)?.into_bytes()),
        )?);
    }
    targets.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok(targets)
}

fn add_obsolete_node_targets(
    repo: &Path,
    categories: &[String],
    targets: &mut Vec<RenderedTarget>,
) -> CoreResult<()> {
    let directory = repo.join(GENERATED_DIR).join("nodes");
    let metadata = match fs::symlink_metadata(&directory) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(map_io_error(error)),
    };
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(CoreError::config("generated nodes path is unsafe"));
    }
    let current = categories
        .iter()
        .map(String::as_str)
        .collect::<BTreeSet<_>>();
    for entry in fs::read_dir(directory).map_err(map_io_error)? {
        let entry = entry.map_err(map_io_error)?;
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| CoreError::config("generated node filename is invalid"))?;
        let slug = name
            .strip_suffix(".md")
            .ok_or_else(|| CoreError::config("generated nodes contain an unsupported file"))?;
        validate_node_slug(slug)?;
        if !current.contains(slug) {
            targets.push(rendered_target(
                repo,
                format!("{GENERATED_DIR}/nodes/{name}"),
                "generated",
                None,
            )?);
        }
    }
    Ok(())
}

fn rendered_target(
    repo: &Path,
    relative_path: String,
    target_kind: &str,
    new_content: Option<Vec<u8>>,
) -> CoreResult<RenderedTarget> {
    let path = super::execution::checked_target_path(repo, &relative_path)?;
    let old_content = match fs::symlink_metadata(&path) {
        Ok(metadata) if metadata.is_file() && !metadata.file_type().is_symlink() => {
            Some(fs::read(&path).map_err(map_io_error)?)
        }
        Ok(_) => return Err(CoreError::config("overview target is not a regular file")),
        Err(error) if error.kind() == io::ErrorKind::NotFound => None,
        Err(error) => return Err(map_io_error(error)),
    };
    Ok(RenderedTarget {
        relative_path,
        target_kind: target_kind.to_owned(),
        old_content,
        new_content,
    })
}

pub(super) fn language_status_for_targets(
    repo: &Path,
    content_locale: &ContentLocale,
    targets: &[RenderedTarget],
) -> CoreResult<OverviewLanguageStatus> {
    let active = targets
        .iter()
        .filter(|target| target.new_content.is_some())
        .collect::<Vec<_>>();
    let obsolete = targets
        .iter()
        .filter(|target| target.old_content.is_some() && target.new_content.is_none())
        .collect::<Vec<_>>();
    let mut locales = BTreeSet::new();
    let mut format_versions = BTreeSet::new();
    let mut known = 0_i64;
    let mut missing = 0_i64;
    let mut unknown = false;
    for target in active.iter().chain(obsolete.iter()) {
        let Some(old) = target.old_content.as_deref() else {
            missing += 1;
            continue;
        };
        match db::load_overview_provenance(repo, &target.relative_path)? {
            Some(value) if value.content_sha256 == super::execution::sha256(old) => {
                locales.insert(value.content_locale.as_str().to_owned());
                format_versions.insert(value.format_contract_version);
                if target.new_content.is_some() {
                    known += 1;
                }
            }
            _ => unknown = true,
        }
    }
    let known_locales = locales
        .iter()
        .filter_map(|value| ContentLocale::parse(value))
        .collect();
    let known_format_versions = format_versions.iter().copied().collect::<Vec<_>>();
    let existing = active.len() as i64 - missing + obsolete.len() as i64;
    let mut reasons = BTreeSet::new();
    if missing > 0 {
        reasons.insert(OverviewRegenerationReason::MissingTargets);
    }
    if !obsolete.is_empty() {
        reasons.insert(OverviewRegenerationReason::ObsoleteTargets);
    }
    if locales
        .iter()
        .any(|locale| locale != content_locale.as_str())
    {
        reasons.insert(OverviewRegenerationReason::LocaleMismatch);
    }
    if format_versions
        .iter()
        .any(|version| *version != super::FORMAT_CONTRACT_VERSION)
    {
        reasons.insert(OverviewRegenerationReason::FormatMismatch);
    }
    let state = if existing == 0 {
        OverviewLanguageState::NotGenerated
    } else if unknown {
        OverviewLanguageState::Unknown
    } else if locales.len() > 1 || format_versions.len() > 1 {
        OverviewLanguageState::Mixed
    } else if missing == 0
        && obsolete.is_empty()
        && locales.len() == 1
        && locales.contains(content_locale.as_str())
        && format_versions.len() == 1
        && format_versions.contains(&super::FORMAT_CONTRACT_VERSION)
    {
        OverviewLanguageState::Synchronized
    } else {
        OverviewLanguageState::NeedsRegeneration
    };
    Ok(OverviewLanguageStatus {
        state,
        content_locale: content_locale.clone(),
        target_count: active.len() as i64,
        known_target_count: known,
        missing_target_count: missing,
        obsolete_target_count: obsolete.len() as i64,
        known_locales,
        known_format_versions,
        reasons: reasons.into_iter().collect(),
    })
}

pub(super) fn hash_target_set(targets: &[RenderedTarget]) -> String {
    let mut hasher = Sha256::new();
    for target in targets {
        feed(&mut hasher, &target.relative_path);
        feed(&mut hasher, &target.target_kind);
        let old = target.old_content.as_deref().map(super::execution::sha256);
        let new = target.new_content.as_deref().map(super::execution::sha256);
        feed(&mut hasher, old.as_deref().unwrap_or("missing"));
        feed(&mut hasher, new.as_deref().unwrap_or("delete"));
    }
    format!("{:x}", hasher.finalize())
}

pub(super) fn encode_token(payload: &PlanPayload) -> CoreResult<String> {
    let bytes = serde_json::to_vec(payload)
        .map_err(|_| CoreError::internal("overview plan encoding failed"))?;
    let payload_hex = hex_encode(&bytes);
    let mut hasher = Sha256::new();
    hasher.update(TOKEN_DOMAIN);
    hasher.update(&bytes);
    Ok(format!("{payload_hex}.{:x}", hasher.finalize()))
}

pub(super) fn decode_token(token: &str) -> CoreResult<PlanPayload> {
    let (payload_hex, digest) = token
        .split_once('.')
        .ok_or_else(|| CoreError::config("overview plan token is invalid"))?;
    let bytes = hex_decode(payload_hex)?;
    let mut hasher = Sha256::new();
    hasher.update(TOKEN_DOMAIN);
    hasher.update(&bytes);
    if format!("{:x}", hasher.finalize()) != digest {
        return Err(CoreError::config("overview plan token is invalid"));
    }
    serde_json::from_slice(&bytes).map_err(|_| CoreError::config("overview plan token is invalid"))
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn hex_decode(value: &str) -> CoreResult<Vec<u8>> {
    if value.len() % 2 != 0 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(CoreError::config("overview plan token is invalid"));
    }
    (0..value.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&value[index..index + 2], 16))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| CoreError::config("overview plan token is invalid"))
}

fn feed(hasher: &mut Sha256, value: &str) {
    hasher.update((value.len() as u64).to_le_bytes());
    hasher.update(value.as_bytes());
}
