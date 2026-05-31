import Foundation

enum SemanticIndexBuildState: Equatable {
    case idle
    case building(request: SearchQueryRequestSnapshot)
    case completed(request: SearchQueryRequestSnapshot, report: SemanticIndexBuildReportSnapshot)
    case failed(request: SearchQueryRequestSnapshot, CoreErrorMappingSnapshot)

    var isBuilding: Bool {
        if case .building = self { return true }
        return false
    }
}

enum SemanticPrivacyGateState: Equatable {
    case idle
    case checking(request: SearchQueryRequestSnapshot)
    case allowed(request: SearchQueryRequestSnapshot, report: AiPrivacyEvaluationReport)
    case blocked(request: SearchQueryRequestSnapshot, report: AiPrivacyEvaluationReport)
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

    var report: AiPrivacyEvaluationReport? {
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

extension MainFileListModel {
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
        semanticIndexBuildState = .building(request: request)
        do {
            let report = try await semanticSearching.buildEmbeddingIndex(repoPath: repoPath, request: request)
            semanticIndexBuildState = .completed(request: request, report: report)
        } catch {
            semanticIndexBuildState = .failed(request: request, await mapCoreError(error))
        }
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
        snapshot: AiPrivacyRulesSnapshot
    ) -> AiPrivacyEvaluationRequest {
        AiPrivacyEvaluationRequest(
            feature: .semanticSearch,
            route: semanticPrivacyRouteForCurrentPage(),
            requestedFields: [
                .fileName, .repoRelativePath, .`extension`, .extractedTextExcerpt,
                .aiSummary, .noteSummary, .tagCategoryContext
            ],
            privacyGateEnabled: snapshot.privacyGateEnabled,
            providerScope: snapshot.providerScope,
            rules: snapshot.rules.map(AiPrivacyRuleInput.init(summaryRule:)),
            remoteAllowedFields: snapshot.remoteAllowedFields.map(AiPrivacyFieldRule.init(state:)),
            context: semanticPrivacyContext(for: request)
        )
    }

    private func semanticPrivacyRouteForCurrentPage() -> AiPrivacyEvaluationRoute {
        searchState.page?.semanticPage?.route == .remote ? .remote : .local
    }

    private func semanticPrivacyContext(for request: SearchQueryRequestSnapshot) -> AiPrivacyEvaluationContext {
        AiPrivacyEvaluationContext(
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
}

extension OnboardingModel {
    @MainActor
    func consumePendingExternalCreatedFileSignals() {
        for signal in AreaMatrixExternalCreatedFileRelay.takePendingSignals() {
            handleExternalCreatedFile(signal)
        }
    }

    @MainActor
    func handleExternalCreatedFile(_ signal: MainExternalCreatedFileSignal) {
        guard let pending = MainPendingExternalCreatedFileEvent(signal: signal) else { return }
        guard currentMainRepositoryPath == pending.repoPath else { return }

        pendingExternalCreatedFileEvent = pending
        toastMessage = nil
    }

    @MainActor
    func externalCreatedEvent(for opening: RepositoryOpeningResult) -> MainExternalCreatedFileEvent? {
        guard pendingExternalCreatedFileEvent?.repoPath == normalizedMainRepositoryPath(opening.config.repoPath) else {
            return nil
        }
        return pendingExternalCreatedFileEvent?.event
    }

    @MainActor
    func finishExternalCreatedFileEvent(_ event: MainExternalCreatedFileEvent) {
        guard pendingExternalCreatedFileEvent?.event == event else { return }
        pendingExternalCreatedFileEvent = nil
    }

    private var currentMainRepositoryPath: String? {
        switch route {
        case let .mainEmpty(opening), let .mainList(opening), let .settingsGeneral(opening):
            normalizedMainRepositoryPath(opening.config.repoPath)
        case let .importProgress(state):
            normalizedMainRepositoryPath(state.sourceOpening.config.repoPath)
        case let .importResult(state):
            normalizedMainRepositoryPath(state.sourceOpening.config.repoPath)
        default:
            nil
        }
    }

    private func normalizedMainRepositoryPath(_ repoPath: String) -> String {
        URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
    }
}
