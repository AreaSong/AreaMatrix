@testable import AreaMatrix
import Foundation
import XCTest

@MainActor
final class RecordingExternalURLPlatformOpener: ExternalURLPlatformOpening {
    private let result: Bool
    private var openedURLs: [URL] = []

    init(result: Bool = true) {
        self.result = result
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return result
    }

    func assertOpenedURLStrings(
        _ expectedURLStrings: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(openedURLs.map(\.absoluteString), expectedURLStrings, file: file, line: line)
    }

    func assertNoOpenedURLs(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertOpenedURLStrings([], file: file, line: line)
    }
}

@MainActor
final class RecordingExternalURLStringOpener: ExternalURLStringOpening {
    private let result: Result<Void, Error>
    private var openedValues: [String] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openHTTPSURLString(_ value: String) throws {
        openedValues.append(value)
        try result.get()
    }

    func assertOpenedValues(
        _ expectedValues: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(openedValues, expectedValues, file: file, line: line)
    }
}
