import Darwin
import Foundation

struct FileImportBatchSessionStore: ImportBatchSessionPersisting {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager _: FileManager = .default) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func saveSession(_ session: ImportBatchSessionSnapshot) async throws {
        do {
            try write(session)
        } catch {
            throw map(error, operation: .save)
        }
    }

    func loadSession(repoPath: String) async throws -> ImportBatchSessionSnapshot? {
        do {
            let data = try withSessionDirectory(repoPath: repoPath, create: false) { directoryFD in
                let fd = try openRelativeFile(
                    directoryFD: directoryFD,
                    name: "current.json",
                    flags: O_RDONLY | O_NOFOLLOW | O_CLOEXEC
                )
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? handle.close() }
                return try handle.readToEnd() ?? Data()
            }
            return try decoder.decode(CodableImportBatchSession.self, from: data).snapshot
        } catch {
            if error is DecodingError {
                throw ImportBatchSessionStoreError.corrupt
            }
            let mapped = map(error, operation: .load)
            if case .missing = mapped { return nil }
            throw mapped
        }
    }

    func clearSession(repoPath: String) async throws {
        do {
            try withSessionDirectory(repoPath: repoPath, create: false) { directoryFD in
                let result = "current.json".withCString { name in
                    unlinkat(directoryFD, name, 0)
                }
                guard result == 0 || errno == ENOENT else {
                    throw POSIXImportSessionError(errno: errno)
                }
                if result == 0, fsync(directoryFD) != 0 {
                    throw POSIXImportSessionError(errno: errno)
                }
            }
        } catch {
            let mapped = map(error, operation: .clear)
            if case .missing = mapped { return }
            throw mapped
        }
    }

    private func write(_ session: ImportBatchSessionSnapshot) throws {
        let data = try encoder.encode(CodableImportBatchSession(snapshot: session))
        try withSessionDirectory(repoPath: session.repoPath, create: true) { directoryFD in
            let temporaryName = ".current.json.\(UUID().uuidString).tmp"
            let fd = try openRelativeFile(
                directoryFD: directoryFD,
                name: temporaryName,
                flags: O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode: 0o600
            )
            var committed = false
            do {
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()

                let renameResult = temporaryName.withCString { source in
                    "current.json".withCString { destination in
                        renameat(directoryFD, source, directoryFD, destination)
                    }
                }
                guard renameResult == 0 else {
                    throw POSIXImportSessionError(errno: errno)
                }
                guard fsync(directoryFD) == 0 else {
                    throw POSIXImportSessionError(errno: errno)
                }
                committed = true
            } catch {
                if !committed {
                    _ = temporaryName.withCString { name in unlinkat(directoryFD, name, 0) }
                }
                throw error
            }
        }
    }

    private func withSessionDirectory<T>(
        repoPath: String,
        create: Bool,
        _ body: (Int32) throws -> T
    ) throws -> T {
        let repositoryFD = try openRepositoryDirectory(repoPath: repoPath)
        defer { close(repositoryFD) }
        let metadataFD = try openDirectoryComponent(
            parentFD: repositoryFD,
            component: ".areamatrix",
            create: create
        )
        defer { close(metadataFD) }
        let sessionsFD = try openDirectoryComponent(
            parentFD: metadataFD,
            component: "import-sessions",
            create: create
        )
        defer { close(sessionsFD) }
        return try body(sessionsFD)
    }

    private func openRepositoryDirectory(repoPath: String) throws -> Int32 {
        let path = canonicalTraversalPath(repoPath)
        guard !path.isEmpty, path.hasPrefix("/"), path != "/" else {
            throw POSIXImportSessionError(errno: EINVAL)
        }
        let rootFD = try openDirectoryPath("/")
        var currentFD = rootFD
        do {
            for component in path.split(separator: "/") {
                let nextFD = try openDirectoryComponent(
                    parentFD: currentFD,
                    component: String(component),
                    create: false
                )
                if currentFD != rootFD { close(currentFD) }
                currentFD = nextFD
            }
            close(rootFD)
            return currentFD
        } catch {
            if currentFD != rootFD { close(currentFD) }
            close(rootFD)
            throw error
        }
    }

    private func canonicalTraversalPath(_ repoPath: String) -> String {
        let path = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
        if path == "/tmp" || path.hasPrefix("/tmp/") { return "/private\(path)" }
        if path == "/var" || path.hasPrefix("/var/") { return "/private\(path)" }
        return path
    }

    private func openDirectoryPath(_ path: String) throws -> Int32 {
        let fd = path.withCString { pointer in
            open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { throw POSIXImportSessionError(errno: errno) }
        return fd
    }

    private func openDirectoryComponent(parentFD: Int32, component: String, create: Bool) throws -> Int32 {
        var fd = component.withCString { name in
            openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        if fd < 0, errno == ENOENT, create {
            let created = component.withCString { name in mkdirat(parentFD, name, 0o700) }
            guard created == 0 || errno == EEXIST else { throw POSIXImportSessionError(errno: errno) }
            fd = component.withCString { name in
                openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
        }
        guard fd >= 0 else { throw POSIXImportSessionError(errno: errno) }
        return fd
    }

    private func openRelativeFile(
        directoryFD: Int32,
        name: String,
        flags: Int32,
        mode: Int32 = 0
    ) throws -> Int32 {
        let fd = name.withCString { path in openat(directoryFD, path, flags, mode) }
        guard fd >= 0 else { throw POSIXImportSessionError(errno: errno) }
        return fd
    }
}

private struct POSIXImportSessionError: Error {
    let code: Int32

    init(errno: Int32) {
        code = errno
    }
}

private extension FileImportBatchSessionStore {
    func map(_ error: Error, operation: ImportBatchSessionStoreError.Operation) -> ImportBatchSessionStoreError {
        guard let posixError = error as? POSIXImportSessionError else {
            return .io(operation: operation, code: EIO)
        }
        switch posixError.code {
        case ENOENT:
            return .missing(operation: operation)
        case EACCES, EPERM:
            return .permission(operation: operation)
        case EINVAL, ELOOP, ENOTDIR:
            return .unsafePath(operation: operation)
        default:
            return .io(operation: operation, code: posixError.code)
        }
    }
}

private struct CodableImportBatchSession: Codable {
    var repoPath: String
    var storageMode: ImportSingleFileStorageMode
    var completed: Int
    var failed: Int
    var total: Int
    var currentPath: String
    var items: [CodableImportBatchSessionItem]

    init(snapshot: ImportBatchSessionSnapshot) {
        repoPath = snapshot.repoPath
        storageMode = snapshot.storageMode
        completed = snapshot.completed
        failed = snapshot.failed
        total = snapshot.total
        currentPath = snapshot.currentPath
        items = snapshot.items.map(CodableImportBatchSessionItem.init(item:))
    }

    var snapshot: ImportBatchSessionSnapshot {
        ImportBatchSessionSnapshot(
            repoPath: repoPath,
            storageMode: storageMode,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            items: items.map(\.snapshotItem)
        )
    }
}

private struct CodableImportBatchSessionItem: Codable {
    var sourcePath: String
    var fileID: Int64?
    var targetPath: String
    var phase: ImportBatchProgressSnapshot.Phase
    var importCommitState: CoreImportCommitState
    var failure: ImportBatchSessionFailureDescriptor?
    var existingRelativePath: String?
    var importConflictBatch: ImportConflictBatchProgressMetadata?

    init(item: ImportBatchProgressSnapshot.Item) {
        sourcePath = item.sourcePath
        fileID = item.fileID
        targetPath = item.targetPath
        phase = item.phase
        importCommitState = item.importCommitState
        failure = item.errorDisplayText.map(ImportBatchSessionFailureDescriptor.init(displayText:))
        existingRelativePath = item.existingRelativePath
        importConflictBatch = item.importConflictBatch
    }

    var snapshotItem: ImportBatchProgressSnapshot.Item {
        ImportBatchProgressSnapshot.Item(
            fileID: fileID,
            sourcePath: sourcePath,
            targetPath: targetPath,
            phase: phase,
            importCommitState: importCommitState,
            errorDisplayText: failure?.displayText,
            existingRelativePath: existingRelativePath,
            importConflictBatch: importConflictBatch
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case fileID
        case targetPath
        case phase
        case importCommitState
        case failure
        case errorDisplayText
        case errorMessage
        case existingRelativePath
        case importConflictBatch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        fileID = try container.decodeIfPresent(Int64.self, forKey: .fileID)
        targetPath = try container.decode(String.self, forKey: .targetPath)
        phase = try container.decode(ImportBatchProgressSnapshot.Phase.self, forKey: .phase)
        importCommitState = try container.decodeIfPresent(
            CoreImportCommitState.self,
            forKey: .importCommitState
        ) ?? .committed
        failure = try container.decodeIfPresent(ImportBatchSessionFailureDescriptor.self, forKey: .failure)
            ?? Self.legacyFailure(from: container)
        existingRelativePath = try container.decodeIfPresent(String.self, forKey: .existingRelativePath)
        importConflictBatch = try container.decodeIfPresent(
            ImportConflictBatchProgressMetadata.self,
            forKey: .importConflictBatch
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encodeIfPresent(fileID, forKey: .fileID)
        try container.encode(targetPath, forKey: .targetPath)
        try container.encode(phase, forKey: .phase)
        try container.encode(importCommitState, forKey: .importCommitState)
        try container.encodeIfPresent(failure, forKey: .failure)
        try container.encodeIfPresent(existingRelativePath, forKey: .existingRelativePath)
        try container.encodeIfPresent(importConflictBatch, forKey: .importConflictBatch)
    }

    private static func legacyFailure(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> ImportBatchSessionFailureDescriptor? {
        if let legacy = try? container.decodeIfPresent(AppDisplayText.self, forKey: .errorDisplayText) {
            return ImportBatchSessionFailureDescriptor(displayText: legacy)
        }
        if let legacy = try? container.decodeIfPresent(String.self, forKey: .errorMessage) {
            return ImportBatchSessionFailureDescriptor(code: .technicalDetail, technicalDetail: legacy)
        }
        return nil
    }
}
