import Foundation

extension OnboardingModel {
    @MainActor
    func openMainRepositoryRepair(repoPath: String) {
        let routeMapping: CoreErrorMappingSnapshot?
        if case .mainRepoError(let errorRepoPath, let mapping) = route, errorRepoPath == repoPath {
            routeMapping = mapping
        } else { routeMapping = nil }
        let mapping = mainRepoRecoveryErrorMapping ?? routeMapping
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
        case .mainLoading(let state):
            route = .mainLoading(state)
        case .mainRepoError(let mapping):
            routeMainRepositoryError(repoPath: repairRoute.repoPath, mapping: mapping)
        case .settingsRepository:
            route = .settingsRepository
        case .settingsGeneral(let opening, let selectedTab):
            settingsGeneralSelectedTab = selectedTab
            route = .settingsGeneral(opening)
        }
    }

    private func currentDatabaseRepairReturnRoute(repoPath: String) -> DatabaseRepairReturnRoute {
        switch route {
        case .mainRepoError(let errorRepoPath, let mapping) where errorRepoPath == repoPath:
            return .mainRepoError(mapping)
        case .mainLoading(let state) where state.repoPath == repoPath:
            return .mainLoading(state)
        case .settingsRepository:
            return .settingsRepository
        case .settingsGeneral(let opening):
            return .settingsGeneral(opening, selectedTab: settingsGeneralSelectedTab)
        case .validatePath:
            return .validatePath
        default:
            return .mainRepoError(mainRepoRecoveryErrorMapping)
        }
    }
}
