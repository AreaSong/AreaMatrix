@testable import AreaMatrix

struct ExternalSyncRequest: Equatable {
    var kind: MainExternalSyncEventKind
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

actor RecordingExternalChangesSyncer: CoreExternalChangesSyncing {
    private let result: Swift.Result<SyncResultSnapshot, Error>
    private var requestsStorage: [ExternalSyncRequest] = []

    init(result: Swift.Result<SyncResultSnapshot, Error>) {
        self.result = result
    }

    func syncExternalCreated(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) async throws -> SyncResultSnapshot {
        try recordAndResolve(kind: .created, repoPath: repoPath, relativePath: relativePath, fsEventID: fsEventID)
    }

    func syncExternalRenamed(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) async throws -> SyncResultSnapshot {
        try recordAndResolve(kind: .renamed, repoPath: repoPath, relativePath: relativePath, fsEventID: fsEventID)
    }

    func syncExternalRemoved(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) async throws -> SyncResultSnapshot {
        try recordAndResolve(kind: .removed, repoPath: repoPath, relativePath: relativePath, fsEventID: fsEventID)
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        nil
    }

    func setFSEventCursor(repoPath _: String, lastEventID _: Int64) async throws {}

    func recordedRequests() -> [ExternalSyncRequest] {
        requestsStorage
    }

    func recordedCreatedRequests() -> [ExternalSyncRequest] {
        requestsStorage.filter { $0.kind == .created }
    }

    func recordedRenamedRequests() -> [ExternalSyncRequest] {
        requestsStorage.filter { $0.kind == .renamed }
    }

    func recordedRemovedRequests() -> [ExternalSyncRequest] {
        requestsStorage.filter { $0.kind == .removed }
    }

    private func recordAndResolve(
        kind: MainExternalSyncEventKind,
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) throws -> SyncResultSnapshot {
        requestsStorage.append(ExternalSyncRequest(
            kind: kind,
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        return try result.get()
    }
}
