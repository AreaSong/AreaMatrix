import Darwin
import Foundation

protocol RepositoryMetadataSnapshotCapturing {
    func capture(repositoryURL: URL) throws -> [DiagnosticPackageAttachmentPayload]
}

struct RepositoryMetadataSnapshotCapture: RepositoryMetadataSnapshotCapturing {
    typealias AfterReadHook = (_ fileName: String) throws -> Void

    private struct CapturedFile {
        let name: String
        let data: Data
        let initialStatus: stat
    }

    private let afterReadHook: AfterReadHook
    private let maximumFileBytes: Int
    private let maximumTotalBytes: Int

    init(
        maximumFileBytes: Int = DiagnosticPackageFormat.maximumMetadataFileBytes,
        maximumTotalBytes: Int = DiagnosticPackageFormat.maximumMetadataBytes,
        afterReadHook: @escaping AfterReadHook = { _ in }
    ) {
        self.maximumFileBytes = maximumFileBytes
        self.maximumTotalBytes = maximumTotalBytes
        self.afterReadHook = afterReadHook
    }

    func capture(repositoryURL: URL) throws -> [DiagnosticPackageAttachmentPayload] {
        guard repositoryURL.isFileURL else { throw DiagnosticPackageError.unsafeFile }
        let repositoryDescriptor = try openDirectory(path: repositoryURL.standardizedFileURL.path)
        defer { close(repositoryDescriptor) }
        let metadataDescriptor = try openMetadataDirectory(repositoryDescriptor: repositoryDescriptor)
        defer { close(metadataDescriptor) }

        let initialDirectoryStatus = try directoryStatus(metadataDescriptor)
        var files: [CapturedFile] = []
        var totalBytes = 0
        for (index, fileName) in DiagnosticPackageFormat.repositoryMetadataFileNames.enumerated() {
            let fileURL = repositoryURL
                .appendingPathComponent(".areamatrix", isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false)
            guard let file = try captureFile(
                named: fileName,
                fileURL: fileURL,
                directoryDescriptor: metadataDescriptor,
                required: index == 0
            ) else { continue }
            totalBytes += file.data.count
            guard totalBytes <= maximumTotalBytes else {
                throw DiagnosticPackageError.limitExceeded
            }
            files.append(file)
        }
        try validateFinalState(
            files: files,
            initialDirectoryStatus: initialDirectoryStatus,
            directoryDescriptor: metadataDescriptor
        )
        return files.map {
            DiagnosticPackageAttachmentPayload(
                relativePath: DiagnosticPackageFormat.metadataRelativePath($0.name),
                data: $0.data
            )
        }
    }

    private func openDirectory(path: String) throws -> Int32 {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw DiagnosticPackageError.unsafeFile }
        do {
            try validateDirectory(descriptor)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func openMetadataDirectory(repositoryDescriptor: Int32) throws -> Int32 {
        let descriptor = openat(
            repositoryDescriptor,
            ".areamatrix",
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

    private func captureFile(
        named name: String,
        fileURL: URL,
        directoryDescriptor: Int32,
        required: Bool
    ) throws -> CapturedFile? {
        guard try preflightFile(named: name, directoryDescriptor: directoryDescriptor, required: required) else {
            return nil
        }
        try rejectPlaceholder(fileURL)
        let descriptor = openat(
            directoryDescriptor,
            name,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw DiagnosticPackageError.unsafeFile }
        defer { close(descriptor) }
        let initial = try regularFileStatus(descriptor)
        let data = try readBounded(descriptor, expectedSize: initial.st_size)
        try afterReadHook(name)
        let final = try regularFileStatus(descriptor)
        let finalPath = try regularFileStatus(named: name, directoryDescriptor: directoryDescriptor)
        guard isStable(initial: initial, final: final, byteCount: data.count),
              isStable(initial: initial, final: finalPath, byteCount: data.count)
        else {
            throw DiagnosticPackageError.unsafeFile
        }
        return CapturedFile(name: name, data: data, initialStatus: initial)
    }

    private func preflightFile(
        named name: String,
        directoryDescriptor: Int32,
        required: Bool
    ) throws -> Bool {
        var status = stat()
        if fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) != 0 {
            if !required, errno == ENOENT { return false }
            throw DiagnosticPackageError.unsafeFile
        }
        try validateRegularFile(status)
        return true
    }

    private func regularFileStatus(_ descriptor: Int32) throws -> stat {
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw DiagnosticPackageError.unsafeFile }
        try validateRegularFile(status)
        return status
    }

    private func regularFileStatus(named name: String, directoryDescriptor: Int32) throws -> stat {
        var status = stat()
        guard fstatat(directoryDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw DiagnosticPackageError.unsafeFile
        }
        try validateRegularFile(status)
        return status
    }

    private func validateRegularFile(_ status: stat) throws {
        guard status.st_mode & S_IFMT == S_IFREG,
              status.st_nlink == 1,
              status.st_size >= 0,
              status.st_flags & UInt32(SF_DATALESS) == 0
        else { throw DiagnosticPackageError.unsafeFile }
        guard status.st_size <= off_t(maximumFileBytes) else {
            throw DiagnosticPackageError.limitExceeded
        }
    }

    private func validateDirectory(_ descriptor: Int32) throws {
        _ = try directoryStatus(descriptor)
    }

    private func directoryStatus(_ descriptor: Int32) throws -> stat {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_flags & UInt32(SF_DATALESS) == 0
        else { throw DiagnosticPackageError.unsafeFile }
        return status
    }

    private func rejectPlaceholder(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])
        guard values.isUbiquitousItem != true || values.ubiquitousItemDownloadingStatus != .notDownloaded else {
            throw DiagnosticPackageError.unsafeFile
        }
    }

    private func readBounded(_ descriptor: Int32, expectedSize: off_t) throws -> Data {
        var data = Data()
        data.reserveCapacity(Int(expectedSize))
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw DiagnosticPackageError.unsafeFile }
            guard count > 0 else { return data }
            guard count <= maximumFileBytes - data.count else {
                throw DiagnosticPackageError.limitExceeded
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private func isStable(initial: stat, final: stat, byteCount: Int) -> Bool {
        initial.st_dev == final.st_dev &&
            initial.st_ino == final.st_ino &&
            initial.st_size == final.st_size &&
            initial.st_size == off_t(byteCount) &&
            initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec &&
            initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec &&
            initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec &&
            initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec
    }

    private func validateFinalState(
        files: [CapturedFile],
        initialDirectoryStatus: stat,
        directoryDescriptor: Int32
    ) throws {
        let finalDirectoryStatus = try directoryStatus(directoryDescriptor)
        guard sameIdentityAndTimes(initialDirectoryStatus, finalDirectoryStatus) else {
            throw DiagnosticPackageError.unsafeFile
        }
        for file in files {
            let final = try regularFileStatus(named: file.name, directoryDescriptor: directoryDescriptor)
            guard isStable(initial: file.initialStatus, final: final, byteCount: file.data.count) else {
                throw DiagnosticPackageError.unsafeFile
            }
        }
    }

    private func sameIdentityAndTimes(_ initial: stat, _ final: stat) -> Bool {
        initial.st_dev == final.st_dev &&
            initial.st_ino == final.st_ino &&
            initial.st_size == final.st_size &&
            initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec &&
            initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec &&
            initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec &&
            initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec
    }
}
