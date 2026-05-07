import Combine
import CoreServices
import Foundation

@MainActor
final class MainExternalCreatedFileWatcher: ObservableObject {
    private var stream: FSEventStreamRef?
    private var watchedRepoPath: String?

    func start(repoPath: String) {
        let normalizedPath = Self.normalizedRepoPath(repoPath)
        guard !normalizedPath.isEmpty else {
            stop()
            return
        }
        guard watchedRepoPath != normalizedPath else { return }

        stop()
        watchedRepoPath = normalizedPath
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
            [normalizedPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        )
        guard let stream else {
            watchedRepoPath = nil
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        if !FSEventStreamStart(stream) {
            stop()
        }
    }

    func stop() {
        guard let stream else {
            watchedRepoPath = nil
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        watchedRepoPath = nil
    }

    func handle(events: [MainExternalCreatedFileWatcherEvent]) {
        guard let repoPath = watchedRepoPath else { return }

        for event in events {
            guard let signal = Self.signal(
                repoPath: repoPath,
                absolutePath: event.path,
                flags: event.flags,
                eventID: event.eventID
            ) else { continue }
            AreaMatrixExternalCreatedFileRelay.publish(
                kind: signal.kind,
                repoPath: signal.repoPath,
                relativePath: signal.relativePath,
                fsEventID: signal.fsEventID
            )
        }
    }

    nonisolated static func signal(
        repoPath: String,
        absolutePath: String,
        flags: FSEventStreamEventFlags,
        eventID: FSEventStreamEventId
    ) -> MainExternalCreatedFileSignal? {
        let ignoredFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
            | FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
        guard flags & ignoredFlags == 0 else { return nil }
        let syncKind: MainExternalSyncEventKind
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            syncKind = .renamed
        } else if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
            syncKind = .created
        } else if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            syncKind = .removed
        } else {
            return nil
        }
        guard flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) == 0 else { return nil }
        guard eventID > 0, eventID <= FSEventStreamEventId(Int64.max) else { return nil }

        let normalizedRepoPath = normalizedRepoPath(repoPath)
        guard let relativePath = relativePath(repoPath: normalizedRepoPath, absolutePath: absolutePath) else {
            return nil
        }
        guard relativePath != ".areamatrix", !relativePath.hasPrefix(".areamatrix/") else { return nil }

        return MainExternalCreatedFileSignal(
            kind: syncKind,
            repoPath: normalizedRepoPath,
            relativePath: relativePath,
            fsEventID: Int64(eventID)
        )
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
}

struct MainExternalCreatedFileWatcherEvent: Sendable {
    let path: String
    let flags: FSEventStreamEventFlags
    let eventID: FSEventStreamEventId
}

private let mainExternalCreatedFileWatcherCallback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
    guard let info else { return }

    let pathArray = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
    let eventCount = min(count, pathArray.count)
    let events = (0..<eventCount).map { index in
        MainExternalCreatedFileWatcherEvent(path: pathArray[index], flags: flags[index], eventID: ids[index])
    }
    let watcher = Unmanaged<MainExternalCreatedFileWatcher>.fromOpaque(info).takeUnretainedValue()
    Task { @MainActor in
        watcher.handle(events: events)
    }
}
