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

protocol RepositoryMissingFilePicking {
    @MainActor
    func chooseReplacementFile(lastKnownPath: String?) -> URL?
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

protocol PasteboardStringWriting: Sendable {
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
    func announce(_ message: LocalizedMessage)
}

protocol WindowClosing {
    @MainActor
    func closeKeyWindow()
}

enum AppAppearancePreference {
    case system
    case light
    case dark
}

enum AppHapticFeedback {
    case alignment
    case levelChange
}

protocol AppInteractionFeedbackPerforming {
    @MainActor
    func applyAppearance(_ preference: AppAppearancePreference)
    @MainActor
    func setPointingCursor(active: Bool)
    @MainActor
    func performHaptic(_ feedback: AppHapticFeedback)
}

struct AppKitInteractionFeedbackPerformer: AppInteractionFeedbackPerforming {
    @MainActor
    func applyAppearance(_ preference: AppAppearancePreference) {
        switch preference {
        case .system:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func setPointingCursor(active: Bool) {
        if active {
            NSCursor.pointingHand.push()
        } else {
            NSCursor.pop()
        }
    }

    @MainActor
    func performHaptic(_ feedback: AppHapticFeedback) {
        switch feedback {
        case .alignment:
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        case .levelChange:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }
}

struct WelcomeHelpOpener: WelcomeHelpOpening {
    static let userGuideURL =
        "https://github.com/AreaSong/AreaMatrix/blob/main/docs/user-guide/getting-started.md"

    private let externalURLOpener: any ExternalURLStringOpening

    init(externalURLOpener: any ExternalURLStringOpening = AppPlatformServices.externalURLStringOpener) {
        self.externalURLOpener = externalURLOpener
    }

    @MainActor
    func openWelcomeHelp() throws {
        do {
            try externalURLOpener.openHTTPSURLString(Self.userGuideURL)
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
        panel.prompt = L10n.string("Choose")
        panel.message = L10n.string("Choose a repository folder.")

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
        panel.prompt = L10n.string("Import")
        panel.message = L10n.string("Choose files or folders to import.")

        return panel.runModal() == .OK ? panel.urls : nil
    }
}

struct NSOpenPanelRepositoryMissingFilePicker: RepositoryMissingFilePicking {
    @MainActor
    func chooseReplacementFile(lastKnownPath: String?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.string("Locate")
        panel.message = L10n.string("Choose the existing local file to relink. AreaMatrix will not move or modify it.")
        if let lastKnownPath, !lastKnownPath.isEmpty {
            let expandedPath = NSString(string: lastKnownPath).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expandedPath).deletingLastPathComponent()
        }

        return panel.runModal() == .OK ? panel.url : nil
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
        panel.message = L10n.string("Export import result details with redacted paths and no file contents.")

        guard panel.runModal() == .OK, let url = panel.url else {
            throw ImportResultExportError.cancelled
        }

        try details.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}

struct VoiceOverAccessibilityAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_ message: LocalizedMessage) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: L10n.resolve(message),
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
            L10n.format("platform.repositoryFinder.missing", path)
        case let .openRejected(path):
            L10n.format("platform.repositoryFinder.openRejected", path)
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
            L10n.format("platform.repositoryFile.outside", path)
        case let .fileMissing(path):
            L10n.format("platform.repositoryFile.missing", path)
        case let .openRejected(path):
            L10n.format("platform.repositoryFile.openRejected", path)
        }
    }
}

enum ImportResultExportError: Error, Equatable, LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled:
            L10n.string("import.result.export.cancelled")
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
