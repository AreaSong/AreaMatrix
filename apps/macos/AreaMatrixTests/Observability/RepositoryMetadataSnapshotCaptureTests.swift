@testable import AreaMatrix
import CryptoKit
import Darwin
import Foundation
import XCTest

final class RepositoryMetadataSnapshotCaptureTests: XCTestCase {
    private struct RepositoryFixture {
        let root: URL
        let repository: URL
        let metadata: URL
    }

    func testCaptureFreezesDatabaseAndOptionalSidecars() throws {
        let fixture = try makeRepository(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        try Data("database".utf8).write(to: fixture.metadata.appendingPathComponent("index.db"))
        try Data("wal".utf8).write(to: fixture.metadata.appendingPathComponent("index.db-wal"))
        try Data("shm".utf8).write(to: fixture.metadata.appendingPathComponent("index.db-shm"))

        let payloads = try RepositoryMetadataSnapshotCapture().capture(repositoryURL: fixture.repository)

        XCTAssertEqual(payloads.map(\.relativePath), metadataPaths)
        XCTAssertEqual(payloads.map(\.data), [Data("database".utf8), Data("wal".utf8), Data("shm".utf8)])
    }

    func testCaptureAllowsMissingOptionalSidecars() throws {
        let fixture = try makeRepository(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        try Data("database".utf8).write(to: fixture.metadata.appendingPathComponent("index.db"))

        let payloads = try RepositoryMetadataSnapshotCapture().capture(repositoryURL: fixture.repository)

        XCTAssertEqual(payloads.map(\.relativePath), [metadataPaths[0]])
    }

    func testCaptureRejectsSymlinkHardlinkAndFIFO() throws {
        try assertUnsafeMetadataEntry(named: #function + "-symlink") { indexURL, outsideURL in
            try Data("outside".utf8).write(to: outsideURL)
            try FileManager.default.createSymbolicLink(at: indexURL, withDestinationURL: outsideURL)
        }
        try assertUnsafeMetadataEntry(named: #function + "-hardlink") { indexURL, outsideURL in
            try Data("outside".utf8).write(to: outsideURL)
            guard Darwin.link(outsideURL.path, indexURL.path) == 0 else { throw posixError() }
        }
        try assertUnsafeMetadataEntry(named: #function + "-fifo") { indexURL, _ in
            guard Darwin.mkfifo(indexURL.path, 0o600) == 0 else { throw posixError() }
        }
    }

    func testCaptureRejectsFileChangedAfterRead() throws {
        let fixture = try makeRepository(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let indexURL = fixture.metadata.appendingPathComponent("index.db")
        try Data("database".utf8).write(to: indexURL)
        let capture = RepositoryMetadataSnapshotCapture { name in
            guard name == "index.db" else { return }
            try Data("replace!".utf8).write(to: indexURL, options: .atomic)
        }

        assertPackageError(.unsafeFile) {
            try capture.capture(repositoryURL: fixture.repository)
        }
    }

    func testCaptureRejectsEarlierFileChangedWhileReadingSidecar() throws {
        let fixture = try makeRepository(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let indexURL = fixture.metadata.appendingPathComponent("index.db")
        try Data("database".utf8).write(to: indexURL)
        try Data("wal".utf8).write(to: fixture.metadata.appendingPathComponent("index.db-wal"))
        let capture = RepositoryMetadataSnapshotCapture { name in
            guard name == "index.db-wal" else { return }
            try Data("replace!".utf8).write(to: indexURL, options: .atomic)
        }

        assertPackageError(.unsafeFile) {
            try capture.capture(repositoryURL: fixture.repository)
        }
    }

    func testCaptureEnforcesPerFileAndAggregateLimits() throws {
        let perFile = try makeRepository(named: #function + "-file")
        defer { removeTestTemporaryItems(perFile.root) }
        try Data(repeating: 0x41, count: 9).write(to: perFile.metadata.appendingPathComponent("index.db"))
        let fileLimited = RepositoryMetadataSnapshotCapture(maximumFileBytes: 8, maximumTotalBytes: 16)
        assertPackageError(.limitExceeded) {
            try fileLimited.capture(repositoryURL: perFile.repository)
        }

        let aggregate = try makeRepository(named: #function + "-aggregate")
        defer { removeTestTemporaryItems(aggregate.root) }
        try Data(repeating: 0x41, count: 8).write(to: aggregate.metadata.appendingPathComponent("index.db"))
        try Data(repeating: 0x42, count: 8).write(to: aggregate.metadata.appendingPathComponent("index.db-wal"))
        let totalLimited = RepositoryMetadataSnapshotCapture(maximumFileBytes: 8, maximumTotalBytes: 12)
        assertPackageError(.limitExceeded) {
            try totalLimited.capture(repositoryURL: aggregate.repository)
        }
    }

    private var metadataPaths: [String] {
        DiagnosticPackageFormat.repositoryMetadataFileNames.map(DiagnosticPackageFormat.metadataRelativePath)
    }

    private func makeRepository(named name: String) throws -> RepositoryFixture {
        let root = try makeTestTemporaryDirectory(named: name)
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let metadata = repository.appendingPathComponent(".areamatrix", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        return RepositoryFixture(root: root, repository: repository, metadata: metadata)
    }

    private func assertUnsafeMetadataEntry(
        named name: String,
        setup: (URL, URL) throws -> Void
    ) throws {
        let fixture = try makeRepository(named: name)
        defer { removeTestTemporaryItems(fixture.root) }
        let indexURL = fixture.metadata.appendingPathComponent("index.db")
        let outsideURL = fixture.root.appendingPathComponent("outside.db")
        try setup(indexURL, outsideURL)
        assertPackageError(.unsafeFile) {
            try RepositoryMetadataSnapshotCapture().capture(repositoryURL: fixture.repository)
        }
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

final class DiagnosticPackageMetadataAttachmentTests: XCTestCase {
    private let reader = DiagnosticPackageReader()

    func testSensitiveEventsDoNotAuthorizeMetadataSnapshot() throws {
        let capture = StubRepositoryMetadataCapture(payloads: makeMetadataPayloads())
        let exporter = DiagnosticPackageExporter(metadataCapture: capture)

        let preview = try exporter.preview(
            events: [makeEvent()],
            privacySelection: DiagnosticPackagePrivacySelection(includeSensitiveFields: true),
            repositoryURL: URL(fileURLWithPath: "/not-read")
        )

        XCTAssertTrue(preview.manifest.includesSensitiveEvents)
        XCTAssertFalse(preview.manifest.includesMetadataSnapshot)
        XCTAssertTrue(preview.attachments.isEmpty)
        XCTAssertEqual(capture.callCount, 0)
    }

    func testMetadataSnapshotRequiresIndependentAuthorizationAndRepository() {
        let capture = StubRepositoryMetadataCapture(payloads: makeMetadataPayloads())
        let exporter = DiagnosticPackageExporter(metadataCapture: capture)
        assertPackageError(.invalidPackage) {
            try exporter.preview(
                events: [makeEvent()],
                privacySelection: DiagnosticPackagePrivacySelection(includeMetadataSnapshot: true),
                repositoryURL: nil
            )
        }
        XCTAssertEqual(capture.callCount, 0)
    }

    func testThreeAttachmentsPreservePreviewExportChecksumAndReaderDescriptors() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let payloads = makeMetadataPayloads()
        let exporter = DiagnosticPackageExporter(
            metadataCapture: StubRepositoryMetadataCapture(payloads: payloads),
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true)
        )
        let preview = try exporter.preview(
            events: [makeEvent()],
            privacySelection: DiagnosticPackagePrivacySelection(includeMetadataSnapshot: true),
            repositoryURL: root
        )
        let package = root.appendingPathComponent("metadata.amdiagnostic", isDirectory: true)

        _ = try exporter.export(preview, to: package)

        XCTAssertTrue(preview.manifest.includesMetadataSnapshot)
        XCTAssertEqual(preview.attachments, payloads)
        let checksums = try JSONDecoder().decode([String: String].self, from: preview.checksumsData)
        for payload in payloads {
            let exported = try Data(contentsOf: package.appendingPathComponent(payload.relativePath))
            XCTAssertEqual(exported, payload.data)
            XCTAssertEqual(checksums[payload.relativePath], sha256(payload.data))
        }
        let inspection = try reader.inspect(package)
        XCTAssertEqual(inspection.attachments.map(\.relativePath), payloads.map(\.relativePath))
        XCTAssertEqual(inspection.attachments.map(\.byteCount), payloads.map { Int64($0.data.count) })
        XCTAssertEqual(inspection.attachments.map(\.sha256), payloads.map { sha256($0.data) })
    }

    func testExportPreservesSHMWhenWALIsAbsent() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let allPayloads = makeMetadataPayloads()
        let payloads = [allPayloads[0], allPayloads[2]]
        let exporter = DiagnosticPackageExporter(
            metadataCapture: StubRepositoryMetadataCapture(payloads: payloads),
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true)
        )
        let preview = try exporter.preview(
            events: [makeEvent()],
            privacySelection: DiagnosticPackagePrivacySelection(includeMetadataSnapshot: true),
            repositoryURL: root
        )
        let package = root.appendingPathComponent("shm-only.amdiagnostic", isDirectory: true)

        _ = try exporter.export(preview, to: package)

        XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent(
            DiagnosticPackageFormat.metadataRelativePath("index.db-wal")
        ).path))
        XCTAssertEqual(
            try Data(contentsOf: package.appendingPathComponent(payloads[1].relativePath)),
            payloads[1].data
        )
        XCTAssertEqual(try reader.inspect(package).attachments.map(\.relativePath), payloads.map(\.relativePath))
    }

    func testReaderRejectsHostileMetadataAttachments() throws {
        try assertReaderRejectsReplacement(named: #function + "-symlink") { target, outside in
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        }
        try assertReaderRejectsReplacement(named: #function + "-hardlink") { target, outside in
            guard Darwin.link(outside.path, target.path) == 0 else { throw posixError() }
        }
        try assertReaderRejectsReplacement(named: #function + "-fifo") { target, _ in
            guard Darwin.mkfifo(target.path, 0o600) == 0 else { throw posixError() }
        }
    }

    func testReaderRejectsUnknownAttachmentAndTraversalChecksum() throws {
        let fixture = try makePackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let metadata = fixture.package
            .appendingPathComponent("attachments/repository-metadata", isDirectory: true)
        try Data("unknown".utf8).write(to: metadata.appendingPathComponent("unknown.db"))
        assertPackageError(.unexpectedEntry) { try reader.inspect(fixture.package) }
        try removeTestTemporaryItem(metadata.appendingPathComponent("unknown.db"))

        let checksumsURL = fixture.package.appendingPathComponent("checksums.json")
        var checksums = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: checksumsURL))
        checksums["attachments/../outside"] = String(repeating: "0", count: 64)
        try sortedEncoder().encode(checksums).write(to: checksumsURL)
        assertPackageError(.checksumMismatch) { try reader.inspect(fixture.package) }
    }

    func testReaderRejectsAttachmentChecksumTampering() throws {
        let fixture = try makePackage(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let index = fixture.package.appendingPathComponent(
            DiagnosticPackageFormat.metadataRelativePath("index.db")
        )
        try Data("tampered".utf8).write(to: index)
        assertPackageError(.checksumMismatch) { try reader.inspect(fixture.package) }
    }

    private func makePackage(named name: String) throws -> (root: URL, package: URL) {
        let root = try makeTestTemporaryDirectory(named: name)
        let exporter = DiagnosticPackageExporter(
            metadataCapture: StubRepositoryMetadataCapture(payloads: makeMetadataPayloads()),
            stagingRootURL: root.appendingPathComponent("staging", isDirectory: true)
        )
        let preview = try exporter.preview(
            events: [makeEvent()],
            privacySelection: DiagnosticPackagePrivacySelection(includeMetadataSnapshot: true),
            repositoryURL: root
        )
        let package = root.appendingPathComponent("fixture.amdiagnostic", isDirectory: true)
        _ = try exporter.export(preview, to: package)
        return (root, package)
    }

    private func assertReaderRejectsReplacement(
        named name: String,
        replacement: (URL, URL) throws -> Void
    ) throws {
        let fixture = try makePackage(named: name)
        defer { removeTestTemporaryItems(fixture.root) }
        let index = fixture.package.appendingPathComponent(
            DiagnosticPackageFormat.metadataRelativePath("index.db")
        )
        let outside = fixture.root.appendingPathComponent("outside.db")
        let original = try Data(contentsOf: index)
        try original.write(to: outside)
        try removeTestTemporaryItem(index)
        try replacement(index, outside)
        assertPackageError(.unsafeFile) { try reader.inspect(fixture.package) }
    }

    private func makeMetadataPayloads() -> [DiagnosticPackageAttachmentPayload] {
        zip(DiagnosticPackageFormat.repositoryMetadataFileNames, ["database", "wal", "shm"]).map {
            DiagnosticPackageAttachmentPayload(
                relativePath: DiagnosticPackageFormat.metadataRelativePath($0.0),
                data: Data($0.1.utf8)
            )
        }
    }

    private func makeEvent() -> ObservabilityEventSnapshot {
        ObservabilityEventSnapshot(
            schemaVersion: DiagnosticPackageFormat.eventSchemaVersion,
            eventID: UUID().uuidString.lowercased(),
            wallTimestampMilliseconds: 1_700_000_000_000,
            monotonicTimestampNanoseconds: 42,
            sequenceNumber: 1,
            sessionID: UUID().uuidString.lowercased(),
            incidentID: nil,
            traceID: UUID().uuidString.lowercased(),
            spanID: UUID().uuidString.lowercased(),
            parentSpanID: nil,
            operationID: nil,
            retryOfOperationID: nil,
            actionID: "diagnostics.export.confirmed",
            componentID: "macos.observability.runtime",
            layer: "platform",
            phase: "completed",
            severity: .info,
            outcome: "succeeded",
            durationMilliseconds: nil,
            resources: [],
            error: nil,
            attributes: [],
            privacy: "public",
            message: "Completed",
            target: "area_matrix_core",
            threadName: "main",
            buildContext: ObservabilityBuildContextSnapshot(
                producer: "areamatrix_macos",
                version: "0.1.0",
                build: "test",
                configuration: "debug",
                platform: "macos",
                architecture: "arm64"
            )
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sortedEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
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

private final class StubRepositoryMetadataCapture: RepositoryMetadataSnapshotCapturing {
    private(set) var callCount = 0
    private let payloads: [DiagnosticPackageAttachmentPayload]

    init(payloads: [DiagnosticPackageAttachmentPayload]) {
        self.payloads = payloads
    }

    func capture(repositoryURL _: URL) throws -> [DiagnosticPackageAttachmentPayload] {
        callCount += 1
        return payloads
    }
}
