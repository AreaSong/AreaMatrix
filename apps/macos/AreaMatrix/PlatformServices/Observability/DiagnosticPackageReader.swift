import CryptoKit
import Darwin
import Foundation

struct DiagnosticPackageReader {
    private let decoder = JSONDecoder()

    func inspect(_ packageURL: URL) throws -> DiagnosticPackageInspection {
        guard packageURL.isFileURL, packageURL.pathExtension == "amdiagnostic" else {
            throw DiagnosticPackageError.invalidPackage
        }
        let descriptor = open(
            packageURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw DiagnosticPackageError.unsafeFile }
        defer { close(descriptor) }
        do {
            try validateDirectory(descriptor)
            return try inspect(directoryDescriptor: descriptor)
        } catch let error as DiagnosticPackageError {
            throw error
        } catch {
            throw DiagnosticPackageError.invalidPackage
        }
    }

    func inspect(directoryDescriptor: Int32) throws -> DiagnosticPackageInspection {
        do {
            try validateDirectory(directoryDescriptor)
            return try inspectOpenedDirectory(directoryDescriptor)
        } catch let error as DiagnosticPackageError {
            throw error
        } catch {
            throw DiagnosticPackageError.invalidPackage
        }
    }
}

private extension DiagnosticPackageReader {
    private func inspectOpenedDirectory(_ directoryDescriptor: Int32) throws -> DiagnosticPackageInspection {
        let names = try directoryEntryNames(
            descriptor: directoryDescriptor,
            maximumCount: DiagnosticPackageFormat.allowedEntryNames.count
        )
        guard names == DiagnosticPackageFormat.allowedEntryNames else {
            throw DiagnosticPackageError.unexpectedEntry
        }
        var payloads = try readRootPayloads(directoryDescriptor: directoryDescriptor)
        let manifest: DiagnosticPackageManifest = try decodeJSON(required(payloads, "manifest.json"))
        try validateSchema(manifest)
        let attachmentPayloads = try readAttachments(
            directoryDescriptor: directoryDescriptor,
            manifest: manifest
        )
        try addAttachments(attachmentPayloads, to: &payloads)
        let checksums = try validateChecksums(payloads)
        let descriptors = try DiagnosticPackageEncoding.attachmentDescriptors(
            attachmentPayloads,
            checksums: checksums
        )
        return try decodeInspection(payloads, manifest: manifest, attachments: descriptors)
    }

    private func readRootPayloads(directoryDescriptor: Int32) throws -> [String: Data] {
        var payloads: [String: Data] = [:]
        var total = 0
        for name in DiagnosticPackageFormat.payloadFileNames {
            guard let limit = DiagnosticPackageFormat.fileByteLimits[name] else {
                throw DiagnosticPackageError.invalidPackage
            }
            let data = try readRegularFile(named: name, directoryDescriptor: directoryDescriptor, limit: limit)
            try addToPackageTotal(data.count, total: &total)
            payloads[name] = data
        }
        return payloads
    }

    private func addAttachments(
        _ attachments: [DiagnosticPackageAttachmentPayload],
        to payloads: inout [String: Data]
    ) throws {
        var total = payloads.values.reduce(0) { $0 + $1.count }
        for attachment in attachments {
            try addToPackageTotal(attachment.data.count, total: &total)
            guard payloads.updateValue(attachment.data, forKey: attachment.relativePath) == nil else {
                throw DiagnosticPackageError.invalidPackage
            }
        }
    }

    private func addToPackageTotal(_ count: Int, total: inout Int) throws {
        guard count <= DiagnosticPackageFormat.maximumPackageBytes - total else {
            throw DiagnosticPackageError.limitExceeded
        }
        total += count
    }

    private func readAttachments(
        directoryDescriptor: Int32,
        manifest: DiagnosticPackageManifest
    ) throws -> [DiagnosticPackageAttachmentPayload] {
        let attachmentsDescriptor = try openDirectory(
            named: DiagnosticPackageFormat.attachmentsDirectoryName,
            parentDescriptor: directoryDescriptor
        )
        defer { close(attachmentsDescriptor) }
        guard manifest.includesMetadataSnapshot else {
            let names = try directoryEntryNames(descriptor: attachmentsDescriptor, maximumCount: 0)
            guard names.isEmpty else { throw DiagnosticPackageError.unexpectedEntry }
            return []
        }
        let names = try directoryEntryNames(descriptor: attachmentsDescriptor, maximumCount: 1)
        guard names == Set([DiagnosticPackageFormat.repositoryMetadataDirectoryName]) else {
            throw DiagnosticPackageError.unexpectedEntry
        }
        return try readMetadataAttachments(attachmentsDescriptor: attachmentsDescriptor)
    }

