import Foundation

protocol CoreExternalChangesSyncing: Sendable {
    func syncExternalChanges(repoPath: String, events: [MainExternalCreatedFileEvent]) async throws
        -> SyncResultSnapshot
    func getFSEventCursor(repoPath: String) async throws -> Int64?
    func setFSEventCursor(repoPath: String, lastEventID: Int64) async throws
}

struct SyncResultSnapshot: Equatable {
    var detectedCreates: Int64
    var detectedRenames: Int64
    var detectedDeletes: Int64
    var detectedModifies: Int64
    var errors: [String]
}

extension CoreExternalChangesSyncing {
    func syncExternalCreated(repoPath: String, relativePath: String,
                             fsEventID: Int64) async throws -> SyncResultSnapshot {
        try await syncSingleExternalChange(
            repoPath: repoPath, relativePath: relativePath, kind: .created, fsEventID: fsEventID
        )
    }

    func syncExternalRenamed(repoPath: String, relativePath: String,
                             fsEventID: Int64) async throws -> SyncResultSnapshot {
        try await syncSingleExternalChange(
            repoPath: repoPath, relativePath: relativePath, kind: .renamed, fsEventID: fsEventID
        )
    }

    func syncExternalRemoved(repoPath: String, relativePath: String,
                             fsEventID: Int64) async throws -> SyncResultSnapshot {
        try await syncSingleExternalChange(
            repoPath: repoPath, relativePath: relativePath, kind: .removed, fsEventID: fsEventID
        )
    }

    func syncExternalModified(repoPath: String, relativePath: String,
                              fsEventID: Int64) async throws -> SyncResultSnapshot {
        try await syncSingleExternalChange(
            repoPath: repoPath, relativePath: relativePath, kind: .modified, fsEventID: fsEventID
        )
    }

    private func syncSingleExternalChange(
        repoPath: String,
        relativePath: String,
        kind: MainExternalSyncEventKind,
        fsEventID: Int64
    ) async throws -> SyncResultSnapshot {
        guard let event = MainExternalCreatedFileEvent(
            kind: kind,
            relativePath: relativePath,
            fsEventID: fsEventID
        ) else {
            throw AppSemanticError.invalidPath(rawContext: relativePath)
        }
        return try await syncExternalChanges(repoPath: repoPath, events: [event])
    }
}

extension CoreBridge: CoreExternalChangesSyncing {
    func syncExternalChanges(
        repoPath: String,
        events: [MainExternalCreatedFileEvent]
    ) async throws -> SyncResultSnapshot {
        let coreEvents = events.map(ExternalEvent.init(mainEvent:))
        let result = try await Task.detached(priority: .userInitiated) {
            try syncCoreExternalChanges(repoPath: repoPath, events: coreEvents)
        }.value
        return SyncResultSnapshot(coreResult: result)
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

}

private extension ExternalEvent {
    init(mainEvent: MainExternalCreatedFileEvent) {
        let kind: ExternalEventKind = switch mainEvent.kind {
        case .created: .created
        case .renamed: .renamed
        case .removed: .removed
        case .modified: .modified
        }
        self.init(path: mainEvent.relativePath, kind: kind, fsEventId: mainEvent.fsEventID)
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
