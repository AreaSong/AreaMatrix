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

    init(localURLOpener: any LocalFileURLOpening) {
        self.localURLOpener = localURLOpener
    }

    func openIgnoreRules(repoPath: String) throws {
        let url = ignoreRulesURL(repoPath: repoPath)
        let metadataFD: Int32
        do {
            metadataFD = try openMetadataDirectory(repoPath: repoPath)
        } catch let error as RepositoryIgnoreRulesError {
            throw error
        } catch {
            throw RepositoryIgnoreRulesError.ignoreRulesMissing
        }
        defer { close(metadataFD) }

        let ignoreFD = "ignore.yaml".withCString { name in
            openat(metadataFD, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard ignoreFD >= 0 else {
            if errno == ENOENT {
                throw RepositoryIgnoreRulesError.ignoreRulesMissing
            }
            throw RepositoryIgnoreRulesError.ignoreRulesNotRegularFile
        }
        defer { close(ignoreFD) }
        var info = stat()
        guard fstat(ignoreFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw RepositoryIgnoreRulesError.ignoreRulesNotRegularFile
        }
        // Bind the URL opener to the same regular file immediately before the
        // external hand-off. A replacement is rejected rather than opened.
        var finalInfo = stat()
        guard fstat(ignoreFD, &finalInfo) == 0,
              finalInfo.st_dev == info.st_dev,
              finalInfo.st_ino == info.st_ino else {
            throw RepositoryIgnoreRulesError.openRejected
        }

        do {
            try localURLOpener.openExisting(url, requiresDirectory: false)
        } catch {
            throw RepositoryIgnoreRulesError.openRejected
        }
    }

    func createDefaultIgnoreRules(repoPath: String) throws {
        let metadataFD: Int32
        do {
            metadataFD = try openMetadataDirectory(repoPath: repoPath)
        } catch let error as RepositoryIgnoreRulesError {
            throw error
        } catch {
            throw RepositoryIgnoreRulesError.metadataDirectoryMissing
        }
        defer { close(metadataFD) }
        try writeNewFile(
            directoryFD: metadataFD,
            name: "ignore.yaml",
            content: Self.defaultIgnoreRulesYAML
        )
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

    func openMetadataDirectory(repoPath: String) throws -> Int32 {
        let rootPath = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
        guard !rootPath.isEmpty, rootPath.hasPrefix("/") else {
            throw RepositoryIgnoreRulesError.metadataPathNotDirectory
        }
        try rejectUntrustedSymlinkAncestors(rootPath)
        let rootFD = rootPath.withCString { path in
            open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard rootFD >= 0 else {
            throw errno == ENOENT
                ? RepositoryIgnoreRulesError.metadataDirectoryMissing
                : RepositoryIgnoreRulesError.metadataPathNotDirectory
        }
        let metadataFD = ".areamatrix".withCString { name in
            openat(rootFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        close(rootFD)
        guard metadataFD >= 0 else {
            throw errno == ENOENT
                ? RepositoryIgnoreRulesError.metadataDirectoryMissing
                : RepositoryIgnoreRulesError.metadataPathNotDirectory
        }
        return metadataFD
    }

    func rejectUntrustedSymlinkAncestors(_ path: String) throws {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in path.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            var info = stat()
            let result = current.path.withCString { pointer in
                lstat(pointer, &info)
            }
            if result != 0 {
                if errno == ENOENT { continue }
                throw RepositoryIgnoreRulesError.metadataPathNotDirectory
            }
            let isSymlink = (info.st_mode & S_IFMT) == S_IFLNK
            let isAllowedAlias = current.path == "/tmp" || current.path == "/var"
            if isSymlink, !isAllowedAlias {
                throw RepositoryIgnoreRulesError.metadataPathNotDirectory
            }
        }
    }

    func writeNewFile(directoryFD: Int32, name: String, content: String) throws {
        let fd = name.withCString { path in
            openat(
                directoryFD,
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
            )
        }
        guard fd >= 0 else {
            throw createError()
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(content.utf8))
            try handle.synchronize()
            try handle.close()
        } catch {
            // Only unlink the name in the already-open metadata directory; never
            // resolve a replacement path through FileManager.
            _ = name.withCString { path in unlinkat(directoryFD, path, 0) }
            throw RepositoryIgnoreRulesError.createRejected(error.localizedDescription)
        }
    }

    func createError() -> RepositoryIgnoreRulesError {
        errno == EEXIST ? .ignoreRulesAlreadyExists : .createRejected(String(cString: strerror(errno)))
    }
}
