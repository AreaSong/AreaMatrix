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
            L10n.string("Needs review")
        case .resolved:
            L10n.string("Resolved")
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
            L10n.string("Same name, different content")
        case .concurrentModification:
            L10n.string("Concurrent modification")
        case .metadataMismatch:
            L10n.string("Metadata mismatch")
        case .missingVersion:
            L10n.string("Missing version")
        case .unknown:
            L10n.string("Unknown")
        }
    }
}

enum SyncConflictSeveritySnapshot: String, Equatable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var displayName: String {
        switch self {
        case .low: L10n.string("Low")
        case .medium: L10n.string("Medium")
        case .high: L10n.string("High")
        }
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
            L10n.string("Existing file")
        case .incoming:
            L10n.string("Incoming file")
        case .conflictCopy:
            L10n.string("Conflict copy")
        case .missing:
            L10n.string("Missing file")
        case .unknown:
            L10n.string("Unknown role")
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
        clean(sourceProvider) ?? L10n.string("Unknown")
    }

    var detectedDisplay: String {
        guard let detectedAt else { return L10n.string("Unknown") }
        return Date(timeIntervalSince1970: TimeInterval(detectedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var summaryDisplay: String {
        clean(summary) ?? L10n.string("Conflict details need review.")
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
        guard let modifiedAt else { return L10n.string("Unknown") }
        return Date(timeIntervalSince1970: TimeInterval(modifiedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var sizeDisplay: String {
        guard let sizeBytes else { return L10n.string("Unknown") }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var hashDisplay: String {
        let trimmed = hashSha256?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return L10n.string("Unknown") }
        return trimmed.count > 8 ? "\(trimmed.prefix(8))..." : trimmed
    }

    var sourceDisplay: String {
        let trimmed = sourcePlatform?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.string("Unknown") : trimmed
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
