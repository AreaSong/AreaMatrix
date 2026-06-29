import Foundation
import SwiftUI

extension MainRepositoryContentView {
    var detailTagActions: MainRepositoryDetailPaneTagActions {
        MainRepositoryDetailPaneTagActions(
            aiSuggestionState: fileListModel.aiTagSuggestionState,
            aiBatchSuggestionState: fileListModel.aiTagBatchSuggestionState,
            onLoadTags: { Task { await fileListModel.loadSelectedFileTags() } },
            onRetryTags: { Task { await fileListModel.retrySelectedFileTags() } },
            onAddTag: { tag in Task { await fileListModel.addSelectedFileTag(tag) } },
            onRemoveTag: { tag in Task { await fileListModel.removeSelectedFileTag(tag) } },
            onLoadSuggestions: { Task { await fileListModel.loadSelectedFileTagSuggestions() } },
            onRetrySuggestions: { Task { await fileListModel.retrySelectedFileTagSuggestions() } },
            onToggleSuggestion: fileListModel.toggleSelectedFileTagSuggestion,
            onSelectAllSuggestions: fileListModel.selectAllSelectedFileTagSuggestions,
            onClearSuggestions: fileListModel.clearSelectedFileTagSuggestions,
            onStartEditingSuggestions: fileListModel.startEditingSelectedFileTagSuggestions,
            onCancelEditingSuggestions: fileListModel.cancelEditingSelectedFileTagSuggestions,
            onEditSuggestionDisplayName: fileListModel.updateSelectedFileTagSuggestionDisplayName,
            onEditSuggestionSlug: fileListModel.updateSelectedFileTagSuggestionSlug,
            onRegenerateSuggestionSlug: fileListModel.regenerateSelectedFileTagSuggestionSlug,
            onApplySuggestions: {
                applyTagSuggestionUndo { await fileListModel.applySelectedFileTagSuggestions() }
            },
            onApplyEditedSuggestions: {
                applyTagSuggestionUndo { await fileListModel.applyEditedSelectedFileTagSuggestions() }
            },
            onRetryFailedSuggestions: {
                applyTagSuggestionUndo { await fileListModel.retryFailedSelectedFileTagSuggestions() }
            },
            onLoadAISuggestions: { Task { await fileListModel.loadSelectedFileAITagSuggestions() } },
            onRetryAISuggestions: { Task { await fileListModel.retrySelectedFileAITagSuggestions() } },
            onToggleAISuggestion: fileListModel.toggleSelectedFileAITagSuggestion,
            onApplySingleAISuggestion: { suggestionID in
                applyTagSuggestionUndo { await fileListModel.applySelectedFileAITagSuggestion(suggestionID) }
            },
            onSelectHighConfidenceAISuggestions: fileListModel.selectHighConfidenceAITagSuggestions,
            onClearAISuggestions: fileListModel.clearSelectedFileAITagSuggestions,
            onStartEditingAISuggestions: fileListModel.startEditingSelectedFileAITagSuggestions,
            onCancelEditingAISuggestions: fileListModel.cancelEditingSelectedFileAITagSuggestions,
            onEditAISuggestionDisplayName: fileListModel.updateSelectedFileAITagSuggestionDisplayName,
            onEditAISuggestionSlug: fileListModel.updateSelectedFileAITagSuggestionSlug,
            onRegenerateAISuggestionSlug: fileListModel.regenerateSelectedFileAITagSuggestionSlug,
            onApplyAISuggestions: {
                applyTagSuggestionUndo { await fileListModel.applySelectedFileAITagSuggestions() }
            },
            onApplyEditedAISuggestions: {
                applyTagSuggestionUndo { await fileListModel.applyEditedSelectedFileAITagSuggestions() }
            },
            onRetryFailedAISuggestions: {
                applyTagSuggestionUndo { await fileListModel.retryFailedSelectedFileAITagSuggestions() }
            },
            aiBatchActions: fileListModel.aiTagBatchSuggestionActions,
            onOpenAISettings: onOpenAISettings,
            onSuggestionPresentationConsumed: fileListModel.consumeTagSuggestionPresentationRequest,
            onUndoTagChange: { Task { await fileListModel.undoLastDetailTagChange() } },
            onDismissTagUndoToast: fileListModel.dismissDetailTagUndoToast,
            onBatchTagUndoStateChange: updateBatchTagUndoState
        )
    }

    func applyTagSuggestionUndo(_ action: @escaping () async -> BatchTagUndoState?) {
        Task {
            if let state = await action() { updateBatchTagUndoState(state) }
        }
    }
}
