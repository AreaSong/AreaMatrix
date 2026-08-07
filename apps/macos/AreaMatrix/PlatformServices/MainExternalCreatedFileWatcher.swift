import Combine
import CoreServices
import Foundation

@MainActor
final class MainExternalCreatedFileWatcher: ObservableObject {
    @Published private(set) var recoveryRequest: MainExternalWatcherRecoveryRequest?
    private(set) var streamStartEventID: Int64?

    private var stream: FSEventStreamRef?
    private var watchedRepoPath: String?
    private(set) var activeCallbackContext: MainExternalWatcherCallbackContext?
    private var pendingEvents: [String: MainExternalCreatedFileWatcherEvent] = [:]
    private var flushTask: Task<Void, Never>?
    private var flushTaskGeneration: UInt64?
    private var flushRevision: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0
    private let cursorStore: any CoreExternalChangesSyncing
    private let inFlightTracker: any InFlightFileChangeTracking
    private let flushDelay: Duration

    init(
        cursorStore: any CoreExternalChangesSyncing,
        inFlightTracker: any InFlightFileChangeTracking,
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

        let generation = beginLifecycleTransition()
        stopCurrentStreamAndPending(clearRepoPath: true)
        watchedRepoPath = normalizedPath
        do {
            guard let cursor = try await cursorStore.getFSEventCursor(repoPath: normalizedPath) else {
                guard isCurrent(generation: generation, repoPath: normalizedPath) else { return }
                requestRescan(repoPath: normalizedPath, reason: L10n.string("external-sync.cursorUnavailable"))
                return
            }
            guard isCurrent(generation: generation, repoPath: normalizedPath) else { return }
            try startStream(
                repoPath: normalizedPath,
                sinceWhen: Self.streamEventID(cursor),
                generation: generation
            )
            guard isCurrent(generation: generation, repoPath: normalizedPath) else {
                stopCurrentStreamAndPending(clearRepoPath: true)
                return
            }
            recoveryRequest = nil
        } catch {
            guard isCurrent(generation: generation, repoPath: normalizedPath) else { return }
            enterRecovery(
                kind: .startupFailed,
                repoPath: normalizedPath,
                resumeEventID: nil,
                reason: L10n.format("external-sync.watcherStartFailed", error.localizedDescription)
            )
        }
    }

    func stop() {
        _ = beginLifecycleTransition()
        stopCurrentStreamAndPending(clearRepoPath: true)
    }

    func handle(events: [MainExternalCreatedFileWatcherEvent]) {
        guard let repoPath = watchedRepoPath else { return }
        receiveCallbackEvents(events, repoPath: repoPath, generation: lifecycleGeneration)
    }

