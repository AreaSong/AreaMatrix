import Foundation

enum SemanticIndexBuildControlState: Equatable {
    case idle
    case cancelConfirm(request: SearchQueryRequestSnapshot)
    case canceling(request: SearchQueryRequestSnapshot)
    case canceled(request: SearchQueryRequestSnapshot)
    case pauseFailed(request: SearchQueryRequestSnapshot, CoreErrorMappingSnapshot)
    case cancelFailed(request: SearchQueryRequestSnapshot, CoreErrorMappingSnapshot)

    var isCanceling: Bool {
        if case .canceling = self { return true }
        return false
    }

    var cancelFailure: CoreErrorMappingSnapshot? {
        if case let .cancelFailed(_, error) = self { return error }
        return nil
    }

    func isCurrent(for request: SearchQueryRequestSnapshot?) -> Bool {
        guard let request else { return self == .idle }
        return self.request == request
    }

    private var request: SearchQueryRequestSnapshot? {
        switch self {
        case .idle:
            nil
        case let .cancelConfirm(request), let .canceling(request), let .canceled(request),
             let .pauseFailed(request, _), let .cancelFailed(request, _):
            request
        }
    }
}

extension MainFileListModel {
    func pauseSemanticIndexBuildForCurrentSearch() async {
        guard let request = searchState.request, request.mode == .semantic else { return }
        guard semanticIndexBuildState.isBuilding else { return }
        semanticIndexControlState = .pauseFailed(
            request: request,
            SemanticIndexBuildControlError.pauseUnsupported
        )
    }

    func resumeSemanticIndexBuildForCurrentSearch() async {
        guard let request = searchState.request, request.mode == .semantic else { return }
        await buildSemanticIndexForCurrentSearch()
    }

    func requestCancelSemanticIndexBuildForCurrentSearch() {
        guard let request = searchState.request, request.mode == .semantic else { return }
        semanticIndexControlState = .cancelConfirm(request: request)
    }

    func keepBuildingSemanticIndexForCurrentSearch() {
        guard case .cancelConfirm = semanticIndexControlState else { return }
        semanticIndexControlState = .idle
    }

    func cancelSemanticIndexBuildForCurrentSearch() async {
        guard let request = searchState.request, request.mode == .semantic else { return }
        semanticIndexControlState = .canceling(request: request)
        guard semanticIndexBuildState.isBuilding else {
            semanticIndexControlState = .cancelFailed(
                request: request,
                SemanticIndexBuildControlError.noActiveBuild
            )
            return
        }
        cancelActiveSemanticIndexBuild()
        semanticIndexBuildGeneration += 1
        if let page = searchState.page, let semanticPage = page.semanticPage {
            let canceledPage = semanticPage.settingIndexStatus(.canceled)
            applySemanticPage(canceledPage, to: page, request: request)
        }
        semanticIndexBuildState = .canceled(request: request)
        semanticIndexControlState = .canceled(request: request)
    }

    func retryFailedSemanticIndexItemsForCurrentSearch() async {
        guard let request = searchState.request, request.mode == .semantic else { return }
        await buildSemanticIndexForCurrentSearch()
    }

    func clearSemanticIndexControlState() {
        semanticIndexControlState = .idle
    }
}

private extension SemanticSearchResultPageSnapshot {
    func settingIndexStatus(_ status: SemanticIndexStatusSnapshot) -> SemanticSearchResultPageSnapshot {
        var copy = self
        copy.indexStatus = status
        copy.fallbackReason = status == .canceled ? .semanticIndexNotReady : fallbackReason
        copy.fallbackMessage = status == .canceled ? "Semantic index build canceled." : fallbackMessage
        return copy
    }
}

private enum SemanticIndexBuildControlError {
    static let pauseUnsupported = CoreErrorMappingSnapshot(
        kind: .config,
        userMessage: "Pause index build requires a Core pause API that is not available in C3-08.",
        severity: .high,
        suggestedAction: "Use Cancel index build to stop the active build, or retry after Core exposes pause support.",
        recoverability: .userActionRequired,
        rawContext: "S3-08 pause index build missing Core API"
    )

    static let noActiveBuild = CoreErrorMappingSnapshot(
        kind: .validation,
        userMessage: "No active semantic index build is available to cancel.",
        severity: .medium,
        suggestedAction: "Start a semantic index build before canceling.",
        recoverability: .refreshRequired,
        rawContext: "S3-08 cancel index build without active task"
    )
}
