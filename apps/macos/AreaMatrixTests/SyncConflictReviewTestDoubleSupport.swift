@testable import AreaMatrix

typealias SyncConflictReviewRecordingFileDetailer = DetailMetaImmediateDetailer

struct SyncConflictPreviewRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var resolution: SyncConflictResolutionStrategySnapshot
}

struct SyncConflictResolveRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var request: SyncConflictResolutionRequestSnapshot

    static let useIncomingConfirmedRequest = SyncConflictResolveRequest(
        repoPath: "/tmp/syncConflictReview-repo",
        conflictID: "conflict-report",
        request: .testFixture(
            strategy: .useIncoming,
            previewToken: "preview-token-use-incoming",
            replaceConfirmed: true,
            replaceConfirmationID: "replace-resolution-replace-confirmation-conflict-report-preview-token-use-incoming"
        )
    )
}
