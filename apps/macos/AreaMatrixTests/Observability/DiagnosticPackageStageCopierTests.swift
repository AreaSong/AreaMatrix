@testable import AreaMatrix
import Darwin
import Foundation
import XCTest

final class DiagnosticPackageStageCopierTests: XCTestCase {
    func testStageCopierRejectsFIFOWithoutBlocking() throws {
        let fixture = try makeFixture(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let summary = fixture.source.appendingPathComponent("summary.txt")
        try removeTestTemporaryItem(summary)
        guard mkfifo(summary.path, 0o600) == 0 else { throw CocoaError(.fileWriteUnknown) }

        assertPackageError(.unsafeFile) {
            try copyStage(fixture)
        }
    }

    func testStageCopierRejectsSourcePathSwapAfterOpen() throws {
        let fixture = try makeFixture(named: #function)
        defer { removeTestTemporaryItems(fixture.root) }
        let replacementName = "replacement.txt"
        let replacement = fixture.source.appendingPathComponent(replacementName)
        try Data("summary.txt".utf8).write(to: replacement)
        let sourceDescriptor = open(fixture.source.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        let destinationDescriptor = open(fixture.destination.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard sourceDescriptor >= 0, destinationDescriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        defer {
            close(sourceDescriptor)
            close(destinationDescriptor)
        }

        assertPackageError(.unsafeFile) {
            try DiagnosticPackageStageCopier.copy(
                from: sourceDescriptor,
                to: destinationDescriptor,
                attachments: [],
                synchronize: { fsync($0) },
                beforeFinalSourceValidation: { name in
                    guard name == "summary.txt" else { return }
                    renameat(sourceDescriptor, replacementName, sourceDescriptor, name)
                }
            )
        }
    }
}

private extension DiagnosticPackageStageCopierTests {
    struct Fixture {
        let root: URL
        let source: URL
        let destination: URL
    }

    func makeFixture(named name: String) throws -> Fixture {
        let root = try makeTestTemporaryDirectory(named: name)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        for fileName in DiagnosticPackageFormat.payloadFileNames {
            try Data(fileName.utf8).write(to: source.appendingPathComponent(fileName))
        }
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent(DiagnosticPackageFormat.attachmentsDirectoryName),
            withIntermediateDirectories: false
        )
        return Fixture(root: root, source: source, destination: destination)
    }

    func copyStage(_ fixture: Fixture) throws {
        let source = open(fixture.source.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        let destination = open(fixture.destination.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard source >= 0, destination >= 0 else { throw CocoaError(.fileReadUnknown) }
        defer {
            close(source)
            close(destination)
        }
        try DiagnosticPackageStageCopier.copy(
            from: source,
            to: destination,
            attachments: [],
            synchronize: { fsync($0) }
        )
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
