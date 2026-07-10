@testable import AreaMatrix
import XCTest

typealias ImportSingleFileStaticICloudDownloader = StaticICloudPlaceholderDownloader
typealias ImportSingleFilePredictRequest = CategoryPredictionRequest
typealias ImportSingleFileRecordingPredictor = RecordingCategoryPredictor
typealias ImportSingleFileStaticRepositoryOpener = RecordingRepositoryOpener

struct ImportSingleFileStaticPreflight: ImportSingleFilePreflighting {
    var result: ImportSingleFilePreflightResult

    static func ready(
        targetRelativePath: String = "docs/source.pdf"
    ) -> ImportSingleFileStaticPreflight {
        ImportSingleFileStaticPreflight(result: .importSingleFileReadyFixture(
            targetRelativePath: targetRelativePath
        ))
    }

    func preflightSingleFileImport(
        request _: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult {
        result
    }
}

struct ImportSingleFileFileLoadRequest: Equatable {
    var repoPath: String
    var categories: Set<String?>
}

actor ImportSingleFileStaticFileLoader: ImportBatchCoreFileLoading {
    private let files: [FileEntrySnapshot]
    private var requests: [ImportSingleFileFileLoadRequest] = []

    init(files: [FileEntrySnapshot]) {
        self.files = files
    }

    func loadImportPreviewFiles(repoPath: String, categories: Set<String?>) async throws -> [FileEntrySnapshot] {
        requests.append(ImportSingleFileFileLoadRequest(repoPath: repoPath, categories: categories))
        return files
    }

    func recordedRequests() -> [ImportSingleFileFileLoadRequest] {
        requests
    }

    func assertRecordedRequests(
        _ expectedRequests: [ImportSingleFileFileLoadRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests, expectedRequests, file: file, line: line)
    }
}
