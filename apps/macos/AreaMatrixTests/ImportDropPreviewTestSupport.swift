@testable import AreaMatrix
import Foundation

typealias ImportDropPredictRequest = CategoryPredictionRequest
typealias ImportDropRecordingPredictor = RecordingCategoryPredictor

func makeImportDropTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixImportDropTests")
}

func makeImportDropTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixImportDropTests")
}
