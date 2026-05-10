import Foundation

enum MainExternalSyncEventKind: String, Equatable {
    case created
    case renamed
    case removed

    var displayName: String {
        switch self {
        case .created:
            "created"
        case .renamed:
            "renamed"
        case .removed:
            "removed"
        }
    }
}

struct MainExternalCreatedFileEvent: Equatable, Identifiable {
    let kind: MainExternalSyncEventKind
    let relativePath: String
    let fsEventID: Int64

    var id: String {
        "\(kind.rawValue):\(fsEventID):\(relativePath)"
    }

    init?(kind: MainExternalSyncEventKind = .created, relativePath: String, fsEventID: Int64) {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fsEventID > 0,
              !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/"),
              !trimmedPath.hasPrefix("../"),
              !trimmedPath.contains("/../") else { return nil }

        self.kind = kind
        self.relativePath = trimmedPath
        self.fsEventID = fsEventID
    }
}

struct MainExternalCreatedFileSignal: Equatable {
    let kind: MainExternalSyncEventKind
    let repoPath: String
    let relativePath: String
    let fsEventID: Int64

    init?(
        kind: MainExternalSyncEventKind = .created,
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) {
        let normalizedRepoPath = Self.normalizedRepoPath(repoPath)
        guard let event = MainExternalCreatedFileEvent(
            kind: kind,
            relativePath: relativePath,
            fsEventID: fsEventID
        ), !normalizedRepoPath.isEmpty else { return nil }

        self.kind = event.kind
        self.repoPath = normalizedRepoPath
        self.relativePath = event.relativePath
        self.fsEventID = fsEventID
    }

    private static func normalizedRepoPath(_ repoPath: String) -> String {
        let trimmedPath = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmedPath, isDirectory: true).standardizedFileURL.path
    }
}

struct MainPendingExternalCreatedFileEvent: Equatable {
    let repoPath: String
    let event: MainExternalCreatedFileEvent

    init?(signal: MainExternalCreatedFileSignal) {
        guard let event = MainExternalCreatedFileEvent(
            kind: signal.kind,
            relativePath: signal.relativePath,
            fsEventID: signal.fsEventID
        ) else { return nil }

        repoPath = signal.repoPath
        self.event = event
    }
}

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
