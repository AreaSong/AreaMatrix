use std::{
    collections::HashSet,
    path::{Path, PathBuf},
};

use crate::{
    search, AiCapabilityState, AiFeatureKind, AiProviderPreference, CoreError, CoreResult,
    SearchFilter, SearchPagination, SearchResultPage, SearchSort,
};

use super::{
    call_log::{
        ensure_semantic_call_log_gate, insert_call_log, insert_call_log_in_tx, SearchLog,
        LOCAL_MODEL,
    },
    executor::{self, RemoteBuildDraft, RemoteSearchDraft, SemanticRemoteError},
    fallback::{BuildFallback, SearchFallback},
    matches::{build_index_groups, build_remote_groups, normal_matches},
    store::{load_indexed_files, load_semantic_index, save_semantic_index, StoredSemanticIndex},
    SemanticIndexBuildReport, SemanticIndexScope, SemanticIndexStatus,
    SemanticSearchFallbackReason, SemanticSearchResultPage, SemanticSearchRoute,
};

pub(super) fn semantic_search(
    repo_path: String,
    query: String,
    filter: SearchFilter,
    pagination: SearchPagination,
) -> CoreResult<SemanticSearchResultPage> {
    let normal_page = normal_search(
        repo_path.clone(),
        query.clone(),
        filter.clone(),
        pagination.clone(),
    );
    let repo = PathBuf::from(&repo_path);
    let ai_config = crate::ai_settings::load_ai_config(repo_path)?;
    let capability = semantic_capability(&ai_config.capabilities)?;

    if !ai_config.config.ai_enabled {
        return fallback_search_page_from_normal_result(
            repo,
            query,
            normal_page,
            SearchFallback::ai_disabled(),
        );
    }
    if !capability.enabled {
        return fallback_search_page_from_normal_result(
            repo,
            query,
            normal_page,
            SearchFallback::feature_disabled(),
        );
    }
    if let Some(rule_id) = search_privacy_block(load_semantic_index(&repo)?.as_ref()) {
        return fallback_search_page_from_normal_result(
            repo,
            query,
            normal_page,
            SearchFallback::privacy(rule_id),
        );
    }

    let Some(route) = select_route(capability, &ai_config.config.provider_preference) else {
        return fallback_search_page_from_normal_result(
            repo,
            query,
            normal_page,
            SearchFallback::provider(),
        );
    };
    let index = load_semantic_index(&repo)?;

    match route {
        SemanticSearchRoute::Remote => {
            remote_semantic_search(repo, query, filter, pagination, normal_page, index)
        }
        SemanticSearchRoute::Local => {
            local_semantic_search(repo, query, filter, pagination, normal_page, index)
        }
    }
}

pub(super) fn build_embedding_index(
    repo_path: String,
    scope: SemanticIndexScope,
) -> CoreResult<SemanticIndexBuildReport> {
    let scope_page = normal_search(
        repo_path.clone(),
        String::new(),
        scope.filter.clone(),
        SearchPagination {
            limit: 1,
            offset: 0,
        },
    )?;
    let repo = PathBuf::from(&repo_path);
    let ai_config = crate::ai_settings::load_ai_config(repo_path)?;
    let capability = semantic_capability(&ai_config.capabilities)?;

    if !ai_config.config.ai_enabled {
        return fallback_build_report(&repo, scope_page.total_count, BuildFallback::ai_disabled());
    }
    if !capability.enabled {
        return fallback_build_report(
            &repo,
            scope_page.total_count,
            BuildFallback::feature_disabled(),
        );
    }
    let Some(route) =
        selected_build_route(&scope, capability, &ai_config.config.provider_preference)
    else {
        return fallback_build_report(&repo, scope_page.total_count, BuildFallback::provider());
    };
    if scope_page.total_count <= 0 {
        return fallback_build_report(&repo, 0, BuildFallback::no_input(route));
    }

    match route {
        SemanticSearchRoute::Remote => {
            remote_build_embedding_index(&repo, scope, scope_page.total_count, &ai_config)
        }
        SemanticSearchRoute::Local => {
            local_build_embedding_index(&repo, scope, scope_page.total_count, &ai_config)
        }
    }
}

