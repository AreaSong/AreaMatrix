import Foundation

protocol SyncConflictEntryCoreBridge: Sendable {
    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictEntryConflict]
    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategy
    ) async throws -> SyncConflictResolutionPreviewReport
    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequest
    ) async throws -> SyncConflictResolveReport
}

enum SyncConflictEntryStatus: String, Equatable {
    case needsReview = "NeedsReview"
    case resolved = "Resolved"
}

enum SyncConflictEntryType: String, Equatable {
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

enum SyncConflictEntrySeverity: String, Equatable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var sortRank: Int {
        switch self {
        case .high:
            3
        case .medium:
            2
        case .low:
            1
        }
    }
}

enum SyncConflictEntryFileRole: String, Equatable {
    case existing = "Existing"
    case incoming = "Incoming"
    case conflictCopy = "ConflictCopy"
    case missing = "Missing"
    case unknown = "Unknown"
}

enum SyncConflictResolutionStrategy: String, Equatable {
    case keepBoth = "KeepBoth"
    case useExisting = "UseExisting"
    case useIncoming = "UseIncoming"
}

struct SyncConflictEntryAffectedFile: Equatable, Identifiable {
    var path: String
    var fileID: Int64?
    var role: SyncConflictEntryFileRole
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
}

struct SyncConflictEntryConflict: Equatable, Identifiable {
    var conflictID: String
    var conflictType: SyncConflictEntryType
    var severity: SyncConflictEntrySeverity
    var status: SyncConflictEntryStatus
    var primaryPath: String
    var affectedFiles: [SyncConflictEntryAffectedFile]
    var versionCount: Int64
    var sourceProvider: String?
    var detectedAt: Int64?
    var summary: String?

    var id: String {
        conflictID
    }

