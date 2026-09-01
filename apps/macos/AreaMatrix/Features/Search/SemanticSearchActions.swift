import Foundation

enum SemanticIndexBuildState: Equatable {
    case idle
    case building(request: SearchQueryRequestSnapshot)
    case completed(request: SearchQueryRequestSnapshot, report: SemanticIndexBuildReportSnapshot)
    case canceled(request: SearchQueryRequestSnapshot)
    case failed(request: SearchQueryRequestSnapshot, CoreErrorMappingSnapshot)

    var isBuilding: Bool {
        if case .building = self { return true }
        return false
    }

    var canCancel: Bool {
        if case .building = self { return true }
        return false
    }

    var canPause: Bool {
        if case .building = self { return true }
        return false
    }

    var canResume: Bool {
        if case let .completed(_, report) = self, report.status == .paused { return true }
        return false
    }

    var canRetryFailedItems: Bool {
        switch self {
        case let .completed(_, report):
            report.failedCount > 0 || report.status == .partial || report.status == .failed
        case .canceled, .failed:
            true
        case .idle, .building:
            false
        }
    }
}

enum SemanticPrivacyGateState: Equatable {
    case idle
    case checking(request: SearchQueryRequestSnapshot)
    case allowed(request: SearchQueryRequestSnapshot, report: AIPrivacyEvaluationReportSnapshot)
    case blocked(request: SearchQueryRequestSnapshot, report: AIPrivacyEvaluationReportSnapshot)
    case failed(request: SearchQueryRequestSnapshot, CoreErrorMappingSnapshot)

    var allowsIndexBuild: Bool {
        if case .allowed = self { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var matchedRuleID: String? {
        guard let ruleID = report?.matchedRules.first?.ruleId.trimmingCharacters(in: .whitespacesAndNewlines),
              !ruleID.isEmpty else { return nil }
        return ruleID
    }

    var report: AIPrivacyEvaluationReportSnapshot? {
        switch self {
        case let .allowed(_, report), let .blocked(_, report):
            report
        case .idle, .checking, .failed:
            nil
        }
    }

    func isCurrent(for request: SearchQueryRequestSnapshot?) -> Bool {
        guard let request else { return self == .idle }
        return self.request == request
    }

    private var request: SearchQueryRequestSnapshot? {
        switch self {
        case .idle:
            nil
        case let .checking(request), let .allowed(request, _), let .blocked(request, _), let .failed(request, _):
            request
        }
    }
}

enum SemanticFallbackState: Equatable {
    case idle
    case loading(request: SearchQueryRequestSnapshot)
    case loaded(request: SearchQueryRequestSnapshot, status: AIFallbackStatusSnapshot)
    case failed(request: SearchQueryRequestSnapshot, CoreErrorMappingSnapshot)

    var status: AIFallbackStatusSnapshot? {
        guard case let .loaded(_, status) = self else { return nil }
        return status
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        guard case let .failed(_, mapping) = self else { return nil }
        return mapping
    }

    var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }

    func isCurrent(for request: SearchQueryRequestSnapshot?) -> Bool {
        guard let request else { return self == .idle }
        return self.request == request
    }

    private var request: SearchQueryRequestSnapshot? {
        switch self {
        case .idle:
            nil
        case let .loading(request), let .loaded(request, _), let .failed(request, _):
            request
        }
    }
}

extension SearchModel {
    func searchPage(for request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        switch request.mode {
        case .normal:
            try await searchQuerying.searchFiles(repoPath: repoPath, request: request)
        case .semantic:
            try await semanticSearching.semanticSearch(repoPath: repoPath, request: request)
        }
    }

    func buildSemanticIndexForCurrentSearch() async {
        guard let request = searchState.request, request.mode == .semantic else { return }
        guard await ensureSemanticPrivacyGate(for: request) else { return }
        cancelActiveSemanticIndexBuild()
        semanticIndexBuildGeneration += 1
        let generation = semanticIndexBuildGeneration
        let task = semanticIndexBuildTask(for: request)
        semanticIndexBuildTask = task
        semanticIndexBuildState = .building(request: request)
        semanticIndexControlState = .idle
        do {
            let report = try await task.value
            guard semanticIndexBuildIsCurrent(generation: generation, request: request) else { return }
            semanticIndexBuildTask = nil
            semanticIndexBuildState = .completed(request: request, report: report)
        } catch is CancellationError {
            guard semanticIndexBuildIsCurrent(generation: generation, request: request) else { return }
            semanticIndexBuildTask = nil
            semanticIndexBuildState = .canceled(request: request)
        } catch {
            guard semanticIndexBuildIsCurrent(generation: generation, request: request) else { return }
            semanticIndexBuildTask = nil
            semanticIndexBuildState = await .failed(request: request, mapCoreError(error))
        }
    }