fn local_semantic_search(
    repo: PathBuf,
    query: String,
    filter: SearchFilter,
    pagination: SearchPagination,
    normal_page: CoreResult<SearchResultPage>,
    index: Option<StoredSemanticIndex>,
) -> CoreResult<SemanticSearchResultPage> {
    let Some(index) = ready_index(index.as_ref()) else {
        return fallback_search_page_from_normal_result(
            repo,
            query,
            normal_page,
            SearchFallback::index_not_ready(),
        );
    };
    let (semantic_total_count, indexed_files) =
        load_indexed_files(&repo, &query, &filter, &pagination)?;
    let call_log_id = match insert_call_log(
        &repo,
        SearchLog::success(&SemanticSearchRoute::Local, indexed_files.len()),
    ) {
        Ok(id) => Some(id),
        Err(_) => {
            return fallback_search_page_from_normal_result(
                repo,
                query,
                normal_page,
                SearchFallback::call_log(),
            )
        }
    };
    success_search_page(
        query,
        normal_page,
        SemanticSearchRoute::Local,
        index.status.clone(),
        call_log_id,
        semantic_total_count,
        indexed_files,
    )
}

fn remote_semantic_search(
    repo: PathBuf,
    query: String,
    filter: SearchFilter,
    pagination: SearchPagination,
    normal_page: CoreResult<SearchResultPage>,
    index: Option<StoredSemanticIndex>,
) -> CoreResult<SemanticSearchResultPage> {
    if let Err(error) = ensure_semantic_call_log_gate(&repo) {
        if matches!(error, CoreError::Db { .. }) {
            return fallback_search_page_from_normal_result(
                repo,
                query,
                normal_page,
                SearchFallback::call_log(),
            );
        }
        return Err(error);
    }

    match executor::execute_remote_search(&repo, &query, &filter, &pagination) {
        Ok(draft) => remote_success_search_page(
            repo,
            query,
            normal_page,
            draft,
            index_status_from_index(index.as_ref()),
        ),
        Err(SemanticRemoteError::RateLimited) => fallback_search_page_from_normal_result(
            repo,
            query,
            normal_page,
            SearchFallback::rate_limited(),
        ),
        Err(SemanticRemoteError::Timeout) => fallback_search_page_from_normal_result(
            repo,
            query,
            normal_page,
            SearchFallback::timeout(),
        ),
        Err(SemanticRemoteError::Unavailable) => fallback_search_page_from_normal_result(
            repo,
            query,
            normal_page,
            SearchFallback::provider(),
        ),
    }
}

fn remote_success_search_page(
    repo: PathBuf,
    query: String,
    normal_page: CoreResult<SearchResultPage>,
    draft: RemoteSearchDraft,
    index_status: SemanticIndexStatus,
) -> CoreResult<SemanticSearchResultPage> {
    let hydrated = executor::hydrate_remote_matches(&repo, draft.matches)?;
    let call_log_id = match insert_call_log(
        &repo,
        SearchLog::success_with_model(
            &SemanticSearchRoute::Remote,
            hydrated.len(),
            Some(&draft.model),
        ),
    ) {
        Ok(id) => Some(id),
        Err(_) => {
            return fallback_search_page(repo, query, normal_page?, SearchFallback::call_log())
        }
    };
    success_remote_search_page(
        repo,
        query,
        normal_page,
        hydrated,
        index_status,
        call_log_id,
    )
}

fn local_build_embedding_index(
    repo: &Path,
    scope: SemanticIndexScope,
    _total_count: i64,
    ai_config: &crate::ai_settings::AiConfigSnapshot,
) -> CoreResult<SemanticIndexBuildReport> {
    let route = SemanticSearchRoute::Local;
    let (outcome, call_log_id) = crate::db::with_write_transaction(repo, |tx| {
        let outcome = save_semantic_index(
            repo,
            tx,
            route.clone(),
            &scope.filter,
            scope
                .privacy_policy_ref
                .as_deref()
                .or(ai_config.config.privacy_policy_ref.as_deref()),
        )?;
        let call_log_id = insert_call_log_in_tx(
            tx,
            SearchLog::build_result(
                &route,
                outcome.metadata.processed_count,
                outcome.metadata.failed_count,
                outcome.privacy_rule_id.as_deref(),
            ),
        )?;
        Ok((outcome, call_log_id))
    })?;
    Ok(build_success_report(
        route,
        outcome.metadata,
        Some(LOCAL_MODEL.to_owned()),
        call_log_id,
        outcome.privacy_rule_id,
    ))
}

