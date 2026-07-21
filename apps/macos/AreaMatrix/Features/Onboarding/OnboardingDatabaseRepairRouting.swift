import Foundation

extension OnboardingModel {
    @MainActor
    func openMainRepositoryRepair(repoPath: String, mapping currentMapping: CoreErrorMappingSnapshot? = nil) {
        let routeMapping: CoreErrorMappingSnapshot? = if case let .mainRepoError(errorRepoPath, mapping) = route,
                                                         errorRepoPath == repoPath {
            mapping
        } else { nil }
        let mapping = currentMapping ?? mainRepoRecoveryErrorMapping ?? routeMapping
        mainRepoRecoveryErrorMapping = nil
        route = .dbRepairConfirm(DatabaseRepairRouteState(
            repoPath: repoPath,
            scanSession: nil,
            mapping: mapping,
            returnRoute: currentDatabaseRepairReturnRoute(repoPath: repoPath)
        ))
    }

    @MainActor
    func returnFromDatabaseRepair(_ repairRoute: DatabaseRepairRouteState) {
        switch repairRoute.returnRoute {
        case .validatePath:
            route = .validatePath
        case let .mainLoading(state):
            route = .mainLoading(state)
        case let .mainRepoError(mapping):
            routeMainRepositoryError(repoPath: repairRoute.repoPath, mapping: mapping)
        case let .mainList(opening):
            route = .mainList(opening)
        case let .mainEmpty(opening):
            route = .mainEmpty(opening)
        case .settingsRepository:
            route = .settingsRepository
        case let .settingsGeneral(opening, selectedTab):
            settingsGeneralSelectedTab = selectedTab
            route = .settingsGeneral(opening)
        }
    }

    private func currentDatabaseRepairReturnRoute(repoPath: String) -> DatabaseRepairReturnRoute {
        switch route {
        case let .mainRepoError(errorRepoPath, mapping) where errorRepoPath == repoPath:
            .mainRepoError(mapping)
        case let .mainLoading(state) where state.repoPath == repoPath:
            .mainLoading(state)
        case let .mainList(opening) where opening.config.repoPath == repoPath:
            .mainList(opening)
        case let .mainEmpty(opening) where opening.config.repoPath == repoPath:
            .mainEmpty(opening)
        case .settingsRepository:
            .settingsRepository
        case let .settingsGeneral(opening):
            .settingsGeneral(opening, selectedTab: settingsGeneralSelectedTab)
        case .validatePath:
            .validatePath
        default:
            .mainRepoError(mainRepoRecoveryErrorMapping)
        }
    }
}
