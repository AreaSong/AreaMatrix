@testable import AreaMatrix
import Foundation

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

    func recordedURLs() -> [URL] {
        urls
    }
}
