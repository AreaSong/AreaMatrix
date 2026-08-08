/// Stable change-log capability surface consumed by feature models.
///
/// The App-owned Bridge remains responsible for converting generated Core
/// values and for localized presentation helpers. These values intentionally
/// contain no AppKit, L10n, or UniFFI types.
public protocol CoreChangeLogListing: Sendable {
    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot]
}

public struct ChangeFilterSnapshot: Equatable, Sendable {
    public let fileID: Int64?
    public let category: String?
    public let action: String?
    public let since: Int64?
    public let until: Int64?
    public let limit: Int64
    public let offset: Int64

    public init(
        fileID: Int64?,
        category: String?,
        action: String?,
        since: Int64?,
        until: Int64?,
        limit: Int64,
        offset: Int64
    ) {
        self.fileID = fileID
        self.category = category
        self.action = action
        self.since = since
        self.until = until
        self.limit = limit
        self.offset = offset
    }

    public static let importResultRecent = ChangeFilterSnapshot(
        fileID: nil,
        category: nil,
        action: "imported",
        since: nil,
        until: nil,
        limit: 100,
        offset: 0
    )

    public static func detailLog(fileID: Int64) -> ChangeFilterSnapshot {
        ChangeFilterSnapshot(
            fileID: fileID,
            category: nil,
            action: nil,
            since: nil,
            until: nil,
            limit: 100,
            offset: 0
        )
    }
}

public struct ChangeLogEntrySnapshot: Equatable, Identifiable, Sendable {
    public let id: Int64
    public let fileID: Int64?
    public let filename: String
    public let category: String
    public let action: String
    public let detailJSON: String
    public let occurredAt: Int64

    public init(
        id: Int64,
        fileID: Int64?,
        filename: String,
        category: String,
        action: String,
        detailJSON: String,
        occurredAt: Int64
    ) {
        self.id = id
        self.fileID = fileID
        self.filename = filename
        self.category = category
        self.action = action
        self.detailJSON = detailJSON
        self.occurredAt = occurredAt
    }
}
