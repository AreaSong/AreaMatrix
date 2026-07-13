@testable import AreaMatrix
import Foundation
import XCTest

struct StaticICloudPlaceholderDownloader: ICloudPlaceholderDownloading {
    var error: Error?

    func downloadPlaceholder(at _: URL) async throws {
        if let error {
            throw error
        }
    }
}

actor RecordingICloudPlaceholderDownloader: ICloudPlaceholderDownloading {
    private var urls: [URL] = []
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func downloadPlaceholder(at sourceURL: URL) async throws {
        urls.append(sourceURL)
        if let error {
            throw error
        }
    }

    func assertDownloadedURLs(
        _ expectedURLs: [URL],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(urls, expectedURLs, file: file, line: line)
    }
}
