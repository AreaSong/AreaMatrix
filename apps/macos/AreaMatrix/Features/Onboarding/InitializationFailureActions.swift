import Foundation

enum InitializationDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

extension OnboardingModel {
    @MainActor
    func routeInitializationFailure(_ error: Error, repoPath: String) async {
        let retryDraft: RepositoryInitializationDraft? = if case let .initializing(draft) = route {
            draft
        } else {
            nil
        }

        let mapping = await errorMapper.mapCoreErrorIfPresent(error)
        route = .initializationFailed(repoPath, mapping, retryDraft)
    }

    @MainActor
    func retryFailedInitialization() async {
        guard case let .initializationFailed(_, _, retryDraft?) = route else {
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
        guard case .confirmingPrivacy = initializationDiagnostics else {
            guard case .collecting = initializationDiagnostics else { return }
            initializationDiagnosticsGeneration += 1
            initializationDiagnostics = .idle
            return
        }
        initializationDiagnosticsGeneration += 1
        initializationDiagnostics = .idle
    }

    @MainActor
    func collectInitializationDiagnostics() async {
        guard case let .initializationFailed(repoPath, _, _) = route else { return }

        initializationDiagnosticsGeneration += 1
        let generation = initializationDiagnosticsGeneration
        initializationDiagnostics = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            guard initializationDiagnosticsGeneration == generation else { return }
            guard case let .initializationFailed(currentRepoPath, _, _) = route,
                  currentRepoPath == repoPath else { return }
            initializationDiagnostics = .collected(snapshot)
        } catch {
            guard initializationDiagnosticsGeneration == generation else { return }
            guard case let .initializationFailed(currentRepoPath, _, _) = route,
                  currentRepoPath == repoPath else { return }
            initializationDiagnostics = await .failed(errorMapper.mapError(error))
        }
    }
}
