import Darwin
import Foundation

protocol RepositoryIgnoreRulesManaging: Sendable {
    @MainActor
    func openIgnoreRules(repoPath: String) throws

    @MainActor
    func createDefaultIgnoreRules(repoPath: String) throws
}

struct NSWorkspaceRepositoryIgnoreRulesManager: RepositoryIgnoreRulesManaging {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    func openIgnoreRules(repoPath: String) throws {
        let url = ignoreRulesURL(repoPath: repoPath)
        guard fileExists(url) else {
            throw RepositoryIgnoreRulesError.ignoreRulesMissing
        }
        guard isRegularFile(url) else {
            throw RepositoryIgnoreRulesError.ignoreRulesNotRegularFile
        }

        do {
            try localURLOpener.open(url)
        } catch {
            throw RepositoryIgnoreRulesError.openRejected
        }
    }

    func createDefaultIgnoreRules(repoPath: String) throws {
        let metadataURL = URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
        guard fileExists(metadataURL) else {
            throw RepositoryIgnoreRulesError.metadataDirectoryMissing
        }
        guard isDirectory(metadataURL) else {
            throw RepositoryIgnoreRulesError.metadataPathNotDirectory
        }

        let url = ignoreRulesURL(repoPath: repoPath)
        try writeNewFile(url: url, content: Self.defaultIgnoreRulesYAML)
    }
}

enum RepositoryIgnoreRulesError: Error, Equatable, LocalizedError {
    case metadataDirectoryMissing
    case metadataPathNotDirectory
    case ignoreRulesMissing
    case ignoreRulesNotRegularFile
    case ignoreRulesAlreadyExists
    case createRejected(String)
    case openRejected

    var errorDescription: String? {
        switch self {
        case .metadataDirectoryMissing:
            L10n.string("settings.ignore.metadataMissing")
        case .metadataPathNotDirectory:
            L10n.string("settings.ignore.metadataNotDirectory")
        case .ignoreRulesMissing:
            L10n.string("settings.ignore.fileMissing")
        case .ignoreRulesNotRegularFile:
            L10n.string("settings.ignore.notRegularFile")
        case .ignoreRulesAlreadyExists:
            L10n.string("settings.ignore.alreadyExists")
        case let .createRejected(reason):
            L10n.format("settings.ignore.createRejected", reason)
        case .openRejected:
            L10n.string("settings.ignore.openRejected")
        }
    }
}

private extension NSWorkspaceRepositoryIgnoreRulesManager {
    static let defaultIgnoreRulesYAML = """
    version: 1
    ignore:
      - ".DS_Store"
      - ".areamatrix/"
      - ".git/"
      - ".hg/"
      - ".svn/"
      - "node_modules/"
      - ".venv/"
      - "venv/"
      - "target/"
      - "build/"
      - "dist/"
      - ".next/"
      - ".cache/"
      - "*.tmp"
      - "*.swp"

    """

    func ignoreRulesURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("ignore.yaml")
    }

    func writeNewFile(url: URL, content: String) throws {
        let path = url.path
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard fd >= 0 else {
            throw createError()
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(content.utf8))
            try handle.close()
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw RepositoryIgnoreRulesError.createRejected(error.localizedDescription)
        }
    }

    func createError() -> RepositoryIgnoreRulesError {
        errno == EEXIST ? .ignoreRulesAlreadyExists : .createRejected(String(cString: strerror(errno)))
    }

    func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
