import AppKit
import Foundation
import UniformTypeIdentifiers

protocol WelcomeHelpOpening {
    @MainActor
    func openWelcomeHelp() throws
}

protocol RepositoryDirectoryPicking {
    @MainActor
    func chooseDirectory() -> URL?
}

protocol RepositoryImportPicking {
    @MainActor
    func chooseImportURLs() -> [URL]?
}

protocol RepositoryFinderOpening {
    @MainActor
    func openRepositoryInFinder(repoPath: String) throws
}

protocol RepositoryFileRevealing {
    @MainActor
    func revealFile(repoPath: String, relativePath: String) throws
}

protocol RepositoryFileOpening {
    @MainActor
    func openFile(repoPath: String, relativePath: String) throws
}

protocol RepositoryPathCopying {
    @MainActor
    func copyPath(repoPath: String, relativePath: String) throws
    @MainActor
    func copyPaths(repoPath: String, relativePaths: [String]) throws
}

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

protocol PasteboardStringWriting {
    @MainActor
    @discardableResult
    func write(_ value: String) -> Bool
}

protocol ImportResultDetailsExporting {
    @MainActor
    func exportDetails(_ details: String, suggestedFilename: String) throws -> String
}

protocol AccessibilityAnnouncing {
    @MainActor
    func announce(_ message: String)
}

protocol WindowClosing {
    @MainActor
    func closeKeyWindow()
}

struct LocalWelcomeHelpOpener: WelcomeHelpOpening {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    @MainActor
    func openWelcomeHelp() throws {
        let docsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/product/prd.md")

        do {
            try localURLOpener.openExisting(docsURL, requiresDirectory: false)
        } catch LocalFileURLOpenError.openRejected(_) {
            return
        } catch {
            throw WelcomeHelpError.helpDocumentUnavailable
        }
    }
}

struct NSApplicationKeyWindowCloser: WindowClosing {
    @MainActor
    func closeKeyWindow() {
        NSApplication.shared.keyWindow?.close()
    }
}

struct NSOpenPanelRepositoryDirectoryPicker: RepositoryDirectoryPicking {
    @MainActor
    func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose a repository folder."

        return panel.runModal() == .OK ? panel.url : nil
    }
}

struct NSOpenPanelRepositoryImportPicker: RepositoryImportPicking {
    @MainActor
    func chooseImportURLs() -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Import"
        panel.message = "Choose files or folders to import."

        return panel.runModal() == .OK ? panel.urls : nil
    }
}

struct NSWorkspaceRepositoryFinderOpener: RepositoryFinderOpening {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    @MainActor
    func openRepositoryInFinder(repoPath: String) throws {
        let url = URL(fileURLWithPath: repoPath, isDirectory: true)
        do {
            try localURLOpener.openExisting(url, requiresDirectory: false)
        } catch LocalFileURLOpenError.openRejected(_) {
            throw RepositoryFinderOpenError.openRejected(repoPath)
        } catch {
            throw RepositoryFinderOpenError.repositoryFolderMissing(repoPath)
        }
    }
}

struct NSWorkspaceRepositoryFileRevealer: RepositoryFileRevealing {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    @MainActor
    func revealFile(repoPath: String, relativePath: String) throws {
        let url = try RepositoryFilePathResolver.fileURL(repoPath: repoPath, relativePath: relativePath)
        do {
            try localURLOpener.revealExisting(url)
        } catch {
            throw RepositoryFileActionError.fileMissing(relativePath)
        }
    }
}

struct NSWorkspaceRepositoryFileOpener: RepositoryFileOpening {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    @MainActor
    func openFile(repoPath: String, relativePath: String) throws {
        let url = try RepositoryFilePathResolver.fileURL(repoPath: repoPath, relativePath: relativePath)
        do {
            try localURLOpener.openExisting(url, requiresDirectory: false)
        } catch LocalFileURLOpenError.openRejected(_) {
            throw RepositoryFileActionError.openRejected(relativePath)
        } catch {
            throw RepositoryFileActionError.fileMissing(relativePath)
        }
    }
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

struct NSPasteboardStringWriter: PasteboardStringWriting {
    @MainActor
    @discardableResult
    func write(_ value: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(value, forType: .string)
    }
}

struct NSPasteboardRepositoryPathCopier: RepositoryPathCopying {
    private let writer: any PasteboardStringWriting

    init(writer: any PasteboardStringWriting = AppPlatformServices.pasteboardStringWriter) {
        self.writer = writer
    }

    @MainActor
    func copyPath(repoPath: String, relativePath: String) throws {
        let path = try pathForCopy(repoPath: repoPath, relativePath: relativePath)
        writer.write(path)
    }

    @MainActor
    func copyPaths(repoPath: String, relativePaths: [String]) throws {
        let paths = try relativePaths.map { relativePath in
            try RepositoryFilePathResolver.fileURL(repoPath: repoPath, relativePath: relativePath).path
        }
        writer.write(paths.joined(separator: "\n"))
    }

    private func pathForCopy(repoPath: String, relativePath: String) throws -> String {
        guard !relativePath.isEmpty else {
            return URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
        }

        return try RepositoryFilePathResolver.fileURL(repoPath: repoPath, relativePath: relativePath).path
    }
}

struct NSSavePanelImportResultDetailsExporter: ImportResultDetailsExporting {
    @MainActor
    func exportDetails(_ details: String, suggestedFilename: String) throws -> String {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [.plainText]
        panel.message = "Export import result details with redacted paths and no file contents."

        guard panel.runModal() == .OK, let url = panel.url else {
            throw ImportResultExportError.cancelled
        }

        try details.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}

struct VoiceOverAccessibilityAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

enum WelcomeHelpError: Error, Equatable {
    case helpDocumentUnavailable
}

enum RepositoryFinderOpenError: Error, Equatable, LocalizedError {
    case repositoryFolderMissing(String)
    case openRejected(String)

    var errorDescription: String? {
        switch self {
        case let .repositoryFolderMissing(path):
            "Repository folder is missing: \(path)"
        case let .openRejected(path):
            "Finder rejected opening repository: \(path)"
        }
    }
}

enum RepositoryFileActionError: Error, Equatable, LocalizedError {
    case unsafeRelativePath(String)
    case fileMissing(String)
    case openRejected(String)

    var errorDescription: String? {
        switch self {
        case let .unsafeRelativePath(path):
            "File path is outside this repository: \(path)"
        case let .fileMissing(path):
            "File is missing from this repository: \(path)"
        case let .openRejected(path):
            "File opener rejected this path: \(path)"
        }
    }
}

enum ImportResultExportError: Error, Equatable, LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            "Import result export was cancelled."
        }
    }
}

private enum RepositoryFilePathResolver {
    static func fileURL(repoPath: String, relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains(".."),
              !components.contains(".")
        else {
            throw RepositoryFileActionError.unsafeRelativePath(relativePath)
        }

        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL
        let fileURL = repoURL.appendingPathComponent(relativePath).standardizedFileURL
        guard fileURL.path.hasPrefix(repoURL.path + "/") else {
            throw RepositoryFileActionError.unsafeRelativePath(relativePath)
        }

        return fileURL
    }
}
