import Darwin
import Foundation

enum ObservabilityOwnedFileKind: Equatable {
    case event
    case incident(id: String)
    case manifest
    case sessionMarker

    var relativeDirectory: String? {
        if case .incident = self { return "incidents" }
        return nil
    }

    func accepts(_ name: String) -> Bool {
        switch self {
        case .event:
            guard name.hasPrefix("events-"), name.hasSuffix(".jsonl") else { return false }
            let sequence = name.dropFirst("events-".count).dropLast(".jsonl".count)
            return Self.isSafeName(name) && sequence.count == 20 && sequence.allSatisfy {
                $0.isASCII && $0.isNumber
            }
        case let .incident(id):
            return Self.isSafeIdentifier(id) && name == "incident-\(id).jsonl"
        case .manifest:
            return name == "manifest.json"
        case .sessionMarker:
            return name == "session-marker.json"
        }
    }

    static func isSafeIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isSafeName(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255, !value.contains("/") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

enum ObservabilitySafeFileError: Error, Equatable {
    case createFailed
    case invalidName
    case missing
    case openFailed
    case permissionsFailed
    case tooLarge
    case unsafePath
    case writeFailed
}

enum ObservabilityAtomicReplaceResult: Equatable {
    case durable
    case replacedDurabilityUncertain
}

struct ObservabilityAtomicReplaceOperations {
    let synchronize: @Sendable (Int32) -> Int32
    let rename: @Sendable (Int32, String, Int32, String) -> Int32

    static let live = Self(
        synchronize: { Darwin.fsync($0) },
        rename: { sourceDirectory, source, targetDirectory, target in
            Darwin.renameat(sourceDirectory, source, targetDirectory, target)
        }
    )
}

/// Anchors observability-owned reads, replacements, and removals to an opened Logs directory.
struct ObservabilitySafeFileOperations {
    let rootURL: URL
    private let atomicReplaceOperations: ObservabilityAtomicReplaceOperations

    init(rootURL: URL) {
        self.init(rootURL: rootURL, atomicReplaceOperations: .live)
    }

    init(
        rootURL: URL,
        atomicReplaceOperations: ObservabilityAtomicReplaceOperations
    ) {
        self.rootURL = rootURL
        self.atomicReplaceOperations = atomicReplaceOperations
    }

    func prepareDirectories(includeIncidents: Bool = true) throws {
        guard rootURL.isFileURL else { throw ObservabilitySafeFileError.unsafePath }
        try FileManager.default.createDirectory(
            at: rootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try ensureDirectory(at: rootURL)
        if includeIncidents {
            try ensureDirectory(at: rootURL.appendingPathComponent("incidents", isDirectory: true))
        }
    }

    func read(_ name: String, kind: ObservabilityOwnedFileKind, maximumBytes: Int) throws -> Data {
        guard maximumBytes >= 0 else { throw ObservabilitySafeFileError.tooLarge }
        return try withDirectoryDescriptor(for: kind) { directoryFD in
            try validate(name, kind: kind)
            let descriptor = openat(directoryFD, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            guard descriptor >= 0 else {
                if errno == ENOENT { throw ObservabilitySafeFileError.missing }
                throw ObservabilitySafeFileError.openFailed
            }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                let metadata = try validatedRegularFile(descriptor)
                guard metadata.st_size >= 0,
                      metadata.st_size <= off_t(maximumBytes)
                else { throw ObservabilitySafeFileError.tooLarge }
                let data = try handle.readToEnd() ?? Data()
                try handle.close()
                return data
            } catch {
                try? handle.close()
                throw error
            }
        }
    }

    func readPrefix(
        _ name: String,
        kind: ObservabilityOwnedFileKind,
        byteCount: Int64
    ) throws -> Data {
        guard byteCount >= 0, byteCount <= Int64(Int.max) else {
            throw ObservabilitySafeFileError.tooLarge
        }
        return try withDirectoryDescriptor(for: kind) { directoryFD in
            try validate(name, kind: kind)
            let descriptor = openat(directoryFD, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            guard descriptor >= 0 else { throw ObservabilitySafeFileError.openFailed }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                let metadata = try validatedRegularFile(descriptor)
                guard metadata.st_size >= byteCount else { throw ObservabilitySafeFileError.tooLarge }
                let data = try readExactly(Int(byteCount), from: handle)
                try handle.close()
                return data
            } catch {
                try? handle.close()
                throw error
            }
        }
    }

    func createExclusive(_ name: String, kind: ObservabilityOwnedFileKind) throws -> FileHandle {
        try withDirectoryDescriptor(for: kind) { directoryFD in
            try validate(name, kind: kind)
            let descriptor = openat(
                directoryFD,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                0o600
            )
            guard descriptor >= 0 else { throw ObservabilitySafeFileError.createFailed }
            do {
                _ = try validatedRegularFile(descriptor)
                guard fchmod(descriptor, 0o600) == 0 else {
                    throw ObservabilitySafeFileError.permissionsFailed
                }
                guard fsync(directoryFD) == 0 else {
                    throw ObservabilitySafeFileError.writeFailed
                }
                return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            } catch {
                close(descriptor)
                _ = unlinkat(directoryFD, name, 0)
                throw error
            }
        }
    }

    func appendAndSynchronize(
        _ data: Data,
        name: String,
        kind: ObservabilityOwnedFileKind,
        expectedSize: Int64,
        synchronize: (Int32) throws -> Void
    ) throws -> Int64 {
        guard expectedSize >= 0,
              let byteCount = Int64(exactly: data.count),
              !expectedSize.addingReportingOverflow(byteCount).overflow
        else { throw ObservabilitySafeFileError.tooLarge }
        let finalSize = expectedSize + byteCount
        return try withDirectoryDescriptor(for: kind) { directoryFD in
            try validate(name, kind: kind)
            let descriptor = openat(
                directoryFD,
                name,
                O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
            guard descriptor >= 0 else { throw ObservabilitySafeFileError.openFailed }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                let metadata = try validatedRegularFile(descriptor)
                guard metadata.st_size == expectedSize else {
                    throw ObservabilitySafeFileError.unsafePath
                }
                guard fchmod(descriptor, 0o600) == 0 else {
                    throw ObservabilitySafeFileError.permissionsFailed
                }
                try handle.write(contentsOf: data)
                try synchronize(descriptor)
                let finalMetadata = try validatedRegularFile(descriptor)
                guard finalMetadata.st_size == finalSize else {
                    throw ObservabilitySafeFileError.writeFailed
                }
                try handle.close()
                return finalSize
            } catch {
                try? handle.close()
                throw error
            }
        }
    }

    func truncate(
        _ name: String,
        kind: ObservabilityOwnedFileKind,
        to byteCount: Int64
    ) throws {
        guard byteCount >= 0 else { throw ObservabilitySafeFileError.tooLarge }
        try withDirectoryDescriptor(for: kind) { directoryFD in
            try validate(name, kind: kind)
            let descriptor = openat(
                directoryFD,
                name,
                O_WRONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
            guard descriptor >= 0 else { throw ObservabilitySafeFileError.openFailed }
            defer { close(descriptor) }
            let metadata = try validatedRegularFile(descriptor)
            guard metadata.st_size >= byteCount else { throw ObservabilitySafeFileError.tooLarge }
            guard ftruncate(descriptor, byteCount) == 0,
                  fsync(descriptor) == 0,
                  try validatedRegularFile(descriptor).st_size == byteCount
            else { throw ObservabilitySafeFileError.writeFailed }
        }
    }

    func replaceAtomically(
        _ data: Data,
        name: String,
        kind: ObservabilityOwnedFileKind
    ) throws -> ObservabilityAtomicReplaceResult {
        try prepareDirectories(includeIncidents: kind.relativeDirectory != nil)
        return try withDirectoryDescriptor(for: kind) { directoryFD in
            try validate(name, kind: kind)
            try validateExistingTarget(name, directoryFD: directoryFD)
            let temporaryName = ".session-\(UUID().uuidString.lowercased()).tmp"
            let descriptor = openat(
                directoryFD,
                temporaryName,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                0o600
            )
            guard descriptor >= 0 else { throw ObservabilitySafeFileError.createFailed }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var temporaryExists = true
            defer {
                try? handle.close()
                if temporaryExists { _ = unlinkat(directoryFD, temporaryName, 0) }
            }
            do {
                guard fchmod(descriptor, 0o600) == 0 else {
                    throw ObservabilitySafeFileError.permissionsFailed
                }
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
                guard atomicReplaceOperations.rename(
                    directoryFD,
                    temporaryName,
                    directoryFD,
                    name
                ) == 0 else { throw ObservabilitySafeFileError.writeFailed }
                temporaryExists = false
                guard atomicReplaceOperations.synchronize(directoryFD) == 0 else {
                    return .replacedDurabilityUncertain
                }
                return .durable
            } catch {
                throw error
            }
        }
    }

    func remove(_ name: String, kind: ObservabilityOwnedFileKind) throws {
        try withDirectoryDescriptor(for: kind) { directoryFD in
            try validate(name, kind: kind)
            _ = try validatedRegularFile(named: name, directoryFD: directoryFD)
            guard unlinkat(directoryFD, name, 0) == 0 else {
                if errno == ENOENT { throw ObservabilitySafeFileError.missing }
                throw ObservabilitySafeFileError.writeFailed
            }
            guard fsync(directoryFD) == 0 else { throw ObservabilitySafeFileError.writeFailed }
        }
    }

    func metadata(_ name: String, kind: ObservabilityOwnedFileKind) throws -> stat {
        try withDirectoryDescriptor(for: kind) { directoryFD in
            try validate(name, kind: kind)
            return try validatedRegularFile(named: name, directoryFD: directoryFD)
        }
    }
}

private extension ObservabilitySafeFileOperations {
    func readExactly(_ byteCount: Int, from handle: FileHandle) throws -> Data {
        var output = Data()
        while output.count < byteCount {
            let remaining = byteCount - output.count
            guard let chunk = try handle.read(upToCount: min(remaining, 64 * 1024)),
                  !chunk.isEmpty
            else { throw ObservabilitySafeFileError.openFailed }
            output.append(chunk)
        }
        return output
    }

    func withDirectoryDescriptor<T>(
        for kind: ObservabilityOwnedFileKind,
        _ operation: (Int32) throws -> T
    ) throws -> T {
        let rootFD = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard rootFD >= 0 else {
            if errno == ENOENT { throw ObservabilitySafeFileError.missing }
            throw ObservabilitySafeFileError.openFailed
        }
        defer { close(rootFD) }
        try validateDirectory(rootFD)
        guard let component = kind.relativeDirectory else { return try operation(rootFD) }
        let directoryFD = openat(
            rootFD,
            component,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard directoryFD >= 0 else {
            if errno == ENOENT { throw ObservabilitySafeFileError.missing }
            throw ObservabilitySafeFileError.openFailed
        }
        defer { close(directoryFD) }
        try validateDirectory(directoryFD)
        return try operation(directoryFD)
    }

    func ensureDirectory(at url: URL) throws {
        if mkdir(url.path, 0o700) != 0, errno != EEXIST {
            throw ObservabilitySafeFileError.createFailed
        }
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw ObservabilitySafeFileError.openFailed }
        defer { close(descriptor) }
        try validateDirectory(descriptor)
        guard fchmod(descriptor, 0o700) == 0 else {
            throw ObservabilitySafeFileError.permissionsFailed
        }
    }

    func validate(_ name: String, kind: ObservabilityOwnedFileKind) throws {
        guard kind.accepts(name) else { throw ObservabilitySafeFileError.invalidName }
    }

    func validateExistingTarget(_ name: String, directoryFD: Int32) throws {
        var metadata = stat()
        if fstatat(directoryFD, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
            try validateOwnedMetadata(metadata)
            return
        }
        guard errno == ENOENT else { throw ObservabilitySafeFileError.unsafePath }
    }

    func validatedRegularFile(named name: String, directoryFD: Int32) throws -> stat {
        var metadata = stat()
        guard fstatat(directoryFD, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else {
            if errno == ENOENT { throw ObservabilitySafeFileError.missing }
            throw ObservabilitySafeFileError.openFailed
        }
        try validateOwnedMetadata(metadata)
        return metadata
    }

    func validatedRegularFile(_ descriptor: Int32) throws -> stat {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw ObservabilitySafeFileError.openFailed }
        try validateOwnedMetadata(metadata)
        return metadata
    }

    func validateOwnedMetadata(_ metadata: stat) throws {
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_nlink == 1,
              metadata.st_uid == geteuid()
        else { throw ObservabilitySafeFileError.unsafePath }
    }

    func validateDirectory(_ descriptor: Int32) throws {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              metadata.st_uid == geteuid()
        else { throw ObservabilitySafeFileError.unsafePath }
    }
}