    func cancelActiveSemanticIndexBuild() {
        semanticIndexBuildTask?.cancel()
        semanticIndexBuildTask = nil
    }

    private func semanticIndexBuildTask(
        for request: SearchQueryRequestSnapshot
    ) -> Task<SemanticIndexBuildReportSnapshot, Error> {
        let repoPath = repoPath
        let semanticSearching = semanticSearching
        return Task {
            let report = try await semanticSearching.buildEmbeddingIndex(repoPath: repoPath, request: request)
            try Task.checkCancellation()
            return report
        }
    }

    private func semanticIndexBuildIsCurrent(
        generation: Int,
        request: SearchQueryRequestSnapshot
    ) -> Bool {
        semanticIndexBuildGeneration == generation && searchState.request == request
    }

    func refreshSemanticPrivacyGateForCurrentSearch() async {
        guard let request = searchState.request, request.mode == .semantic else {
            semanticPrivacyGateState = .idle
            return
        }
        _ = await evaluateSemanticPrivacyGate(for: request)
    }

    func clearSemanticPrivacyGate() {
        semanticPrivacyGateState = .idle
    }

    func loadSemanticFallbackStatus(for request: SearchQueryRequestSnapshot) async {
        guard request.mode == .semantic else {
            semanticFallbackState = .idle
            return
        }
        guard searchState.page?.semanticPage?.fallbackReason != nil else {
            semanticFallbackState = .idle
            return
        }

        semanticFallbackState = .loading(request: request)
        let fallbackRequest = semanticFallbackRequest(for: request)
        do {
            let status = try await semanticFallbackReader.semanticFallbackStatus(
                repoPath: repoPath,
                request: fallbackRequest
            )
            guard searchState.request == request else { return }
            semanticFallbackState = .loaded(request: request, status: status)
        } catch {
            let mappedError = await mapCoreError(error)
            guard searchState.request == request else { return }
            semanticFallbackState = .failed(request: request, mappedError)
        }
    }

    private func ensureSemanticPrivacyGate(for request: SearchQueryRequestSnapshot) async -> Bool {
        if semanticPrivacyGateState.isCurrent(for: request), semanticPrivacyGateState.allowsIndexBuild {
            return true
        }
        return await evaluateSemanticPrivacyGate(for: request)
    }

    private func evaluateSemanticPrivacyGate(for request: SearchQueryRequestSnapshot) async -> Bool {
        semanticPrivacyGateState = .checking(request: request)
        do {
            let snapshot = try await aiPrivacyRules.loadAIPrivacyRules(repoPath: repoPath)
            let report = try await aiPrivacyRules.evaluateAIPrivacy(
                repoPath: repoPath,
                request: semanticPrivacyEvaluationRequest(for: request, snapshot: snapshot)
            )
            guard searchState.request == request else { return false }
            if report.decision == .allowed {
                semanticPrivacyGateState = .allowed(request: request, report: report)
                return true
            }
            semanticPrivacyGateState = .blocked(request: request, report: report)
            return false
        } catch {
            let mapping = await mapCoreError(error)
            guard searchState.request == request else { return false }
            semanticPrivacyGateState = .failed(request: request, mapping)
            return false
        }
    }

    private func semanticPrivacyEvaluationRequest(
        for request: SearchQueryRequestSnapshot,
        snapshot: AIPrivacyRulesSnapshot
    ) -> AIPrivacyEvaluationRequestSnapshot {
        AIPrivacyEvaluationRequestSnapshot(
            feature: .semanticSearch,
            route: semanticPrivacyRouteForCurrentPage(),
            requestedFields: [
                .fileName, .repoRelativePath, .extension, .extractedTextExcerpt,
                .aiSummary, .noteSummary, .tagCategoryContext
            ],
            privacyGateEnabled: snapshot.privacyGateEnabled,
            providerScope: snapshot.providerScope,
            rules: snapshot.rules.map(AIPrivacyRuleInputSnapshot.init(summaryRule:)),
            remoteAllowedFields: snapshot.remoteAllowedFields.map(AIPrivacyFieldRuleSnapshot.init(state:)),
            context: semanticPrivacyContext(for: request)
        )
    }

