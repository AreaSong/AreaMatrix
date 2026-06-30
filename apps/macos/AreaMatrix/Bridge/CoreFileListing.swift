import Foundation

protocol CoreFileListing: Sendable {
    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot]
}

protocol CoreFileDetailing: Sendable {
    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot
}

extension CoreBridge: CoreFileListing, CoreFileDetailing {}

struct FileFilterSnapshot: Equatable {
    var category: String?
    var includeDeleted: Bool?
    var importedAfter: Int64?
    var importedBefore: Int64?
    var limit: Int64
    var offset: Int64

    static func currentCategory(_ category: String?) -> FileFilterSnapshot {
        FileFilterSnapshot(
            category: category,
            includeDeleted: false,
            importedAfter: nil,
            importedBefore: nil,
            limit: 50,
            offset: 0
        )
    }
}

enum FileAvailabilitySnapshot: String, Equatable {
    case available
    case missing
    case iCloudPlaceholder
}

protocol FileAvailabilityChecking: Sendable {
    func availability(
        repoPath: String,
        relativePath: String,
        sourcePath: String?,
        coreStatus: FileAvailabilityStatus
    ) async -> FileAvailabilitySnapshot
}

struct LocalFileAvailabilityChecker: FileAvailabilityChecking {
    func availability(
        repoPath: String,
        relativePath: String,
        sourcePath: String?,
        coreStatus: FileAvailabilityStatus
    ) async -> FileAvailabilitySnapshot {
        FileAvailabilityResolver.availability(
            repoPath: repoPath,
            relativePath: relativePath,
            sourcePath: sourcePath,
            coreStatus: coreStatus
        )
    }
}

struct FileEntrySnapshot: Equatable, Identifiable {
    var id: Int64
    var path: String
    var originalName: String
    var currentName: String
    var category: String
    var sizeBytes: Int64
    var hashSha256: String
    var storageMode: String
    var origin: String
    var sourcePath: String?
    var importedAt: Int64
    var updatedAt: Int64
    var availability: FileAvailabilitySnapshot = .available
}

extension FileEntrySnapshot {
    var statusDisplay: String {
        switch availability {
        case .missing:
            "Missing"
        case .iCloudPlaceholder:
            "iCloud"
        case .available:
            storageMode == "Indexed" ? "Index-only" : "OK"
        }
    }
}

extension FileFilter {
    init(_ snapshot: FileFilterSnapshot) {
        self.init(
            category: snapshot.category,
            includeDeleted: snapshot.includeDeleted,
            importedAfter: snapshot.importedAfter,
            importedBefore: snapshot.importedBefore,
            limit: snapshot.limit,
            offset: snapshot.offset
        )
    }
}

extension FileEntrySnapshot {
    init(coreEntry: FileEntry, availabilityChecker: (String, String?) -> FileAvailabilitySnapshot) {
        id = coreEntry.id
        path = coreEntry.path
        originalName = coreEntry.originalName
        currentName = coreEntry.currentName
        category = coreEntry.category
        sizeBytes = coreEntry.sizeBytes
        hashSha256 = coreEntry.hashSha256
        storageMode = coreEntry.storageMode.fileListDisplayName
        origin = coreEntry.origin.fileListDisplayName
        sourcePath = coreEntry.sourcePath
        importedAt = coreEntry.importedAt
        updatedAt = coreEntry.updatedAt
        availability = availabilityChecker(coreEntry.path, coreEntry.sourcePath)
    }
}

private enum FileAvailabilityResolver {
    static func availability(
        repoPath _: String,
        relativePath: String,
        sourcePath: String?,
        coreStatus: FileAvailabilityStatus
    ) -> FileAvailabilitySnapshot {
        if isICloudPlaceholder(relativePath) || sourcePath.map(isICloudPlaceholder) == true {
            return .iCloudPlaceholder
        }

        return FileAvailabilitySnapshot(coreStatus: coreStatus)
    }

    private static func isICloudPlaceholder(_ path: String) -> Bool {
        path.hasSuffix(".icloud") || path.contains(".icloud/")
    }
}

private extension FileAvailabilitySnapshot {
    init(coreStatus: FileAvailabilityStatus) {
        switch coreStatus {
        case .available:
            self = .available
        case .missing:
            self = .missing
        }
    }
}
