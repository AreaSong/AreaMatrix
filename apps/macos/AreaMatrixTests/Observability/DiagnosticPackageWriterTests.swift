@testable import AreaMatrix
import Darwin
import Foundation
import XCTest

final class DiagnosticPackageWriterTests: XCTestCase {
    func testStagingSelfReadRejectsInvalidPreviewBeforePublishing() throws {
        let fixture = try makeFixture(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let valid = try fixture.exporter.preview(events: [makeEvent()])
        let invalid = DiagnosticPackagePreview(
            manifest: valid.manifest,
            manifestData: valid.manifestData,
            eventsData: valid.eventsData,
            environmentData: valid.environmentData,
            privacyReportData: valid.privacyReportData,
            summaryData: valid.summaryData,
            checksumsData: Data("{}".utf8),
            privacyReport: valid.privacyReport,
            attachments: valid.attachments
        )

        assertPackageError(.checksumMismatch) {
            try fixture.exporter.export(invalid, to: fixture.destination)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.path))
        XCTAssertEqual(try directoryNames(fixture.stagingRoot), [])
        XCTAssertTrue(try partialNames(fixture.root).isEmpty)
    }

    func testPublishingCopiesValidatedStageAndRevalidatesPartial() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let state = PublishState()
        let operations = DiagnosticPackagePublishOperations(
            synchronize: { Darwin.fsync($0) },
            renameExclusive: { renameatx_np($0, $1, $2, $3, $4) },
            beforeStageCopy: { stageDescriptor in
                let summary = openat(
                    stageDescriptor,
                    "summary.txt",
                    O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW
                )
                guard summary >= 0 else { return }
                defer { close(summary) }
                let tampered = Data("tampered after stage validation".utf8)
                let wroteAll = tampered.withUnsafeBytes { bytes in
                    Darwin.write(summary, bytes.baseAddress, bytes.count) == bytes.count
                }
                state.didMutateStage = wroteAll && Darwin.fsync(summary) == 0
            }
        )
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let destination = root.appendingPathComponent("result.amdiagnostic", isDirectory: true)
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: stagingRoot,
            publishOperations: operations
        )
        let preview = try exporter.preview(events: [makeEvent()])

        assertPackageError(.checksumMismatch) {
            try exporter.export(preview, to: destination)
        }

        XCTAssertTrue(state.didMutateStage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try directoryNames(stagingRoot), [])
        XCTAssertTrue(try partialNames(root).isEmpty)
    }

    func testPublishRefusesExistingFileDirectoryAndSymlinkWithoutChangingThem() throws {
        let fixture = try makeFixture(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let preview = try fixture.exporter.preview(events: [makeEvent()])
        let sentinelData = Data("keep me".utf8)

        let file = fixture.root.appendingPathComponent("existing-file.amdiagnostic")
        try sentinelData.write(to: file)
        assertPackageError(.destinationExists) { try fixture.exporter.export(preview, to: file) }
        XCTAssertEqual(try Data(contentsOf: file), sentinelData)

        let directory = fixture.root.appendingPathComponent("existing-directory.amdiagnostic", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let sentinel = directory.appendingPathComponent("sentinel.txt")
        try sentinelData.write(to: sentinel)
        assertPackageError(.destinationExists) { try fixture.exporter.export(preview, to: directory) }
        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelData)

        let symlink = fixture.root.appendingPathComponent("existing-symlink.amdiagnostic")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: directory)
        assertPackageError(.destinationExists) { try fixture.exporter.export(preview, to: symlink) }
        let values = try symlink.resourceValues(forKeys: [.isSymbolicLinkKey])
        XCTAssertEqual(values.isSymbolicLink, true)

        XCTAssertEqual(try directoryNames(fixture.stagingRoot), [])
        XCTAssertTrue(try partialNames(fixture.root).isEmpty)
    }

    func testTargetCreatedDuringPublishWinsWithoutBeingOverwritten() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let destination = root.appendingPathComponent("race.amdiagnostic", isDirectory: true)
        let operations = DiagnosticPackagePublishOperations(
            synchronize: { Darwin.fsync($0) },
            renameExclusive: { sourceFD, source, targetFD, target, flags in
                guard mkdirat(targetFD, target, 0o700) == 0 else { return -1 }
                return renameatx_np(sourceFD, source, targetFD, target, flags)
            }
        )
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: stagingRoot,
            publishOperations: operations
        )
        let preview = try exporter.preview(events: [makeEvent()])

        assertPackageError(.destinationExists) {
            try exporter.export(preview, to: destination)
        }

        XCTAssertTrue(try directoryNames(destination).isEmpty)
        XCTAssertEqual(try directoryNames(stagingRoot), [])
        XCTAssertTrue(try partialNames(root).isEmpty)
    }

    func testPostRenameDirectorySyncFailureReportsUncertainDurability() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let state = PublishState()
        let operations = DiagnosticPackagePublishOperations(
            synchronize: { descriptor in
                if state.didRename {
                    errno = EIO
                    return -1
                }
                return Darwin.fsync(descriptor)
            },
            renameExclusive: { sourceFD, source, targetFD, target, flags in
                let result = renameatx_np(sourceFD, source, targetFD, target, flags)
                if result == 0 { state.didRename = true }
                return result
            }
        )
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: stagingRoot,
            publishOperations: operations
        )
        let destination = root.appendingPathComponent("uncertain.amdiagnostic", isDirectory: true)
        let preview = try exporter.preview(events: [makeEvent()])

        assertPackageError(.durabilityUncertain) {
            try exporter.export(preview, to: destination)
        }

        XCTAssertEqual(try DiagnosticPackageReader().inspect(destination).manifest, preview.manifest)
        XCTAssertEqual(try directoryNames(stagingRoot), [])
        XCTAssertTrue(try partialNames(root).isEmpty)
    }
}

private extension DiagnosticPackageWriterTests {
    final class PublishState: @unchecked Sendable {
        private let lock = NSLock()
        private var storedDidRename = false
        private var storedDidMutateStage = false

        var didRename: Bool {
            get { withLock { storedDidRename } }
            set { withLock { storedDidRename = newValue } }
        }

        var didMutateStage: Bool {
            get { withLock { storedDidMutateStage } }
            set { withLock { storedDidMutateStage = newValue } }
        }

        private func withLock<T>(_ operation: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return operation()
        }
    }

    struct Fixture {
        let root: URL
        let stagingRoot: URL
        let destination: URL
        let exporter: DiagnosticPackageExporter
    }

    func makeFixture(named name: String) throws -> Fixture {
        let root = try makeTestTemporaryDirectory(named: name)
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        return Fixture(
            root: root,
            stagingRoot: stagingRoot,
            destination: root.appendingPathComponent("result.amdiagnostic", isDirectory: true),
            exporter: DiagnosticPackageExporter(stagingRootURL: stagingRoot)
        )
    }

    func directoryNames(_ directory: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    func partialNames(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
            $0.hasPrefix(".amdiagnostic-partial-")
        }
    }

    func makeEvent() -> ObservabilityEventSnapshot {
        var value = event(
            id: UUID().uuidString.lowercased(),
            timestamp: 1_700_000_000_000,
            sessionID: UUID().uuidString.lowercased(),
            message: "Completed"
        )
        value.durationMilliseconds = 1
        value.target = "area_matrix_core"
        value.threadName = "main"
        return value
    }

    func assertPackageError(
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
}
