import Foundation

enum MainDetailExternalCreateSyncState: Equatable {
    case idle
    case syncing(event: MainExternalCreatedFileEvent)
    case synced(event: MainExternalCreatedFileEvent, fileID: Int64?, SyncResultSnapshot)
    case failed(event: MainExternalCreatedFileEvent, CoreErrorMappingSnapshot)

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}
