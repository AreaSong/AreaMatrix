import Foundation

func makeChangeCategoryFeatureTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixChangeCategory")
}

func makeChangeCategoryTemporaryDirectory(prefix: String) throws -> URL {
    try makeTestTemporaryDirectory(prefix: prefix, named: "AreaMatrixChangeCategoryIntegration")
}
