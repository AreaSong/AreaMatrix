import AreaMatrixCoreSDK

struct SyncConflictResolveCoreFFIClient {
    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategy
    ) throws -> SyncConflictResolutionPreviewReport {
        do {
            let value = try AreaMatrixCoreSDK.previewSyncConflictResolution(
                repoPath: repoPath,
                conflictId: conflictID,
                resolution: SyncConflictCoreSDKMapping.sdkResolution(resolution)
            )
            return SyncConflictCoreSDKMapping.preview(value)
        } catch {
            throw SyncConflictCoreSDKMapping.error(error)
        }
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequest
    ) throws -> SyncConflictResolveReport {
        do {
            let value = try AreaMatrixCoreSDK.resolveSyncConflict(
                repoPath: repoPath,
                conflictId: conflictID,
                resolution: SyncConflictCoreSDKMapping.sdkRequest(request)
            )
            return SyncConflictCoreSDKMapping.resolve(value)
        } catch {
            throw SyncConflictCoreSDKMapping.error(error)
        }
    }
}
