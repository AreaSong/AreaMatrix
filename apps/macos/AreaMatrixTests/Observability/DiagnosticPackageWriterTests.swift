@testable import AreaMatrix
import CryptoKit
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

    func testPublishingRejectsCoherentlyRechecksummedStageMutation() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let state = PublishState()
        let operations = DiagnosticPackagePublishOperations(
            synchronize: { Darwin.fsync($0) },
            renameExclusive: { renameatx_np($0, $1, $2, $3, $4) },
            beforeStageCopy: { descriptor in
                state.didMutateStage = (try? Self.coherentlyMutateStage(descriptor)) != nil
            }
        )
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let destination = root.appendingPathComponent("result.amdiagnostic", isDirectory: true)
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: stagingRoot,
            publishOperations: operations
        )
        let preview = try exporter.preview(events: [makeEvent()])

        assertPackageError(.invalidPackage) {
            try exporter.export(preview, to: destination)
        }

        XCTAssertTrue(state.didMutateStage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try directoryNames(stagingRoot), [])
        XCTAssertTrue(try partialNames(root).isEmpty)
    }

    func testCleanupNeverUnlinksConcurrentReplacementChild() throws {
        let root = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(root) }
        let state = PublishState()
        let replacement = Data("concurrent replacement must survive".utf8)
        let operations = DiagnosticPackagePublishOperations(
            synchronize: { Darwin.fsync($0) },
            renameExclusive: { renameatx_np($0, $1, $2, $3, $4) },
            beforeCleanup: { descriptor in
                guard !state.didReplaceCleanupChild else { return }
                state.didReplaceCleanupChild = Self.replaceSummary(replacement, descriptor: descriptor)
            }
        )
        let stagingRoot = root.appendingPathComponent("staging", isDirectory: true)
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: stagingRoot,
            publishOperations: operations
        )
        let valid = try exporter.preview(events: [makeEvent()])
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
            try exporter.export(invalid, to: root.appendingPathComponent("result.amdiagnostic"))
        }

        XCTAssertTrue(state.didReplaceCleanupChild)
        let residueName = try XCTUnwrap(directoryNames(stagingRoot).first)
        let residue = stagingRoot.appendingPathComponent(residueName, isDirectory: true)
        XCTAssertEqual(try Data(contentsOf: residue.appendingPathComponent("summary.txt")), replacement)
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

    func testPublishRejectsDestinationParentReplacementInsteadOfReturningWrongURL() throws {
        let container = try makeTestTemporaryDirectory(named: #function)
        defer { removeTestTemporaryItems(container) }
        let parent = container.appendingPathComponent("destination", isDirectory: true)
        let displacedParent = container.appendingPathComponent("displaced", isDirectory: true)
        let stagingRoot = container.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let state = PublishState()
        let sentinel = Data("concurrent parent replacement".utf8)
        let operations = DiagnosticPackagePublishOperations(
            synchronize: { Darwin.fsync($0) },
            renameExclusive: { renameatx_np($0, $1, $2, $3, $4) },
            beforePublish: { _ in
                guard !state.didReplaceDestinationParent else { return }
                do {
                    try FileManager.default.moveItem(at: parent, to: displacedParent)
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
                    try sentinel.write(to: parent.appendingPathComponent("sentinel.txt"))
                    state.didReplaceDestinationParent = true
                } catch {
                    state.destinationParentReplacementError = error
                }
            }
        )
        let exporter = DiagnosticPackageExporter(
            stagingRootURL: stagingRoot,
            publishOperations: operations
        )
        let destination = parent.appendingPathComponent("result.amdiagnostic", isDirectory: true)
        let preview = try exporter.preview(events: [makeEvent()])

        assertPackageError(.invalidDestination) {
            try exporter.export(preview, to: destination)
        }

        XCTAssertNil(state.destinationParentReplacementError)
        XCTAssertTrue(state.didReplaceDestinationParent)
        XCTAssertEqual(try Data(contentsOf: parent.appendingPathComponent("sentinel.txt")), sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try partialNames(displacedParent).isEmpty)
        XCTAssertEqual(try directoryNames(stagingRoot), [])
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
        private var storedDidReplaceCleanupChild = false
        private var storedDidReplaceDestinationParent = false
        private var storedDestinationParentReplacementError: Error?

        var didRename: Bool {
            get { withLock { storedDidRename } }
            set { withLock { storedDidRename = newValue } }
        }

        var didMutateStage: Bool {
            get { withLock { storedDidMutateStage } }
            set { withLock { storedDidMutateStage = newValue } }
        }

        var didReplaceCleanupChild: Bool {
            get { withLock { storedDidReplaceCleanupChild } }
            set { withLock { storedDidReplaceCleanupChild = newValue } }
        }

        var didReplaceDestinationParent: Bool {
            get { withLock { storedDidReplaceDestinationParent } }
            set { withLock { storedDidReplaceDestinationParent = newValue } }
        }

        var destinationParentReplacementError: Error? {
            get { withLock { storedDestinationParentReplacementError } }
            set { withLock { storedDestinationParentReplacementError = newValue } }
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

    static func coherentlyMutateStage(_ descriptor: Int32) throws {
        var line = try readFile(named: "events.jsonl", descriptor: descriptor)
        if line.last == 0x0A { line.removeLast() }
        var event = try JSONDecoder().decode(ObservabilityEventSnapshot.self, from: line)
        event.message = "coherently mutated after preview"
        let eventEncoder = JSONEncoder()
        eventEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var mutated = try eventEncoder.encode(event)
        mutated.append(0x0A)
        try writeFile(mutated, named: "events.jsonl", descriptor: descriptor)
        var checksums = try JSONDecoder().decode(
            [String: String].self,
            from: readFile(named: "checksums.json", descriptor: descriptor)
        )
        checksums["events.jsonl"] = SHA256.hash(data: mutated)
            .map { String(format: "%02x", $0) }
            .joined()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try writeFile(encoder.encode(checksums), named: "checksums.json", descriptor: descriptor)
    }

    static func readFile(named name: String, descriptor: Int32) throws -> Data {
        let file = openat(descriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard file >= 0 else { throw DiagnosticPackageError.unsafeFile }
        defer { close(file) }
        return try FileHandle(fileDescriptor: file, closeOnDealloc: false).readToEnd()
            ?? Data()
    }

    static func writeFile(_ data: Data, named name: String, descriptor: Int32) throws {
        let file = openat(descriptor, name, O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW)
        guard file >= 0 else { throw DiagnosticPackageError.unsafeFile }
        defer { close(file) }
        try FileHandle(fileDescriptor: file, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(file) == 0 else { throw DiagnosticPackageError.unsafeFile }
    }

    static func replaceSummary(_ data: Data, descriptor: Int32) -> Bool {
        guard unlinkat(descriptor, "summary.txt", 0) == 0 else { return false }
        let replacement = openat(
            descriptor,
            "summary.txt",
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard replacement >= 0 else { return false }
        defer { close(replacement) }
        do {
            try FileHandle(fileDescriptor: replacement, closeOnDealloc: false).write(contentsOf: data)
            return fsync(replacement) == 0
        } catch {
            return false
        }
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
