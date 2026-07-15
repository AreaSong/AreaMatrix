@testable import AreaMatrix
import Foundation

struct RepositorySettingsMetadataFootprint: Equatable {
    struct Entry: Equatable {
        var relativePath: String
        var isDirectory: Bool
        var contents: Data?
        var fileSize: UInt64
        var modificationDate: Date?
        var permissions: Int
    }

    var entries: [Entry]

    func normalizingSQLiteSharedMemoryCoordination() -> RepositorySettingsMetadataFootprint {
        RepositorySettingsMetadataFootprint(entries: entries.map { entry in
            guard entry.relativePath == "amatrix/index.db-shm" else {
                return entry
            }
            var normalized = entry
            normalized.contents = nil
            normalized.modificationDate = nil
            return normalized
        })
    }
}

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

func repositorySettingsMetadataURL(in repoURL: URL) -> URL {
    repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
}

func repositorySettingsMetadataDatabaseURL(in repoURL: URL) -> URL {
    repositorySettingsMetadataURL(in: repoURL).appendingPathComponent("index.db")
}

func repositorySettingsMetadataFootprint(in repoURL: URL) throws -> RepositorySettingsMetadataFootprint {
    let fileManager = FileManager.default
    let metadataURL = repositorySettingsMetadataURL(in: repoURL)
    guard fileManager.fileExists(atPath: metadataURL.path) else {
        return RepositorySettingsMetadataFootprint(entries: [])
    }

    let children = fileManager.enumerator(at: metadataURL, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL } ?? []
    let entries = try ([metadataURL] + children).map { url in
        try repositorySettingsMetadataFootprintEntry(url: url, rootURL: metadataURL, fileManager: fileManager)
    }
    return RepositorySettingsMetadataFootprint(entries: entries.sorted { $0.relativePath < $1.relativePath })
}

func openRepositorySettingsWalFixture(in repoURL: URL) throws -> OpaquePointer {
    let dbURL = repositorySettingsMetadataDatabaseURL(in: repoURL)
    var database: OpaquePointer?
    let openResult = sqlite3_open_v2(dbURL.path, &database, SQLITE_OPEN_READWRITE, nil)
    guard openResult == SQLITE_OK, let database else {
        if let database {
            sqlite3_close(database)
        }
        throw NSError(domain: "RepositorySettingsWalFixture", code: Int(openResult))
    }

    do {
        try executeRepositorySettingsSQL(database: database, sql: "PRAGMA wal_autocheckpoint=0")
        try executeRepositorySettingsSQL(
            database: database,
            sql: "INSERT OR REPLACE INTO repo_config(key, value, updated_at) "
                + "VALUES('last_opened_at', '1778000000', 1778000000)"
        )
        return database
    } catch {
        sqlite3_close(database)
        throw error
    }
}

private func repositorySettingsMetadataFootprintEntry(
    url: URL,
    rootURL: URL,
    fileManager: FileManager
) throws -> RepositorySettingsMetadataFootprint.Entry {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
    let relativePath = url == rootURL ? "." : String(url.path.dropFirst(rootURL.path.count + 1))
    return try RepositorySettingsMetadataFootprint.Entry(
        relativePath: relativePath,
        isDirectory: isDirectory,
        contents: isDirectory ? nil : Data(contentsOf: url),
        fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
        modificationDate: attributes[.modificationDate] as? Date,
        permissions: (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    )
}

private func executeRepositorySettingsSQL(database: OpaquePointer, sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "sqlite fixture failed"
        sqlite3_free(errorMessage)
        throw NSError(
            domain: "RepositorySettingsWalFixture",
            code: Int(sqlite3_errcode(database)),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
