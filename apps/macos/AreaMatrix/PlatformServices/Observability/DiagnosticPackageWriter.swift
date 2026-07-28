import Darwin
import Foundation

private struct DiagnosticPackageDestination {
    let parentPath: String
    let fileName: String
    let url: URL
}

struct DiagnosticPackageWriter {
    private struct PackageDirectory {
        let name: String
        let descriptor: Int32
        let identity: stat
    }

    private let stagingRootURL: URL?
    private let reader: DiagnosticPackageReader
    private let operations: DiagnosticPackagePublishOperations

    init(
        stagingRootURL: URL? = nil,
        reader: DiagnosticPackageReader = DiagnosticPackageReader(),
        operations: DiagnosticPackagePublishOperations = .live
    ) {
        self.stagingRootURL = stagingRootURL ?? Self.defaultStagingRootURL
        self.reader = reader
        self.operations = operations
    }

    func export(_ preview: DiagnosticPackagePreview, to destination: URL) throws -> URL {
        let destination = try destinationComponents(destination)
        let stageRoot = try openStagingRoot()
        defer { close(stageRoot) }
        let stage = try createPackageDirectory(
            parentDescriptor: stageRoot,
            directoryNamePrefix: ".amdiagnostic-stage-"
        )
        defer {
            cleanup(stage, parentDescriptor: stageRoot)
            close(stage.descriptor)
        }

        try writeAndValidate(preview, in: stage, parentDescriptor: stageRoot)
        operations.beforeStageCopy(stage.descriptor)
        return try publish(
            preview,
            stageDescriptor: stage.descriptor,
            destination: destination
        )
    }
}

