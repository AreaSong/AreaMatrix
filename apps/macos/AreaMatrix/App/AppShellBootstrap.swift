import Foundation

extension OnboardingModel {
    @MainActor func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await loadConfiguredRepository()
    }

    @MainActor func retryConfigurationLoad() async {
        await loadConfiguredRepository()
    }

    @MainActor
    func loadConfiguredRepository() async {
        guard let repoPath = settingsReader.configuredRepoPath() else { route = .welcome; return }
        let cancellationToken = beginMainOpening(repoPath: repoPath)
        var loadingRefreshTask: Task<Void, Never>?

        do {
            try await recoverMainOpeningResidue(repoPath: repoPath, cancellationToken: cancellationToken)
            guard openingCancellationToken == cancellationToken else { return }
            loadingRefreshTask = makeMainLoadingRefreshTask(
                repoPath: repoPath,
                cancellationToken: cancellationToken,
                shouldLoadAdoptSession: true,
                shouldLoadTree: true
            )
            let opening = try await emptyRepositoryOpener.openConfiguredRepository(repoPath: repoPath)
            guard openingCancellationToken == cancellationToken else { return }
            loadingRefreshTask?.cancel()
            finishSuccessfulRepositoryOpen(opening)
        } catch {
            guard openingCancellationToken == cancellationToken else { return }
            await loadingRefreshTask?.value
            await updateMainRepoExternalRemoval(from: error, repoPath: repoPath)
            await routeMainOpeningFailure(error, repoPath: repoPath, cancellationToken: cancellationToken)
        }
    }
}
