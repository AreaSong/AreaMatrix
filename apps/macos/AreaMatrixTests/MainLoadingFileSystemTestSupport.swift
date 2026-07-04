import Foundation

func makeMainLoadingTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixMainLoadingTreeTests")
}
