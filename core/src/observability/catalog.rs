//! Machine-readable action and component catalog shared with platform tooling.

use std::{collections::BTreeSet, sync::OnceLock};

use serde::Deserialize;

use crate::{CoreError, CoreResult};

const CATALOG_SCHEMA_VERSION: u64 = 1;
const CATALOG_JSON: &str = include_str!("../../resources/observability_catalog.json");

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CatalogDocument {
    schema_version: u64,
    actions: Vec<CatalogAction>,
    components: Vec<CatalogComponent>,
    expected_flows: Vec<CatalogExpectedFlow>,
}

#[derive(Debug, Deserialize)]
struct CatalogVersionHeader {
    schema_version: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CatalogAction {
    id: String,
    group: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CatalogComponent {
    id: String,
    owner: String,
    role: String,
    symbol: String,
    authority: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CatalogExpectedFlow {
    id: String,
    entry_action_ids: Vec<String>,
    steps: Vec<CatalogExpectedStep>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CatalogExpectedStep {
    id: String,
    required: bool,
    match_any: Vec<CatalogSelector>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CatalogSelector {
    action_id: Option<String>,
    action_group: Option<String>,
    component_id: String,
    phase: Option<String>,
}

#[derive(Debug)]
struct CatalogIndex {
    actions: BTreeSet<String>,
    components: BTreeSet<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CatalogLoadError {
    InvalidDocument,
    UnsupportedSchema,
}

impl CatalogLoadError {
    fn reason(self) -> &'static str {
        match self {
            Self::InvalidDocument => "observability catalog is invalid",
            Self::UnsupportedSchema => "observability catalog schema is unsupported",
        }
    }
}

static CATALOG: OnceLock<Result<CatalogIndex, CatalogLoadError>> = OnceLock::new();

pub(super) fn ensure_catalog() -> CoreResult<()> {
    catalog().map(|_| ())
}

pub(super) fn validate_action_id(value: &str) -> CoreResult<()> {
    if catalog()?.actions.contains(value) {
        Ok(())
    } else {
        Err(CoreError::validation(
            "observability action id is not registered",
        ))
    }
}

pub(super) fn validate_component_id(value: &str) -> CoreResult<()> {
    if catalog()?.components.contains(value) {
        Ok(())
    } else {
        Err(CoreError::validation(
            "observability component id is not registered",
        ))
    }
}

fn catalog() -> CoreResult<&'static CatalogIndex> {
    match CATALOG.get_or_init(|| parse_catalog(CATALOG_JSON)) {
        Ok(catalog) => Ok(catalog),
        Err(error) => Err(CoreError::internal(error.reason())),
    }
}

fn parse_catalog(json: &str) -> Result<CatalogIndex, CatalogLoadError> {
    let version: CatalogVersionHeader =
        serde_json::from_str(json).map_err(|_| CatalogLoadError::InvalidDocument)?;
    if version.schema_version != CATALOG_SCHEMA_VERSION {
        return Err(CatalogLoadError::UnsupportedSchema);
    }
    let document: CatalogDocument =
        serde_json::from_str(json).map_err(|_| CatalogLoadError::InvalidDocument)?;
    debug_assert_eq!(document.schema_version, CATALOG_SCHEMA_VERSION);
    validate_document(&document)
}

fn validate_document(document: &CatalogDocument) -> Result<CatalogIndex, CatalogLoadError> {
    let actions = validate_actions(&document.actions)?;
    let components = validate_components(&document.components)?;
    let groups = document
        .actions
        .iter()
        .map(|action| action.group.clone())
        .collect();
    validate_flows(&document.expected_flows, &actions, &components, &groups)?;
    Ok(CatalogIndex {
        actions,
        components,
    })
}

fn validate_actions(actions: &[CatalogAction]) -> Result<BTreeSet<String>, CatalogLoadError> {
    validate_sorted_entries(actions, |action| action.id.as_str())?;
    if actions
        .iter()
        .any(|action| !valid_id(&action.id) || !valid_id(&action.group))
    {
        return Err(CatalogLoadError::InvalidDocument);
    }
    Ok(actions.iter().map(|action| action.id.clone()).collect())
}

fn validate_components(
    components: &[CatalogComponent],
) -> Result<BTreeSet<String>, CatalogLoadError> {
    validate_sorted_entries(components, |component| component.id.as_str())?;
    for component in components {
        let owner_prefix = format!("{}.", component.owner);
        if !valid_id(&component.id)
            || !valid_id(&component.owner)
            || !valid_id(&component.role)
            || !component.id.starts_with(&owner_prefix)
            || !valid_symbol(&component.symbol)
            || !valid_authority(&component.authority)
        {
            return Err(CatalogLoadError::InvalidDocument);
        }
    }
    Ok(components
        .iter()
        .map(|component| component.id.clone())
        .collect())
}

fn validate_flows(
    flows: &[CatalogExpectedFlow],
    actions: &BTreeSet<String>,
    components: &BTreeSet<String>,
    groups: &BTreeSet<String>,
) -> Result<(), CatalogLoadError> {
    validate_sorted_entries(flows, |flow| flow.id.as_str())?;
    let mut claimed_entry_actions = BTreeSet::new();
    for flow in flows {
        validate_flow(
            flow,
            actions,
            components,
            groups,
            &mut claimed_entry_actions,
        )?;
    }
    Ok(())
}

fn validate_flow(
    flow: &CatalogExpectedFlow,
    actions: &BTreeSet<String>,
    components: &BTreeSet<String>,
    groups: &BTreeSet<String>,
    claimed_entry_actions: &mut BTreeSet<String>,
) -> Result<(), CatalogLoadError> {
    if !valid_id(&flow.id)
        || flow.entry_action_ids.is_empty()
        || flow.steps.is_empty()
        || !flow.steps.iter().any(|step| step.required)
    {
        return Err(CatalogLoadError::InvalidDocument);
    }
    validate_sorted_values(&flow.entry_action_ids)?;
    for action_id in &flow.entry_action_ids {
        if !actions.contains(action_id) || !claimed_entry_actions.insert(action_id.clone()) {
            return Err(CatalogLoadError::InvalidDocument);
        }
    }
    let mut step_ids = BTreeSet::new();
    for step in &flow.steps {
        if !valid_id(&step.id) || !step_ids.insert(step.id.as_str()) || step.match_any.is_empty() {
            return Err(CatalogLoadError::InvalidDocument);
        }
        validate_selectors(&step.match_any, actions, components, groups)?;
    }
    Ok(())
}

fn validate_selectors(
    selectors: &[CatalogSelector],
    actions: &BTreeSet<String>,
    components: &BTreeSet<String>,
    groups: &BTreeSet<String>,
) -> Result<(), CatalogLoadError> {
    let mut identities = BTreeSet::new();
    for selector in selectors {
        let action_identity = match (&selector.action_id, &selector.action_group) {
            (Some(action_id), None) if actions.contains(action_id) => ("action", action_id),
            (None, Some(group)) if groups.contains(group) => ("group", group),
            _ => return Err(CatalogLoadError::InvalidDocument),
        };
        if !components.contains(&selector.component_id)
            || selector
                .phase
                .as_deref()
                .is_some_and(|phase| !valid_id(phase))
        {
            return Err(CatalogLoadError::InvalidDocument);
        }
        let identity = (
            action_identity.0,
            action_identity.1.as_str(),
            selector.component_id.as_str(),
            selector.phase.as_deref(),
        );
        if !identities.insert(identity) {
            return Err(CatalogLoadError::InvalidDocument);
        }
    }
    Ok(())
}

fn validate_sorted_entries<T>(
    values: &[T],
    id: impl Fn(&T) -> &str,
) -> Result<(), CatalogLoadError> {
    if values.is_empty() || values.windows(2).any(|pair| id(&pair[0]) >= id(&pair[1])) {
        return Err(CatalogLoadError::InvalidDocument);
    }
    Ok(())
}

fn validate_sorted_values(values: &[String]) -> Result<(), CatalogLoadError> {
    if values
        .windows(2)
        .any(|pair| pair[0].as_str() >= pair[1].as_str())
        || values.iter().any(|value| !valid_id(value))
    {
        return Err(CatalogLoadError::InvalidDocument);
    }
    Ok(())
}

fn valid_id(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.is_empty() || bytes.len() > 128 || !bytes[0].is_ascii_lowercase() {
        return false;
    }
    let mut previous_was_separator = false;
    for byte in bytes {
        if byte.is_ascii_lowercase() || byte.is_ascii_digit() {
            previous_was_separator = false;
        } else if matches!(byte, b'.' | b'_' | b'-') && !previous_was_separator {
            previous_was_separator = true;
        } else {
            return false;
        }
    }
    !previous_was_separator
}

fn valid_symbol(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 256
        && !value.chars().any(char::is_control)
        && !value.contains(['\n', '\r'])
}

fn valid_authority(value: &str) -> bool {
    value.starts_with("docs/")
        && value.ends_with(".md")
        && value.len() <= 256
        && !value.contains(['\\', '\0'])
        && value
            .split('/')
            .all(|segment| !segment.is_empty() && !matches!(segment, "." | ".."))
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURES: &[(&str, Result<(), CatalogLoadError>)] = &[
        (
            include_str!("../../tests/fixtures/observability_catalog/valid-minimal-v1.json"),
            Ok(()),
        ),
        (
            include_str!("../../tests/fixtures/observability_catalog/invalid-malformed.json"),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!("../../tests/fixtures/observability_catalog/invalid-unknown-field.json"),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!("../../tests/fixtures/observability_catalog/invalid-duplicate-id.json"),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!("../../tests/fixtures/observability_catalog/invalid-non-ascii-id.json"),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!(
                "../../tests/fixtures/observability_catalog/invalid-dangling-reference.json"
            ),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!("../../tests/fixtures/observability_catalog/invalid-selector-shape.json"),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!("../../tests/fixtures/observability_catalog/invalid-empty-flow.json"),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!(
                "../../tests/fixtures/observability_catalog/invalid-all-optional-flow.json"
            ),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!(
                "../../tests/fixtures/observability_catalog/invalid-control-authority.json"
            ),
            Err(CatalogLoadError::InvalidDocument),
        ),
        (
            include_str!("../../tests/fixtures/observability_catalog/unsupported-schema.json"),
            Err(CatalogLoadError::UnsupportedSchema),
        ),
    ];

    #[test]
    fn embedded_catalog_is_strict_and_contains_runtime_flow() {
        let catalog = parse_catalog(CATALOG_JSON).expect("embedded catalog should be valid");
        assert!(catalog.actions.contains("observability.events_dropped"));
        assert!(catalog.components.contains("core.observability.runtime"));
    }

    #[test]
    fn golden_catalog_documents_have_expected_results() {
        for (json, expected) in FIXTURES {
            assert_eq!(parse_catalog(json).map(|_| ()), *expected);
        }
    }

    #[test]
    fn membership_is_exact_and_does_not_accept_prefix_extensions() {
        assert!(validate_action_id("repository.import.confirmed").is_ok());
        assert!(matches!(
            validate_action_id("repository.import.confirmed.unregistered"),
            Err(CoreError::Validation { .. })
        ));
    }
}
