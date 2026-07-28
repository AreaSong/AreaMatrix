import Darwin
import Foundation

enum DiagnosticPackageStageCopier {
    static func copy(
        from sourceDirectory: Int32,
        to destinationDirectory: Int32,
        attachments: [DiagnosticPackageAttachmentPayload],
        synchronize: (Int32) -> Int32
    ) throws {
        for name in DiagnosticPackageFormat.payloadFileNames {
            guard let limit = DiagnosticPackageFormat.fileByteLimits[name] else {
                throw DiagnosticPackageError.invalidPackage
            }
            try copyFile(
                named: name,
                from: sourceDirectory,
                to: destinationDirectory,
                byteLimit: Int64(limit),
                synchronize: synchronize
            )
        }
        try copyAttachments(
            from: sourceDirectory,
            to: destinationDirectory,
            attachments: attachments,
            synchronize: synchronize
        )
        guard synchronize(destinationDirectory) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
    }
}

private extension DiagnosticPackageStageCopier {
    static let bufferSize = 64 * 1024

    static func copyAttachments(
        from sourceDirectory: Int32,
        to destinationDirectory: Int32,
        attachments: [DiagnosticPackageAttachmentPayload],
        synchronize: (Int32) -> Int32
    ) throws {
        let sourceAttachments = try openDirectory(
            named: DiagnosticPackageFormat.attachmentsDirectoryName,
            parentDescriptor: sourceDirectory
        )
        defer { close(sourceAttachments) }
        let destinationAttachments = try createDirectory(
            named: DiagnosticPackageFormat.attachmentsDirectoryName,
            parentDescriptor: destinationDirectory
        )
        defer { close(destinationAttachments) }

        if !attachments.isEmpty {
            try copyMetadataAttachments(
                from: sourceAttachments,
                to: destinationAttachments,
                attachments: attachments,
                synchronize: synchronize
            )
        }
        guard synchronize(destinationAttachments) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
    }

    static func copyMetadataAttachments(
        from sourceAttachments: Int32,
        to destinationAttachments: Int32,
        attachments: [DiagnosticPackageAttachmentPayload],
        synchronize: (Int32) -> Int32
    ) throws {
        let sourceMetadata = try openDirectory(
            named: DiagnosticPackageFormat.repositoryMetadataDirectoryName,
            parentDescriptor: sourceAttachments
        )
        defer { close(sourceMetadata) }
        let destinationMetadata = try createDirectory(
            named: DiagnosticPackageFormat.repositoryMetadataDirectoryName,
            parentDescriptor: destinationAttachments
        )
        defer { close(destinationMetadata) }

        var copiedNames = Set<String>()
        for attachment in attachments {
            guard let name = DiagnosticPackageFormat.repositoryMetadataFileNames.first(where: {
                DiagnosticPackageFormat.metadataRelativePath($0) == attachment.relativePath
            }), copiedNames.insert(name).inserted else {
                throw DiagnosticPackageError.invalidPackage
            }
            try copyFile(
                named: name,
                from: sourceMetadata,
                to: destinationMetadata,
                byteLimit: Int64(DiagnosticPackageFormat.maximumMetadataFileBytes),
                synchronize: synchronize
            )
        }
        guard synchronize(destinationMetadata) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
    }

    static func copyFile(
        named name: String,
        from sourceDirectory: Int32,
        to destinationDirectory: Int32,
        byteLimit: Int64,
        synchronize: (Int32) -> Int32
    ) throws {
        let source = openat(sourceDirectory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard source >= 0 else { throw DiagnosticPackageError.unsafeFile }
        defer { close(source) }
        let sourceIdentity = try validatedRegularFile(source, byteLimit: byteLimit)

        let destination = openat(
            destinationDirectory,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard destination >= 0 else { throw DiagnosticPackageError.invalidDestination }
        defer { close(destination) }
        _ = try validatedRegularFile(destination, byteLimit: byteLimit)

        try copyBytes(
            from: source,
            to: destination,
            expectedByteCount: sourceIdentity.st_size,
            byteLimit: byteLimit
        )
        guard synchronize(destination) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
        let finalSourceIdentity = try validatedRegularFile(source, byteLimit: byteLimit)
        guard sameIdentityAndContents(sourceIdentity, finalSourceIdentity) else {
            throw DiagnosticPackageError.unsafeFile
        }
        let destinationIdentity = try validatedRegularFile(destination, byteLimit: byteLimit)
        guard destinationIdentity.st_size == sourceIdentity.st_size else {
            throw DiagnosticPackageError.invalidPackage
        }
    }

    static func copyBytes(
        from source: Int32,
        to destination: Int32,
        expectedByteCount: Int64,
        byteLimit: Int64
    ) throws {
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var total: Int64 = 0
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(source, $0.baseAddress, $0.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw DiagnosticPackageError.unsafeFile }
            if count == 0 { break }
            let (nextTotal, overflow) = total.addingReportingOverflow(Int64(count))
            guard !overflow, nextTotal <= byteLimit, nextTotal <= expectedByteCount else {
                throw DiagnosticPackageError.limitExceeded
            }
            try buffer.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                try writeAll(baseAddress, count: count, descriptor: destination)
            }
            total = nextTotal
        }
        guard total == expectedByteCount else { throw DiagnosticPackageError.unsafeFile }
    }

    static func writeAll(_ baseAddress: UnsafeRawPointer, count: Int, descriptor: Int32) throws {
        var offset = 0
        while offset < count {
            let written = Darwin.write(descriptor, baseAddress.advanced(by: offset), count - offset)
            if written < 0, errno == EINTR { continue }
            guard written > 0 else { throw DiagnosticPackageError.invalidDestination }
            offset += written
        }
    }

    static func openDirectory(named name: String, parentDescriptor: Int32) throws -> Int32 {
        let descriptor = openat(parentDescriptor, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw DiagnosticPackageError.unsafeFile }
        do {
            try validateDirectory(descriptor)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    static func createDirectory(named name: String, parentDescriptor: Int32) throws -> Int32 {
        guard mkdirat(parentDescriptor, name, 0o700) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
        let descriptor = openat(parentDescriptor, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw DiagnosticPackageError.invalidDestination }
        do {
            try validateDirectory(descriptor)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    static func validateDirectory(_ descriptor: Int32) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_uid == geteuid(),
              status.st_flags & UInt32(SF_DATALESS) == 0
        else { throw DiagnosticPackageError.unsafeFile }
    }

    static func validatedRegularFile(_ descriptor: Int32, byteLimit: Int64) throws -> stat {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_nlink == 1,
              status.st_uid == geteuid(),
              status.st_flags & UInt32(SF_DATALESS) == 0,
              status.st_size >= 0,
              status.st_size <= byteLimit
        else { throw DiagnosticPackageError.unsafeFile }
        return status
    }

    static func sameIdentityAndContents(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev &&
            lhs.st_ino == rhs.st_ino &&
            lhs.st_size == rhs.st_size &&
            lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec &&
            lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec &&
            lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec &&
            lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
