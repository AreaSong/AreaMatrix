import Foundation

func makeInitDoneTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixInitDoneTests")
}
