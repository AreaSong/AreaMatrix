@testable import AreaMatrix
import Foundation

actor S4X01RecordingSyncConflictResolver: CoreSyncConflictResolving {
    private let previewResults: [
        SyncConflictResolutionStrategySnapshot: Result<SyncConflictResolutionPreviewSnapshot, Error>
    ]
    private let resolveResult: Result<SyncConflictResolveReportSnapshot, Error>
    private var previewRequests: [S4X01SyncConflictPreviewRequest] = []
    private var resolveRequests: [S4X01SyncConflictResolveRequest] = []

    init(
        previewResults: [SyncConflictResolutionStrategySnapshot: Result<SyncConflictResolutionPreviewSnapshot, Error>],
        resolveResult: Result<SyncConflictResolveReportSnapshot, Error> = .success(.s4x01ResolveFixture())
    ) {
        self.previewResults = previewResults
        self.resolveResult = resolveResult
    }

    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategySnapshot
    ) async throws -> SyncConflictResolutionPreviewSnapshot {
        previewRequests.append(S4X01SyncConflictPreviewRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            resolution: resolution
        ))
        return try (previewResults[resolution] ?? .success(.s4x01PreviewFixture(resolution: resolution))).get()
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequestSnapshot
    ) async throws -> SyncConflictResolveReportSnapshot {
        resolveRequests.append(S4X01SyncConflictResolveRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            request: request
        ))
        return try resolveResult.get()
    }

    func recordedPreviewRequests() -> [S4X01SyncConflictPreviewRequest] {
        previewRequests
    }

    func recordedResolveRequests() -> [S4X01SyncConflictResolveRequest] {
        resolveRequests
    }
}

struct S4X01SyncConflictPreviewRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var resolution: SyncConflictResolutionStrategySnapshot
}

struct S4X01SyncConflictResolveRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var request: SyncConflictResolutionRequestSnapshot

    static let s4x01UseIncomingConfirmedRequest = S4X01SyncConflictResolveRequest(
        repoPath: "/tmp/s4x01-repo",
        conflictID: "conflict-report",
        request: SyncConflictResolutionRequestSnapshot(
            strategy: .useIncoming,
            previewToken: "preview-token-use-incoming",
            replaceConfirmed: true,
            replaceConfirmationID: "S4-X-09-C4-16-conflict-report-preview-token-use-incoming"
        )
    )
}

extension SyncConflictResolutionPreviewSnapshot {
    static func s4x01PreviewFixture(
        conflictID: String = "conflict-report",
        resolution: SyncConflictResolutionStrategySnapshot = .keepBoth,
        canApply: Bool = true,
        requiresReplaceConfirmation: Bool = false,
        trashAvailable: Bool = true,
        blockedReason: String? = nil,
        previewToken: String? = "preview-token-keep-both"
    ) -> SyncConflictResolutionPreviewSnapshot {
        SyncConflictResolutionPreviewSnapshot(
            conflictID: conflictID,
            resolution: resolution,
            defaultResolution: .keepBoth,
            statusAfter: .resolved,
            versionImpacts: [
                .s4x01ImpactFixture(path: "docs/report.pdf", role: .existing, willBeCanonical: true),
                .s4x01ImpactFixture(
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
            replacePlan: resolution == .useIncoming ? .s4x01ReplacePlanFixture() : nil
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
    static func s4x01ImpactFixture(
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
            reason: "Visible file is preserved by C4-16."
        )
    }
}

extension SyncConflictReplacePlanSnapshot {
    static func s4x01ReplacePlanFixture() -> SyncConflictReplacePlanSnapshot {
        SyncConflictReplacePlanSnapshot(
            oldPath: "docs/report.pdf",
            newPath: "docs/report (Windows conflict).pdf",
            oldHashSha256: "abcdef1234567890",
            newHashSha256: "fedcba9876543210",
            affectedFileID: 42,
            backupTarget: "Trash",
            databaseUpdate: "canonical record points to incoming",
            changeLogAction: "conflict_resolved_use_incoming",
            recoveryNote: "S4-X-09 confirmation is required."
        )
    }
}

extension SyncConflictResolveReportSnapshot {
    static func s4x01ResolveFixture(
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
