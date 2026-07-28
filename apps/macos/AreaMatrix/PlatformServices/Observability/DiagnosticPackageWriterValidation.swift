import Darwin
import Foundation

extension DiagnosticPackageWriter {
    func previewPayloads(_ preview: DiagnosticPackagePreview) throws -> [String: Data] {
        var payloads: [String: Data] = [:]
        for payload in preview.filePayloads.prefix(DiagnosticPackageFormat.payloadFileNames.count) {
            guard DiagnosticPackageFormat.payloadFileNames.contains(payload.name),
                  payloads.updateValue(payload.data, forKey: payload.name) == nil
            else { throw DiagnosticPackageError.invalidPackage }
        }
        guard Set(payloads.keys) == Set(DiagnosticPackageFormat.payloadFileNames) else {
            throw DiagnosticPackageError.invalidPackage
        }
        for attachment in preview.attachments {
            guard payloads.updateValue(attachment.data, forKey: attachment.relativePath) == nil else {
                throw DiagnosticPackageError.invalidPackage
            }
        }
        return payloads
    }

    func captureDestinationParentIdentity(path: String, descriptor: Int32) throws -> stat {
        var identity = stat()
        guard fstat(descriptor, &identity) == 0 else {
            throw DiagnosticPackageError.invalidDestination
        }
        try validateDestinationParentIdentity(
            path: path,
            descriptor: descriptor,
            expected: identity
        )
        return identity
    }

    func validateDestinationParentIdentity(
        path: String,
        descriptor: Int32,
        expected: stat
    ) throws {
        var descriptorIdentity = stat()
        var pathIdentity = stat()
        guard fstat(descriptor, &descriptorIdentity) == 0,
              lstat(path, &pathIdentity) == 0,
              descriptorIdentity.st_mode & S_IFMT == S_IFDIR,
              pathIdentity.st_mode & S_IFMT == S_IFDIR,
              descriptorIdentity.st_dev == expected.st_dev,
              descriptorIdentity.st_ino == expected.st_ino,
              pathIdentity.st_dev == expected.st_dev,
              pathIdentity.st_ino == expected.st_ino
        else { throw DiagnosticPackageError.invalidDestination }
    }
}

final class DiagnosticPackageCleanupOwnership {
    struct Entry {
        let relativePath: String
        let identity: stat
        let isDirectory: Bool

        var depth: Int {
            relativePath.split(separator: "/").count
        }
    }

    private var entries: [Entry] = []

    func capture(
        directoryDescriptor: Int32,
        attachments: [DiagnosticPackageAttachmentPayload]
    ) throws {
        var captured = [Entry]()
        for name in DiagnosticPackageFormat.payloadFileNames {
            try captured.append(entry(named: name, parentDescriptor: directoryDescriptor, isDirectory: false))
        }
        let attachmentsName = DiagnosticPackageFormat.attachmentsDirectoryName
        try captured.append(entry(
            named: attachmentsName,
            parentDescriptor: directoryDescriptor,
            isDirectory: true
        ))
        let attachmentsDescriptor = try openDirectory(named: attachmentsName, parentDescriptor: directoryDescriptor)
        defer { close(attachmentsDescriptor) }
        if !attachments.isEmpty {
            try captureMetadata(
                attachments,
                attachmentsDescriptor: attachmentsDescriptor,
                into: &captured
            )
        }
        entries = captured
        try validateTree(directoryDescriptor: directoryDescriptor)
    }

    func removeContents(directoryDescriptor: Int32) throws {
        try validateTree(directoryDescriptor: directoryDescriptor)
        let removalOrder = entries.sorted {
            if $0.depth != $1.depth { return $0.depth > $1.depth }
            if $0.isDirectory != $1.isDirectory { return !$0.isDirectory }
            return $0.relativePath < $1.relativePath
        }
        for entry in removalOrder {
            try remove(entry, directoryDescriptor: directoryDescriptor)
        }
        let names = try DiagnosticPackageReader().directoryEntryNames(descriptor: directoryDescriptor, maximumCount: 0)
        guard names.isEmpty else { throw DiagnosticPackageError.unsafeFile }
    }
}

private extension DiagnosticPackageCleanupOwnership {
    func captureMetadata(
        _ attachments: [DiagnosticPackageAttachmentPayload],
        attachmentsDescriptor: Int32,
        into captured: inout [Entry]
    ) throws {
        let metadataName = DiagnosticPackageFormat.repositoryMetadataDirectoryName
        try captured.append(entry(
            named: "\(DiagnosticPackageFormat.attachmentsDirectoryName)/\(metadataName)",
            leafName: metadataName,
            parentDescriptor: attachmentsDescriptor,
            isDirectory: true
        ))
        let metadataDescriptor = try openDirectory(named: metadataName, parentDescriptor: attachmentsDescriptor)
        defer { close(metadataDescriptor) }
        for attachment in attachments {
            guard let name = DiagnosticPackageFormat.repositoryMetadataFileNames.first(where: {
                DiagnosticPackageFormat.metadataRelativePath($0) == attachment.relativePath
            }) else { throw DiagnosticPackageError.invalidPackage }
            try captured.append(entry(
                named: attachment.relativePath,
                leafName: name,
                parentDescriptor: metadataDescriptor,
                isDirectory: false
            ))
        }
    }

