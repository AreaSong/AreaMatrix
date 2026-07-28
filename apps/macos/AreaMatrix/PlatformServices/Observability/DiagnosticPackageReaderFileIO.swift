import Darwin
import Foundation

extension DiagnosticPackageReader {
    func openDirectory(named name: String, parentDescriptor: Int32) throws -> Int32 {
        let descriptor = openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw DiagnosticPackageError.unsafeFile }
        do {
            try validateDirectory(descriptor)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    func validateDirectory(_ descriptor: Int32) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_flags & UInt32(SF_DATALESS) == 0
        else { throw DiagnosticPackageError.unsafeFile }
    }

    func readRegularFile(
        named name: String,
        directoryDescriptor: Int32,
        limit: Int
    ) throws -> Data {
        try preflightRegularFile(named: name, directoryDescriptor: directoryDescriptor, limit: limit)
        let descriptor = openat(
            directoryDescriptor,
            name,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw DiagnosticPackageError.unsafeFile }
        defer { close(descriptor) }
        let initial = try regularFileStatus(descriptor, limit: limit)
        let data = try readBounded(descriptor: descriptor, limit: limit)
        let final = try regularFileStatus(descriptor, limit: limit)
        let finalPath = try regularFileStatus(
            named: name,
            directoryDescriptor: directoryDescriptor,
            limit: limit
        )
        guard isStable(initial: initial, final: final, byteCount: data.count),
              isStable(initial: initial, final: finalPath, byteCount: data.count)
        else {
            throw DiagnosticPackageError.unsafeFile
        }
        return data
    }

    func directoryEntryNames(descriptor: Int32, maximumCount: Int) throws -> Set<String> {
        let duplicate = dup(descriptor)
        guard duplicate >= 0 else { throw DiagnosticPackageError.unsafeFile }
        guard let directory = fdopendir(duplicate) else {
            close(duplicate)
            throw DiagnosticPackageError.unsafeFile
        }
        defer { closedir(directory) }
        var names: Set<String> = []
        errno = 0
        while let entry = readdir(directory) {
            guard let name = directoryEntryName(entry) else { throw DiagnosticPackageError.unsafeFile }
            guard name != ".", name != ".." else { continue }
            names.insert(name)
            guard names.count <= maximumCount else { throw DiagnosticPackageError.unexpectedEntry }
        }
        guard errno == 0 else { throw DiagnosticPackageError.unsafeFile }
        return names
    }
}

private extension DiagnosticPackageReader {
    func preflightRegularFile(
        named name: String,
        directoryDescriptor: Int32,
        limit: Int
    ) throws {
        var status = stat()
        guard fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw DiagnosticPackageError.unsafeFile
        }
        try validateRegularFile(status, limit: limit)
    }

    func regularFileStatus(_ descriptor: Int32, limit: Int) throws -> stat {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw DiagnosticPackageError.unsafeFile }
        try validateRegularFile(status, limit: limit)
        return status
    }

    func regularFileStatus(
        named name: String,
        directoryDescriptor: Int32,
        limit: Int
    ) throws -> stat {
        var status = stat()
        guard fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw DiagnosticPackageError.unsafeFile
        }
        try validateRegularFile(status, limit: limit)
        return status
    }

    func validateRegularFile(_ status: stat, limit: Int) throws {
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_nlink == 1,
              status.st_size >= 0,
              status.st_flags & UInt32(SF_DATALESS) == 0
        else { throw DiagnosticPackageError.unsafeFile }
        guard status.st_size <= off_t(limit) else { throw DiagnosticPackageError.limitExceeded }
    }

    func isStable(initial: stat, final: stat, byteCount: Int) -> Bool {
        initial.st_dev == final.st_dev &&
            initial.st_ino == final.st_ino &&
            initial.st_size == final.st_size &&
            initial.st_size == off_t(byteCount) &&
            initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec &&
            initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec &&
            initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec &&
            initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec
    }

    func readBounded(descriptor: Int32, limit: Int) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw DiagnosticPackageError.unsafeFile }
            guard count > 0 else { return data }
            guard count <= limit - data.count else { throw DiagnosticPackageError.limitExceeded }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    func directoryEntryName(_ entry: UnsafeMutablePointer<dirent>) -> String? {
        withUnsafePointer(to: entry.pointee.d_name) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                String(validatingUTF8: $0)
            }
        }
    }
}
