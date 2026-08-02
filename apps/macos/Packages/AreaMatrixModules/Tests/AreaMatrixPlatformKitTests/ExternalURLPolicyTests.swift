@testable import AreaMatrixPlatformKit
import XCTest

final class ExternalURLPolicyTests: XCTestCase {
    func testOnlyHTTPSURLsWithHostsAreAccepted() {
        XCTAssertNotNil(ExternalURLPolicy.validatedHTTPSURL("https://example.com/path"))
        XCTAssertNotNil(ExternalURLPolicy.validatedHTTPSURL("HTTPS://example.com"))
        XCTAssertNil(ExternalURLPolicy.validatedHTTPSURL("http://example.com"))
        XCTAssertNil(ExternalURLPolicy.validatedHTTPSURL("https:///missing-host"))
    }

    @MainActor
    func testStringOpenerValidatesBeforeCallingPlatform() throws {
        let opener = RecordingPlatformOpener(result: true)
        let stringOpener = NSWorkspaceExternalURLStringOpener(platformOpener: opener)

        try stringOpener.openHTTPSURLString("https://example.com")
        let openedCount = opener.openedURLs.count
        XCTAssertEqual(openedCount, 1)

        do {
            try stringOpener.openHTTPSURLString("http://example.com")
            XCTFail("Expected invalid URL")
        } catch let error as ExternalURLOpenError {
            XCTAssertEqual(error, .invalidURL("http://example.com"))
        }
        let finalOpenedCount = opener.openedURLs.count
        XCTAssertEqual(finalOpenedCount, 1)
    }
}

@MainActor
private final class RecordingPlatformOpener: ExternalURLPlatformOpening {
    let result: Bool
    private(set) var openedURLs: [URL] = []

    init(result: Bool) {
        self.result = result
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return result
    }
}
