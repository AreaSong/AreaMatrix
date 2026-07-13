@testable import AreaMatrix
import Foundation
import XCTest

@MainActor
final class RecordingLocalFileURLResourceReader: LocalFileURLResourceReading {
    private let snapshot: LocalFileURLResourceSnapshot
    private var requestedURLs: [URL] = []

    init(snapshot: LocalFileURLResourceSnapshot) {
        self.snapshot = snapshot
    }

    func resourceSnapshot(for url: URL) -> LocalFileURLResourceSnapshot {
        requestedURLs.append(url)
        return snapshot
    }

    func assertRequestedPaths(
        _ expectedPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestedURLs.map(\.path), expectedPaths, file: file, line: line)
    }
}

@MainActor
final class RecordingLocalFileURLPlatformOpener: LocalFileURLPlatformOpening {
    private let openResult: Bool
    private var openedURLs: [URL] = []
    private var revealedURLs: [[URL]] = []

    init(openResult: Bool = true) {
        self.openResult = openResult
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }

    func reveal(_ urls: [URL]) {
        revealedURLs.append(urls)
    }

    func assertOpenedPaths(
        _ expectedPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(openedURLs.map(\.path), expectedPaths, file: file, line: line)
    }

    func assertNoOpenedURLs(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertOpenedPaths([], file: file, line: line)
    }

    func assertRevealedPathGroups(
        _ expectedPathGroups: [[String]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(revealedURLs.map { $0.map(\.path) }, expectedPathGroups, file: file, line: line)
    }

    func assertNoRevealedURLs(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRevealedPathGroups([], file: file, line: line)
    }
}

@MainActor
final class RecordingLocalFileURLOpener: LocalFileURLOpening {
    private let result: Result<Void, Error>
    private var openURLs: [URL] = []
    private var openExistingRequests: [(url: URL, requiresDirectory: Bool)] = []
    private var revealExistingURLs: [URL] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func open(_ url: URL) throws {
        openURLs.append(url)
        try result.get()
    }

    func openExisting(_ url: URL, requiresDirectory: Bool) throws {
        openExistingRequests.append((url, requiresDirectory))
        try result.get()
    }

    func revealExisting(_ url: URL) throws {
        revealExistingURLs.append(url)
        try result.get()
    }

    func assertOpenedPaths(
        _ expectedPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(openURLs.map(\.path), expectedPaths, file: file, line: line)
    }

    func assertNoOpenedURLs(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertOpenedPaths([], file: file, line: line)
    }

    func assertOpenExistingRequests(
        _ expectedRequests: [(path: String, requiresDirectory: Bool)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(openExistingRequests.map(\.url.path), expectedRequests.map(\.path), file: file, line: line)
        XCTAssertEqual(
            openExistingRequests.map(\.requiresDirectory),
            expectedRequests.map(\.requiresDirectory),
            file: file,
            line: line
        )
    }

    func assertNoOpenExistingRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertOpenExistingRequests([], file: file, line: line)
    }

    func assertRevealExistingPaths(
        _ expectedPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(revealExistingURLs.map(\.path), expectedPaths, file: file, line: line)
    }

    func assertNoRevealExistingURLs(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRevealExistingPaths([], file: file, line: line)
    }
}
