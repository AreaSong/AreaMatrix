@testable import AreaMatrix
import Foundation
import XCTest

final class ExternalURLPolicyTests: XCTestCase {
    func testValidatedHTTPSURLAllowsHTTPSWithHost() throws {
        let url = try XCTUnwrap(ExternalURLPolicy.validatedHTTPSURL("https://github.com/AreaSong/AreaMatrix"))

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
    }

    func testValidatedHTTPSURLRejectsNonHTTPSAndMissingHost() {
        let rejectedValues = [
            "http://example.com",
            "file:///tmp/areamatrix",
            "mailto:support@example.com",
            "areamatrix://settings",
            "javascript:alert(1)",
            "not a url",
            "https:/missing-host"
        ]

        for value in rejectedValues {
            XCTAssertNil(ExternalURLPolicy.validatedHTTPSURL(value), value)
        }
    }

    func testAboutExternalLinksStayHTTPS() {
        let invalidLinks = AboutExternalLink.allCases
            .map(\.urlString)
            .filter { ExternalURLPolicy.validatedHTTPSURL($0) == nil }

        XCTAssertEqual(invalidLinks, [])
    }

    @MainActor
    func testExternalURLStringOpenerOpensValidatedHTTPSURL() throws {
        let platformOpener = RecordingExternalURLPlatformOpener()
        let opener = NSWorkspaceExternalURLStringOpener(platformOpener: platformOpener)

        try opener.openHTTPSURLString("https://example.com/path?q=1")

        platformOpener.assertOpenedURLStrings(["https://example.com/path?q=1"])
    }

    @MainActor
    func testExternalURLStringOpenerRejectsInvalidURLBeforePlatformOpen() {
        let platformOpener = RecordingExternalURLPlatformOpener()
        let opener = NSWorkspaceExternalURLStringOpener(platformOpener: platformOpener)

        XCTAssertThrowsError(try opener.openHTTPSURLString("http://example.com")) { error in
            XCTAssertEqual(error as? ExternalURLOpenError, .invalidURL("http://example.com"))
        }
        platformOpener.assertNoOpenedURLs()
    }

    @MainActor
    func testExternalURLStringOpenerMapsRejectedOpen() {
        let platformOpener = RecordingExternalURLPlatformOpener(result: false)
        let opener = NSWorkspaceExternalURLStringOpener(platformOpener: platformOpener)

        XCTAssertThrowsError(try opener.openHTTPSURLString("https://example.com")) { error in
            XCTAssertEqual(error as? ExternalURLOpenError, .openRejected("https://example.com"))
        }
        platformOpener.assertOpenedURLStrings(["https://example.com"])
    }

    @MainActor
    func testExternalHelpOpenersUseSharedExternalURLOpener() throws {
        let aboutExternalURLOpener = RecordingExternalURLStringOpener()
        let openedURL = try NSWorkspaceAboutExternalLinkOpener(
            externalURLOpener: aboutExternalURLOpener
        ).open(link: .github)
        XCTAssertEqual(openedURL, AboutExternalLink.github.urlString)
        aboutExternalURLOpener.assertOpenedValues([AboutExternalLink.github.urlString])

        let iCloudExternalURLOpener = RecordingExternalURLStringOpener()
        try NSWorkspaceICloudHelpOpener(externalURLOpener: iCloudExternalURLOpener).openICloudHelp()
        iCloudExternalURLOpener.assertOpenedValues([
            "https://support.apple.com/guide/mac-help/use-icloud-drive-mchl1a02d711/mac"
        ])

        let localModelExternalURLOpener = RecordingExternalURLStringOpener()
        try NSWorkspaceLocalModelInstallHelpOpener(
            externalURLOpener: localModelExternalURLOpener
        ).openLocalModelInstallHelp()
        localModelExternalURLOpener.assertOpenedValues(["https://github.com/AreaSong/AreaMatrix"])
    }

    @MainActor
    func testExternalHelpOpenersPreserveInvalidURLMapping() {
        let invalidURLError = ExternalURLOpenError.invalidURL("invalid")

        XCTAssertThrowsError(try NSWorkspaceAboutExternalLinkOpener(
            externalURLOpener: RecordingExternalURLStringOpener(result: .failure(invalidURLError))
        ).open(link: .github)) { error in
            XCTAssertEqual(error as? AboutSettingsPlatformError, .invalidURL(AboutExternalLink.github.urlString))
        }

        XCTAssertThrowsError(try NSWorkspaceICloudHelpOpener(
            externalURLOpener: RecordingExternalURLStringOpener(result: .failure(invalidURLError))
        ).openICloudHelp()) { error in
            XCTAssertEqual(error as? ICloudHelpOpenError, .helpURLUnavailable)
        }

        XCTAssertThrowsError(try NSWorkspaceLocalModelInstallHelpOpener(
            externalURLOpener: RecordingExternalURLStringOpener(result: .failure(invalidURLError))
        ).openLocalModelInstallHelp()) { error in
            XCTAssertEqual(error as? LocalModelStatusActionError, .unavailable)
        }
    }

    @MainActor
    func testExternalHelpOpenersPreserveOpenRejectedMapping() {
        let rejectedError = ExternalURLOpenError.openRejected("https://example.com")

        XCTAssertThrowsError(try NSWorkspaceAboutExternalLinkOpener(
            externalURLOpener: RecordingExternalURLStringOpener(result: .failure(rejectedError))
        ).open(link: .github)) { error in
            XCTAssertEqual(error as? AboutSettingsPlatformError, .openRejected(AboutExternalLink.github.urlString))
        }

        XCTAssertThrowsError(try NSWorkspaceICloudHelpOpener(
            externalURLOpener: RecordingExternalURLStringOpener(result: .failure(rejectedError))
        ).openICloudHelp()) { error in
            XCTAssertEqual(error as? ICloudHelpOpenError, .openRejected)
        }

        XCTAssertThrowsError(try NSWorkspaceLocalModelInstallHelpOpener(
            externalURLOpener: RecordingExternalURLStringOpener(result: .failure(rejectedError))
        ).openLocalModelInstallHelp()) { error in
            XCTAssertEqual(error as? LocalModelStatusActionError, .openRejected)
        }
    }
}

@MainActor
private final class RecordingExternalURLPlatformOpener: ExternalURLPlatformOpening {
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
private final class RecordingExternalURLStringOpener: ExternalURLStringOpening {
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
