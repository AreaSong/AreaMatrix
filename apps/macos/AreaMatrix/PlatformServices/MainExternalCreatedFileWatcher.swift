import Combine
import CoreServices
import Foundation

@MainActor
final class MainExternalCreatedFileWatcher: ObservableObject {
    @Published private(set) var recoveryRequest: MainExternalWatcherRecoveryRequest?
    private(set) var streamStartEventID: Int64?

    private var stream: FSEventStreamRef?
    private var watchedRepoPath: String?
    private var pendingEvents: [String: MainExternalCreatedFileWatcherEvent] = [:]
    private var flushTask: Task<Void, Never>?
    private let cursorStore: any CoreExternalChangesSyncing
    private let inFlightTracker: any InFlightFileChangeTracking
    private let flushDelay: Duration

    init(
        cursorStore: any CoreExternalChangesSyncing = AppCoreServices.externalChangesSyncer,
        inFlightTracker: any InFlightFileChangeTracking = InFlightFileChangeTracker.shared,
        flushDelay: Duration = .milliseconds(200)
    ) {
        self.cursorStore = cursorStore
        self.inFlightTracker = inFlightTracker
        self.flushDelay = flushDelay
    }

    func start(repoPath: String) async {
        let normalizedPath = Self.normalizedRepoPath(repoPath)
        guard !normalizedPath.isEmpty else {
            stop()
            return
        }
        guard watchedRepoPath != normalizedPath || stream == nil else { return }

        stop()
        watchedRepoPath = normalizedPath
        do {
            guard let cursor = try await cursorStore.getFSEventCursor(repoPath: normalizedPath) else {
                requestRescan(repoPath: normalizedPath, reason: "No filesystem event cursor is available.")
                return
            }
            try startStream(repoPath: normalizedPath, sinceWhen: Self.streamEventID(cursor))
            recoveryRequest = nil
        } catch {
            stopStream(clearRepoPath: false)
            recoveryRequest = MainExternalWatcherRecoveryRequest(
                kind: .startupFailed,
                repoPath: normalizedPath,
                resumeEventID: nil,
                reason: "Filesystem watcher could not start: \(error.localizedDescription)"
            )
        }
    }

    func stop() {
        stopStream(clearRepoPath: true)
        pendingEvents.removeAll()
        flushTask?.cancel()
        flushTask = nil
    }

    func handle(events: [MainExternalCreatedFileWatcherEvent]) {
        guard let repoPath = watchedRepoPath else { return }
        if events.contains(where: {
            $0.hasFlag(FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged))
        }) {
            stopStream(clearRepoPath: false)
            pendingEvents.removeAll()
            recoveryRequest = MainExternalWatcherRecoveryRequest(
                kind: .rootChanged,
                repoPath: repoPath,
                resumeEventID: nil,
                reason: "The repository root moved, was renamed, or became unavailable."
            )
            return
        }
        let replayInvalidatingFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
        if events.contains(where: { $0.flags & replayInvalidatingFlags != 0 }) {
            requestRescan(repoPath: repoPath, reason: "macOS can no longer replay the complete event history.")
            return
        }

