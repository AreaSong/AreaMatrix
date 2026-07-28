import CryptoKit
import Darwin
import Foundation

enum DiagnosticPackageEncoding {
    static func coveredPayloads(
        manifestData: Data,
        eventsData: Data,
        environmentData: Data,
        privacyReportData: Data,
        summaryData: Data
    ) -> [(name: String, data: Data)] {
        [
            ("manifest.json", manifestData),
            ("events.jsonl", eventsData),
            ("environment.json", environmentData),
            ("privacy-report.json", privacyReportData),
            ("summary.txt", summaryData)
        ]
    }

    static func checksums(
        for payloads: [(name: String, data: Data)]
    ) throws -> [String: String] {
        var checksums: [String: String] = [:]
        for payload in payloads {
            let digest = SHA256.hash(data: payload.data).map { String(format: "%02x", $0) }.joined()
            guard checksums.updateValue(digest, forKey: payload.name) == nil else {
                throw DiagnosticPackageError.invalidPackage
            }
        }
        return checksums
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func attachmentDescriptors(
        _ attachments: [DiagnosticPackageAttachmentPayload],
        checksums: [String: String]
    ) throws -> [DiagnosticPackageAttachmentDescriptor] {
        try attachments.map { attachment in
            guard let checksum = checksums[attachment.relativePath] else {
                throw DiagnosticPackageError.checksumMismatch
            }
            return DiagnosticPackageAttachmentDescriptor(
                relativePath: attachment.relativePath,
                byteCount: Int64(attachment.data.count),
                sha256: checksum
            )
        }
    }

    static func architecture() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

struct DiagnosticPackageAttachmentPayload: Equatable {
    let relativePath: String
    let data: Data
}

struct DiagnosticPackageAttachmentDescriptor: Codable, Equatable {
    let relativePath: String
    let byteCount: Int64
    let sha256: String
}

struct DiagnosticPackagePreview {
    let manifest: DiagnosticPackageManifest
    let manifestData: Data
    let eventsData: Data
    let environmentData: Data
    let privacyReportData: Data
    let summaryData: Data
    let checksumsData: Data
    let privacyReport: DiagnosticPrivacyReport
    let attachments: [DiagnosticPackageAttachmentPayload]

    var estimatedSizeBytes: Int64 {
        Int64(filePayloads.reduce(0) { $0 + $1.data.count })
    }

    var filePayloads: [(name: String, data: Data)] {
        [
            ("manifest.json", manifestData),
            ("events.jsonl", eventsData),
            ("environment.json", environmentData),
            ("privacy-report.json", privacyReportData),
            ("summary.txt", summaryData),
            ("checksums.json", checksumsData)
        ] + attachments.map { ($0.relativePath, $0.data) }
    }
}

struct DiagnosticPackageInspection {
    var manifest: DiagnosticPackageManifest
    var privacyReport: DiagnosticPrivacyReport
    var events: [ObservabilityEventSnapshot]
    var summary: String
    var attachments: [DiagnosticPackageAttachmentDescriptor] = []

    var isLegacy: Bool {
        manifest.schemaVersion < DiagnosticPackageFormat.schemaVersion
            || manifest.eventSchemaVersion < DiagnosticPackageFormat.eventSchemaVersion
    }
}

enum DiagnosticPackageError: Error, Equatable {
    case invalidDestination
    case destinationExists
    case durabilityUncertain
    case invalidPackage
    case unsupportedSchema
    case unexpectedEntry
    case unsafeFile
    case limitExceeded
    case checksumMismatch
    case redactionFailed
}