    private func semanticPrivacyRouteForCurrentPage() -> AIPrivacyEvaluationRouteState {
        searchState.page?.semanticPage?.route == .remote ? .remote : .local
    }

    private func semanticPrivacyContext(for request: SearchQueryRequestSnapshot) -> AIPrivacyEvaluationContextSnapshot {
        AIPrivacyEvaluationContextSnapshot(
            fileId: nil,
            repoRelativePath: request.currentPath,
            fileName: request.query,
            category: request.category ?? request.filters.category,
            extension: semanticPrivacyExtension(from: request.filters.fileKind),
            tags: request.filters.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func semanticPrivacyExtension(from fileKind: String?) -> String? {
        guard let value = fileKind?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }

    private func semanticFallbackRequest(for _: SearchQueryRequestSnapshot) -> AIFallbackStatusRequestSnapshot {
        let semanticPage = searchState.page?.semanticPage
        let providerError = semanticProviderError(for: semanticPage?.fallbackReason)
        return AIFallbackStatusRequestSnapshot(
            operation: .semanticSearch,
            route: semanticPage?.route.map(AICallLogRouteSnapshot.init),
            providerError: providerError,
            providerErrorCode: semanticProviderErrorCode(for: providerError),
            privacyDecision: privacyDecision(for: semanticPage?.fallbackReason),
            privacySkippedReason: privacySkippedReason(for: semanticPage?.fallbackReason),
            categorySkippedReason: nil,
            semanticFallbackReason: semanticPage?.fallbackReason,
            callLogStatus: semanticCallLogStatus(for: semanticPage?.fallbackReason),
            callLogID: semanticPage?.callLogID,
            privacyRuleID: semanticPage?.privacyRuleID,
            retryAfter: nil
        )
    }

    private func semanticProviderError(for reason: SemanticSearchFallbackReasonSnapshot?)
        -> AIFallbackProviderErrorKindSnapshot? {
        switch reason {
        case .providerUnavailable:
            .providerUnavailable
        case .rateLimited:
            .rateLimited
        case .timeout:
            .timeout
        case .callLogUnavailable:
            .callLogUnavailable
        case .aiDisabled, .featureDisabled, .privacyRule, .semanticIndexNotReady, .noEligibleInput,
             .normalSearchUnavailable, nil:
            nil
        }
    }

    private func semanticProviderErrorCode(for providerError: AIFallbackProviderErrorKindSnapshot?) -> String? {
        switch providerError {
        case .providerUnavailable:
            "ProviderUnavailable"
        case .rateLimited:
            "RateLimited"
        case .timeout:
            "Timeout"
        case .callLogUnavailable:
            "CallLogUnavailable"
        case .localModelNotReady, .remoteNotConfigured, .remoteFailed, .internalFailure, nil:
            nil
        }
    }

    private func privacyDecision(for reason: SemanticSearchFallbackReasonSnapshot?) -> AIPrivacyDecisionSnapshot? {
        reason == .privacyRule ? .skipped : nil
    }

    private func privacySkippedReason(for reason: SemanticSearchFallbackReasonSnapshot?)
        -> AIPrivacySkippedReasonSnapshot? {
        reason == .privacyRule ? .privacyRule : nil
    }

    private func semanticCallLogStatus(for reason: SemanticSearchFallbackReasonSnapshot?) -> AICallLogStatusSnapshot? {
        switch reason {
        case .privacyRule:
            .skipped
        case .providerUnavailable, .rateLimited, .timeout, .callLogUnavailable, .aiDisabled, .featureDisabled,
             .semanticIndexNotReady, .noEligibleInput, .normalSearchUnavailable:
            .failed
        case nil:
            nil
        }
    }
}

private extension AICallLogRouteSnapshot {
    init(_ route: SemanticSearchRouteSnapshot) {
        switch route {
        case .local:
            self = .local
        case .remote:
            self = .remote
        }
    }
}
