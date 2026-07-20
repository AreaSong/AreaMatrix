import Foundation

enum MainDetailExternalCreateSyncState: Equatable {
    case idle
    case syncing(fileID: Int64, event: MainExternalCreatedFileEvent)
    case synced(fileID: Int64, event: MainExternalCreatedFileEvent, SyncResultSnapshot)
    case failed(fileID: Int64, event: MainExternalCreatedFileEvent, CoreErrorMappingSnapshot)

    var fileID: Int64? {
        switch self {
        case .idle:
            nil
        case let .syncing(fileID, _), let .synced(fileID, _, _), let .failed(fileID, _, _):
            fileID
        }
    }

    func isolated(to selectedFileID: Int64?) -> Self {
        fileID == selectedFileID ? self : .idle
    }

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}
