import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

struct DiagnosticPackageExporter {
    private let metadataCapture: any RepositoryMetadataSnapshotCapturing
    private let writer: DiagnosticPackageWriter
    private let interfaceLocaleIdentifier: @Sendable () -> String

    init(
        metadataCapture: any RepositoryMetadataSnapshotCapturing = RepositoryMetadataSnapshotCapture(),
        stagingRootURL: URL? = nil,
        publishOperations: DiagnosticPackagePublishOperations = .live,
        interfaceLocaleIdentifier: @escaping @Sendable () -> String = { "en" }
    ) {
        self.metadataCapture = metadataCapture
        self.interfaceLocaleIdentifier = interfaceLocaleIdentifier
        writer = DiagnosticPackageWriter(
            stagingRootURL: stagingRootURL,
            operations: publishOperations
        )
    }

    func preview(
        events: [ObservabilityEventSnapshot],
        privacySelection: DiagnosticPackagePrivacySelection = .redacted,
        repositoryURL: URL? = nil,
        summary: String = ""
    ) throws -> DiagnosticPackagePreview {
        guard privacySelection.isValid else { throw DiagnosticPackageError.invalidPackage }
        try validateEventLimits(events)
        let eventSchemaVersion = try resolvedEventSchemaVersion(events)
        let attachments = try metadataAttachments(
            isIncluded: privacySelection.includeMetadataSnapshot,
            repositoryURL: repositoryURL
        )
        let redaction = try DiagnosticPackageRedactor.redact(
            events,
            selection: privacySelection
        )
        let manifest = makeManifest(
            eventCount: redaction.events.count,
            eventSchemaVersion: eventSchemaVersion,
            privacySelection: privacySelection
        )
        try validateAttachments(attachments, manifest: manifest)
        let report = makePrivacyReport(
            sourceCount: events.count,
            redaction: redaction,
            manifest: manifest,
            attachments: attachments
        )
        let preview = try encodePreview(
            manifest: manifest,
            events: redaction.events,
            report: report,
            summary: summary,
            attachments: attachments
        )
        try validatePayloadSizes(preview)
        return preview
    }

    func export(_ preview: DiagnosticPackagePreview, to destination: URL) throws -> URL {
        try validatePayloadSizes(preview)
        return try writer.export(preview, to: destination)
    }
}

private extension DiagnosticPackageExporter {
    private func validateEventLimits(_ events: [ObservabilityEventSnapshot]) throws {
        guard events.count <= DiagnosticPackageFormat.maximumEventCount,
              events.allSatisfy({
                  $0.attributes.count <= DiagnosticPackageFormat.maximumAttributeCount &&
                      $0.resources.count <= DiagnosticPackageFormat.maximumResourceCount
              })
        else { throw DiagnosticPackageError.limitExceeded }
    }

    private func resolvedEventSchemaVersion(_ events: [ObservabilityEventSnapshot]) throws -> UInt64 {
        let versions = Set(events.map(\.schemaVersion))
        guard versions.count <= 1,
              versions.isSubset(of: DiagnosticPackageFormat.supportedEventSchemaVersions)
        else { throw DiagnosticPackageError.unsupportedSchema }
        return versions.first ?? DiagnosticPackageFormat.eventSchemaVersion
    }

    private func metadataAttachments(
        isIncluded: Bool,
        repositoryURL: URL?
    ) throws -> [DiagnosticPackageAttachmentPayload] {
        guard isIncluded else { return [] }
        guard let repositoryURL else { throw DiagnosticPackageError.invalidPackage }
        return try metadataCapture.capture(repositoryURL: repositoryURL)
    }

    private func makeManifest(
        eventCount: Int,
        eventSchemaVersion: UInt64,
        privacySelection: DiagnosticPackagePrivacySelection
    ) -> DiagnosticPackageManifest {
        DiagnosticPackageManifest(
            schemaVersion: DiagnosticPackageFormat.schemaVersion,
            eventSchemaVersion: eventSchemaVersion,
            packageID: UUID().uuidString.lowercased(),
            createdAtMilliseconds: ObservabilityTime.milliseconds(Date()),
            eventCount: eventCount,
            includesSensitiveEvents: privacySelection.includeSensitiveFields,
            includesFileNames: privacySelection.includeFileNames,
            includesFullPaths: privacySelection.includeFullPaths,
            includesMetadataSnapshot: privacySelection.includeMetadataSnapshot,
            includesAttachments: privacySelection.includeMetadataSnapshot,
            automaticUpload: false
        )
    }

    private func makePrivacyReport(
        sourceCount: Int,
        redaction: DiagnosticPackageRedactionResult,
        manifest: DiagnosticPackageManifest,
        attachments: [DiagnosticPackageAttachmentPayload]
    ) -> DiagnosticPrivacyReport {
        let attachmentFiles = attachments.map(\.relativePath)
        let metadataDirectory = attachments.isEmpty ? [] : [
            "attachments/\(DiagnosticPackageFormat.repositoryMetadataDirectoryName)/"
        ]
        return DiagnosticPrivacyReport(
            sourceEventCount: sourceCount,
            exportedEventCount: redaction.events.count,
            redactedFieldCount: redaction.redacted,
            rejectedEventCount: redaction.rejected,
            includesSensitiveEvents: manifest.includesSensitiveEvents,
            includesFileNames: manifest.includesFileNames,
            includesFullPaths: manifest.includesFullPaths,
            includesMetadataSnapshot: manifest.includesMetadataSnapshot,
            prohibitedDataIncluded: false,
            includedFiles: DiagnosticPackageFormat.reportedEntryNames + metadataDirectory + attachmentFiles
        )
    }

