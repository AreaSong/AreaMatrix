import Foundation
import SwiftUI

extension MainRepositoryContentView {
    var detailTagActions: MainRepositoryDetailPaneTagActions {
        MainRepositoryDetailPaneTagActions(
            aiSuggestionState: detailTagModel.aiSuggestionState,
            aiBatchSuggestionState: fileListModel.aiTagBatchSuggestionState,
            onLoadTags: { Task { await detailTagModel.loadSelectedFileTags() } },
            onRetryTags: { Task { await detailTagModel.retrySelectedFileTags() } },
            onAddTag: { tag in Task { await detailTagModel.addSelectedFileTag(tag) } },
            onRemoveTag: { tag in Task { await detailTagModel.removeSelectedFileTag(tag) } },
            onLoadSuggestions: { Task { await detailTagModel.loadSelectedFileTagSuggestions() } },
            onRetrySuggestions: { Task { await detailTagModel.retrySelectedFileTagSuggestions() } },
            onToggleSuggestion: detailTagModel.toggleSelectedFileTagSuggestion,
            onSelectAllSuggestions: detailTagModel.selectAllSelectedFileTagSuggestions,
            onClearSuggestions: detailTagModel.clearSelectedFileTagSuggestions,
            onStartEditingSuggestions: detailTagModel.startEditingSelectedFileTagSuggestions,
            onCancelEditingSuggestions: detailTagModel.cancelEditingSelectedFileTagSuggestions,
            onEditSuggestionDisplayName: detailTagModel.updateSelectedFileTagSuggestionDisplayName,
            onEditSuggestionSlug: detailTagModel.updateSelectedFileTagSuggestionSlug,
            onRegenerateSuggestionSlug: detailTagModel.regenerateSelectedFileTagSuggestionSlug,
            onApplySuggestions: {
                applyTagSuggestionUndo { await detailTagModel.applySelectedFileTagSuggestions() }
            },
            onApplyEditedSuggestions: {
                applyTagSuggestionUndo { await detailTagModel.applyEditedSelectedFileTagSuggestions() }
            },
            onRetryFailedSuggestions: {
                applyTagSuggestionUndo { await detailTagModel.retryFailedSelectedFileTagSuggestions() }
            },
            onLoadAISuggestions: { Task { await detailTagModel.loadSelectedFileAITagSuggestions() } },
            onRetryAISuggestions: { Task { await detailTagModel.retrySelectedFileAITagSuggestions() } },
            onToggleAISuggestion: detailTagModel.toggleSelectedFileAITagSuggestion,
            onApplySingleAISuggestion: { suggestionID in
                applyTagSuggestionUndo { await detailTagModel.applySelectedFileAITagSuggestion(suggestionID) }
            },
            onSelectHighConfidenceAISuggestions: detailTagModel.selectHighConfidenceAITagSuggestions,
            onClearAISuggestions: detailTagModel.clearSelectedFileAITagSuggestions,
            onStartEditingAISuggestions: detailTagModel.startEditingSelectedFileAITagSuggestions,
            onCancelEditingAISuggestions: detailTagModel.cancelEditingSelectedFileAITagSuggestions,
            onEditAISuggestionDisplayName: detailTagModel.updateSelectedFileAITagSuggestionDisplayName,
            onEditAISuggestionSlug: detailTagModel.updateSelectedFileAITagSuggestionSlug,
            onRegenerateAISuggestionSlug: detailTagModel.regenerateSelectedFileAITagSuggestionSlug,
            onApplyAISuggestions: {
                applyTagSuggestionUndo { await detailTagModel.applySelectedFileAITagSuggestions() }
            },
            onApplyEditedAISuggestions: {
                applyTagSuggestionUndo { await detailTagModel.applyEditedSelectedFileAITagSuggestions() }
            },
            onRetryFailedAISuggestions: {
                applyTagSuggestionUndo { await detailTagModel.retryFailedSelectedFileAITagSuggestions() }
            },
            aiBatchActions: fileListModel.aiTagBatchSuggestionActions,
            onOpenAISettings: onOpenAISettings,
            onSuggestionPresentationConsumed: detailTagModel.consumeTagSuggestionPresentationRequest,
            onUndoTagChange: { Task { await detailTagModel.undoLastDetailTagChange() } },
            onDismissTagUndoToast: detailTagModel.dismissDetailTagUndoToast,
            onBatchTagUndoStateChange: updateBatchTagUndoState
        )
    }

    func applyTagSuggestionUndo(_ action: @escaping () async -> BatchTagUndoState?) {
        Task {
            if let state = await action() { updateBatchTagUndoState(state) }
        }
    }
}
