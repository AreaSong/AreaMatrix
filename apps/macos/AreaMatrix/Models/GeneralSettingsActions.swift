import Foundation

extension OnboardingModel {
    @MainActor
    func showGeneralSettings(opening: RepositoryOpeningResult) {
        route = .settingsGeneral(opening)
        toastMessage = nil
    }

    @MainActor
    func closeGeneralSettings(opening: RepositoryOpeningResult) {
        route = Self.mainRoute(for: opening)
    }

    @MainActor
    func refreshAfterGeneralSettings(opening: RepositoryOpeningResult) async {
        do {
            let refreshed = try await emptyRepositoryOpener.openConfiguredRepository(repoPath: opening.config.repoPath)
            finishSuccessfulRepositoryOpen(refreshed)
        } catch {
            await routeMainOpeningFailure(error, repoPath: opening.config.repoPath)
        }
    }
}