    fileprivate func receiveCallbackEvents(
        _ events: [MainExternalCreatedFileWatcherEvent],
        repoPath: String,
        generation: UInt64
    ) {
        guard isCurrentLifecycle(generation: generation, repoPath: repoPath) else { return }
        if events.contains(where: {
            $0.hasFlag(FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged))
        }) {
            enterRecovery(
                kind: .rootChanged,
                repoPath: repoPath,
                resumeEventID: nil,
                reason: L10n.string("external-sync.rootUnavailable")
            )
            return
        }
        let replayInvalidatingFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped)
        if events.contains(where: { $0.flags & replayInvalidatingFlags != 0 }) {
            requestRescan(repoPath: repoPath, reason: L10n.string("external-sync.historyUnavailable"))
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

    private func startStream(
        repoPath: String,
        sinceWhen: FSEventStreamEventId,
        generation: UInt64
    ) throws {
        let callbackContext = MainExternalWatcherCallbackContext(
            watcher: self,
            repoPath: repoPath,
            generation: generation
        )
        activeCallbackContext = callbackContext
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callbackContext).toOpaque(),
            retain: mainExternalWatcherContextRetain,
            release: mainExternalWatcherContextRelease,
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
        guard let stream else {
            activeCallbackContext = nil
            throw MainExternalWatcherStartError.creationFailed
        }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            stopStream(clearRepoPath: false)
            throw MainExternalWatcherStartError.startFailed
        }
        streamStartEventID = Int64(sinceWhen)
    }

    private func requestRescan(repoPath: String, reason: String) {
        enterRecovery(
            kind: .rescanRequired,
            repoPath: repoPath,
            resumeEventID: Self.currentEventID(),
            reason: reason
        )
    }

    private func scheduleFlush(repoPath: String) {
        guard !pendingEvents.isEmpty else { return }
        let generation = lifecycleGeneration
        flushRevision &+= 1
        guard flushTask == nil else { return }
        flushTaskGeneration = generation
        flushTask = Task { [weak self] in
            guard let self else { return }
            await runFlushLoop(repoPath: repoPath, generation: generation)
        }
    }

    private func runFlushLoop(repoPath: String, generation: UInt64) async {
        defer { finishFlushTask(generation: generation) }
        while canContinueFlush(generation: generation, repoPath: repoPath) {
            let debounceRevision = flushRevision
            do {
                try await Task.sleep(for: flushDelay)
            } catch {
                return
            }
            guard canContinueFlush(generation: generation, repoPath: repoPath) else { return }
            guard debounceRevision == flushRevision else { continue }

            let events = takePendingEvents()
            guard !events.isEmpty else { return }
            await publish(events: events, repoPath: repoPath, generation: generation)
            guard canContinueFlush(generation: generation, repoPath: repoPath) else { return }
            if pendingEvents.isEmpty { return }
        }
    }

    private func takePendingEvents() -> [MainExternalCreatedFileWatcherEvent] {
        let events = pendingEvents.values.sorted { lhs, rhs in
            if lhs.eventID == rhs.eventID { return lhs.path < rhs.path }
            return lhs.eventID < rhs.eventID
        }
        pendingEvents.removeAll()
        return events
    }

    private func publish(
        events: [MainExternalCreatedFileWatcherEvent],
        repoPath: String,
        generation: UInt64
    ) async {
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
            guard canContinueFlush(generation: generation, repoPath: repoPath) else { return }
            signals.append(signal)
        }
        let watermarkedSignals = signals.compactMap { $0.withCursorWatermark(cursorWatermark) }
        let syncEvents = watermarkedSignals.compactMap { signal in
            MainExternalCreatedFileEvent(
                kind: signal.kind,
                relativePath: signal.relativePath,
                fsEventID: signal.fsEventID,
                cursorWatermark: cursorWatermark
            )
        }
        guard canContinueFlush(generation: generation, repoPath: repoPath),
              let window = MainExternalSyncWindow(
                  repoPath: repoPath,
                  events: syncEvents,
                  cursorWatermark: cursorWatermark
              ) else { return }
        AreaMatrixExternalCreatedFileRelay.publish(window)
    }

    private func finishFlushTask(generation: UInt64) {
        guard flushTaskGeneration == generation else { return }
        flushTask = nil
        flushTaskGeneration = nil
    }

    private func stopStream(clearRepoPath: Bool) {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        streamStartEventID = nil
        activeCallbackContext = nil
        if clearRepoPath { watchedRepoPath = nil }
    }

    private func stopCurrentStreamAndPending(clearRepoPath: Bool) {
        stopStream(clearRepoPath: clearRepoPath)
        pendingEvents.removeAll()
        flushTask?.cancel()
        flushTask = nil
        flushTaskGeneration = nil
        flushRevision &+= 1
    }

    private func enterRecovery(
        kind: MainExternalWatcherRecoveryKind,
        repoPath: String,
        resumeEventID: Int64?,
        reason: String
    ) {
        _ = beginLifecycleTransition()
        stopCurrentStreamAndPending(clearRepoPath: false)
        recoveryRequest = MainExternalWatcherRecoveryRequest(
            kind: kind,
            repoPath: repoPath,
            resumeEventID: resumeEventID,
            reason: reason
        )
    }

    private func beginLifecycleTransition() -> UInt64 {
        lifecycleGeneration &+= 1
        return lifecycleGeneration
    }

    private func isCurrent(generation: UInt64, repoPath: String) -> Bool {
        isCurrentLifecycle(generation: generation, repoPath: repoPath) && !Task.isCancelled
    }

    private func isCurrentLifecycle(generation: UInt64, repoPath: String) -> Bool {
        generation == lifecycleGeneration && watchedRepoPath == repoPath
    }

    private func canContinueFlush(generation: UInt64, repoPath: String) -> Bool {
        isCurrentLifecycle(generation: generation, repoPath: repoPath) && !Task.isCancelled
    }
}

extension MainExternalCreatedFileWatcher {
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

final class MainExternalWatcherCallbackContext {
    weak var watcher: MainExternalCreatedFileWatcher?
    let repoPath: String
    let generation: UInt64

    init(watcher: MainExternalCreatedFileWatcher, repoPath: String, generation: UInt64) {
        self.watcher = watcher
        self.repoPath = repoPath
        self.generation = generation
    }

    func deliver(_ events: [MainExternalCreatedFileWatcherEvent]) {
        let repoPath = repoPath
        let generation = generation
        Task { @MainActor [weak watcher] in
            watcher?.receiveCallbackEvents(events, repoPath: repoPath, generation: generation)
        }
    }
}

private enum MainExternalWatcherStartError: LocalizedError {
    case creationFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .creationFailed: L10n.string("FSEventStream creation failed.")
        case .startFailed: L10n.string("FSEventStream start failed.")
        }
    }
}

private let mainExternalWatcherContextRetain: CFAllocatorRetainCallBack = { info in
    guard let info else { return nil }
    return UnsafeRawPointer(Unmanaged<MainExternalWatcherCallbackContext>.fromOpaque(info).retain().toOpaque())
}

private let mainExternalWatcherContextRelease: CFAllocatorReleaseCallBack = { info in
    guard let info else { return }
    Unmanaged<MainExternalWatcherCallbackContext>.fromOpaque(info).release()
}

private let mainExternalCreatedFileWatcherCallback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
    guard let info else { return }
    let pathArray = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
    let eventCount = min(count, pathArray.count)
    let events = (0 ..< eventCount).map { index in
        MainExternalCreatedFileWatcherEvent(path: pathArray[index], flags: flags[index], eventID: ids[index])
    }
    let context = Unmanaged<MainExternalWatcherCallbackContext>.fromOpaque(info).takeUnretainedValue()
    context.deliver(events)
}
