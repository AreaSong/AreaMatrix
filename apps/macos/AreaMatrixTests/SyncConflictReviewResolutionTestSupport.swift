@testable import AreaMatrix
import Foundation

actor SyncConflictReviewRecordingSyncConflictResolver: CoreSyncConflictResolving {
    private let previewResults: [
        SyncConflictResolutionStrategySnapshot: Result<SyncConflictResolutionPreviewSnapshot, Error>
    ]
    private let resolveResult: Result<SyncConflictResolveReportSnapshot, Error>
    private var previewRequests: [SyncConflictReviewSyncConflictPreviewRequest] = []
    private var resolveRequests: [SyncConflictReviewSyncConflictResolveRequest] = []

    init(
        previewResults: [SyncConflictResolutionStrategySnapshot: Result<SyncConflictResolutionPreviewSnapshot, Error>],
        resolveResult: Result<SyncConflictResolveReportSnapshot, Error> = .success(.syncConflictReviewResolveFixture())
    ) {
        self.previewResults = previewResults
        self.resolveResult = resolveResult
    }

    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategySnapshot
    ) async throws -> SyncConflictResolutionPreviewSnapshot {
        previewRequests.append(SyncConflictReviewSyncConflictPreviewRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            resolution: resolution
        ))
        return try (previewResults[resolution] ?? .success(.syncConflictReviewPreviewFixture(resolution: resolution))).get()
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequestSnapshot
    ) async throws -> SyncConflictResolveReportSnapshot {
        resolveRequests.append(SyncConflictReviewSyncConflictResolveRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            request: request
        ))
        return try resolveResult.get()
    }

    func recordedPreviewRequests() -> [SyncConflictReviewSyncConflictPreviewRequest] {
        previewRequests
    }

    func recordedResolveRequests() -> [SyncConflictReviewSyncConflictResolveRequest] {
        resolveRequests
    }
}

struct SyncConflictReviewSyncConflictPreviewRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var resolution: SyncConflictResolutionStrategySnapshot
}

struct SyncConflictReviewSyncConflictResolveRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var request: SyncConflictResolutionRequestSnapshot

    static let syncConflictReviewUseIncomingConfirmedRequest = SyncConflictReviewSyncConflictResolveRequest(
        repoPath: "/tmp/syncConflictReview-repo",
        conflictID: "conflict-report",
        request: SyncConflictResolutionRequestSnapshot(
            strategy: .useIncoming,
            previewToken: "preview-token-use-incoming",
            replaceConfirmed: true,
            replaceConfirmationID: "replace-resolution-replace-confirmation-conflict-report-preview-token-use-incoming"
        )
    )
}

extension SyncConflictResolutionPreviewSnapshot {
    static func syncConflictReviewPreviewFixture(
        conflictID: String = "conflict-report",
        resolution: SyncConflictResolutionStrategySnapshot = .keepBoth,
        canApply: Bool = true,
        requiresReplaceConfirmation: Bool = false,
        trashAvailable: Bool = true,
        backupTarget: String? = "Trash",
        blockedReason: String? = nil,
        previewToken: String? = "preview-token-keep-both"
    ) -> SyncConflictResolutionPreviewSnapshot {
        SyncConflictResolutionPreviewSnapshot(
            conflictID: conflictID,
            resolution: resolution,
            defaultResolution: .keepBoth,
            statusAfter: .resolved,
            versionImpacts: [
                .syncConflictReviewImpactFixture(path: "docs/report.pdf", role: .existing, willBeCanonical: true),
                .syncConflictReviewImpactFixture(
                    path: "docs/report (Windows conflict).pdf",
                    fileID: 43,
                    role: .incoming,
                    willBeCanonical: resolution == .useIncoming
                )
            ],
            keptPaths: ["docs/report.pdf"],
            retainedPaths: resolution == .keepBoth ? ["docs/report (Windows conflict).pdf"] : [],
            plannedTrashPaths: resolution == .useIncoming ? ["docs/report.pdf"] : [],
            affectedFileIDs: [42, 43],
            canonicalPath: "docs/report.pdf",
            changeLogAction: changeLogAction(for: resolution),
            destructive: resolution == .useIncoming,
            requiresReplaceConfirmation: requiresReplaceConfirmation,
            trashRequired: resolution == .useIncoming,
            trashAvailable: trashAvailable,
            canApply: canApply,
            blockedReason: blockedReason,
            previewToken: previewToken,
            replacePlan: resolution == .useIncoming ? .syncConflictReviewReplacePlanFixture(backupTarget: backupTarget) : nil
        )
    }

    static func changeLogAction(for resolution: SyncConflictResolutionStrategySnapshot) -> String {
        switch resolution {
        case .keepBoth:
            "conflict_resolved_keep_both"
        case .useExisting:
            "conflict_resolved_use_existing"
        case .useIncoming:
            "conflict_resolved_use_incoming"
        }
    }
}

extension SyncConflictVersionImpactSnapshot {
    static func syncConflictReviewImpactFixture(
        path: String,
        fileID: Int64 = 42,
        role: SyncConflictFileRoleSnapshot,
        willBeCanonical: Bool
    ) -> SyncConflictVersionImpactSnapshot {
        SyncConflictVersionImpactSnapshot(
            path: path,
            fileID: fileID,
            role: role,
            willKeep: true,
            willBeCanonical: willBeCanonical,
            willRemainUserVisible: true,
            willMoveToTrash: false,
            recoveryTarget: nil,
            reason: "Visible file is preserved by sync-conflict-resolve."
        )
    }
}

extension SyncConflictReplacePlanSnapshot {
    static func syncConflictReviewReplacePlanFixture(backupTarget: String? = "Trash") -> SyncConflictReplacePlanSnapshot {
        SyncConflictReplacePlanSnapshot(
            oldPath: "docs/report.pdf",
            newPath: "docs/report (Windows conflict).pdf",
            oldHashSha256: "abcdef1234567890",
            newHashSha256: "fedcba9876543210",
            affectedFileID: 42,
            backupTarget: backupTarget,
            databaseUpdate: "canonical record points to incoming",
            changeLogAction: "conflict_resolved_use_incoming",
            recoveryNote: "replace-resolution confirmation is required."
        )
    }
}

extension SyncConflictResolveReportSnapshot {
    static func syncConflictReviewResolveFixture(
        resolution: SyncConflictResolutionStrategySnapshot = .keepBoth
    ) -> SyncConflictResolveReportSnapshot {
        SyncConflictResolveReportSnapshot(
            conflictID: "conflict-report",
            resolution: resolution,
            status: .resolved,
            keptPaths: ["docs/report.pdf"],
            retainedPaths: ["docs/report (Windows conflict).pdf"],
            trashedPaths: resolution == .useIncoming ? ["docs/report.pdf"] : [],
            affectedFileIDs: [42, 43],
            changeLogAction: SyncConflictResolutionPreviewSnapshot.changeLogAction(for: resolution),
            undoToken: nil,
            resolvedAt: 1_778_738_500
        )
    }
}