        for event in events where !event.hasFlag(FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)) {
            guard event.eventID > 0, event.eventID <= FSEventStreamEventId(Int64.max) else { continue }
            if let existing = pendingEvents[event.path] {
                pendingEvents[event.path] = existing.merging(event)
            } else {
                pendingEvents[event.path] = event
            }
        }
        scheduleFlush(repoPath: repoPath)
    }

    nonisolated static func signal(
        repoPath: String,
        absolutePath: String,
        flags: FSEventStreamEventFlags,
        eventID: FSEventStreamEventId,
        pathExists: Bool? = nil
    ) -> MainExternalCreatedFileSignal? {
        let specialFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
        guard flags & specialFlags == 0 else { return nil }
        guard flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) == 0 else { return nil }
        guard eventID > 0, eventID <= FSEventStreamEventId(Int64.max) else { return nil }

        let normalizedRepoPath = normalizedRepoPath(repoPath)
        guard let relativePath = relativePath(repoPath: normalizedRepoPath, absolutePath: absolutePath) else {
            return nil
        }
        guard relativePath != ".areamatrix", !relativePath.hasPrefix(".areamatrix/") else { return nil }

        let syncKind: MainExternalSyncEventKind
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            syncKind = pathExists == false ? .removed : .renamed
        } else if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0,
                  pathExists != true {
            syncKind = .removed
        } else if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
            syncKind = .created
        } else if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 {
            syncKind = .modified
        } else {
            return nil
        }

        return MainExternalCreatedFileSignal(
            kind: syncKind,
            repoPath: normalizedRepoPath,
            relativePath: relativePath,
            fsEventID: Int64(eventID)
        )
    }

    nonisolated static func currentEventID() -> Int64? {
        let eventID = FSEventsGetCurrentEventId()
        guard eventID <= FSEventStreamEventId(Int64.max) else { return nil }
        return Int64(eventID)
    }

    private func startStream(repoPath: String, sinceWhen: FSEventStreamEventId) throws {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            mainExternalCreatedFileWatcherCallback,
            &context,
            [repoPath] as CFArray,
            sinceWhen,
            0.2,
            flags
        )
        guard let stream else { throw MainExternalWatcherStartError.creationFailed }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            stopStream(clearRepoPath: false)
            throw MainExternalWatcherStartError.startFailed
        }
        streamStartEventID = Int64(sinceWhen)
    }

    private func requestRescan(repoPath: String, reason: String) {
        stopStream(clearRepoPath: false)
        pendingEvents.removeAll()
        flushTask?.cancel()
        flushTask = nil
        recoveryRequest = MainExternalWatcherRecoveryRequest(
            kind: .rescanRequired,
            repoPath: repoPath,
            resumeEventID: Self.currentEventID(),
            reason: reason
        )
    }

    private func scheduleFlush(repoPath: String) {
        guard !pendingEvents.isEmpty else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: flushDelay)
            guard !Task.isCancelled else { return }
            await flush(repoPath: repoPath)
        }
    }

    private func flush(repoPath: String) async {
        guard watchedRepoPath == repoPath else { return }
        let events = pendingEvents.values.sorted { lhs, rhs in
            if lhs.eventID == rhs.eventID { return lhs.path < rhs.path }
            return lhs.eventID < rhs.eventID
        }
        pendingEvents.removeAll()
        flushTask = nil
        guard let cursorWatermark = events.last.map({ Int64($0.eventID) }) else { return }

        var signals: [MainExternalCreatedFileSignal] = []
        for event in events {
            let pathExists = FileManager.default.fileExists(atPath: event.path)
            guard let signal = Self.signal(
                repoPath: repoPath,
                absolutePath: event.path,
                flags: event.flags,
                eventID: event.eventID,
                pathExists: pathExists
            ) else { continue }
            if await inFlightTracker.contains(repoPath: signal.repoPath, relativePath: signal.relativePath) {
                continue
            }
            signals.append(signal)
        }
        if signals.isEmpty {
            await advanceFilteredEventCursor(repoPath: repoPath, cursorWatermark: cursorWatermark)
            return
        }
        let watermarkedSignals = signals.compactMap { $0.withCursorWatermark(cursorWatermark) }
        AreaMatrixExternalCreatedFileRelay.publish(watermarkedSignals)
    }

    private func advanceFilteredEventCursor(repoPath: String, cursorWatermark: Int64) async {
        do {
            try await cursorStore.setFSEventCursor(repoPath: repoPath, lastEventID: cursorWatermark)
        } catch {
            requestRescan(
                repoPath: repoPath,
                reason: "Filesystem watcher could not persist the filtered event cursor."
            )
        }
    }

    private func stopStream(clearRepoPath: Bool) {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        streamStartEventID = nil
        if clearRepoPath { watchedRepoPath = nil }
    }

    private nonisolated static func relativePath(repoPath: String, absolutePath: String) -> String? {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL
        let fileURL = URL(fileURLWithPath: absolutePath).standardizedFileURL
        let repoPrefix = repoURL.path + "/"
        guard fileURL.path.hasPrefix(repoPrefix) else { return nil }
        return String(fileURL.path.dropFirst(repoPrefix.count))
    }

    private nonisolated static func normalizedRepoPath(_ repoPath: String) -> String {
        let trimmedPath = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmedPath, isDirectory: true).standardizedFileURL.path
    }

    private nonisolated static func streamEventID(_ cursor: Int64) -> FSEventStreamEventId {
        FSEventStreamEventId(max(cursor, 0))
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

private enum MainExternalWatcherStartError: LocalizedError {
    case creationFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .creationFailed: "FSEventStream creation failed."
        case .startFailed: "FSEventStream start failed."
        }
    }
}

private let mainExternalCreatedFileWatcherCallback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
    guard let info else { return }
    let pathArray = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
    let eventCount = min(count, pathArray.count)
    let events = (0 ..< eventCount).map { index in
        MainExternalCreatedFileWatcherEvent(path: pathArray[index], flags: flags[index], eventID: ids[index])
    }
    let watcher = Unmanaged<MainExternalCreatedFileWatcher>.fromOpaque(info).takeUnretainedValue()
    Task { @MainActor in watcher.handle(events: events) }
}
