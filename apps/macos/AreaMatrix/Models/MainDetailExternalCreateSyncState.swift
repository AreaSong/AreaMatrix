import Foundation

struct MainExternalCreatedFileEvent: Equatable, Identifiable, Sendable {
    let relativePath: String
    let fsEventID: Int64

    var id: String {
        "\(fsEventID):\(relativePath)"
    }

    init?(relativePath: String, fsEventID: Int64) {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fsEventID > 0,
              !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/"),
              !trimmedPath.hasPrefix("../"),
              !trimmedPath.contains("/../") else { return nil }

        self.relativePath = trimmedPath
        self.fsEventID = fsEventID
    }
}

struct MainExternalCreatedFileSignal: Equatable, Sendable {
    let repoPath: String
    let relativePath: String
    let fsEventID: Int64

    init?(repoPath: String, relativePath: String, fsEventID: Int64) {
        let normalizedRepoPath = Self.normalizedRepoPath(repoPath)
        guard !normalizedRepoPath.isEmpty,
              MainExternalCreatedFileEvent(relativePath: relativePath, fsEventID: fsEventID) != nil else { return nil }

        self.repoPath = normalizedRepoPath
        self.relativePath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.fsEventID = fsEventID
    }

    private static func normalizedRepoPath(_ repoPath: String) -> String {
        let trimmedPath = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmedPath, isDirectory: true).standardizedFileURL.path
    }
}

struct MainPendingExternalCreatedFileEvent: Equatable, Sendable {
    let repoPath: String
    let event: MainExternalCreatedFileEvent

    init?(signal: MainExternalCreatedFileSignal) {
        guard let event = MainExternalCreatedFileEvent(
            relativePath: signal.relativePath,
            fsEventID: signal.fsEventID
        ) else { return nil }

        repoPath = signal.repoPath
        self.event = event
    }
}

enum MainDetailExternalCreateSyncState: Equatable, Sendable {
    case idle
    case syncing(event: MainExternalCreatedFileEvent)
    case synced(event: MainExternalCreatedFileEvent, fileID: Int64?, SyncResultSnapshot)
    case failed(event: MainExternalCreatedFileEvent, CoreErrorMappingSnapshot)

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}
