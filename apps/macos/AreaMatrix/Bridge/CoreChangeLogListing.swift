import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreChangeLogListing = AreaMatrixCoreBridgeContract.CoreChangeLogListing
typealias ChangeFilterSnapshot = AreaMatrixCoreBridgeContract.ChangeFilterSnapshot
typealias ChangeLogEntrySnapshot = AreaMatrixCoreBridgeContract.ChangeLogEntrySnapshot

extension ChangeLogEntrySnapshot {
    var actionDisplayName: String {
        switch action {
        case "imported":
            L10n.string("Imported")
        case "adopted":
            L10n.string("Adopted")
        case "renamed":
            L10n.string("Renamed")
        case "moved":
            L10n.string("Moved")
        case "edited_note":
            L10n.string("Edited note")
        case "deleted":
            L10n.string("Deleted")
        case "removed_from_index":
            L10n.string("Removed from index")
        case "restored":
            L10n.string("Restored")
        case "external_modified":
            L10n.string("External change")
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
            try self.generatedAdapter.listChanges(
                repoPath: repoPath,
                filter: ChangeFilter(filter)
            ).map(ChangeLogEntrySnapshot.init)
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
        self.init(
            id: coreEntry.id,
            fileID: coreEntry.fileId,
            filename: coreEntry.filename,
            category: coreEntry.category,
            action: coreEntry.action,
            detailJSON: coreEntry.detailJson,
            occurredAt: coreEntry.occurredAt
        )
    }
}

private enum ChangeLogDetailSummary {
    static func summarize(_ detailJSON: String) -> String {
        guard let data = detailJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return L10n.string("Detail unavailable")
        }

        let parts = object.keys.sorted().compactMap { key -> String? in
            guard let value = object[key] else { return nil }
            return "\(key): \(safeDisplay(value, for: key))"
        }
        return parts.isEmpty ? L10n.string("Detail unavailable") : parts.joined(separator: " · ")
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
