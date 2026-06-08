import Foundation

protocol CoreSyncConflictResolving: Sendable {
    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategySnapshot
    ) async throws -> SyncConflictResolutionPreviewSnapshot

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequestSnapshot
    ) async throws -> SyncConflictResolveReportSnapshot
}

enum SyncConflictResolutionStrategySnapshot: String, CaseIterable, Equatable, Identifiable {
    case keepBoth = "KeepBoth"
    case useExisting = "UseExisting"
    case useIncoming = "UseIncoming"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .keepBoth:
            "Keep both"
        case .useExisting:
            "Use existing version"
        case .useIncoming:
            "Use incoming version"
        }
    }

    var impactSummary: String {
        switch self {
        case .keepBoth:
            "Both versions remain visible. Core keeps or creates visible records and closes the conflict."
        case .useExisting:
            "The existing version remains canonical. Incoming remains visible as a retained copy."
        case .useIncoming:
            "Incoming becomes canonical only after replace confirmation; existing must move to Trash or safety backup."
        }
    }
}

struct SyncConflictVersionImpactSnapshot: Equatable, Identifiable {
    var path: String
    var fileID: Int64?
    var role: SyncConflictFileRoleSnapshot
    var willKeep: Bool
    var willBeCanonical: Bool
    var willRemainUserVisible: Bool
    var willMoveToTrash: Bool
    var recoveryTarget: String?
    var reason: String?

    var id: String {
        [role.rawValue, fileID.map(String.init) ?? "unknown", path].joined(separator: "|")
    }

    var fileIDDisplay: String {
        fileID.map(String.init) ?? "Unknown"
    }

    var recoveryDisplay: String {
        clean(recoveryTarget) ?? "None"
    }

    var reasonDisplay: String {
        clean(reason) ?? "Core did not provide an additional note."
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SyncConflictReplacePlanSnapshot: Equatable {
    var oldPath: String
    var newPath: String
    var oldHashSha256: String?
    var newHashSha256: String?
    var affectedFileID: Int64?
    var backupTarget: String?
    var databaseUpdate: String
    var changeLogAction: String
    var recoveryNote: String
}

struct SyncConflictResolutionPreviewSnapshot: Equatable {
    var conflictID: String
    var resolution: SyncConflictResolutionStrategySnapshot
    var defaultResolution: SyncConflictResolutionStrategySnapshot
    var statusAfter: SyncConflictStatusSnapshot
    var versionImpacts: [SyncConflictVersionImpactSnapshot]
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
    var replacePlan: SyncConflictReplacePlanSnapshot?

    var normalizedPreviewToken: String? {
        let trimmed = previewToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var blockedReasonDisplay: String? {
        let trimmed = blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SyncConflictResolutionRequestSnapshot: Equatable {
    var strategy: SyncConflictResolutionStrategySnapshot
    var previewToken: String
    var replaceConfirmed: Bool
    var replaceConfirmationID: String?
}

struct SyncConflictResolveReportSnapshot: Equatable {
    var conflictID: String
    var resolution: SyncConflictResolutionStrategySnapshot
    var status: SyncConflictStatusSnapshot
    var keptPaths: [String]
    var retainedPaths: [String]
    var trashedPaths: [String]
    var affectedFileIDs: [Int64]
    var changeLogAction: String
    var undoToken: String?
    var resolvedAt: Int64?
}

extension CoreBridge: CoreSyncConflictResolving {
    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategySnapshot
    ) async throws -> SyncConflictResolutionPreviewSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let report = try AreaMatrix.previewSyncConflictResolution(
                repoPath: repoPath,
                conflictId: conflictID,
                resolution: SyncConflictResolutionStrategy(resolution)
            )
            return SyncConflictResolutionPreviewSnapshot(coreReport: report)
        }.value
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequestSnapshot
    ) async throws -> SyncConflictResolveReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let report = try AreaMatrix.resolveSyncConflict(
                repoPath: repoPath,
                conflictId: conflictID,
                resolution: SyncConflictResolutionRequest(request)
            )
            return SyncConflictResolveReportSnapshot(coreReport: report)
        }.value
    }
}

