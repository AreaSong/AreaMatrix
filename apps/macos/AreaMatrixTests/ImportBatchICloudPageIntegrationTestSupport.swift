@testable import AreaMatrix
import Foundation

extension MainRepositoryDetailPaneTagActions {
    static var noop: MainRepositoryDetailPaneTagActions {
        let noAction: () -> Void = {}
        let noStringAction: (String) -> Void = { _ in }
        let noEditAction: (String, String) -> Void = { _, _ in }
        let noBatchAction: (BatchTagUndoState) -> Void = { _ in }
        return MainRepositoryDetailPaneTagActions(
            aiSuggestionState: .idle,
            aiBatchSuggestionState: .idle,
            onLoadTags: noAction,
            onRetryTags: noAction,
            onAddTag: noStringAction,
            onRemoveTag: noStringAction,
            onLoadSuggestions: noAction,
            onRetrySuggestions: noAction,
            onToggleSuggestion: noStringAction,
            onSelectAllSuggestions: noAction,
            onClearSuggestions: noAction,
            onStartEditingSuggestions: noAction,
            onCancelEditingSuggestions: noAction,
            onEditSuggestionDisplayName: noEditAction,
            onEditSuggestionSlug: noEditAction,
            onRegenerateSuggestionSlug: noStringAction,
            onApplySuggestions: noAction,
            onApplyEditedSuggestions: noAction,
            onRetryFailedSuggestions: noAction,
            onLoadAISuggestions: noAction,
            onRetryAISuggestions: noAction,
            onToggleAISuggestion: noStringAction,
            onApplySingleAISuggestion: noStringAction,
            onSelectHighConfidenceAISuggestions: noAction,
            onClearAISuggestions: noAction,
            onStartEditingAISuggestions: noAction,
            onCancelEditingAISuggestions: noAction,
            onEditAISuggestionDisplayName: noEditAction,
            onEditAISuggestionSlug: noEditAction,
            onRegenerateAISuggestionSlug: noStringAction,
            onApplyAISuggestions: noAction,
            onApplyEditedAISuggestions: noAction,
            onRetryFailedAISuggestions: noAction,
            aiBatchActions: .noop,
            onOpenAISettings: noAction,
            onSuggestionPresentationConsumed: { _ in },
            onUndoTagChange: noAction,
            onDismissTagUndoToast: noAction,
            onBatchTagUndoStateChange: noBatchAction
        )
    }
}

extension FileEntrySnapshot {
    static func batchAddTagsRouteFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "batchAddTags-route-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension UndoActionRecordSnapshot {
    static func undoToastMovedFilesToTrash() -> UndoActionRecordSnapshot {
        testMovedFilesToTrashUndoAction()
    }

    static func undoToastBlockedRename() -> UndoActionRecordSnapshot {
        testBlockedRenameUndoAction()
    }

    static func undoToastRenamedFiles() -> UndoActionRecordSnapshot {
        testRenamedFilesUndoAction()
    }

    static func undoToastMovedFilesToCategory() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-move-finance-5",
            kind: "move_files",
            summary: "Moved 5 files to finance.",
            affectedCount: 5,
            affectedFileNames: ["statement.pdf", "invoice.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_030,
            updatedAt: 1_700_000_030
        )
    }

    static func undoToastAddedTags() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-tags-24",
            kind: "batch_add_tags",
            summary: #"Added tag "finance" to 24 files."#,
            affectedCount: 24,
            affectedFileNames: ["invoice.pdf", "receipt.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_040,
            updatedAt: 1_700_000_040
        )
    }

    static func undoToastExecutedTrashMove() -> UndoActionRecordSnapshot {
        testExecutedTrashMoveUndoAction()
    }
}

extension UndoActionResultSnapshot {
    static func undoToastUndoneTrashMove() -> UndoActionResultSnapshot {
        testUndoneTrashMoveUndoResult()
    }
}

extension CoreErrorMappingSnapshot {
    static func undoToastUndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Undo failed",
            severity: .medium,
            suggestedAction: "View details in Undo history.",
            recoverability: .refreshRequired,
            rawContext: "undo-toast undo-action-log undo-action-log"
        )
    }
}

typealias UndoToastRecordingUndoStore = LenientUndoActionRecordingTestStore

actor UndoToastErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: CoreErrorKindTestMapper.kind(for: error),
            userMessage: "Undo failed",
            severity: .medium,
            suggestedAction: "View details in Undo history.",
            recoverability: .refreshRequired,
            rawContext: "undo-toast undo-action-log undo-action-log"
        )
    }
}
