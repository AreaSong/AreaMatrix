import Foundation

protocol CoreExternalChangesSyncing: Sendable {
    func syncExternalCreated(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot
    func syncExternalRenamed(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot
    func syncExternalRemoved(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot
    func getFSEventCursor(repoPath: String) async throws -> Int64?
    func setFSEventCursor(repoPath: String, lastEventID: Int64) async throws
}

struct SyncResultSnapshot: Equatable, Sendable {
    var detectedCreates: Int64
    var detectedRenames: Int64
    var detectedDeletes: Int64
    var detectedModifies: Int64
    var errors: [String]
}

extension CoreBridge: CoreExternalChangesSyncing {
    func syncExternalCreated(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        try await syncExternalChange(repoPath: repoPath, relativePath: relativePath, kind: .created, fsEventID: fsEventID)
    }

    func syncExternalRenamed(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        try await syncExternalChange(repoPath: repoPath, relativePath: relativePath, kind: .renamed, fsEventID: fsEventID)
    }

    func syncExternalRemoved(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        try await syncExternalChange(repoPath: repoPath, relativePath: relativePath, kind: .removed, fsEventID: fsEventID)
    }

    func getFSEventCursor(repoPath: String) async throws -> Int64? {
        try await Task.detached(priority: .userInitiated) {
            try getCoreFSEventCursor(repoPath: repoPath)
        }.value
    }

    func setFSEventCursor(repoPath: String, lastEventID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try setCoreFSEventCursor(repoPath: repoPath, lastEventID: lastEventID)
        }.value
    }

    private func syncExternalChange(
        repoPath: String,
        relativePath: String,
        kind: ExternalEventKind,
        fsEventID: Int64
    ) async throws -> SyncResultSnapshot {
        let event = ExternalEvent(path: relativePath, kind: kind, fsEventId: fsEventID)
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

private func getCoreFSEventCursor(repoPath: String) throws -> Int64? {
    try getFsEventCursor(repoPath: repoPath)
}

private func setCoreFSEventCursor(repoPath: String, lastEventID: Int64) throws {
    try setFsEventCursor(repoPath: repoPath, lastEventId: lastEventID)
}
