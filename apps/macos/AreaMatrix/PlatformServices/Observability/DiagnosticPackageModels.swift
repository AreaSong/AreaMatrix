import CryptoKit
import Darwin
import Foundation

enum DiagnosticPackageFormat {
    static let schemaVersion = 2
    static let supportedSchemaVersions = Set([1, 2])
    static let eventSchemaVersion: UInt64 = 2
    static let supportedEventSchemaVersions = Set<UInt64>([1, 2])
    static let maximumEventCount = 100_000
    static let maximumAttributeCount = 64
    static let maximumResourceCount = 64
    static let maximumEventLineBytes = 256 * 1024
    static let maximumEventsBytes = 128 * 1024 * 1024
    static let maximumJSONDepth = 32
    static let maximumPackageBytes = 256 * 1024 * 1024
    static let maximumMetadataFileBytes = 128 * 1024 * 1024
    static let maximumMetadataBytes = 128 * 1024 * 1024
    static let attachmentsDirectoryName = "attachments"
    static let repositoryMetadataDirectoryName = "repository-metadata"
    static let repositoryMetadataFileNames = ["index.db", "index.db-wal", "index.db-shm"]

    static let payloadFileNames = [
        "manifest.json",
        "events.jsonl",
        "environment.json",
        "privacy-report.json",
        "summary.txt",
        "checksums.json"
    ]

    static let checksumCoveredFileNames = Array(payloadFileNames.dropLast())
    static let allowedEntryNames = Set(payloadFileNames + [attachmentsDirectoryName])
    static let reportedEntryNames = checksumCoveredFileNames + ["checksums.json", "attachments/"]
    static let fileByteLimits = [
        "manifest.json": 256 * 1024,
        "events.jsonl": maximumEventsBytes,
        "environment.json": 1 * 1024 * 1024,
        "privacy-report.json": 1 * 1024 * 1024,
        "summary.txt": 1 * 1024 * 1024,
        "checksums.json": 1 * 1024 * 1024
    ]

    static func metadataRelativePath(_ fileName: String) -> String {
        "attachments/\(repositoryMetadataDirectoryName)/\(fileName)"
    }
}

struct DiagnosticPackageManifest: Codable, Equatable {
    var schemaVersion: Int
    var eventSchemaVersion: UInt64
    var packageID: String
    var createdAtMilliseconds: Int64
    var eventCount: Int
    var includesSensitiveEvents: Bool
    var includesFileNames: Bool
    var includesFullPaths: Bool
    var includesMetadataSnapshot: Bool
    var includesAttachments: Bool
    var automaticUpload: Bool

    var includesSensitiveMetadata: Bool {
        includesSensitiveEvents
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case eventSchemaVersion
        case packageID
        case createdAtMilliseconds
        case eventCount
        case includesSensitiveEvents
        case includesSensitiveMetadata
        case includesFileNames
        case includesFullPaths
        case includesMetadataSnapshot
        case includesAttachments
        case automaticUpload
    }

    init(
        schemaVersion: Int,
        eventSchemaVersion: UInt64,
        packageID: String,
        createdAtMilliseconds: Int64,
        eventCount: Int,
        includesSensitiveEvents: Bool,
        includesFileNames: Bool = false,
        includesFullPaths: Bool = false,
        includesMetadataSnapshot: Bool,
        includesAttachments: Bool,
        automaticUpload: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.eventSchemaVersion = eventSchemaVersion
        self.packageID = packageID
        self.createdAtMilliseconds = createdAtMilliseconds
        self.eventCount = eventCount
        self.includesSensitiveEvents = includesSensitiveEvents
        self.includesFileNames = includesFileNames
        self.includesFullPaths = includesFullPaths
        self.includesMetadataSnapshot = includesMetadataSnapshot
        self.includesAttachments = includesAttachments
        self.automaticUpload = automaticUpload
    }

