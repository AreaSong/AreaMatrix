import Foundation

extension OnboardingModel {
    @MainActor
    func handleSettingsMenuCommand() {
        switch route {
        case let .mainEmpty(opening), let .mainList(opening):
            showGeneralSettings(opening: opening)
        case .settingsGeneral:
            break
        default:
            toastMessage = "Open a repository before changing repository settings."
        }
    }

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
