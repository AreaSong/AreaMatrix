import Foundation

func makeRenameTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixRenameFile")
}