    private func readMetadataAttachments(
        attachmentsDescriptor: Int32
    ) throws -> [DiagnosticPackageAttachmentPayload] {
        let descriptor = try openDirectory(
            named: DiagnosticPackageFormat.repositoryMetadataDirectoryName,
            parentDescriptor: attachmentsDescriptor
        )
        defer { close(descriptor) }
        let names = try directoryEntryNames(
            descriptor: descriptor,
            maximumCount: DiagnosticPackageFormat.repositoryMetadataFileNames.count
        )
        let allowed = Set(DiagnosticPackageFormat.repositoryMetadataFileNames)
        guard names.isSubset(of: allowed), names.contains("index.db") else {
            throw DiagnosticPackageError.unexpectedEntry
        }
        var payloads: [DiagnosticPackageAttachmentPayload] = []
        var total = 0
        for name in DiagnosticPackageFormat.repositoryMetadataFileNames where names.contains(name) {
            let data = try readRegularFile(
                named: name,
                directoryDescriptor: descriptor,
                limit: DiagnosticPackageFormat.maximumMetadataFileBytes
            )
            guard data.count <= DiagnosticPackageFormat.maximumMetadataBytes - total else {
                throw DiagnosticPackageError.limitExceeded
            }
            total += data.count
            payloads.append(DiagnosticPackageAttachmentPayload(
                relativePath: DiagnosticPackageFormat.metadataRelativePath(name),
                data: data
            ))
        }
        return payloads
    }

    private func decodeInspection(
        _ payloads: [String: Data],
        manifest: DiagnosticPackageManifest,
        attachments: [DiagnosticPackageAttachmentDescriptor]
    ) throws -> DiagnosticPackageInspection {
        let environment: DiagnosticEnvironment = try decodeJSON(required(payloads, "environment.json"))
        let report: DiagnosticPrivacyReport = try decodeJSON(required(payloads, "privacy-report.json"))
        try validateMetadata(
            manifest: manifest,
            environment: environment,
            report: report,
            attachments: attachments
        )
        let events = try decodeEvents(required(payloads, "events.jsonl"), manifest: manifest)
        guard events.count == manifest.eventCount else { throw DiagnosticPackageError.invalidPackage }
        try DiagnosticPackageRedactor.validateExportedEvents(
            events,
            selection: privacySelection(for: manifest)
        )
        guard let summary = try String(data: required(payloads, "summary.txt"), encoding: .utf8) else {
            throw DiagnosticPackageError.invalidPackage
        }
        try DiagnosticPackageRedactor.validateCredentialFree([summary])
        return DiagnosticPackageInspection(
            manifest: manifest,
            privacyReport: report,
            events: events,
            summary: summary,
            attachments: attachments
        )
    }

    private func validateSchema(_ manifest: DiagnosticPackageManifest) throws {
        guard DiagnosticPackageFormat.supportedSchemaVersions.contains(manifest.schemaVersion),
              DiagnosticPackageFormat.supportedEventSchemaVersions.contains(manifest.eventSchemaVersion)
        else { throw DiagnosticPackageError.unsupportedSchema }
        if manifest.schemaVersion == 1 {
            guard manifest.eventSchemaVersion == 1,
                  !manifest.includesFileNames,
                  !manifest.includesFullPaths,
                  !manifest.includesMetadataSnapshot,
                  !manifest.includesAttachments
            else { throw DiagnosticPackageError.invalidPackage }
        } else {
            guard manifest.includesAttachments == manifest.includesMetadataSnapshot,
                  !manifest.includesFullPaths || manifest.includesFileNames
            else {
                throw DiagnosticPackageError.invalidPackage
            }
        }
    }

    private func privacySelection(
        for manifest: DiagnosticPackageManifest
    ) -> DiagnosticPackagePrivacySelection {
        if manifest.schemaVersion == 1, manifest.includesSensitiveEvents {
            return .allSensitive()
        }
        return DiagnosticPackagePrivacySelection(
            includeSensitiveFields: manifest.includesSensitiveEvents,
            includeFileNames: manifest.includesFileNames,
            includeFullPaths: manifest.includesFullPaths,
            includeMetadataSnapshot: manifest.includesMetadataSnapshot
        )
    }

    private func validateMetadata(
        manifest: DiagnosticPackageManifest,
        environment: DiagnosticEnvironment,
        report: DiagnosticPrivacyReport,
        attachments: [DiagnosticPackageAttachmentDescriptor]
    ) throws {
        try validateCounts(manifest: manifest, report: report)
        let attachmentPaths = attachments.map(\.relativePath)
        let metadataDirectory = attachments.isEmpty ? [] : [
            "attachments/\(DiagnosticPackageFormat.repositoryMetadataDirectoryName)/"
        ]
        let expectedFiles = DiagnosticPackageFormat.reportedEntryNames + metadataDirectory + attachmentPaths
        guard UUID(uuidString: manifest.packageID) != nil,
              manifest.createdAtMilliseconds >= 0,
              !manifest.automaticUpload,
              report.sourceEventCount == report.exportedEventCount + report.rejectedEventCount,
              report.exportedEventCount == manifest.eventCount,
              report.redactedFieldCount >= 0,
              report.rejectedEventCount >= 0,
              report.includesSensitiveEvents == manifest.includesSensitiveEvents,
              report.includesFileNames == manifest.includesFileNames,
              report.includesFullPaths == manifest.includesFullPaths,
              report.includesMetadataSnapshot == manifest.includesMetadataSnapshot,
              report.wireSchemaVersion == manifest.schemaVersion,
              !report.prohibitedDataIncluded,
              report.includedFiles == expectedFiles,
              manifest.includesMetadataSnapshot == !attachments.isEmpty,
              !environment.appVersion.isEmpty,
              !environment.operatingSystemVersion.isEmpty,
              !environment.architecture.isEmpty,
              !environment.interfaceLanguage.isEmpty
        else { throw DiagnosticPackageError.invalidPackage }
        try DiagnosticPackageRedactor.validateCredentialFree([
            environment.appVersion,
            environment.operatingSystemVersion,
            environment.architecture,
            environment.interfaceLanguage
        ])
    }

