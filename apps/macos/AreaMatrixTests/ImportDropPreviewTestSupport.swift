@testable import AreaMatrix
import Foundation

struct ImportDropPredictRequest: Equatable {
    var repoPath: String
    var filename: String
}

actor ImportDropRecordingPredictor: CoreCategoryPredicting {
    private var results: [Result<ClassifyResultSnapshot, Error>]
    private var requests: [ImportDropPredictRequest] = []

    init(results: [Result<ClassifyResultSnapshot, Error>]) {
        self.results = results
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requests.append(ImportDropPredictRequest(repoPath: repoPath, filename: filename))
        guard !results.isEmpty else {
            throw CoreError.Classify(reason: "missing test result")
        }
        switch results.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [ImportDropPredictRequest] {
        requests
    }
}

func makeImportDropTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixImportDropTests")
}

func makeImportDropTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixImportDropTests")
}
