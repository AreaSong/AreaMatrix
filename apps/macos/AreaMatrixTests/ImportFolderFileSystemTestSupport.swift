import Foundation

func makeImportFolderTemporaryDirectory() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixImportFolderTests")
}
