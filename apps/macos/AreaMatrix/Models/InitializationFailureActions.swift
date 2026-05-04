import Foundation

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
}