    private func encodePreview(
        manifest: DiagnosticPackageManifest,
        events: [ObservabilityEventSnapshot],
        report: DiagnosticPrivacyReport,
        summary: String,
        attachments: [DiagnosticPackageAttachmentPayload]
    ) throws -> DiagnosticPackagePreview {
        let encoder = DiagnosticPackageEncoding.makeEncoder()
        let manifestData = try encoder.encode(manifest)
        let eventsData = try encodeJSONLines(events)
        let environmentData = try encoder.encode(environment())
        let privacyReportData = try encoder.encode(report)
        let summaryData = try Data(DiagnosticPackageRedactor.sanitizedSummary(summary).utf8)
        let covered = DiagnosticPackageEncoding.coveredPayloads(
            manifestData: manifestData,
            eventsData: eventsData,
            environmentData: environmentData,
            privacyReportData: privacyReportData,
            summaryData: summaryData
        ) + attachments.map { ($0.relativePath, $0.data) }
        let checksumsData = try encoder.encode(DiagnosticPackageEncoding.checksums(for: covered))
        return DiagnosticPackagePreview(
            manifest: manifest,
            manifestData: manifestData,
            eventsData: eventsData,
            environmentData: environmentData,
            privacyReportData: privacyReportData,
            summaryData: summaryData,
            checksumsData: checksumsData,
            privacyReport: report,
            attachments: attachments
        )
    }

    private func encodeJSONLines(_ events: [ObservabilityEventSnapshot]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var output = Data()
        for event in events {
            let line = try encoder.encode(event)
            let appendedBytes = line.count + 1
            guard line.count <= DiagnosticPackageFormat.maximumEventLineBytes,
                  appendedBytes <= DiagnosticPackageFormat.maximumEventsBytes - output.count
            else {
                throw DiagnosticPackageError.limitExceeded
            }
            output.append(line)
            output.append(0x0A)
        }
        return output
    }

    private func validatePayloadSizes(_ preview: DiagnosticPackagePreview) throws {
        let rootPayloads = Array(preview.filePayloads.prefix(DiagnosticPackageFormat.payloadFileNames.count))
        guard rootPayloads.map(\.name) == DiagnosticPackageFormat.payloadFileNames else {
            throw DiagnosticPackageError.invalidPackage
        }
        var total = 0
        for payload in rootPayloads {
            guard let limit = DiagnosticPackageFormat.fileByteLimits[payload.name],
                  payload.data.count <= limit
            else { throw DiagnosticPackageError.limitExceeded }
            total += payload.data.count
        }
        try validateAttachments(preview.attachments, manifest: preview.manifest)
        total += preview.attachments.reduce(0) { $0 + $1.data.count }
        guard total <= DiagnosticPackageFormat.maximumPackageBytes else {
            throw DiagnosticPackageError.limitExceeded
        }
    }

    private func validateAttachments(
        _ attachments: [DiagnosticPackageAttachmentPayload],
        manifest: DiagnosticPackageManifest
    ) throws {
        let expectedPaths = DiagnosticPackageFormat.repositoryMetadataFileNames.map(
            DiagnosticPackageFormat.metadataRelativePath
        )
        let paths = attachments.map(\.relativePath)
        guard Set(paths).count == paths.count,
              paths == expectedPaths.filter(paths.contains),
              manifest.includesMetadataSnapshot == !attachments.isEmpty,
              manifest.includesAttachments == manifest.includesMetadataSnapshot,
              !manifest.includesMetadataSnapshot || paths.first == expectedPaths.first
        else { throw DiagnosticPackageError.invalidPackage }
        var total = 0
        for attachment in attachments {
            guard attachment.data.count <= DiagnosticPackageFormat.maximumMetadataFileBytes else {
                throw DiagnosticPackageError.limitExceeded
            }
            total += attachment.data.count
        }
        guard total <= DiagnosticPackageFormat.maximumMetadataBytes else {
            throw DiagnosticPackageError.limitExceeded
        }
    }

    private func environment() -> DiagnosticEnvironment {
        DiagnosticEnvironment(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: DiagnosticPackageEncoding.architecture(),
            interfaceLanguage: interfaceLocaleIdentifier()
        )
    }
}

@MainActor
struct DiagnosticPackagePanelService {
    // The nonisolated dependency default must remain constructible from the handler's nonisolated initializer.
    // swiftlint:disable:next unneeded_synthesized_initializer
    nonisolated init() {}

    func chooseNewPackageDestination(suggestedFileName: String) -> URL? {
        guard let fileName = normalizedPackageFileName(suggestedFileName) else { return nil }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.packageType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = fileName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return normalizedPackageURL(url)
    }

    func choosePackageToRead() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.packageType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              url.isFileURL,
              url.pathExtension == "amdiagnostic"
        else { return nil }
        return url
    }

    private func normalizedPackageFileName(_ suggestedFileName: String) -> String? {
        let component = URL(fileURLWithPath: suggestedFileName).lastPathComponent
        guard !component.isEmpty, component != ".", component != ".." else { return nil }
        if URL(fileURLWithPath: component).pathExtension == "amdiagnostic" {
            return component
        }
        return "\(component).amdiagnostic"
    }

    private func normalizedPackageURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        if url.pathExtension == "amdiagnostic" { return url }
        return url.appendingPathExtension("amdiagnostic")
    }

    private static let packageType = UTType(
        exportedAs: "app.areamatrix.diagnostic",
        conformingTo: .package
    )
}
