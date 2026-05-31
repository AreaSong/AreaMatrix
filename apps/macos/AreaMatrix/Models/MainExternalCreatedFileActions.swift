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
        semanticIndexBuildState = .building(request: request)
        do {
            let report = try await semanticSearching.buildEmbeddingIndex(repoPath: repoPath, request: request)
            semanticIndexBuildState = .completed(request: request, report: report)
        } catch {
            semanticIndexBuildState = .failed(request: request, await mapCoreError(error))
        }
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