private extension SyncConflictVersionImpactSnapshot {
    init(coreImpact: SyncConflictVersionImpact) {
        path = coreImpact.path
        fileID = coreImpact.fileId
        role = SyncConflictFileRoleSnapshot(coreRole: coreImpact.role)
        willKeep = coreImpact.willKeep
        willBeCanonical = coreImpact.willBeCanonical
        willRemainUserVisible = coreImpact.willRemainUserVisible
        willMoveToTrash = coreImpact.willMoveToTrash
        recoveryTarget = coreImpact.recoveryTarget
        reason = coreImpact.reason
    }
}

private extension SyncConflictReplacePlanSnapshot {
    init(corePlan: SyncConflictReplacePlan) {
        oldPath = corePlan.oldPath
        newPath = corePlan.newPath
        oldHashSha256 = corePlan.oldHashSha256
        newHashSha256 = corePlan.newHashSha256
        affectedFileID = corePlan.affectedFileId
        backupTarget = corePlan.backupTarget
        databaseUpdate = corePlan.databaseUpdate
        changeLogAction = corePlan.changeLogAction
        recoveryNote = corePlan.recoveryNote
    }
}

private extension SyncConflictResolutionPreviewSnapshot {
    init(coreReport: SyncConflictResolutionPreviewReport) {
        conflictID = coreReport.conflictId
        resolution = SyncConflictResolutionStrategySnapshot(coreStrategy: coreReport.resolution)
        defaultResolution = SyncConflictResolutionStrategySnapshot(coreStrategy: coreReport.defaultResolution)
        statusAfter = SyncConflictStatusSnapshot(coreStatus: coreReport.statusAfter)
        versionImpacts = coreReport.versionImpacts.map(SyncConflictVersionImpactSnapshot.init(coreImpact:))
        keptPaths = coreReport.keptPaths
        retainedPaths = coreReport.retainedPaths
        plannedTrashPaths = coreReport.plannedTrashPaths
        affectedFileIDs = coreReport.affectedFileIds
        canonicalPath = coreReport.canonicalPath
        changeLogAction = coreReport.changeLogAction
        destructive = coreReport.destructive
        requiresReplaceConfirmation = coreReport.requiresReplaceConfirmation
        trashRequired = coreReport.trashRequired
        trashAvailable = coreReport.trashAvailable
        canApply = coreReport.canApply
        blockedReason = coreReport.blockedReason
        previewToken = coreReport.previewToken
        replacePlan = coreReport.replacePlan.map(SyncConflictReplacePlanSnapshot.init(corePlan:))
    }
}

private extension SyncConflictResolveReportSnapshot {
    init(coreReport: SyncConflictResolveReport) {
        conflictID = coreReport.conflictId
        resolution = SyncConflictResolutionStrategySnapshot(coreStrategy: coreReport.resolution)
        status = SyncConflictStatusSnapshot(coreStatus: coreReport.status)
        keptPaths = coreReport.keptPaths
        retainedPaths = coreReport.retainedPaths
        trashedPaths = coreReport.trashedPaths
        affectedFileIDs = coreReport.affectedFileIds
        changeLogAction = coreReport.changeLogAction
        undoToken = coreReport.undoToken
        resolvedAt = coreReport.resolvedAt
    }
}

private extension SyncConflictResolutionStrategySnapshot {
    init(coreStrategy: SyncConflictResolutionStrategy) {
        switch coreStrategy {
        case .keepBoth:
            self = .keepBoth
        case .useExisting:
            self = .useExisting
        case .useIncoming:
            self = .useIncoming
        }
    }
}

private extension SyncConflictResolutionStrategy {
    init(_ snapshot: SyncConflictResolutionStrategySnapshot) {
        switch snapshot {
        case .keepBoth:
            self = .keepBoth
        case .useExisting:
            self = .useExisting
        case .useIncoming:
            self = .useIncoming
        }
    }
}

private extension SyncConflictResolutionRequest {
    init(_ snapshot: SyncConflictResolutionRequestSnapshot) {
        self.init(
            strategy: SyncConflictResolutionStrategy(snapshot.strategy),
            previewToken: snapshot.previewToken,
            replaceConfirmed: snapshot.replaceConfirmed,
            replaceConfirmationId: snapshot.replaceConfirmationID
        )
    }
}
