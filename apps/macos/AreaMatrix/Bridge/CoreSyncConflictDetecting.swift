import Foundation

protocol CoreSyncConflictDetecting: Sendable {
    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictSnapshot]
}

enum SyncConflictStatusSnapshot: String, Equatable {
    case needsReview = "NeedsReview"
    case resolved = "Resolved"

    var displayName: String {
        switch self {
        case .needsReview:
            "Needs review"
        case .resolved:
            "Resolved"
        }
    }
}

enum SyncConflictTypeSnapshot: String, Equatable {
    case sameNameDifferentContent = "SameNameDifferentContent"
    case concurrentModification = "ConcurrentModification"
    case metadataMismatch = "MetadataMismatch"
    case missingVersion = "MissingVersion"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .sameNameDifferentContent:
            "Same name, different content"
        case .concurrentModification:
            "Concurrent modification"
        case .metadataMismatch:
            "Metadata mismatch"
        case .missingVersion:
            "Missing version"
        case .unknown:
            "Unknown"
        }
    }
}

enum SyncConflictSeveritySnapshot: String, Equatable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var displayName: String {
        rawValue
    }
}

enum SyncConflictFileRoleSnapshot: String, Equatable {
    case existing = "Existing"
    case incoming = "Incoming"
    case conflictCopy = "ConflictCopy"
    case missing = "Missing"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .existing:
            "Existing file"
        case .incoming:
            "Incoming file"
        case .conflictCopy:
            "Conflict copy"
        case .missing:
            "Missing file"
        case .unknown:
            "Unknown role"
        }
    }
}

struct SyncConflictSnapshot: Equatable, Identifiable {
    var conflictID: String
    var conflictType: SyncConflictTypeSnapshot
    var severity: SyncConflictSeveritySnapshot
    var status: SyncConflictStatusSnapshot
    var primaryPath: String
    var affectedFiles: [SyncConflictAffectedFileSnapshot]
    var versionCount: Int64
    var sourceProvider: String?
    var detectedAt: Int64?
    var summary: String?

    var id: String {
        conflictID
    }

    var fileDisplayName: String {
        let name = URL(fileURLWithPath: primaryPath).lastPathComponent
        return name.isEmpty ? primaryPath : name
    }

    var sourceDisplay: String {
        clean(sourceProvider) ?? "Unknown"
    }

    var detectedDisplay: String {
        guard let detectedAt else { return "Unknown" }
        return Date(timeIntervalSince1970: TimeInterval(detectedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var summaryDisplay: String {
        clean(summary) ?? "Conflict details need review."
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SyncConflictAffectedFileSnapshot: Equatable, Identifiable {
    var path: String
    var fileID: Int64?
    var role: SyncConflictFileRoleSnapshot
    var sizeBytes: Int64?
    var modifiedAt: Int64?
    var hashSha256: String?
    var sourcePlatform: String?

    var id: String {
        if let fileID {
            return "\(fileID)-\(path)"
        }
        return "\(role.rawValue)-\(path)"
    }

    var modifiedDisplay: String {
        guard let modifiedAt else { return "Unknown" }
        return Date(timeIntervalSince1970: TimeInterval(modifiedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var sizeDisplay: String {
        guard let sizeBytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var hashDisplay: String {
        let trimmed = hashSha256?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Unknown" }
        return trimmed.count > 8 ? "\(trimmed.prefix(8))..." : trimmed
    }

    var sourceDisplay: String {
        let trimmed = sourcePlatform?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

extension CoreBridge: CoreSyncConflictDetecting {
    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictSnapshot] {
        try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.detectSyncConflicts(repoPath: repoPath).map(SyncConflictSnapshot.init(coreConflict:))
        }.value
    }
}

private extension SyncConflictSnapshot {
    init(coreConflict: SyncConflict) {
        conflictID = coreConflict.conflictId
        conflictType = SyncConflictTypeSnapshot(coreType: coreConflict.conflictType)
        severity = SyncConflictSeveritySnapshot(coreSeverity: coreConflict.severity)
        status = SyncConflictStatusSnapshot(coreStatus: coreConflict.status)
        primaryPath = coreConflict.primaryPath
        affectedFiles = coreConflict.affectedFiles.map(SyncConflictAffectedFileSnapshot.init(coreFile:))
        versionCount = coreConflict.versionCount
        sourceProvider = coreConflict.sourceProvider
        detectedAt = coreConflict.detectedAt
        summary = coreConflict.summary
    }
}

private extension SyncConflictAffectedFileSnapshot {
    init(coreFile: SyncConflictAffectedFile) {
        path = coreFile.path
        fileID = coreFile.fileId
        role = SyncConflictFileRoleSnapshot(coreRole: coreFile.role)
        sizeBytes = coreFile.sizeBytes
        modifiedAt = coreFile.modifiedAt
        hashSha256 = coreFile.hashSha256
        sourcePlatform = coreFile.sourcePlatform
    }
}

extension SyncConflictStatusSnapshot {
    init(coreStatus: SyncConflictStatus) {
        switch coreStatus {
        case .needsReview:
            self = .needsReview
        case .resolved:
            self = .resolved
        }
    }
}

private extension SyncConflictTypeSnapshot {
    init(coreType: SyncConflictType) {
        switch coreType {
        case .sameNameDifferentContent:
            self = .sameNameDifferentContent
        case .concurrentModification:
            self = .concurrentModification
        case .metadataMismatch:
            self = .metadataMismatch
        case .missingVersion:
            self = .missingVersion
        case .unknown:
            self = .unknown
        }
    }
}

private extension SyncConflictSeveritySnapshot {
    init(coreSeverity: SyncConflictSeverity) {
        switch coreSeverity {
        case .low:
            self = .low
        case .medium:
            self = .medium
        case .high:
            self = .high
        }
    }
}

extension SyncConflictFileRoleSnapshot {
    init(coreRole: SyncConflictFileRole) {
        switch coreRole {
        case .existing:
            self = .existing
        case .incoming:
            self = .incoming
        case .conflictCopy:
            self = .conflictCopy
        case .missing:
            self = .missing
        case .unknown:
            self = .unknown
        }
    }
}
