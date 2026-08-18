public protocol CoreFileListing: Sendable {
    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot]
}

public protocol CoreFileDetailing: Sendable {
    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot
}

public struct FileFilterSnapshot: Equatable, Sendable {
    public var category: String?
    public var includeDeleted: Bool?
    public var importedAfter: Int64?
    public var importedBefore: Int64?
    public var limit: Int64
    public var offset: Int64

    public init(
        category: String?,
        includeDeleted: Bool?,
        importedAfter: Int64?,
        importedBefore: Int64?,
        limit: Int64,
        offset: Int64
    ) {
        self.category = category
        self.includeDeleted = includeDeleted
        self.importedAfter = importedAfter
        self.importedBefore = importedBefore
        self.limit = limit
        self.offset = offset
    }

    public static func currentCategory(_ category: String?) -> Self {
        Self(
            category: category,
            includeDeleted: false,
            importedAfter: nil,
            importedBefore: nil,
            limit: 50,
            offset: 0
        )
    }
}

public enum FileAvailabilitySnapshot: String, Equatable, Sendable {
    case available
    case missing
    case iCloudPlaceholder
}

public enum CoreImportCommitState: String, Codable, Equatable, Sendable {
    case committed
    case sourceRetained

    public var isDegraded: Bool {
        self == .sourceRetained
    }
}

public struct FileEntrySnapshot: Equatable, Identifiable, Sendable {
    public var id: Int64
    public var path: String
    public var originalName: String
    public var currentName: String
    public var category: String
    public var sizeBytes: Int64
    public var hashSha256: String
    public var storageMode: String
    public var origin: String
    public var sourcePath: String?
    public var importedAt: Int64
    public var updatedAt: Int64
    public var availability: FileAvailabilitySnapshot
    public var importCommitState: CoreImportCommitState

    public init(
        id: Int64,
        path: String,
        originalName: String,
        currentName: String,
        category: String,
        sizeBytes: Int64,
        hashSha256: String,
        storageMode: String,
        origin: String,
        sourcePath: String?,
        importedAt: Int64,
        updatedAt: Int64,
        availability: FileAvailabilitySnapshot = .available,
        importCommitState: CoreImportCommitState = .committed
    ) {
        self.id = id
        self.path = path
        self.originalName = originalName
        self.currentName = currentName
        self.category = category
        self.sizeBytes = sizeBytes
        self.hashSha256 = hashSha256
        self.storageMode = storageMode
        self.origin = origin
        self.sourcePath = sourcePath
        self.importedAt = importedAt
        self.updatedAt = updatedAt
        self.availability = availability
        self.importCommitState = importCommitState
    }
}