fn remote_build_embedding_index(
    repo: &Path,
    scope: SemanticIndexScope,
    total_count: i64,
    ai_config: &crate::ai_settings::AiConfigSnapshot,
) -> CoreResult<SemanticIndexBuildReport> {
    if let Err(error) = ensure_semantic_call_log_gate(repo) {
        if matches!(error, CoreError::Db { .. }) {
            let (fallback, total_count) = BuildFallback::call_log(total_count);
            return fallback_build_report(repo, total_count, fallback);
        }
        return Err(error);
    }

    let route = SemanticSearchRoute::Remote;
    let draft = match executor::execute_remote_build(repo, &scope.filter) {
        Ok(draft) => draft,
        Err(SemanticRemoteError::RateLimited) => {
            return fallback_build_report(repo, total_count, BuildFallback::rate_limited());
        }
        Err(SemanticRemoteError::Timeout) => {
            return fallback_build_report(repo, total_count, BuildFallback::timeout());
        }
        Err(SemanticRemoteError::Unavailable) => {
            return fallback_build_report(repo, total_count, BuildFallback::provider());
        }
    };
    complete_remote_build(repo, scope, ai_config, route, draft)
}

fn complete_remote_build(
    repo: &Path,
    scope: SemanticIndexScope,
    ai_config: &crate::ai_settings::AiConfigSnapshot,
    route: SemanticSearchRoute,
    draft: RemoteBuildDraft,
) -> CoreResult<SemanticIndexBuildReport> {
    let (outcome, call_log_id) = crate::db::with_write_transaction(repo, |tx| {
        let outcome = save_semantic_index(
            repo,
            tx,
            route.clone(),
            &scope.filter,
            scope
                .privacy_policy_ref
                .as_deref()
                .or(ai_config.config.privacy_policy_ref.as_deref()),
        )?;
        let call_log_id = insert_call_log_in_tx(
            tx,
            SearchLog::build_result_with_model(
                &route,
                outcome.metadata.processed_count,
                outcome.metadata.failed_count,
                outcome.privacy_rule_id.as_deref(),
                Some(&draft.model),
            ),
        )?;
        Ok((outcome, call_log_id))
    })?;
    Ok(build_success_report(
        route,
        outcome.metadata,
        Some(draft.model),
        call_log_id,
        outcome.privacy_rule_id,
    ))
}

fn normal_search(
    repo_path: String,
    query: String,
    filter: SearchFilter,
    pagination: SearchPagination,
) -> CoreResult<SearchResultPage> {
    search::search_files(repo_path, query, filter, SearchSort::Relevance, pagination)
}

fn fallback_search_page_from_normal_result(
    repo: PathBuf,
    query: String,
    normal_page: CoreResult<SearchResultPage>,
    fallback: SearchFallback,
) -> CoreResult<SemanticSearchResultPage> {
    fallback_search_page(repo, query, normal_page?, fallback)
}

fn semantic_capability(capabilities: &[AiCapabilityState]) -> CoreResult<&AiCapabilityState> {
    capabilities
        .iter()
        .find(|state| state.feature == AiFeatureKind::SemanticSearch)
        .ok_or_else(|| CoreError::config("Semantic search capability is not configured"))
}

fn search_privacy_block(index: Option<&StoredSemanticIndex>) -> Option<String> {
    let index = index?;
    if index.processed_count == 0
        && index.privacy_skipped_count > 0
        && matches!(index.status, SemanticIndexStatus::NotReady)
    {
        return index.privacy_rule_id.clone();
    }
    None
}

fn select_route(
    capability: &AiCapabilityState,
    preference: &AiProviderPreference,
) -> Option<SemanticSearchRoute> {
    if matches!(preference, AiProviderPreference::RemoteFirst) && capability.remote_allowed {
        return Some(SemanticSearchRoute::Remote);
    }
    if capability.local_allowed {
        return Some(SemanticSearchRoute::Local);
    }
    if capability.remote_allowed {
        return Some(SemanticSearchRoute::Remote);
    }
    None
}

