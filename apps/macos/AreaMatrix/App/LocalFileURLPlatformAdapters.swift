import AppKit
import Foundation

struct LocalFileURLResourceSnapshot: Equatable {
    var exists: Bool
    var isDirectory: Bool
}

enum LocalFileURLOpenError: Error, Equatable {
    case missing(String)
    case notDirectory(String)
    case openRejected(String)
}

protocol LocalFileURLResourceReading: Sendable {
    @MainActor
    func resourceSnapshot(for url: URL) -> LocalFileURLResourceSnapshot
}

protocol LocalFileURLPlatformOpening: Sendable {
    @MainActor
    func open(_ url: URL) -> Bool
    @MainActor
    func reveal(_ urls: [URL])
}

protocol LocalFileURLOpening: Sendable {
    @MainActor
    func open(_ url: URL) throws
    @MainActor
    func openExisting(_ url: URL, requiresDirectory: Bool) throws
    @MainActor
    func revealExisting(_ url: URL) throws
}

struct FileManagerLocalFileURLResourceReader: LocalFileURLResourceReading {
    @MainActor
    func resourceSnapshot(for url: URL) -> LocalFileURLResourceSnapshot {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return LocalFileURLResourceSnapshot(exists: exists, isDirectory: isDirectory.boolValue)
    }
}

struct NSWorkspaceLocalFileURLPlatformOpener: LocalFileURLPlatformOpening {
    @MainActor
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

struct NSWorkspaceLocalFileURLOpener: LocalFileURLOpening {
    private let resourceReader: any LocalFileURLResourceReading
    private let platformOpener: any LocalFileURLPlatformOpening

    init(
        resourceReader: any LocalFileURLResourceReading = FileManagerLocalFileURLResourceReader(),
        platformOpener: any LocalFileURLPlatformOpening = NSWorkspaceLocalFileURLPlatformOpener()
    ) {
        self.resourceReader = resourceReader
        self.platformOpener = platformOpener
    }

    @MainActor
    func open(_ url: URL) throws {
        guard platformOpener.open(url) else {
            throw LocalFileURLOpenError.openRejected(url.path)
        }
    }

    @MainActor
    func openExisting(_ url: URL, requiresDirectory: Bool) throws {
        let snapshot = resourceReader.resourceSnapshot(for: url)
        guard snapshot.exists else {
            throw LocalFileURLOpenError.missing(url.path)
        }
        guard !requiresDirectory || snapshot.isDirectory else {
            throw LocalFileURLOpenError.notDirectory(url.path)
        }
        try open(url)
    }

    @MainActor
    func revealExisting(_ url: URL) throws {
        guard resourceReader.resourceSnapshot(for: url).exists else {
            throw LocalFileURLOpenError.missing(url.path)
        }
        platformOpener.reveal([url])
    }
}
