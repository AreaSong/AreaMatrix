@testable import AreaMatrix
import CryptoKit
import Darwin
import Foundation
import XCTest

final class DiagnosticPackageTests: XCTestCase {
    private struct ExportedFixture {
        let root: URL
        let package: URL
        let preview: DiagnosticPackagePreview
    }

    private let exporter = DiagnosticPackageExporter()
    private let reader = DiagnosticPackageReader()

    func testPreviewBytesMatchExportedPackage() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let destination = root.appendingPathComponent("incident.amdiagnostic", isDirectory: true)
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true)
        )
        let event = makeEvent()
        let preview = try exporter.preview(events: [event], summary: "Reproduction summary")

        XCTAssertEqual(preview.manifest.schemaVersion, 2)
        XCTAssertEqual(preview.manifest.eventSchemaVersion, event.schemaVersion)
        XCTAssertFalse(preview.manifest.includesMetadataSnapshot)
        XCTAssertTrue(preview.attachments.isEmpty)

        XCTAssertEqual(try exporter.export(preview, to: destination), destination)

        for payload in preview.filePayloads {
            let exported = try Data(contentsOf: destination.appendingPathComponent(payload.name))
            XCTAssertEqual(exported, payload.data, "Export changed preview bytes for \(payload.name)")
        }
        let entries = try Set(FileManager.default.contentsOfDirectory(atPath: destination.path))
        XCTAssertEqual(entries, DiagnosticPackageFormat.allowedEntryNames)
        let attachments = destination.appendingPathComponent("attachments", isDirectory: true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: attachments.path).isEmpty)
        let inspection = try reader.inspect(destination)
        XCTAssertEqual(inspection.events, [event])
        XCTAssertEqual(inspection.summary, "Reproduction summary")
        XCTAssertTrue(inspection.attachments.isEmpty)
    }

    func testPreviewRedactsSensitiveValuesByDefault() throws {
        var event = makeEvent()
        event.privacy = "sensitive"
        event.message = "/Users/example/Private/report.txt"
        event.error = ObservabilityErrorSnapshot(
            code: "repository.read_failed",
            kind: "io",
            technicalDetails: "Private error details"
        )
        event.attributes = [
            ObservabilityAttributeSnapshot(key: "source.name", value: "report.txt", privacy: "sensitive")
        ]

        let preview = try exporter.preview(events: [event])
        let decoded = try decodeOnlyEvent(preview.eventsData)

        XCTAssertEqual(decoded.message, DiagnosticPackageRedactor.redactedValue)
        XCTAssertEqual(decoded.error?.technicalDetails, DiagnosticPackageRedactor.redactedValue)
        XCTAssertEqual(decoded.attributes.first?.value, DiagnosticPackageRedactor.redactedValue)
        XCTAssertEqual(preview.privacyReport.redactedFieldCount, 3)
        let serialized = try XCTUnwrap(String(bytes: preview.eventsData, encoding: .utf8))
        XCTAssertFalse(serialized.contains("report.txt"))
        XCTAssertFalse(serialized.contains("Private error details"))
    }

    func testPreviewRejectsCredentialMaterial() {
        var event = makeEvent()
        event.attributes = [
            ObservabilityAttributeSnapshot(
                key: "response.header",
                value: "Authorization: Bearer top-secret-token",
                privacy: "public"
            )
        ]

        assertPackageError(.redactionFailed) {
            try exporter.preview(events: [event])
        }
        assertPackageError(.redactionFailed) {
            try exporter.preview(events: [makeEvent()], summary: "client_secret=not-exportable")
        }
        event.attributes = [
            ObservabilityAttributeSnapshot(key: "api_key", value: "opaque-value", privacy: "sensitive")
        ]
        assertPackageError(.redactionFailed) {
            try exporter.preview(events: [event])
        }
    }

    func testReaderRejectsChecksumTampering() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let summaryURL = fixture.package.appendingPathComponent("summary.txt")
        try Data("tampered".utf8).write(to: summaryURL)

        assertPackageError(.checksumMismatch) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderRejectsSymlinkPayload() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside-events.jsonl")
        try fixture.preview.eventsData.write(to: outside)
        let eventsURL = fixture.package.appendingPathComponent("events.jsonl")
        try removeTestTemporaryItem(eventsURL)
        try FileManager.default.createSymbolicLink(at: eventsURL, withDestinationURL: outside)

        assertPackageError(.unsafeFile) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderRejectsHardLinkedPayload() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside-manifest.json")
        try fixture.preview.manifestData.write(to: outside)
        let manifestURL = fixture.package.appendingPathComponent("manifest.json")
        try removeTestTemporaryItem(manifestURL)
        guard Darwin.link(outside.path, manifestURL.path) == 0 else {
            throw posixError()
        }

        assertPackageError(.unsafeFile) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderRejectsUnexpectedTopLevelEntry() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        try Data("unexpected".utf8).write(
            to: fixture.package.appendingPathComponent("unexpected.txt")
        )

        assertPackageError(.unexpectedEntry) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderRejectsNonemptyAttachmentsDirectory() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let attachment = fixture.package
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent("note.txt")
        try Data("not yet supported".utf8).write(to: attachment)

        assertPackageError(.unexpectedEntry) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderRejectsOversizedEventLine() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        var oversized = Data(repeating: 0x20, count: DiagnosticPackageFormat.maximumEventLineBytes + 1)
        oversized.append(0x0A)
        try replacePayload("events.jsonl", with: oversized, in: fixture.package)

        assertPackageError(.limitExceeded) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderRejectsExcessiveJSONDepth() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let depth = DiagnosticPackageFormat.maximumJSONDepth + 1
        let nested = String(repeating: "[", count: depth) + "0" + String(repeating: "]", count: depth) + "\n"
        try replacePayload("events.jsonl", with: Data(nested.utf8), in: fixture.package)

        assertPackageError(.limitExceeded) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderRejectsExcessiveAttributeCount() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        var event = makeEvent()
        event.attributes = (0 ... DiagnosticPackageFormat.maximumAttributeCount).map { index in
            ObservabilityAttributeSnapshot(key: "field_\(index)", value: "value", privacy: "public")
        }
        var eventsData = try JSONEncoder().encode(event)
        eventsData.append(0x0A)
        try replacePayload("events.jsonl", with: eventsData, in: fixture.package)

        assertPackageError(.limitExceeded) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderRejectsUnsupportedPackageSchema() throws {
        let fixture = try makeExportedPackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        var manifest = fixture.preview.manifest
        manifest.schemaVersion += 1
        try replacePayload("manifest.json", with: sortedEncoder().encode(manifest), in: fixture.package)

        assertPackageError(.unsupportedSchema) {
            try reader.inspect(fixture.package)
        }
    }

    func testReaderAcceptsLegacySchemaOnePackage() throws {
        let fixture = try makeExportedPackage(named: #function, event: makeLegacyEvent())
        defer { removeTestTemporaryItems(fixture.root) }
        var manifest = fixture.preview.manifest
        manifest.schemaVersion = 1
        let manifestData = try sortedEncoder().encode(manifest)
        try replacePayload("manifest.json", with: manifestData, in: fixture.package)
        try rewritePrivacyReportAsSchemaOne(in: fixture.package)

        let inspection = try reader.inspect(fixture.package)

        XCTAssertEqual(inspection.manifest.schemaVersion, 1)
        XCTAssertEqual(inspection.manifest.eventSchemaVersion, 1)
        XCTAssertFalse(inspection.manifest.includesMetadataSnapshot)
        XCTAssertEqual(inspection.events.count, 1)
        XCTAssertTrue(inspection.attachments.isEmpty)
    }

    func testReaderRejectsManifestAndPrivacyReportSchemaMismatchBothDirections() throws {
        let current = try makeExportedPackage(named: #function + "-current")
        defer { removeTestTemporaryItems(current.root) }
        try rewritePrivacyReportAsSchemaOne(in: current.package)
        assertPackageError(.invalidPackage) {
            try reader.inspect(current.package)
        }

        let legacy = try makeExportedPackage(named: #function + "-legacy", event: makeLegacyEvent())
        defer { removeTestTemporaryItems(legacy.root) }
        var manifest = legacy.preview.manifest
        manifest.schemaVersion = 1
        try replacePayload("manifest.json", with: sortedEncoder().encode(manifest), in: legacy.package)
        assertPackageError(.invalidPackage) {
            try reader.inspect(legacy.package)
        }
    }

    func testExportRefusesExistingDestinationWithoutChangingIt() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let destination = root.appendingPathComponent("existing.amdiagnostic", isDirectory: true)
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let sentinel = destination.appendingPathComponent("sentinel.txt")
        let sentinelData = Data("keep me".utf8)
        try sentinelData.write(to: sentinel)
        let preview = try exporter.preview(events: [makeEvent()])

        assertPackageError(.destinationExists) {
            try exporter.export(preview, to: destination)
        }

        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelData)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            $0.hasPrefix(".amdiagnostic-partial-")
        }
        XCTAssertTrue(leftovers.isEmpty)
    }
}

