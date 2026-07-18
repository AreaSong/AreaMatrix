import Foundation

enum ICloudConflictListPlatformServices {
    static var repositoryFinderOpener: any RepositoryFinderOpening {
        AppPlatformServices.finderOpener
    }

    static var fileRevealer: any RepositoryFileRevealing {
        AppPlatformServices.fileRevealer
    }
}

enum MainExternalSyncEventKind: String, Equatable, Hashable {
    case created
    case renamed
    case removed
    case modified

    var displayName: String {
        switch self {
        case .created:
            "created"
        case .renamed:
            "renamed"
        case .removed:
            "removed"
        case .modified:
            "modified"
        }
    }
}

struct MainExternalCreatedFileEvent: Equatable, Hashable, Identifiable {
    let kind: MainExternalSyncEventKind
    let relativePath: String
    let fsEventID: Int64
    let cursorWatermark: Int64

    var id: String {
        "\(kind.rawValue):\(fsEventID):\(cursorWatermark):\(relativePath)"
    }

    init?(
        kind: MainExternalSyncEventKind = .created,
        relativePath: String,
        fsEventID: Int64,
        cursorWatermark: Int64? = nil
    ) {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedWatermark = cursorWatermark ?? fsEventID
        guard fsEventID > 0,
              resolvedWatermark >= fsEventID,
              !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/"),
              !trimmedPath.hasPrefix("../"),
              !trimmedPath.contains("/../") else { return nil }

        self.kind = kind
        self.relativePath = trimmedPath
        self.fsEventID = fsEventID
        self.cursorWatermark = resolvedWatermark
    }
}

struct MainExternalCreatedFileSignal: Equatable, Hashable {
    let kind: MainExternalSyncEventKind
    let repoPath: String
    let relativePath: String
    let fsEventID: Int64
    let cursorWatermark: Int64

    init?(
        kind: MainExternalSyncEventKind = .created,
        repoPath: String,
        relativePath: String,
        fsEventID: Int64,
        cursorWatermark: Int64? = nil
    ) {
        let normalizedRepoPath = Self.normalizedRepoPath(repoPath)
        guard let event = MainExternalCreatedFileEvent(
            kind: kind,
            relativePath: relativePath,
            fsEventID: fsEventID,
            cursorWatermark: cursorWatermark
        ), !normalizedRepoPath.isEmpty else { return nil }

        self.kind = event.kind
        self.repoPath = normalizedRepoPath
        self.relativePath = event.relativePath
        self.fsEventID = fsEventID
        self.cursorWatermark = event.cursorWatermark
    }

    func withCursorWatermark(_ cursorWatermark: Int64) -> MainExternalCreatedFileSignal? {
        MainExternalCreatedFileSignal(
            kind: kind,
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID,
            cursorWatermark: cursorWatermark
        )
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
            fsEventID: signal.fsEventID,
            cursorWatermark: signal.cursorWatermark
        ) else { return nil }

        repoPath = signal.repoPath
        self.event = event
    }
}

enum MainExternalWatcherRecoveryKind: Equatable {
    case rescanRequired
    case rootChanged
    case startupFailed
}

struct MainExternalWatcherRecoveryRequest: Equatable {
    let kind: MainExternalWatcherRecoveryKind
    let repoPath: String
    let resumeEventID: Int64?
    let reason: String
}
