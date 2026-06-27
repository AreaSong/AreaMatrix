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
        UndoActionRecordSnapshot(
            actionID: "undo-trash-3",
            kind: "trash_delete",
            summary: "Moved 3 files to Trash.",
            affectedCount: 3,
            affectedFileNames: ["a.pdf", "b.pdf", "c.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_010
        )
    }

    static func undoToastBlockedRename() -> UndoActionRecordSnapshot {
        var action = undoToastRenamedFiles()
        action.actionID = "undo-rename-blocked"
        action.status = .blocked
        action.canUndo = false
        action.disabledReason = "External change prevents undo."
        return action
    }

    static func undoToastRenamedFiles() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-rename-12",
            kind: "rename_files",
            summary: "Renamed 12 files.",
            affectedCount: 12,
            affectedFileNames: ["a.pdf", "b.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_020,
            updatedAt: 1_700_000_020
        )
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
        var action = undoToastMovedFilesToTrash()
        action.status = .executed
        action.canUndo = false
        action.updatedAt = 1_700_000_030
        return action
    }
}

extension UndoActionResultSnapshot {
    static func undoToastUndoneTrashMove() -> UndoActionResultSnapshot {
        UndoActionResultSnapshot(
            actionID: "undo-trash-3",
            status: .executed,
            summary: "Undone: moved 3 files to Trash.",
            affectedCount: 3,
            refreshTargets: ["files", "undo_actions", "change_log"],
            completedAt: 1_700_000_040
        )
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

actor UndoToastRecordingUndoStore: CoreUndoActionLogging {
    enum Result {
        case list(Swift.Result<[UndoActionRecordSnapshot], Error>)
        case undo(Swift.Result<UndoActionResultSnapshot, Error>)
    }

    private var results: [Result]
    private var recordedListRequests: [String] = []
    private var recordedUndoRequests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        guard !results.isEmpty else { return [] }
        guard case let .list(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected listUndoActions")
        }
        return try result.get()
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: actionID)
        }
        guard case let .undo(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected undoAction")
        }
        return try result.get()
    }

    func listRequests() -> [String] {
        recordedListRequests
    }

    func undoRequests() -> [String] {
        recordedUndoRequests
    }
}

actor UndoToastErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind(for: error),
            userMessage: "Undo failed",
            severity: .medium,
            suggestedAction: "View details in Undo history.",
            recoverability: .refreshRequired,
            rawContext: "undo-toast undo-action-log undo-action-log"
        )
    }

    private func kind(for error: CoreError) -> CoreErrorKindSnapshot {
        ImportBatchICloudErrorKindMapper.kind(for: error)
    }
}