private extension DiagnosticPackageWriter {
    static var defaultStagingRootURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AreaMatrix", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("Staging", isDirectory: true)
    }

    func publish(
        _ preview: DiagnosticPackagePreview,
        stageDescriptor: Int32,
        destination: DiagnosticPackageDestination
    ) throws -> URL {
        let parentDescriptor = open(
            destination.parentPath,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else { throw DiagnosticPackageError.invalidDestination }
        defer { close(parentDescriptor) }
        try validateDirectory(parentDescriptor, requireCurrentUser: false)
        try ensureDestinationAbsent(named: destination.fileName, parentDescriptor: parentDescriptor)
        return try publishPartial(
            preview,
            stageDescriptor: stageDescriptor,
            destination: destination,
            parentDescriptor: parentDescriptor
        )
    }

    func publishPartial(
        _ preview: DiagnosticPackagePreview,
        stageDescriptor: Int32,
        destination: DiagnosticPackageDestination,
        parentDescriptor: Int32
    ) throws -> URL {
        let partial = try createPackageDirectory(
            parentDescriptor: parentDescriptor,
            directoryNamePrefix: ".amdiagnostic-partial-"
        )
        var shouldCleanup = true
        defer {
            if shouldCleanup { cleanup(partial, parentDescriptor: parentDescriptor) }
            close(partial.descriptor)
        }
        try DiagnosticPackageStageCopier.copy(
            from: stageDescriptor,
            to: partial.descriptor,
            attachments: preview.attachments,
            synchronize: operations.synchronize
        )
        guard operations.synchronize(parentDescriptor) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
        try validateIdentity(partial, parentDescriptor: parentDescriptor)
        try validatePackage(preview, directoryDescriptor: partial.descriptor)
        try renamePartial(
            partial,
            destinationName: destination.fileName,
            parentDescriptor: parentDescriptor
        )
        shouldCleanup = false
        guard operations.synchronize(parentDescriptor) == 0 else {
            throw DiagnosticPackageError.durabilityUncertain
        }
        return destination.url
    }

    private func renamePartial(
        _ partial: PackageDirectory,
        destinationName: String,
        parentDescriptor: Int32
    ) throws {
        let result = operations.renameExclusive(
            parentDescriptor,
            partial.name,
            parentDescriptor,
            destinationName,
            UInt32(RENAME_EXCL)
        )
        guard result == 0 else {
            if errno == EEXIST || errno == ENOTEMPTY {
                throw DiagnosticPackageError.destinationExists
            }
            throw DiagnosticPackageError.invalidDestination
        }
    }

    private func writeAndValidate(
        _ preview: DiagnosticPackagePreview,
        in directory: PackageDirectory,
        parentDescriptor: Int32
    ) throws {
        try writePackage(preview, directoryDescriptor: directory.descriptor)
        guard operations.synchronize(parentDescriptor) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
        try validateIdentity(directory, parentDescriptor: parentDescriptor)
        try validatePackage(preview, directoryDescriptor: directory.descriptor)
    }

    func validatePackage(
        _ preview: DiagnosticPackagePreview,
        directoryDescriptor: Int32
    ) throws {
        let inspection = try reader.inspect(directoryDescriptor: directoryDescriptor)
        guard let expectedSummary = String(data: preview.summaryData, encoding: .utf8) else {
            throw DiagnosticPackageError.invalidPackage
        }
        guard inspection.manifest == preview.manifest,
              inspection.privacyReport == preview.privacyReport,
              inspection.summary == expectedSummary
        else { throw DiagnosticPackageError.invalidPackage }
    }

    func destinationComponents(
        _ destination: URL
    ) throws -> DiagnosticPackageDestination {
        let fileName = destination.lastPathComponent
        guard destination.isFileURL,
              destination.pathExtension == "amdiagnostic",
              !fileName.isEmpty,
              fileName != ".",
              fileName != "..",
              !fileName.contains("/"),
              fileName.utf8.count <= Int(NAME_MAX)
        else { throw DiagnosticPackageError.invalidDestination }
        return DiagnosticPackageDestination(
            parentPath: destination.deletingLastPathComponent().path,
            fileName: fileName,
            url: destination
        )
    }

    func openStagingRoot() throws -> Int32 {
        guard let stagingRootURL, stagingRootURL.isFileURL else {
            throw DiagnosticPackageError.invalidDestination
        }
        try FileManager.default.createDirectory(
            at: stagingRootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if mkdir(stagingRootURL.path, 0o700) != 0, errno != EEXIST {
            throw DiagnosticPackageError.invalidDestination
        }
        let descriptor = open(
            stagingRootURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw DiagnosticPackageError.invalidDestination }
        do {
            try validateDirectory(descriptor, requireCurrentUser: true)
            guard fchmod(descriptor, 0o700) == 0 else {
                throw DiagnosticPackageError.invalidDestination
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    func ensureDestinationAbsent(named name: String, parentDescriptor: Int32) throws {
        var status = stat()
        if fstatat(parentDescriptor, name, &status, AT_SYMLINK_NOFOLLOW) == 0 {
            throw DiagnosticPackageError.destinationExists
        }
        guard errno == ENOENT else { throw DiagnosticPackageError.invalidDestination }
    }

    private func createPackageDirectory(
        parentDescriptor: Int32,
        directoryNamePrefix: String
    ) throws -> PackageDirectory {
        for _ in 0 ..< 3 {
            let name = "\(directoryNamePrefix)\(UUID().uuidString.lowercased()).amdiagnostic"
            guard mkdirat(parentDescriptor, name, 0o700) == 0 else {
                if errno == EEXIST { continue }
                throw DiagnosticPackageError.invalidDestination
            }
            return try openCreatedPackageDirectory(
                named: name,
                parentDescriptor: parentDescriptor
            )
        }
        throw DiagnosticPackageError.invalidDestination
    }

    private func openCreatedPackageDirectory(
        named name: String,
        parentDescriptor: Int32
    ) throws -> PackageDirectory {
        let descriptor = openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            unlinkat(parentDescriptor, name, AT_REMOVEDIR)
            throw DiagnosticPackageError.invalidDestination
        }
        do {
            try validateDirectory(descriptor, requireCurrentUser: true)
            var identity = stat()
            guard fstat(descriptor, &identity) == 0 else {
                throw DiagnosticPackageError.invalidDestination
            }
            return PackageDirectory(name: name, descriptor: descriptor, identity: identity)
        } catch {
            close(descriptor)
            unlinkat(parentDescriptor, name, AT_REMOVEDIR)
            throw error
        }
    }

    private func validateIdentity(
        _ directory: PackageDirectory,
        parentDescriptor: Int32
    ) throws {
        var current = stat()
        guard fstatat(parentDescriptor, directory.name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_mode & S_IFMT == S_IFDIR,
              current.st_dev == directory.identity.st_dev,
              current.st_ino == directory.identity.st_ino
        else { throw DiagnosticPackageError.unsafeFile }
    }

    func validateDirectory(_ descriptor: Int32, requireCurrentUser: Bool) throws {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_flags & UInt32(SF_DATALESS) == 0,
              !requireCurrentUser || status.st_uid == geteuid()
        else { throw DiagnosticPackageError.invalidDestination }
    }

    func writePackage(
        _ preview: DiagnosticPackagePreview,
        directoryDescriptor: Int32
    ) throws {
        for payload in preview.filePayloads.prefix(DiagnosticPackageFormat.payloadFileNames.count) {
            try writeExclusive(payload.data, named: payload.name, directoryDescriptor: directoryDescriptor)
        }
        let attachments = try createDirectory(
            named: DiagnosticPackageFormat.attachmentsDirectoryName,
            parentDescriptor: directoryDescriptor
        )
        defer { close(attachments) }
        if !preview.attachments.isEmpty {
            try writeMetadataAttachments(preview.attachments, attachmentsDescriptor: attachments)
        }
        guard operations.synchronize(attachments) == 0,
              operations.synchronize(directoryDescriptor) == 0
        else { throw DiagnosticPackageError.invalidDestination }
    }

    func writeMetadataAttachments(
        _ attachments: [DiagnosticPackageAttachmentPayload],
        attachmentsDescriptor: Int32
    ) throws {
        let metadata = try createDirectory(
            named: DiagnosticPackageFormat.repositoryMetadataDirectoryName,
            parentDescriptor: attachmentsDescriptor
        )
        defer { close(metadata) }
        for payload in attachments {
            guard let name = DiagnosticPackageFormat.repositoryMetadataFileNames.first(where: {
                DiagnosticPackageFormat.metadataRelativePath($0) == payload.relativePath
            }) else { throw DiagnosticPackageError.invalidPackage }
            try writeExclusive(payload.data, named: name, directoryDescriptor: metadata)
        }
        guard operations.synchronize(metadata) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
    }

    func createDirectory(named name: String, parentDescriptor: Int32) throws -> Int32 {
        guard mkdirat(parentDescriptor, name, 0o700) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
        let descriptor = openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw DiagnosticPackageError.invalidDestination }
        do {
            try validateDirectory(descriptor, requireCurrentUser: true)
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    func writeExclusive(
        _ data: Data,
        named name: String,
        directoryDescriptor: Int32
    ) throws {
        let descriptor = openat(
            directoryDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0 else { throw DiagnosticPackageError.invalidDestination }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_nlink == 1,
              status.st_uid == geteuid()
        else { throw DiagnosticPackageError.unsafeFile }
        try writeAll(data, descriptor: descriptor)
        guard operations.synchronize(descriptor) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
    }

    func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw DiagnosticPackageError.invalidDestination }
                offset += count
            }
        }
    }

    private func cleanup(_ directory: PackageDirectory, parentDescriptor: Int32) {
        for fileName in DiagnosticPackageFormat.payloadFileNames {
            unlinkat(directory.descriptor, fileName, 0)
        }
        cleanupAttachments(directoryDescriptor: directory.descriptor)
        unlinkat(
            directory.descriptor,
            DiagnosticPackageFormat.attachmentsDirectoryName,
            AT_REMOVEDIR
        )
        guard (try? validateIdentity(directory, parentDescriptor: parentDescriptor)) != nil else {
            return
        }
        unlinkat(parentDescriptor, directory.name, AT_REMOVEDIR)
        _ = operations.synchronize(parentDescriptor)
    }

    func cleanupAttachments(directoryDescriptor: Int32) {
        let attachments = openat(
            directoryDescriptor,
            DiagnosticPackageFormat.attachmentsDirectoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard attachments >= 0 else { return }
        defer { close(attachments) }
        let metadata = openat(
            attachments,
            DiagnosticPackageFormat.repositoryMetadataDirectoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard metadata >= 0 else { return }
        for fileName in DiagnosticPackageFormat.repositoryMetadataFileNames {
            unlinkat(metadata, fileName, 0)
        }
        close(metadata)
        unlinkat(
            attachments,
            DiagnosticPackageFormat.repositoryMetadataDirectoryName,
            AT_REMOVEDIR
        )
    }
}
