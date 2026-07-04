import Foundation

func makeImportSingleFileTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixImportSingleFile")
}