    private func validateCounts(
        manifest: DiagnosticPackageManifest,
        report: DiagnosticPrivacyReport
    ) throws {
        let allowed = 0 ... DiagnosticPackageFormat.maximumEventCount
        guard allowed.contains(manifest.eventCount),
              allowed.contains(report.sourceEventCount),
              allowed.contains(report.exportedEventCount),
              allowed.contains(report.rejectedEventCount)
        else { throw DiagnosticPackageError.limitExceeded }
    }

    private func validateChecksums(_ payloads: [String: Data]) throws -> [String: String] {
        let checksums: [String: String] = try decodeJSON(required(payloads, "checksums.json"))
        let expectedNames = Set(payloads.keys).subtracting(["checksums.json"])
        guard Set(checksums.keys) == expectedNames else {
            throw DiagnosticPackageError.checksumMismatch
        }
        for name in expectedNames {
            let data = try required(payloads, name)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard checksums[name] == digest else { throw DiagnosticPackageError.checksumMismatch }
        }
        return checksums
    }

    private func decodeEvents(
        _ data: Data,
        manifest: DiagnosticPackageManifest
    ) throws -> [ObservabilityEventSnapshot] {
        let lines = try eventLines(data)
        var events: [ObservabilityEventSnapshot] = []
        events.reserveCapacity(lines.count)
        for line in lines {
            try validateJSONDepth(line)
            let event = try decoder.decode(ObservabilityEventSnapshot.self, from: line)
            guard event.schemaVersion == manifest.eventSchemaVersion else {
                throw DiagnosticPackageError.unsupportedSchema
            }
            guard event.attributes.count <= DiagnosticPackageFormat.maximumAttributeCount,
                  event.resources.count <= DiagnosticPackageFormat.maximumResourceCount
            else { throw DiagnosticPackageError.limitExceeded }
            events.append(event)
        }
        return events
    }

    private func eventLines(_ data: Data) throws -> [Data] {
        guard !data.isEmpty else { return [] }
        var lines: [Data] = []
        var start = data.startIndex
        for index in data.indices where data[index] == 0x0A {
            try appendEventLine(data[start ..< index], to: &lines)
            start = data.index(after: index)
        }
        if start != data.endIndex {
            try appendEventLine(data[start ..< data.endIndex], to: &lines)
        }
        return lines
    }

    private func appendEventLine(_ line: Data.SubSequence, to lines: inout [Data]) throws {
        guard !line.isEmpty else { throw DiagnosticPackageError.invalidPackage }
        guard line.count <= DiagnosticPackageFormat.maximumEventLineBytes,
              lines.count < DiagnosticPackageFormat.maximumEventCount
        else { throw DiagnosticPackageError.limitExceeded }
        lines.append(Data(line))
    }

    private func decodeJSON<Value: Decodable>(_ data: Data) throws -> Value {
        try validateJSONDepth(data)
        return try decoder.decode(Value.self, from: data)
    }

    private func validateJSONDepth(_ data: Data) throws {
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        for byte in data {
            if updateStringState(byte, isInside: &isInsideString, isEscaped: &isEscaped) { continue }
            if byte == 0x22 {
                isInsideString = true
            } else if byte == 0x7B || byte == 0x5B {
                depth += 1
                guard depth <= DiagnosticPackageFormat.maximumJSONDepth else {
                    throw DiagnosticPackageError.limitExceeded
                }
            } else if byte == 0x7D || byte == 0x5D {
                guard depth > 0 else { throw DiagnosticPackageError.invalidPackage }
                depth -= 1
            }
        }
        guard depth == 0, !isInsideString, !isEscaped else {
            throw DiagnosticPackageError.invalidPackage
        }
    }

    private func updateStringState(
        _ byte: UInt8,
        isInside: inout Bool,
        isEscaped: inout Bool
    ) -> Bool {
        guard isInside else { return false }
        if isEscaped {
            isEscaped = false
        } else if byte == 0x5C {
            isEscaped = true
        } else if byte == 0x22 {
            isInside = false
        }
        return true
    }

    private func required(_ payloads: [String: Data], _ name: String) throws -> Data {
        guard let data = payloads[name] else { throw DiagnosticPackageError.invalidPackage }
        return data
    }
}
