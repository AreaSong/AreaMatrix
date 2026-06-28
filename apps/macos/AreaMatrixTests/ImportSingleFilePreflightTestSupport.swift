@testable import AreaMatrix
import Foundation

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
}

extension ImportSingleFilePreflightRequest {
    static func fixture(
        repoPath: String,
        sourceURL: URL,
        category: String,
        targetFilename: String
    ) -> ImportSingleFilePreflightRequest {
        ImportSingleFilePreflightRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            category: category,
            targetFilename: targetFilename
        )
    }
}