private extension DiagnosticPackageTests {
    private func makeExportedPackage(
        named name: String,
        event sourceEvent: ObservabilityEventSnapshot? = nil
    ) throws -> ExportedFixture {
        let root = try makeTestTemporaryDirectory(named: name)
        let package = root.appendingPathComponent("fixture.amdiagnostic", isDirectory: true)
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true)
        )
        let preview = try exporter.preview(events: [sourceEvent ?? makeEvent()], summary: "Summary")
        do {
            _ = try exporter.export(preview, to: package)
            return ExportedFixture(root: root, package: package, preview: preview)
        } catch {
            removeTestTemporaryItems(root)
            throw error
        }
    }

    private func replacePayload(_ name: String, with data: Data, in package: URL) throws {
        try data.write(to: package.appendingPathComponent(name))
        let checksumsURL = package.appendingPathComponent("checksums.json")
        var checksums = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: checksumsURL))
        checksums[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try sortedEncoder().encode(checksums).write(to: checksumsURL)
    }

    private func rewritePrivacyReportAsSchemaOne(in package: URL) throws {
        let reportURL = package.appendingPathComponent("privacy-report.json")
        let data = try Data(contentsOf: reportURL)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let includesSensitive = object.removeValue(forKey: "includesSensitiveEvents") as? Bool
        else {
            throw DiagnosticPackageError.invalidPackage
        }
        object.removeValue(forKey: "includesFileNames")
        object.removeValue(forKey: "includesFullPaths")
        object.removeValue(forKey: "includesMetadataSnapshot")
        object["includesSensitiveMetadata"] = includesSensitive
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try replacePayload("privacy-report.json", with: legacyData, in: package)
    }

    private func sortedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func decodeOnlyEvent(_ data: Data) throws -> ObservabilityEventSnapshot {
        var line = data
        if line.last == 0x0A { line.removeLast() }
        return try JSONDecoder().decode(ObservabilityEventSnapshot.self, from: line)
    }

    private func makeEvent() -> ObservabilityEventSnapshot {
        var value = event(
            id: UUID().uuidString.lowercased(),
            timestamp: 1_700_000_000_000,
            sessionID: UUID().uuidString.lowercased(),
            message: "Completed"
        )
        value.durationMilliseconds = 12
        value.target = "area_matrix_core"
        value.threadName = "main"
        return value
    }

    private func makeLegacyEvent() -> ObservabilityEventSnapshot {
        var value = makeEvent()
        value.schemaVersion = 1
        value.buildContext = nil
        return value
    }

    private func assertPackageError(
        _ expected: DiagnosticPackageError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> some Any
    ) {
        do {
            _ = try operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as DiagnosticPackageError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
