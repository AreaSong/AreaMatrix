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

    @MainActor
    func refreshAfterCategoryMove(_ movedFile: FileEntrySnapshot) {
        Task {
            await refreshTreeAndFocusMovedFile(movedFile)
        }
    }

    @MainActor
    func refreshAfterClassifierCorrection(_ correctedFile: FileEntrySnapshot) async {
        await fileListModel.retryCurrentCategory()
        selectedFileIDs = [correctedFile.id]
        await fileListModel.selectFiles([correctedFile.id])
        fileListModel.statusBanner = .correctedClassification(
            fileID: correctedFile.id,
            category: correctedFile.category,
            ruleConfirmationRequired: fileListModel.classifierCorrectionResult?.ruleConfirmationRequired ?? false
        )
    }

    @MainActor
    func refreshTreeAndFocusMovedFile(_ movedFile: FileEntrySnapshot) async {
        let refreshedTree = await refreshedTreeAfterCategoryMove()
        let plan = CategoryMoveRefreshPlan.make(
            movedFile: movedFile,
            currentSidebarID: selectedSidebarID,
            currentTree: repositoryTree,
            refreshedTree: refreshedTree
        )

        repositoryTree = plan.tree
        pendingMovedFileFocusID = movedFile.id
        selectedSidebarID = plan.selectedSidebarID
        selectedFileIDs = [movedFile.id]
        await fileListModel.loadCurrentCategory(plan.categoryForFileList, focusingOn: movedFile.id)
        selectedFileIDs = [movedFile.id]
        if refreshedTree == nil {
            fileListModel.statusBanner = .changedCategoryTreeRefreshFailed(
                fileID: movedFile.id,
                category: movedFile.category
            )
        } else if fileListModel.errorMapping == nil {
            fileListModel.statusBanner = .changedCategory(fileID: movedFile.id, category: movedFile.category)
        }
    }

    private func refreshedTreeAfterCategoryMove() async -> RepositoryTreeNodeSnapshot? {
        do {
            return try await treeLister.listTree(repoPath: opening.config.repoPath, locale: opening.config.locale)
        } catch {
            return nil
        }
    }
}

struct CategoryMoveRefreshPlan: Equatable {
    var tree: RepositoryTreeNodeSnapshot
    var selectedSidebarID: String
    var focusedFileID: Int64
    var categoryForFileList: String?

    static func make(
        movedFile: FileEntrySnapshot,
        currentSidebarID: String,
        currentTree: RepositoryTreeNodeSnapshot,
        refreshedTree: RepositoryTreeNodeSnapshot?
    ) -> CategoryMoveRefreshPlan {
        let tree = refreshedTree ?? currentTree
        let fallbackSidebarID = sidebarID(forMovedFile: movedFile, in: currentTree) ?? currentSidebarID
        let selectedSidebarID = sidebarID(forMovedFile: movedFile, in: tree) ?? fallbackSidebarID
        let selectedRow = tree.sidebarRow(id: selectedSidebarID) ??
            tree.sidebarRows.first ??
            RepositorySidebarRowSnapshot(node: tree, depth: 0)
        return CategoryMoveRefreshPlan(
            tree: tree,
            selectedSidebarID: selectedSidebarID,
            focusedFileID: movedFile.id,
            categoryForFileList: selectedRow.categoryForFileList
        )
    }

    private static func sidebarID(forMovedFile file: FileEntrySnapshot,
                                  in tree: RepositoryTreeNodeSnapshot) -> String? {
        tree.sidebarRows.first { row in
            row.categoryForFileList == file.category && row.contains(file)
        }?.id ?? tree.sidebarRows.first { row in
            row.categoryForFileList == file.category && row.pathFilterPrefix == nil
        }?.id
    }
}
