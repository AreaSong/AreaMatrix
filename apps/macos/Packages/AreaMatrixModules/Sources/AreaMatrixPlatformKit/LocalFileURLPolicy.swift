import AppKit
import Foundation

public struct LocalFileURLResourceSnapshot: Equatable, Sendable {
    public var exists: Bool
    public var isDirectory: Bool

    public init(exists: Bool, isDirectory: Bool) {
        self.exists = exists
        self.isDirectory = isDirectory
    }
}

public enum LocalFileURLOpenError: Error, Equatable, Sendable {
    case missing(String)
    case notDirectory(String)
    case openRejected(String)
}

public protocol LocalFileURLResourceReading: Sendable {
    @MainActor
    func resourceSnapshot(for url: URL) -> LocalFileURLResourceSnapshot
}

public protocol LocalFileURLPlatformOpening: Sendable {
    @MainActor
    func open(_ url: URL) -> Bool

    @MainActor
    func reveal(_ urls: [URL])
}

public protocol LocalFileURLOpening: Sendable {
    @MainActor
    func open(_ url: URL) throws

    @MainActor
    func openExisting(_ url: URL, requiresDirectory: Bool) throws

    @MainActor
    func revealExisting(_ url: URL) throws
}

public struct FileManagerLocalFileURLResourceReader: LocalFileURLResourceReading {
    public init() {}

    @MainActor
    public func resourceSnapshot(for url: URL) -> LocalFileURLResourceSnapshot {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return LocalFileURLResourceSnapshot(exists: exists, isDirectory: isDirectory.boolValue)
    }
}

public struct NSWorkspaceLocalFileURLPlatformOpener: LocalFileURLPlatformOpening {
    public init() {}

    @MainActor
    public func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    public func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

public struct NSWorkspaceLocalFileURLOpener: LocalFileURLOpening {
    private let resourceReader: any LocalFileURLResourceReading
    private let platformOpener: any LocalFileURLPlatformOpening

    public init(
        resourceReader: any LocalFileURLResourceReading = FileManagerLocalFileURLResourceReader(),
        platformOpener: any LocalFileURLPlatformOpening = NSWorkspaceLocalFileURLPlatformOpener()
    ) {
        self.resourceReader = resourceReader
        self.platformOpener = platformOpener
    }

    @MainActor
    public func open(_ url: URL) throws {
        guard platformOpener.open(url) else {
            throw LocalFileURLOpenError.openRejected(url.path)
        }
    }

    @MainActor
    public func openExisting(_ url: URL, requiresDirectory: Bool) throws {
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
    public func revealExisting(_ url: URL) throws {
        guard resourceReader.resourceSnapshot(for: url).exists else {
            throw LocalFileURLOpenError.missing(url.path)
        }
        platformOpener.reveal([url])
    }
}
