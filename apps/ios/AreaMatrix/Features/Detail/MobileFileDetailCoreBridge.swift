import Foundation

protocol MobileFileDetailCoreBridge: Sendable {
    func getFile(repoPath: String, fileID: Int64) async throws -> MobileFileDetailMetadata
    func listChanges(repoPath: String, filter: MobileFileDetailChangeFilter) async throws -> [MobileFileChangeLogEntry]
    func readNote(repoPath: String, fileID: Int64) async throws -> String?
}

enum MobileFileDetailAvailability: String, Equatable, Sendable {
    case available = "Available"
    case missing = "Missing"

    var statusText: String {
        rawValue
    }
}

struct MobileFileDetailMetadata: Equatable, Identifiable, Sendable {
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
    var availability: MobileFileDetailAvailability
    var importedAt: Int64
    var updatedAt: Int64

    var categoryPath: String {
        if category.isEmpty {
            return path
        }
        return "\(category) / \(path)"
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var sourceText: String {
        guard let sourcePath, !sourcePath.isEmpty else { return origin }
        return sourcePath
    }
}

struct MobileFileDetailChangeFilter: Equatable, Sendable {
    var fileID: Int64?
    var category: String?
    var action: String?
    var since: Int64?
    var until: Int64?
    var limit: Int64
    var offset: Int64

    static func detail(fileID: Int64, limit: Int64 = 100, offset: Int64 = 0) -> MobileFileDetailChangeFilter {
        MobileFileDetailChangeFilter(
            fileID: fileID,
            category: nil,
            action: nil,
            since: nil,
            until: nil,
            limit: limit,
            offset: offset
        )
    }
}

struct MobileFileChangeLogEntry: Equatable, Identifiable, Sendable {
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
        case "renamed":
            "Renamed"
        case "moved":
            "Moved"
        case "replaced":
            "Replaced"
        case "deleted":
            "Deleted"
        case "external_modified":
            "External change"
        case "edited_note":
            "Edited note"
        default:
            action
        }
    }

    var detailSummary: String {
        MobileFileChangeLogDetailSummary.summarize(detailJSON)
    }

    var isWarning: Bool {
        action.contains("delete") || action.contains("replace") || action.contains("removed")
    }
}

enum MobileFileDetailError: Error, Equatable, Sendable {
    case fileNotFound(String)
    case database(String)
    case permissionDenied(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .fileNotFound:
            "This file is no longer in the repository."
        case let .database(message):
            message.isEmpty ? "Repository metadata could not be read." : message
        case .permissionDenied:
            "AreaMatrix does not have permission to read this file detail."
        case let .unavailable(message):
            message.isEmpty ? "File detail is unavailable." : message
        }
    }

    static func map(_ error: Error) -> MobileFileDetailError {
        if let detailError = error as? MobileFileDetailError {
            return detailError
        }
        if let libraryError = error as? MobileLibraryQueryError {
            return .unavailable(libraryError.message)
        }
        return .unavailable(error.localizedDescription)
    }
}

extension LiveMobileRepositoryCoreBridge: MobileFileDetailCoreBridge {
    func getFile(repoPath: String, fileID: Int64) async throws -> MobileFileDetailMetadata {
        try await Task.detached(priority: .userInitiated) {
            try MobileFileDetailCoreFFIClient().getFile(repoPath: repoPath, fileID: fileID)
        }.value
    }

    func listChanges(
        repoPath: String,
        filter: MobileFileDetailChangeFilter
    ) async throws -> [MobileFileChangeLogEntry] {
        try await Task.detached(priority: .userInitiated) {
            try MobileFileDetailCoreFFIClient().listChanges(repoPath: repoPath, filter: filter)
        }.value
    }

    func readNote(repoPath: String, fileID: Int64) async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            try MobileFileDetailCoreFFIClient().readNote(repoPath: repoPath, fileID: fileID)
        }.value
    }
}

private enum MobileFileChangeLogDetailSummary {
    static func summarize(_ detailJSON: String) -> String {
        guard let data = detailJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "Detail unavailable"
        }
        let parts = object.keys.sorted().compactMap { key -> String? in
            guard let value = object[key] else { return nil }
            return "\(key): \(display(value, for: key))"
        }
        return parts.isEmpty ? "Detail unavailable" : parts.joined(separator: " · ")
    }

    private static func display(_ value: Any, for key: String) -> String {
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
