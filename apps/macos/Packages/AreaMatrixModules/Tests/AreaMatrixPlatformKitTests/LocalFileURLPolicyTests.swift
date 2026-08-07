@testable import AreaMatrixPlatformKit
import Foundation
import XCTest

@MainActor
final class LocalFileURLPolicyTests: XCTestCase {
    func testOpenExistingChecksResourceAndDelegatesToPlatform() throws {
        let reader = RecordingResourceReader(snapshot: .init(exists: true, isDirectory: true))
        let opener = RecordingLocalFilePlatformOpener(openResult: true)
        let sut = NSWorkspaceLocalFileURLOpener(resourceReader: reader, platformOpener: opener)
        let url = URL(fileURLWithPath: "/tmp/repository", isDirectory: true)

        try sut.openExisting(url, requiresDirectory: true)

        XCTAssertEqual(reader.requestedURLs, [url])
        XCTAssertEqual(opener.openedURLs, [url])
    }

    func testOpenExistingRejectsMissingAndNonDirectoryBeforeOpening() {
        let missingReader = RecordingResourceReader(snapshot: .init(exists: false, isDirectory: false))
        let opener = RecordingLocalFilePlatformOpener(openResult: true)
        let missingSut = NSWorkspaceLocalFileURLOpener(resourceReader: missingReader, platformOpener: opener)
        let missingURL = URL(fileURLWithPath: "/tmp/missing")

        XCTAssertThrowsError(try missingSut.openExisting(missingURL, requiresDirectory: false)) { error in
            XCTAssertEqual(error as? LocalFileURLOpenError, .missing(missingURL.path))
        }

        let fileReader = RecordingResourceReader(snapshot: .init(exists: true, isDirectory: false))
        let fileSut = NSWorkspaceLocalFileURLOpener(resourceReader: fileReader, platformOpener: opener)
        let fileURL = URL(fileURLWithPath: "/tmp/file.txt")

        XCTAssertThrowsError(try fileSut.openExisting(fileURL, requiresDirectory: true)) { error in
            XCTAssertEqual(error as? LocalFileURLOpenError, .notDirectory(fileURL.path))
        }
        XCTAssertTrue(opener.openedURLs.isEmpty)
    }

    func testRevealExistingChecksResourceAndDelegatesToPlatform() throws {
        let reader = RecordingResourceReader(snapshot: .init(exists: true, isDirectory: false))
        let opener = RecordingLocalFilePlatformOpener(openResult: true)
        let sut = NSWorkspaceLocalFileURLOpener(resourceReader: reader, platformOpener: opener)
        let url = URL(fileURLWithPath: "/tmp/file.txt")

        try sut.revealExisting(url)

        XCTAssertEqual(opener.revealedURLGroups, [[url]])
    }
}

@MainActor
private final class RecordingResourceReader: LocalFileURLResourceReading {
    let snapshot: LocalFileURLResourceSnapshot
    private(set) var requestedURLs: [URL] = []

    init(snapshot: LocalFileURLResourceSnapshot) {
        self.snapshot = snapshot
    }

    func resourceSnapshot(for url: URL) -> LocalFileURLResourceSnapshot {
        requestedURLs.append(url)
        return snapshot
    }
}

@MainActor
private final class RecordingLocalFilePlatformOpener: LocalFileURLPlatformOpening {
    let openResult: Bool
    private(set) var openedURLs: [URL] = []
    private(set) var revealedURLGroups: [[URL]] = []

    init(openResult: Bool) {
        self.openResult = openResult
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }

    func reveal(_ urls: [URL]) {
        revealedURLGroups.append(urls)
    }
}
