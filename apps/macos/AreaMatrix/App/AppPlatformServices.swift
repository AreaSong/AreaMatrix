import AppKit
import Foundation

struct AppShellModel: Equatable, Sendable {
    var statusText = "Onboarding configuration router"
}

protocol AppSettingsReading {
    func configuredRepoPath() -> String?
}

protocol AppSettingsWriting {
    func saveConfiguredRepoPath(_ repoPath: String)
}

struct UserDefaultsAppSettingsReader: AppSettingsReading {
    private let defaults: UserDefaults
    private let repoPathKey: String

    init(defaults: UserDefaults = .standard, repoPathKey: String = "AreaMatrix.repoPath") {
        self.defaults = defaults
        self.repoPathKey = repoPathKey
    }

    func configuredRepoPath() -> String? {
        guard let value = defaults.string(forKey: repoPathKey) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UserDefaultsAppSettingsReader: AppSettingsWriting {
    func saveConfiguredRepoPath(_ repoPath: String) {
        defaults.set(repoPath, forKey: repoPathKey)
    }
}

protocol WelcomeHelpOpening {
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

protocol RepositoryPathCopying {
    @MainActor
    func copyPath(repoPath: String, relativePath: String) throws
}

protocol AccessibilityAnnouncing {
    @MainActor
    func announce(_ message: String)
}

struct LocalWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        let docsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/product/prd.md")

        guard FileManager.default.fileExists(atPath: docsURL.path) else {
            throw WelcomeHelpError.helpDocumentUnavailable
        }

        NSWorkspace.shared.open(docsURL)
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
    @MainActor
    func openRepositoryInFinder(repoPath: String) throws {
        let url = URL(fileURLWithPath: repoPath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RepositoryFinderOpenError.repositoryFolderMissing(repoPath)
        }
        guard NSWorkspace.shared.open(url) else {
            throw RepositoryFinderOpenError.openRejected(repoPath)
        }
    }
}

struct NSWorkspaceRepositoryFileRevealer: RepositoryFileRevealing {
    @MainActor
    func revealFile(repoPath: String, relativePath: String) throws {
        let url = try RepositoryFilePathResolver.fileURL(repoPath: repoPath, relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RepositoryFileActionError.fileMissing(relativePath)
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct NSPasteboardRepositoryPathCopier: RepositoryPathCopying {
    @MainActor
    func copyPath(repoPath: String, relativePath: String) throws {
        let path = try RepositoryFilePathResolver.fileURL(repoPath: repoPath, relativePath: relativePath).path
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
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
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

enum WelcomeHelpError: Error, Equatable, Sendable {
    case helpDocumentUnavailable
}

enum RepositoryFinderOpenError: Error, Equatable, LocalizedError, Sendable {
    case repositoryFolderMissing(String)
    case openRejected(String)

    var errorDescription: String? {
        switch self {
        case .repositoryFolderMissing(let path):
            return "Repository folder is missing: \(path)"
        case .openRejected(let path):
            return "Finder rejected opening repository: \(path)"
        }
    }
}

enum RepositoryFileActionError: Error, Equatable, LocalizedError, Sendable {
    case unsafeRelativePath(String)
    case fileMissing(String)

    var errorDescription: String? {
        switch self {
        case .unsafeRelativePath(let path):
            return "File path is outside this repository: \(path)"
        case .fileMissing(let path):
            return "File is missing from this repository: \(path)"
        }
    }
}

private enum RepositoryFilePathResolver {
    static func fileURL(repoPath: String, relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains(".."),
              !components.contains(".") else {
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
