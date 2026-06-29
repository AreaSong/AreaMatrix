import Foundation

extension OnboardingModel {
    @MainActor
    func showGeneralSettings(opening: RepositoryOpeningResult, selectedTab: String? = "general") {
        settingsGeneralSelectedTab = selectedTab
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