    func validateTree(directoryDescriptor: Int32) throws {
        try validateChildren(expectedParentPath: nil, parentDescriptor: directoryDescriptor)
        let attachmentsPath = DiagnosticPackageFormat.attachmentsDirectoryName
        if entries.contains(where: { $0.relativePath == attachmentsPath }) {
            let attachments = try openDirectory(named: attachmentsPath, parentDescriptor: directoryDescriptor)
            defer { close(attachments) }
            try validateChildren(expectedParentPath: attachmentsPath, parentDescriptor: attachments)
            let metadataPath = "\(attachmentsPath)/\(DiagnosticPackageFormat.repositoryMetadataDirectoryName)"
            if entries.contains(where: { $0.relativePath == metadataPath }) {
                let metadata = try openDirectory(
                    named: DiagnosticPackageFormat.repositoryMetadataDirectoryName,
                    parentDescriptor: attachments
                )
                defer { close(metadata) }
                try validateChildren(expectedParentPath: metadataPath, parentDescriptor: metadata)
            }
        }
    }

    func validateChildren(expectedParentPath: String?, parentDescriptor: Int32) throws {
        let children = entries.filter { parentPath(of: $0.relativePath) == expectedParentPath }
        let expectedNames = try Set(children.map { try leafName(of: $0.relativePath) })
        let actualNames = try DiagnosticPackageReader().directoryEntryNames(
            descriptor: parentDescriptor,
            maximumCount: expectedNames.count
        )
        guard actualNames == expectedNames else { throw DiagnosticPackageError.unsafeFile }
        for child in children {
            try validate(child, parentDescriptor: parentDescriptor)
        }
    }

    func remove(_ entry: Entry, directoryDescriptor: Int32) throws {
        let components = entry.relativePath.split(separator: "/").map(String.init)
        var openedDescriptors = [Int32]()
        var parentDescriptor = directoryDescriptor
        for component in components.dropLast() {
            let descriptor = try openDirectory(named: component, parentDescriptor: parentDescriptor)
            openedDescriptors.append(descriptor)
            parentDescriptor = descriptor
        }
        defer { openedDescriptors.reversed().forEach { close($0) } }
        guard let leafName = components.last else { throw DiagnosticPackageError.unsafeFile }
        try validate(entry, parentDescriptor: parentDescriptor)
        let flags = entry.isDirectory ? AT_REMOVEDIR : 0
        guard unlinkat(parentDescriptor, leafName, flags) == 0 else {
            throw DiagnosticPackageError.unsafeFile
        }
    }

    func entry(
        named relativePath: String,
        leafName: String? = nil,
        parentDescriptor: Int32,
        isDirectory: Bool
    ) throws -> Entry {
        let leaf = leafName ?? relativePath
        var identity = stat()
        guard fstatat(parentDescriptor, leaf, &identity, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw DiagnosticPackageError.unsafeFile
        }
        let value = Entry(relativePath: relativePath, identity: identity, isDirectory: isDirectory)
        try validateIdentity(value.identity, isDirectory: isDirectory)
        return value
    }

    func validate(_ entry: Entry, parentDescriptor: Int32) throws {
        var current = stat()
        let name = try leafName(of: entry.relativePath)
        guard fstatat(parentDescriptor, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
              current.st_dev == entry.identity.st_dev,
              current.st_ino == entry.identity.st_ino
        else { throw DiagnosticPackageError.unsafeFile }
        try validateIdentity(current, isDirectory: entry.isDirectory)
    }

    func validateIdentity(_ identity: stat, isDirectory: Bool) throws {
        let expectedType = isDirectory ? S_IFDIR : S_IFREG
        guard identity.st_mode & S_IFMT == expectedType,
              identity.st_uid == geteuid(),
              identity.st_flags & UInt32(SF_DATALESS) == 0,
              isDirectory || identity.st_nlink == 1
        else { throw DiagnosticPackageError.unsafeFile }
    }

    func openDirectory(named name: String, parentDescriptor: Int32) throws -> Int32 {
        let descriptor = openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw DiagnosticPackageError.unsafeFile }
        return descriptor
    }

    func parentPath(of path: String) -> String? {
        let components = path.split(separator: "/")
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: "/")
    }

    func leafName(of path: String) throws -> String {
        guard let name = path.split(separator: "/").last else {
            throw DiagnosticPackageError.unsafeFile
        }
        return String(name)
    }
}