fn selected_build_route(
    scope: &SemanticIndexScope,
    capability: &AiCapabilityState,
    preference: &AiProviderPreference,
) -> Option<SemanticSearchRoute> {
    match scope.route {
        Some(SemanticSearchRoute::Local) => capability
            .local_allowed
            .then_some(SemanticSearchRoute::Local),
        Some(SemanticSearchRoute::Remote) => capability
            .remote_allowed
            .then_some(SemanticSearchRoute::Remote),
        None => select_route(capability, preference),
    }
}

fn ready_index(index: Option<&StoredSemanticIndex>) -> Option<&StoredSemanticIndex> {
    index.filter(|metadata| {
        matches!(
            metadata.status,
            SemanticIndexStatus::Ready | SemanticIndexStatus::Partial
        )
    })
}

fn index_status_from_index(index: Option<&StoredSemanticIndex>) -> SemanticIndexStatus {
    index
        .map(|metadata| metadata.status.clone())
        .unwrap_or(SemanticIndexStatus::NotReady)
}

fn fallback_search_page(
    repo: PathBuf,
    query: String,
    normal_page: SearchResultPage,
    fallback: SearchFallback,
) -> CoreResult<SemanticSearchResultPage> {
    let call_log_id = insert_call_log(&repo, SearchLog::skipped(&fallback)).ok();
    let reason = if call_log_id.is_none() {
        SemanticSearchFallbackReason::CallLogUnavailable
    } else {
        fallback.reason
    };
    let message = if call_log_id.is_none() {
        "Semantic search call log is unavailable"
    } else {
        fallback.message
    };
    Ok(SemanticSearchResultPage {
        query,
        semantic_total_count: 0,
        normal_total_count: normal_page.total_count,
        semantic_matches: Vec::new(),
        normal_matches: normal_matches(normal_page.results, &HashSet::new()),
        deduped_normal_count: 0,
        index_status: SemanticIndexStatus::NotReady,
        route: None,
        fallback_reason: Some(reason),
        fallback_message: Some(message.to_owned()),
        call_log_id,
        privacy_rule_id: fallback.privacy_rule_id,
        low_confidence: false,
    })
}

fn success_search_page(
    query: String,
    normal_page: CoreResult<SearchResultPage>,
    route: SemanticSearchRoute,
    index_status: SemanticIndexStatus,
    call_log_id: Option<i64>,
    semantic_total_count: i64,
    indexed_files: Vec<super::store::SemanticIndexedFile>,
) -> CoreResult<SemanticSearchResultPage> {
    let normal_unavailable = normal_page.is_err();
    let (normal_total_count, normal_results) = match normal_page {
        Ok(page) => (page.total_count, page.results),
        Err(_) => (0, Vec::new()),
    };
    let groups = build_index_groups(
        semantic_total_count,
        indexed_files,
        normal_results,
        route.clone(),
        call_log_id,
    )?;
    Ok(SemanticSearchResultPage {
        query,
        semantic_total_count: groups.semantic_total_count,
        normal_total_count,
        semantic_matches: groups.semantic_matches,
        normal_matches: groups.normal_matches,
        deduped_normal_count: groups.deduped_normal_count,
        index_status,
        route: Some(route),
        fallback_reason: normal_unavailable
            .then_some(SemanticSearchFallbackReason::NormalSearchUnavailable),
        fallback_message: normal_unavailable
            .then_some("Normal search fallback is unavailable".to_owned()),
        call_log_id,
        privacy_rule_id: None,
        low_confidence: groups.low_confidence,
    })
}

