import CoreServices
import Foundation

enum MainExternalSyncEventKind: String, Equatable, Hashable {
    case created
    case renamed
    case removed
    case modified

    var displayName: String {
        switch self {
        case .created:
            L10n.string("external-sync.event.created")
        case .renamed:
            L10n.string("external-sync.event.renamed")
        case .removed:
            L10n.string("external-sync.event.removed")
        case .modified:
            L10n.string("external-sync.event.modified")
        }
    }
}

struct MainExternalCreatedFileWatcherEvent {
    let path: String
    let flags: FSEventStreamEventFlags
    let eventID: FSEventStreamEventId

    func hasFlag(_ flag: FSEventStreamEventFlags) -> Bool {
        flags & flag != 0
    }

    func merging(_ other: MainExternalCreatedFileWatcherEvent) -> MainExternalCreatedFileWatcherEvent {
        MainExternalCreatedFileWatcherEvent(
            path: path,
            flags: flags | other.flags,
            eventID: max(eventID, other.eventID)
        )
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

struct MainExternalSyncWindow: Equatable, Identifiable {
    let repoPath: String
    let events: [MainExternalCreatedFileEvent]
    let cursorWatermark: Int64

    var id: String {
        let eventIDs = events.map(\.id).joined(separator: "|")
        return "\(repoPath):\(cursorWatermark):\(eventIDs)"
    }

    init?(repoPath: String, events: [MainExternalCreatedFileEvent], cursorWatermark: Int64) {
        let normalizedRepoPath = URL(
            fileURLWithPath: repoPath,
            isDirectory: true
        ).standardizedFileURL.path
        guard !normalizedRepoPath.isEmpty,
              cursorWatermark > 0,
              events.allSatisfy({ $0.fsEventID <= cursorWatermark }) else { return nil }

        self.repoPath = normalizedRepoPath
        var latestByPath: [String: MainExternalCreatedFileEvent] = [:]
        let orderedEvents = events.enumerated().sorted { lhs, rhs in
            if lhs.element.fsEventID == rhs.element.fsEventID { return lhs.offset < rhs.offset }
            return lhs.element.fsEventID < rhs.element.fsEventID
        }.map(\.element)
        for event in orderedEvents {
            if let existing = latestByPath[event.relativePath],
               event.kind == .modified,
               existing.kind != .modified {
                latestByPath[event.relativePath] = event.withKind(existing.kind)
            } else {
                latestByPath[event.relativePath] = event
            }
        }
        self.events = latestByPath.values.sorted { lhs, rhs in
            if lhs.fsEventID == rhs.fsEventID { return lhs.relativePath < rhs.relativePath }
            return lhs.fsEventID < rhs.fsEventID
        }
        self.cursorWatermark = cursorWatermark
    }

    init?(signals: [MainExternalCreatedFileSignal]) {
        guard let first = signals.first,
              signals.allSatisfy({
                  $0.repoPath == first.repoPath && $0.cursorWatermark == first.cursorWatermark
              }) else { return nil }
        let events = signals.compactMap { signal in
            MainExternalCreatedFileEvent(
                kind: signal.kind,
                relativePath: signal.relativePath,
                fsEventID: signal.fsEventID,
                cursorWatermark: signal.cursorWatermark
            )
        }
        guard events.count == signals.count else { return nil }
        self.init(repoPath: first.repoPath, events: events, cursorWatermark: first.cursorWatermark)
    }

    func merging(_ other: MainExternalSyncWindow) -> MainExternalSyncWindow? {
        guard repoPath == other.repoPath, cursorWatermark == other.cursorWatermark else { return nil }
        return MainExternalSyncWindow(
            repoPath: repoPath,
            events: events + other.events,
            cursorWatermark: cursorWatermark
        )
    }
}

private extension MainExternalCreatedFileEvent {
    func withKind(_ retainedKind: MainExternalSyncEventKind) -> Self {
        MainExternalCreatedFileEvent(
            kind: retainedKind,
            relativePath: relativePath,
            fsEventID: fsEventID,
            cursorWatermark: cursorWatermark
        ) ?? self
    }
}

extension SyncResultSnapshot {
    var hasNoDetectedChanges: Bool {
        detectedCreates + detectedRenames + detectedDeletes + detectedModifies == 0
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
