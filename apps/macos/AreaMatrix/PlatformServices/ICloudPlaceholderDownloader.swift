import Foundation

protocol ICloudPlaceholderDownloading: Sendable {
    func downloadPlaceholder(at sourceURL: URL) async throws
}

enum ICloudPlaceholderDownloadError: LocalizedError, Equatable {
    case timedOut(path: String)

    var errorDescription: String? {
        switch self {
        case let .timedOut(path):
            L10n.format("icloud.download.timeout", path)
        }
    }
}

struct LocalICloudPlaceholderDownloader: ICloudPlaceholderDownloading {
    typealias StartDownload = @Sendable (URL) throws -> Void
    typealias IsMaterialized = @Sendable (URL) throws -> Bool
    typealias Sleep = @Sendable (UInt64) async throws -> Void

    private let startDownload: StartDownload
    private let isMaterialized: IsMaterialized
    private let sleep: Sleep
    private let pollIntervalNanoseconds: UInt64
    private let maximumPollCount: Int

    init(
        startDownload: @escaping StartDownload = { sourceURL in
            try FileManager.default.startDownloadingUbiquitousItem(at: sourceURL)
        },
        isMaterialized: @escaping IsMaterialized = { sourceURL in
            let values = try sourceURL.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingErrorKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            if let error = values.ubiquitousItemDownloadingError { throw error }
            guard values.isUbiquitousItem == true else { return true }
            return values.ubiquitousItemDownloadingStatus == .current ||
                values.ubiquitousItemDownloadingStatus == .downloaded
        },
        sleep: @escaping Sleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        },
        pollIntervalNanoseconds: UInt64 = 250_000_000,
        maximumPollCount: Int = 240
    ) {
        self.startDownload = startDownload
        self.isMaterialized = isMaterialized
        self.sleep = sleep
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maximumPollCount = max(1, maximumPollCount)
    }

    func downloadPlaceholder(at sourceURL: URL) async throws {
        try Task.checkCancellation()
        if try isMaterialized(sourceURL) { return }
        try startDownload(sourceURL)

        for pollIndex in 0 ..< maximumPollCount {
            try Task.checkCancellation()
            if try isMaterialized(sourceURL) { return }
            guard pollIndex + 1 < maximumPollCount else {
                throw ICloudPlaceholderDownloadError.timedOut(path: sourceURL.path)
            }
            try await sleep(pollIntervalNanoseconds)
        }
    }
}