    init(from decoder: Decoder) throws {
        try rejectDiagnosticUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        packageID = try values.decode(String.self, forKey: .packageID)
        createdAtMilliseconds = try values.decode(Int64.self, forKey: .createdAtMilliseconds)
        eventCount = try values.decode(Int.self, forKey: .eventCount)
        includesAttachments = try values.decode(Bool.self, forKey: .includesAttachments)
        automaticUpload = try values.decode(Bool.self, forKey: .automaticUpload)
        if schemaVersion == 1 {
            guard !values.contains(.eventSchemaVersion),
                  !values.contains(.includesSensitiveEvents),
                  !values.contains(.includesFileNames),
                  !values.contains(.includesFullPaths),
                  !values.contains(.includesMetadataSnapshot)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: values,
                    debugDescription: "Schema 1 manifest contains schema 2 privacy fields."
                )
            }
            eventSchemaVersion = 1
            includesSensitiveEvents = try values.decode(Bool.self, forKey: .includesSensitiveMetadata)
            includesFileNames = false
            includesFullPaths = false
            includesMetadataSnapshot = false
        } else {
            guard !values.contains(.includesSensitiveMetadata) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: values,
                    debugDescription: "Current manifest contains a legacy privacy field."
                )
            }
            eventSchemaVersion = try values.decode(UInt64.self, forKey: .eventSchemaVersion)
            includesSensitiveEvents = try values.decode(Bool.self, forKey: .includesSensitiveEvents)
            includesFileNames = try values.decode(Bool.self, forKey: .includesFileNames)
            includesFullPaths = try values.decode(Bool.self, forKey: .includesFullPaths)
            includesMetadataSnapshot = try values.decode(Bool.self, forKey: .includesMetadataSnapshot)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(packageID, forKey: .packageID)
        try values.encode(createdAtMilliseconds, forKey: .createdAtMilliseconds)
        try values.encode(eventCount, forKey: .eventCount)
        try values.encode(includesAttachments, forKey: .includesAttachments)
        try values.encode(automaticUpload, forKey: .automaticUpload)
        if schemaVersion == 1 {
            try values.encode(includesSensitiveEvents, forKey: .includesSensitiveMetadata)
        } else {
            try values.encode(eventSchemaVersion, forKey: .eventSchemaVersion)
            try values.encode(includesSensitiveEvents, forKey: .includesSensitiveEvents)
            try values.encode(includesFileNames, forKey: .includesFileNames)
            try values.encode(includesFullPaths, forKey: .includesFullPaths)
            try values.encode(includesMetadataSnapshot, forKey: .includesMetadataSnapshot)
        }
    }
}

struct DiagnosticEnvironment: Codable, Equatable {
    var appVersion: String
    var operatingSystemVersion: String
    var architecture: String
    var interfaceLanguage: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case appVersion, operatingSystemVersion, architecture, interfaceLanguage
    }

    init(
        appVersion: String,
        operatingSystemVersion: String,
        architecture: String,
        interfaceLanguage: String
    ) {
        self.appVersion = appVersion
        self.operatingSystemVersion = operatingSystemVersion
        self.architecture = architecture
        self.interfaceLanguage = interfaceLanguage
    }

    init(from decoder: Decoder) throws {
        try rejectDiagnosticUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appVersion = try values.decode(String.self, forKey: .appVersion)
        operatingSystemVersion = try values.decode(String.self, forKey: .operatingSystemVersion)
        architecture = try values.decode(String.self, forKey: .architecture)
        interfaceLanguage = try values.decode(String.self, forKey: .interfaceLanguage)
    }
}

struct DiagnosticPrivacyReport: Codable, Equatable {
    private(set) var wireSchemaVersion: Int
    var sourceEventCount: Int
    var exportedEventCount: Int
    var redactedFieldCount: Int
    var rejectedEventCount: Int
    var includesSensitiveEvents: Bool
    var includesFileNames: Bool
    var includesFullPaths: Bool
    var includesMetadataSnapshot: Bool
    var prohibitedDataIncluded: Bool
    var includedFiles: [String]

    var includesSensitiveMetadata: Bool {
        includesSensitiveEvents
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceEventCount
        case exportedEventCount
        case redactedFieldCount
        case rejectedEventCount
        case includesSensitiveEvents
        case includesSensitiveMetadata
        case includesFileNames
        case includesFullPaths
        case includesMetadataSnapshot
        case prohibitedDataIncluded
        case includedFiles
    }

