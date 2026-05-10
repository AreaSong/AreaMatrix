import Foundation

protocol CoreChangeLogListing: Sendable {
    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot]
}

struct ChangeFilterSnapshot: Equatable {
    var fileID: Int64?
    var category: String?
    var action: String?
    var since: Int64?
    var until: Int64?
    var limit: Int64
    var offset: Int64

    static let importResultRecent = ChangeFilterSnapshot(
        fileID: nil,
        category: nil,
        action: "imported",
        since: nil,
        until: nil,
        limit: 100,
        offset: 0
    )

    static func detailLog(fileID: Int64) -> ChangeFilterSnapshot {
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

struct ChangeLogEntrySnapshot: Equatable, Identifiable {
    var id: Int64
    var fileID: Int64?
    var filename: String
    var category: String
    var action: String
    var detailJSON: String
    var occurredAt: Int64

    var actionDisplayName: String {
        switch action {
        case "imported":
            "Imported"
        case "adopted":
            "Adopted"
        case "renamed":
            "Renamed"
        case "moved":
            "Moved"
        case "edited_note":
            "Edited note"
        case "deleted":
            "Deleted"
        case "removed_from_index":
            "Removed from index"
        case "restored":
            "Restored"
        case "external_modified":
            "External change"
        default:
            action
        }
    }

    var occurredAtDisplay: String {
        Date(timeIntervalSince1970: TimeInterval(occurredAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var detailSummary: String {
        ChangeLogDetailSummary.summarize(detailJSON)
    }
}

extension CoreBridge: CoreChangeLogListing {
    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        try await Task.detached(priority: .userInitiated) {
            try listCoreChanges(repoPath: repoPath, filter: ChangeFilter(filter)).map(ChangeLogEntrySnapshot.init)
        }.value
    }
}

extension ChangeFilter {
    init(_ snapshot: ChangeFilterSnapshot) {
        self.init(
            fileId: snapshot.fileID,
            category: snapshot.category,
            action: snapshot.action,
            since: snapshot.since,
            until: snapshot.until,
            limit: snapshot.limit,
            offset: snapshot.offset
        )
    }
}

extension ChangeLogEntrySnapshot {
    init(coreEntry: ChangeLogEntry) {
        id = coreEntry.id
        fileID = coreEntry.fileId
        filename = coreEntry.filename
        category = coreEntry.category
        action = coreEntry.action
        detailJSON = coreEntry.detailJson
        occurredAt = coreEntry.occurredAt
    }
}

private enum ChangeLogDetailSummary {
    static func summarize(_ detailJSON: String) -> String {
        guard let data = detailJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "Detail unavailable"
        }

        let parts = object.keys.sorted().compactMap { key -> String? in
            guard let value = object[key] else { return nil }
            return "\(key): \(safeDisplay(value, for: key))"
        }
        return parts.isEmpty ? "Detail unavailable" : parts.joined(separator: " · ")
    }

    private static func safeDisplay(_ value: Any, for key: String) -> String {
        if let string = value as? String {
            return keyDisplaysPath(key) ? sanitizedPathDisplay(string) : string
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return "value"
    }

    private static func keyDisplaysPath(_ key: String) -> Bool {
        key == "source" || key == "path" || key.hasSuffix("_path")
    }

    private static func sanitizedPathDisplay(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "redacted path" : ".../\(name)"
    }
}

private func listCoreChanges(repoPath: String, filter: ChangeFilter) throws -> [ChangeLogEntry] {
    try listChanges(repoPath: repoPath, filter: filter)
}