fn success_remote_search_page(
    repo: PathBuf,
    query: String,
    normal_page: CoreResult<SearchResultPage>,
    matches: Vec<executor::RemoteSearchMatchDraft>,
    index_status: SemanticIndexStatus,
    call_log_id: Option<i64>,
) -> CoreResult<SemanticSearchResultPage> {
    let normal_unavailable = normal_page.is_err();
    let (normal_total_count, normal_results) = match normal_page {
        Ok(page) => (page.total_count, page.results),
        Err(_) => (0, Vec::new()),
    };
    let semantic_total_count =
        i64::try_from(matches.len()).map_err(|error| CoreError::db(error.to_string()))?;
    let groups = build_remote_groups(
        semantic_total_count,
        matches,
        &repo,
        SemanticSearchRoute::Remote,
        call_log_id,
        normal_results,
    )?;
    Ok(SemanticSearchResultPage {
        query,
        semantic_total_count: groups.semantic_total_count,
        normal_total_count,
        semantic_matches: groups.semantic_matches,
        normal_matches: groups.normal_matches,
        deduped_normal_count: groups.deduped_normal_count,
        index_status,
        route: Some(SemanticSearchRoute::Remote),
        fallback_reason: normal_unavailable
            .then_some(SemanticSearchFallbackReason::NormalSearchUnavailable),
        fallback_message: normal_unavailable
            .then_some("Normal search fallback is unavailable".to_owned()),
        call_log_id,
        privacy_rule_id: None,
        low_confidence: groups.low_confidence,
    })
}

fn fallback_build_report(
    repo: &Path,
    total_count: i64,
    fallback: BuildFallback,
) -> CoreResult<SemanticIndexBuildReport> {
    let call_log_id = match insert_call_log(repo, SearchLog::build_fallback(&fallback)) {
        Ok(id) => Some(id),
        Err(_) => {
            let (fallback, total_count) = BuildFallback::call_log(total_count);
            return Ok(build_report(total_count, fallback, None));
        }
    };
    Ok(build_report(total_count, fallback, call_log_id))
}

fn build_success_report(
    route: SemanticSearchRoute,
    metadata: StoredSemanticIndex,
    provider_name: Option<String>,
    call_log_id: i64,
    _privacy_rule_id: Option<String>,
) -> SemanticIndexBuildReport {
    SemanticIndexBuildReport {
        status: metadata.status.clone(),
        route: Some(route),
        total_count: metadata.total_count,
        processed_count: metadata.processed_count,
        skipped_count: metadata.skipped_count,
        failed_count: metadata.failed_count,
        privacy_skipped_count: metadata.privacy_skipped_count,
        provider_name,
        call_log_id: Some(call_log_id),
        fallback_reason: build_fallback_reason(&metadata),
        message: Some(build_message(&metadata)),
    }
}

fn build_report(
    total_count: i64,
    fallback: BuildFallback,
    call_log_id: Option<i64>,
) -> SemanticIndexBuildReport {
    SemanticIndexBuildReport {
        status: SemanticIndexStatus::NotReady,
        route: fallback.route,
        total_count,
        processed_count: 0,
        skipped_count: 0,
        failed_count: 0,
        privacy_skipped_count: 0,
        provider_name: None,
        call_log_id,
        fallback_reason: Some(fallback.reason),
        message: Some(fallback.message.to_owned()),
    }
}

fn build_fallback_reason(metadata: &StoredSemanticIndex) -> Option<SemanticSearchFallbackReason> {
    if metadata.processed_count == 0 && metadata.privacy_skipped_count > 0 {
        Some(SemanticSearchFallbackReason::PrivacyRule)
    } else {
        None
    }
}

fn build_message(metadata: &StoredSemanticIndex) -> String {
    if metadata.failed_count > 0 && metadata.processed_count == 0 {
        return format!(
            "Semantic index is not ready; {} file(s) failed",
            metadata.failed_count
        );
    }
    if metadata.failed_count > 0 {
        return format!(
            "Semantic index is partially ready; {} file(s) failed",
            metadata.failed_count
        );
    }
    if metadata.processed_count == 0 && metadata.privacy_skipped_count > 0 {
        return "Embedding input was skipped by privacy policy".to_owned();
    }
    if metadata.privacy_skipped_count > 0 {
        return format!(
            "Semantic index is partially ready; {} file(s) skipped by privacy rules",
            metadata.privacy_skipped_count
        );
    }
    if metadata.skipped_count > 0 {
        return format!(
            "Semantic index is partially ready; {} file(s) skipped",
            metadata.skipped_count
        );
    }
    "Semantic index is ready".to_owned()
}
