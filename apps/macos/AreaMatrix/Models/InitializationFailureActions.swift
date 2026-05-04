import Foundation

enum InitializationDiagnosticsState: Equatable, Sendable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

extension OnboardingModel {
    @MainActor
    func routeInitializationFailure(_ error: Error, repoPath: String) async {
        let retryDraft: RepositoryInitializationDraft?
        if case .initializing(let draft) = route {
            retryDraft = draft
        } else {
            retryDraft = nil
        }

        guard let coreError = error as? CoreError else {
            route = .initializationFailed(repoPath, nil, retryDraft)
            return
        }

        let mapping = await errorMapper.mapCoreError(coreError)
        route = .initializationFailed(repoPath, mapping, retryDraft)
    }

    @MainActor
    func retryFailedInitialization() async {
        guard case .initializationFailed(_, _, let retryDraft?) = route else {
            return
        }

        route = .confirmRepositoryInitialization(retryDraft)
        switch retryDraft.mode {
        case .createEmpty:
            await createEmptyRepositoryFromConfirmInit()
        case .adoptExisting:
            await adoptExistingRepositoryFromConfirmInit()
        }
    }

    @MainActor
    func requestInitializationDiagnosticsPrivacyConfirmation() {
        guard case .initializationFailed = route else { return }
        initializationDiagnostics = .confirmingPrivacy
    }

    @MainActor
    func cancelInitializationDiagnosticsPrivacyConfirmation() {
        guard case .confirmingPrivacy = initializationDiagnostics else { return }
        initializationDiagnostics = .idle
    }

    @MainActor
    func collectInitializationDiagnostics() async {
        guard case .initializationFailed(let repoPath, _, _) = route else { return }

        initializationDiagnostics = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            guard case .initializationFailed(let currentRepoPath, _, _) = route,
                  currentRepoPath == repoPath else { return }
            initializationDiagnostics = .collected(snapshot)
        } catch {
            guard case .initializationFailed(let currentRepoPath, _, _) = route,
                  currentRepoPath == repoPath else { return }
            initializationDiagnostics = .failed(await diagnosticsFailureMapping(for: error))
        }
    }

    private func diagnosticsFailureMapping(for error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}
