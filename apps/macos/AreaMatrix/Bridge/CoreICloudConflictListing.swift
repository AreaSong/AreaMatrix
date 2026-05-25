import Foundation

protocol CoreICloudConflictListing: Sendable {
    func listICloudConflicts(repoPath: String) async throws -> [ICloudConflictPairSnapshot]
}

enum ICloudConflictStatusSnapshot: String, Equatable {
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

enum ICloudConflictVersionRoleSnapshot: String, Equatable {
    case original = "Original"
    case conflictedCopy = "ConflictedCopy"

    var displayName: String {
        switch self {
        case .original:
            "Original"
        case .conflictedCopy:
            "Conflicted copy"
        }
    }
}

enum ICloudConflictPreviewStatusSnapshot: String, Equatable {
    case available = "Available"
    case metadataOnly = "MetadataOnly"
    case unavailable = "Unavailable"

    var displayName: String {
        switch self {
        case .available:
            "Preview available"
        case .metadataOnly:
            "Metadata only"
        case .unavailable:
            "Preview unavailable"
        }
    }
}

struct ICloudConflictPairSnapshot: Equatable, Identifiable {
    var conflictID: String
    var originalPath: String?
    var conflictedCopyPath: String
    var originalModifiedAt: Int64?
    var conflictedModifiedAt: Int64
    var status: ICloudConflictStatusSnapshot
    var uncertaintyReason: String?

    var id: String {
        conflictID
    }

    var fileDisplayName: String {
        let path = originalPath ?? conflictedCopyPath
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Unknown file" : name
    }

    var originalVersionDisplay: String {
        originalPath ?? "Unknown original version"
    }

    var conflictedCopyDisplay: String {
        conflictedCopyPath
    }

