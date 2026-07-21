import SwiftUI

struct MainRepositoryDetailFileActionMenu: View {
    let detail: FileEntrySnapshot
    let disabledReason: MainFileWriteActionDisabledReason?
    let missingFileRelinkState: MainMissingFileRelinkState
    let onLocateMissingFile: (Int64) -> Void
    let onBeginRenameFile: (Int64) -> Void
    let onBeginChangeCategoryFile: (Int64) -> Void
    let onBeginClassifierCorrectionFile: (Int64) -> Void
    let onBeginAIClassificationSuggestionFile: (Int64) -> Void
    let onBeginDeleteFile: (Int64) -> Void
    let onBeginICloudConflictResolution: (Int64) -> Void
    let onBeginSyncConflictReview: (FileEntrySnapshot) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            Menu {
                Button("Rename...") {
                    onBeginRenameFile(detail.id)
                }
                .disabled(disabledReason != nil)
                .accessibilityIdentifier("file-detail-rename-file")
                Button("Change Category...") {
                    onBeginChangeCategoryFile(detail.id)
                }
                .disabled(disabledReason != nil)
                .accessibilityIdentifier("file-detail-change-category")
                Button("Correct Classification...") {
                    onBeginClassifierCorrectionFile(detail.id)
                }
                .disabled(disabledReason != nil)
                .accessibilityIdentifier("classifier-correction-correct-classification")
                Button("Review AI Suggestion...") {
                    onBeginAIClassificationSuggestionFile(detail.id)
                }
                .disabled(disabledReason != nil)
                .accessibilityIdentifier("ai-category-suggestion-review-ai-suggestion")
                Button("Review Sync Conflict...") {
                    onBeginSyncConflictReview(detail)
                }
                .disabled(disabledReason != nil)
                .accessibilityIdentifier("sync-conflict-review-sync-conflict-detect-review-sync-conflict")
                if detail.hasICloudConflictCopySignal {
                    Button("Resolve iCloud Conflict...") {
                        onBeginICloudConflictResolution(detail.id)
                    }
                    .disabled(disabledReason != nil)
                    .accessibilityIdentifier("icloud-conflict-minimal-resolve-icloud-conflict")
                }
                if MainRepositoryDetailFileActionPolicy.shouldShowLocate(for: detail) {
                    Button(missingFileRelinkState.isBusy(for: detail.id) ? "Locating…" : "Locate…") {
                        onLocateMissingFile(detail.id)
                    }
                    .disabled(disabledReason != nil || missingFileRelinkState.isBusy(for: detail.id))
                    .accessibilityIdentifier("file-detail-locate-missing-file")
                }
                if MainRepositoryDetailFileActionPolicy.shouldShowRemoveFromIndex(for: detail) {
                    Button("Remove from Index", role: .destructive) {
                        onBeginDeleteFile(detail.id)
                    }
                    .disabled(disabledReason != nil)
                    .accessibilityIdentifier("file-detail-remove-from-index")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help(disabledReason?.rawValue ?? "File actions")
            .accessibilityIdentifier("file-detail-file-action-menu")
        }
    }
}

enum MainRepositoryDetailFileActionPolicy {
    static func shouldShowLocate(for detail: FileEntrySnapshot) -> Bool {
        detail.availability == .missing
    }

    static func shouldShowRemoveFromIndex(for detail: FileEntrySnapshot) -> Bool {
        MainFileDeleteOperation.recommended(for: detail) == .removeFromIndex
    }
}