    var normalizedConflictID: String? {
        let trimmed = conflictID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var displayName: String {
        let name = URL(fileURLWithPath: primaryPath).lastPathComponent
        return name.isEmpty ? primaryPath : name
    }

    var detectedText: String {
        guard let detectedAt else { return "Unknown" }
        return Date(timeIntervalSince1970: TimeInterval(detectedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var sourceText: String {
        let trimmed = sourceProvider?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown source" : trimmed
    }

    var summaryText: String {
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Conflict details need review." : trimmed
    }

    func matches(fileID: Int64, path: String) -> Bool {
        primaryPath == path ||
            affectedFiles.contains { affected in
                affected.fileID == fileID || affected.path == path
            }
    }
}

struct SyncConflictEntryReviewRoute: Equatable, Hashable, Identifiable {
    var repoPath: String
    var conflictID: String
    var primaryPath: String

    var id: String {
        conflictID
    }
}

struct SyncConflictVersionImpact: Equatable, Identifiable {
    var path: String
    var fileID: Int64?
    var role: SyncConflictEntryFileRole
    var willKeep: Bool
    var willBeCanonical: Bool
    var willRemainUserVisible: Bool
    var willMoveToTrash: Bool
    var recoveryTarget: String?
    var reason: String?

    var id: String {
        if let fileID {
            return "\(fileID)-\(path)"
        }
        return "\(role.rawValue)-\(path)"
    }
}

struct SyncConflictReplacePlan: Equatable {
    var oldPath: String
    var newPath: String
    var oldHashSha256: String?
    var newHashSha256: String?
    var affectedFileID: Int64?
    var backupTarget: String?
    var databaseUpdate: String
    var changeLogAction: String
    var recoveryNote: String

    var affectedRecordText: String {
        affectedFileID.map(String.init) ?? "Unknown"
    }

    var backupTargetText: String {
        let trimmed = backupTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Trash or Core safety backup required" : trimmed
    }

    var hasCoreSafetyBackup: Bool {
        let target = backupTargetText.lowercased()
        return !target.contains("unavailable")
            && !target.contains("trash")
            && !target.contains("recycle bin")
    }

    var oldHashPrefix: String {
        hashPrefix(oldHashSha256)
    }

    var newHashPrefix: String {
        hashPrefix(newHashSha256)
    }

    private func hashPrefix(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : String(trimmed.prefix(8))
    }
}

struct SyncConflictResolutionPreviewReport: Equatable {
    var conflictID: String
    var resolution: SyncConflictResolutionStrategy
    var defaultResolution: SyncConflictResolutionStrategy
    var statusAfter: SyncConflictEntryStatus
    var versionImpacts: [SyncConflictVersionImpact]
    var keptPaths: [String]
    var retainedPaths: [String]
    var plannedTrashPaths: [String]
    var affectedFileIDs: [Int64]
    var canonicalPath: String?
    var changeLogAction: String
    var destructive: Bool
    var requiresReplaceConfirmation: Bool
    var trashRequired: Bool
    var trashAvailable: Bool
    var canApply: Bool
    var blockedReason: String?
    var previewToken: String?
    var replacePlan: SyncConflictReplacePlan?

    var normalizedPreviewToken: String? {
        let trimmed = previewToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var blocksOnlyForReplaceConfirmation: Bool {
        !canApply &&
            requiresReplaceConfirmation &&
            (blockedReason?.localizedCaseInsensitiveContains("confirmation") == true)
    }

    var hasRecoverableOldVersion: Bool {
        !trashRequired || trashAvailable || replacePlan?.hasCoreSafetyBackup == true
    }
}

struct SyncConflictResolutionRequest: Equatable {
    var strategy: SyncConflictResolutionStrategy
    var previewToken: String
    var replaceConfirmed: Bool
    var replaceConfirmationID: String?
}

struct SyncConflictResolveReport: Equatable {
    var conflictID: String
    var resolution: SyncConflictResolutionStrategy
    var status: SyncConflictEntryStatus
    var keptPaths: [String]
    var retainedPaths: [String]
    var trashedPaths: [String]
    var affectedFileIDs: [Int64]
    var changeLogAction: String
    var undoToken: String?
    var resolvedAt: Int64?
}

struct SyncConflictReplaceConfirmation: Equatable {
    var conflictID: String
    var previewToken: String
    var confirmationID: String
    var replacePlan: SyncConflictReplacePlan
}

enum SyncConflictEntryError: Error, Equatable {
    case database(String)
    case io(String)
    case conflict(String)
    case permissionDenied(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .database:
            "Could not load review items"
        case .io:
            "Could not read conflict metadata"
        case .conflict:
            "Conflict records changed before they could be loaded"
        case .permissionDenied:
            "AreaMatrix cannot read conflict metadata"
        case let .unavailable(message):
            message.isEmpty ? "Could not load review items" : message
        }
    }

    var recovery: String {
        switch self {
        case .database:
            "Try again after the repository database is available."
        case .io:
            "Check repository permissions and try again."
        case .conflict:
            "Try again to refresh the review list."
        case .permissionDenied:
            "Review repository permissions and try again."
        case .unavailable:
            "Try again."
        }
    }

    static func map(_ error: Error) -> SyncConflictEntryError {
        if let entryError = error as? SyncConflictEntryError {
            return entryError
        }
        if let queryError = error as? MobileLibraryQueryError {
            return .unavailable(queryError.message)
        }
        if let detailError = error as? MobileFileDetailError {
            return .unavailable(detailError.message)
        }
        return .unavailable(error.localizedDescription)
    }
}

extension LiveMobileRepositoryCoreBridge: SyncConflictEntryCoreBridge {
    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictEntryConflict] {
        try await Task.detached(priority: .userInitiated) {
            try SyncConflictEntryCoreFFIClient().detectSyncConflicts(repoPath: repoPath)
        }.value
    }

    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategy
    ) async throws -> SyncConflictResolutionPreviewReport {
        try await Task.detached(priority: .userInitiated) {
            try SyncConflictResolveCoreFFIClient().previewSyncConflictResolution(
                repoPath: repoPath,
                conflictID: conflictID,
                resolution: resolution
            )
        }.value
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequest
    ) async throws -> SyncConflictResolveReport {
        try await Task.detached(priority: .userInitiated) {
            try SyncConflictResolveCoreFFIClient().resolveSyncConflict(
                repoPath: repoPath,
                conflictID: conflictID,
                request: request
            )
        }.value
    }
}