    init(
        wireSchemaVersion: Int = DiagnosticPackageFormat.schemaVersion,
        sourceEventCount: Int,
        exportedEventCount: Int,
        redactedFieldCount: Int,
        rejectedEventCount: Int,
        includesSensitiveEvents: Bool,
        includesFileNames: Bool = false,
        includesFullPaths: Bool = false,
        includesMetadataSnapshot: Bool,
        prohibitedDataIncluded: Bool,
        includedFiles: [String]
    ) {
        self.wireSchemaVersion = wireSchemaVersion
        self.sourceEventCount = sourceEventCount
        self.exportedEventCount = exportedEventCount
        self.redactedFieldCount = redactedFieldCount
        self.rejectedEventCount = rejectedEventCount
        self.includesSensitiveEvents = includesSensitiveEvents
        self.includesFileNames = includesFileNames
        self.includesFullPaths = includesFullPaths
        self.includesMetadataSnapshot = includesMetadataSnapshot
        self.prohibitedDataIncluded = prohibitedDataIncluded
        self.includedFiles = includedFiles
    }

    init(from decoder: Decoder) throws {
        try rejectDiagnosticUnknownKeys(decoder, allowed: CodingKeys.wireNames)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourceEventCount = try values.decode(Int.self, forKey: .sourceEventCount)
        exportedEventCount = try values.decode(Int.self, forKey: .exportedEventCount)
        redactedFieldCount = try values.decode(Int.self, forKey: .redactedFieldCount)
        rejectedEventCount = try values.decode(Int.self, forKey: .rejectedEventCount)
        prohibitedDataIncluded = try values.decode(Bool.self, forKey: .prohibitedDataIncluded)
        includedFiles = try values.decode([String].self, forKey: .includedFiles)
        if values.contains(.includesSensitiveMetadata) {
            wireSchemaVersion = 1
            guard !values.contains(.includesSensitiveEvents),
                  !values.contains(.includesFileNames),
                  !values.contains(.includesFullPaths),
                  !values.contains(.includesMetadataSnapshot)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .includesSensitiveMetadata,
                    in: values,
                    debugDescription: "Legacy privacy report contains current privacy fields."
                )
            }
            includesSensitiveEvents = try values.decode(Bool.self, forKey: .includesSensitiveMetadata)
            includesFileNames = false
            includesFullPaths = false
            includesMetadataSnapshot = false
        } else {
            wireSchemaVersion = DiagnosticPackageFormat.schemaVersion
            includesSensitiveEvents = try values.decode(Bool.self, forKey: .includesSensitiveEvents)
            includesFileNames = try values.decode(Bool.self, forKey: .includesFileNames)
            includesFullPaths = try values.decode(Bool.self, forKey: .includesFullPaths)
            includesMetadataSnapshot = try values.decode(Bool.self, forKey: .includesMetadataSnapshot)
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sourceEventCount, forKey: .sourceEventCount)
        try values.encode(exportedEventCount, forKey: .exportedEventCount)
        try values.encode(redactedFieldCount, forKey: .redactedFieldCount)
        try values.encode(rejectedEventCount, forKey: .rejectedEventCount)
        if wireSchemaVersion == 1 {
            try values.encode(includesSensitiveEvents, forKey: .includesSensitiveMetadata)
        } else {
            try values.encode(includesSensitiveEvents, forKey: .includesSensitiveEvents)
            try values.encode(includesFileNames, forKey: .includesFileNames)
            try values.encode(includesFullPaths, forKey: .includesFullPaths)
            try values.encode(includesMetadataSnapshot, forKey: .includesMetadataSnapshot)
        }
        try values.encode(prohibitedDataIncluded, forKey: .prohibitedDataIncluded)
        try values.encode(includedFiles, forKey: .includedFiles)
    }
}

struct DiagnosticPackagePrivacySelection: Equatable {
    var includeSensitiveFields = false
    var includeFileNames = false
    var includeFullPaths = false
    var includeMetadataSnapshot = false

    static let redacted = Self()

    var isValid: Bool {
        !includeFullPaths || includeFileNames
    }

    static func allSensitive(includeMetadataSnapshot: Bool = false) -> Self {
        Self(
            includeSensitiveFields: true,
            includeFileNames: true,
            includeFullPaths: true,
            includeMetadataSnapshot: includeMetadataSnapshot
        )
    }
}

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

private struct DiagnosticPackageWireCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

private func rejectDiagnosticUnknownKeys(_ decoder: Decoder, allowed: Set<String>) throws {
    let values = try decoder.container(keyedBy: DiagnosticPackageWireCodingKey.self)
    let unknown = Set(values.allKeys.map(\.stringValue)).subtracting(allowed)
    guard unknown.isEmpty else {
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "Unknown diagnostic package keys: \(unknown.sorted())"
        ))
    }
}

private extension CaseIterable where Self: RawRepresentable, RawValue == String {
    static var wireNames: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}
