import Combine
import Foundation

@MainActor
final class SyncConflictCoordinator: ObservableObject {
    @Published var resolutionState = ICloudConflictResolutionState.idle
    @Published var reviewRoutingState = SyncConflictReviewRoutingState()

    let repoPath: String
    let resolver: any ICloudConflictResolving
    let errorMapper: any CoreErrorMapping

    init(repoPath: String, resolver: any ICloudConflictResolving, errorMapper: any CoreErrorMapping) {
        self.repoPath = repoPath
        self.resolver = resolver
        self.errorMapper = errorMapper
    }

    func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }
}
