import Foundation

protocol CoreExternalChangesSyncing: Sendable {
    func syncExternalRemoved(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot
}

struct SyncResultSnapshot: Equatable, Sendable {
    var detectedCreates: Int64
    var detectedRenames: Int64
    var detectedDeletes: Int64
    var detectedModifies: Int64
    var errors: [String]
}

extension CoreBridge: CoreExternalChangesSyncing {
    func syncExternalRemoved(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        let event = ExternalEvent(path: relativePath, kind: .removed, fsEventId: fsEventID)
        let result = try await Task.detached(priority: .userInitiated) {
            try syncCoreExternalChanges(repoPath: repoPath, events: [event])
        }.value
        return SyncResultSnapshot(coreResult: result)
    }
}

extension SyncResultSnapshot {
    init(coreResult: SyncResult) {
        detectedCreates = coreResult.detectedCreates
        detectedRenames = coreResult.detectedRenames
        detectedDeletes = coreResult.detectedDeletes
        detectedModifies = coreResult.detectedModifies
        errors = coreResult.errors
    }
}

private func syncCoreExternalChanges(repoPath: String, events: [ExternalEvent]) throws -> SyncResult {
    try syncExternalChanges(repoPath: repoPath, events: events)
}