    var modifiedDisplay: String {
        Date(timeIntervalSince1970: TimeInterval(conflictedModifiedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var statusDisplay: String {
        guard status == .needsReview, let uncertaintyReason, !uncertaintyReason.isEmpty else {
            return status.displayName
        }
        return "\(status.displayName): \(uncertaintyReason)"
    }
}

struct ICloudConflictVersionMetadataSnapshot: Equatable, Identifiable {
    var versionID: String
    var role: ICloudConflictVersionRoleSnapshot
    var path: String
    var modifiedAt: Int64?
    var sizeBytes: Int64?
    var hashSha256: String?
    var previewSummary: String?
    var previewStatus: ICloudConflictPreviewStatusSnapshot

    var id: String {
        versionID
    }

    var displayName: String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    var hashDisplay: String {
        guard let hashSha256, !hashSha256.isEmpty else { return "Unknown" }
        return hashSha256.count > 12 ? "\(hashSha256.prefix(12))..." : hashSha256
    }

    var previewDisplay: String {
        let summary = previewSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty { return summary }
        return previewStatus.displayName
    }
}

struct ICloudConflictResolutionOptionSnapshot: Equatable, Identifiable {
    var resolution: ICloudConflictResolutionStrategy
    var destructive: Bool
    var requiresTrash: Bool
    var enabled: Bool
    var disabledReason: String?

    var id: ICloudConflictResolutionStrategy {
        resolution
    }
}

struct ICloudConflictPreviewSnapshot: Equatable {
    var conflictID: String
    var versions: [ICloudConflictVersionMetadataSnapshot]
    var defaultResolution: ICloudConflictResolutionStrategy
    var resolutionOptions: [ICloudConflictResolutionOptionSnapshot]
    var metadataComplete: Bool
    var trashAvailable: Bool
    var canKeepBoth: Bool
    var canResolveDestructive: Bool
    var blockedReason: String?
}

struct ICloudConflictResolveReportSnapshot: Equatable {
    var conflictID: String
    var resolution: ICloudConflictResolutionStrategy
    var status: ICloudConflictStatusSnapshot
    var keptPaths: [String]
    var trashedPaths: [String]
    var undoToken: String?
    var changeLogAction: String
}

extension CoreBridge: CoreICloudConflictListing {
    func listICloudConflicts(repoPath: String) async throws -> [ICloudConflictPairSnapshot] {
        try await Task.detached(priority: .userInitiated) {
            try listCoreICloudConflicts(repoPath: repoPath).map(ICloudConflictPairSnapshot.init)
        }.value
    }
}

protocol CoreICloudConflictReviewing: Sendable {
    func previewICloudConflict(repoPath: String, conflictID: String) async throws
        -> ICloudConflictPreviewSnapshot
    func resolvePreviewedICloudConflict(_ request: ICloudConflictResolutionRequest) async throws
        -> ICloudConflictResolutionResult
}

extension CoreBridge: CoreICloudConflictReviewing {
    func previewICloudConflict(repoPath: String, conflictID: String) async throws
        -> ICloudConflictPreviewSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try ICloudConflictPreviewSnapshot(coreReport: previewConflictVersions(
                repoPath: repoPath,
                conflictId: conflictID
            ))
        }.value
    }

    func resolvePreviewedICloudConflict(_ request: ICloudConflictResolutionRequest) async throws
        -> ICloudConflictResolutionResult {
        let report = try await Task.detached(priority: .userInitiated) {
            try ICloudConflictResolveReportSnapshot(coreReport: AreaMatrix.resolveIcloudConflict(
                repoPath: request.repoPath,
                conflictId: request.conflictID,
                resolution: ICloudConflictResolution(strategy: request.strategy)
            ))
        }.value
        return ICloudConflictResolutionResult(report: report)
    }
}

extension ICloudConflictPairSnapshot {
    init(corePair: ICloudConflictPair) {
        conflictID = corePair.conflictId
        originalPath = corePair.originalPath
        conflictedCopyPath = corePair.conflictedCopyPath
        originalModifiedAt = corePair.originalModifiedAt
        conflictedModifiedAt = corePair.conflictedModifiedAt
        status = ICloudConflictStatusSnapshot(coreStatus: corePair.status)
        uncertaintyReason = corePair.uncertaintyReason
    }
}

private extension ICloudConflictPreviewSnapshot {
    init(coreReport: ICloudConflictPreviewReport) {
        conflictID = coreReport.conflictId
        versions = coreReport.versions.map(ICloudConflictVersionMetadataSnapshot.init)
        defaultResolution = ICloudConflictResolutionStrategy(coreResolution: coreReport.defaultResolution)
        resolutionOptions = coreReport.resolutionOptions.map(ICloudConflictResolutionOptionSnapshot.init)
        metadataComplete = coreReport.metadataComplete
        trashAvailable = coreReport.trashAvailable
        canKeepBoth = coreReport.canKeepBoth
        canResolveDestructive = coreReport.canResolveDestructive
        blockedReason = coreReport.blockedReason
    }
}

private extension ICloudConflictVersionMetadataSnapshot {
    init(coreVersion: ICloudConflictVersionMetadata) {
        versionID = coreVersion.versionId
        role = ICloudConflictVersionRoleSnapshot(coreRole: coreVersion.role)
        path = coreVersion.path
        modifiedAt = coreVersion.modifiedAt
        sizeBytes = coreVersion.sizeBytes
        hashSha256 = coreVersion.hashSha256
        previewSummary = coreVersion.previewSummary
        previewStatus = ICloudConflictPreviewStatusSnapshot(coreStatus: coreVersion.previewStatus)
    }
}

private extension ICloudConflictResolutionOptionSnapshot {
    init(coreOption: ICloudConflictResolutionOption) {
        resolution = ICloudConflictResolutionStrategy(coreResolution: coreOption.resolution)
        destructive = coreOption.destructive
        requiresTrash = coreOption.requiresTrash
        enabled = coreOption.enabled
        disabledReason = coreOption.disabledReason
    }
}

private extension ICloudConflictResolveReportSnapshot {
    init(coreReport: ICloudConflictResolveReport) {
        conflictID = coreReport.conflictId
        resolution = ICloudConflictResolutionStrategy(coreResolution: coreReport.resolution)
        status = ICloudConflictStatusSnapshot(coreStatus: coreReport.status)
        keptPaths = coreReport.keptPaths
        trashedPaths = coreReport.trashedPaths
        undoToken = coreReport.undoToken
        changeLogAction = coreReport.changeLogAction
    }
}

private extension ICloudConflictStatusSnapshot {
    init(coreStatus: ICloudConflictStatus) {
        switch coreStatus {
        case .needsReview:
            self = .needsReview
        case .resolved:
            self = .resolved
        }
    }
}

private extension ICloudConflictVersionRoleSnapshot {
    init(coreRole: ICloudConflictVersionRole) {
        switch coreRole {
        case .original:
            self = .original
        case .conflictedCopy:
            self = .conflictedCopy
        }
    }
}

private extension ICloudConflictPreviewStatusSnapshot {
    init(coreStatus: ICloudConflictPreviewStatus) {
        switch coreStatus {
        case .available:
            self = .available
        case .metadataOnly:
            self = .metadataOnly
        case .unavailable:
            self = .unavailable
        }
    }
}

extension ICloudConflictResolutionStrategy {
    init(coreResolution: ICloudConflictResolution) {
        switch coreResolution {
        case .keepBoth:
            self = .keepBoth
        case .keepOriginal:
            self = .keepOriginalOnly
        case .keepConflictedCopy:
            self = .keepConflictedCopyOnly
        }
    }
}

private extension ICloudConflictResolution {
    init(strategy: ICloudConflictResolutionStrategy) {
        switch strategy {
        case .keepBoth:
            self = .keepBoth
        case .keepOriginalOnly:
            self = .keepOriginal
        case .keepConflictedCopyOnly:
            self = .keepConflictedCopy
        }
    }
}

private func listCoreICloudConflicts(repoPath: String) throws -> [ICloudConflictPair] {
    try listIcloudConflicts(repoPath: repoPath)
}
