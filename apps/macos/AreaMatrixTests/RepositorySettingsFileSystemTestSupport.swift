@testable import AreaMatrix
import Foundation

func temporaryRepositorySettingsRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixRepositorySettings")
}

func createRepositorySettingsMetadataDatabaseMarker(in repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    try Data().write(to: metadataURL.appendingPathComponent("index.db"))
}

func removeRepositorySettingsMetadataDatabaseSidecars(in repoURL: URL) {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    for name in ["index.db-wal", "index.db-shm"] {
        try? removeTestTemporaryItem(metadataURL.appendingPathComponent(name))
    }
}
