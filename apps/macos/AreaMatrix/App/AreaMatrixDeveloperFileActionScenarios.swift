import SwiftUI

#if DEBUG
@MainActor
struct DeveloperFileActionScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .fileActionsBatchAddTags:
            DeveloperBatchAddTagsScenario()
        case .fileActionsBatchChangeCategory:
            DeveloperBatchChangeCategoryScenario()
        case .fileActionsBatchDelete:
            DeveloperBatchDeleteScenario()
        case .fileActionsBatchRename:
            DeveloperBatchRenameScenario()
        case .fileActionsChangeCategory:
            DeveloperChangeCategoryScenario()
        case .fileActionsClassifierImpact:
            DeveloperClassifierImpactScenario()
        case .fileActionsDelete:
            DeveloperDeleteFileScenario()
        case .fileActionsRename:
            DeveloperRenameFileScenario()
        case .fileActionsReplace:
            DeveloperReplaceScenario()
        case .fileActionsTagSuggestions:
            DeveloperTagSuggestionsScenario()
        case .fileActionsUndoHistory:
            DeveloperUndoHistoryScenario()
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct DeveloperBatchAddTagsScenario: View {
    private let core = DeveloperFileActionCoreFixture()

    var body: some View {
        BatchAddTagsSheet(
            repoPath: fixture.repoPath,
            fileIDs: fileIDs,
            selectedCount: fileIDs.count,
            disabledReason: nil,
            tagStore: core,
            undoStore: core,
            errorMapper: CoreErrorSnapshotMapper(),
            onUndoStateChange: { _ in },
            onClose: {}
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperBatchChangeCategoryScenario: View {
    private let core = DeveloperFileActionCoreFixture()

    var body: some View {
        BatchChangeCategorySheet(
            repoPath: fixture.repoPath,
            fileIDs: fileIDs,
            selectedFiles: fixture.selectedFiles,
            selectedCount: fileIDs.count,
            disabledReason: nil,
            categoryRows: fixture.categoryRows,
            changer: core,
            undoStore: core,
            errorMapper: CoreErrorSnapshotMapper(),
            initialTargetCategory: "finance",
            onApplied: { _ in },
            onUndoStateChange: { _ in },
            onClose: {}
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperBatchDeleteScenario: View {
    private let core = DeveloperFileActionCoreFixture()

    var body: some View {
        BatchDeleteConfirmSheet(
            repoPath: fixture.repoPath,
            fileIDs: fileIDs,
            selectedFiles: fixture.selectedFiles,
            selectedCount: fileIDs.count,
            disabledReason: nil,
            deleter: core,
            undoStore: core,
            errorMapper: CoreErrorSnapshotMapper(),
            onApplied: { _ in },
            onUndoStateChange: { _ in },
            onClose: {}
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperBatchRenameScenario: View {
    private let core = DeveloperFileActionCoreFixture()

    var body: some View {
        BatchRenameSheet(
            repoPath: fixture.repoPath,
            fileIDs: fileIDs,
            selectedFiles: fixture.selectedFiles,
            selectedCount: fileIDs.count,
            disabledReason: nil,
            renamer: core,
            undoStore: core,
            errorMapper: CoreErrorSnapshotMapper(),
            onApplied: { _ in },
            onUndoStateChange: { _ in },
            onClose: {}
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperChangeCategoryScenario: View {
    private let file = fixture.primaryFile

    var body: some View {
        ChangeCategorySheet(
            file: file,
            categoryRows: fixture.categoryRows,
            state: .ready(previewRequest, fixture.movePreview(file: file, targetCategory: "finance")),
            initialTargetCategory: "finance",
            onCancel: {},
            onPreview: { _, _ in },
            onChangeCategory: { _, _, _, _ in },
            onRenameFirst: { _, _ in },
            onOpenPermissionRecovery: {},
            onCollectDiagnostics: {}
        )
        .background(.background)
    }

    private var previewRequest: MainFileCategoryMovePreviewRequest {
        MainFileCategoryMovePreviewRequest(fileID: file.id, targetCategory: "finance")
    }
}

@MainActor
private struct DeveloperClassifierImpactScenario: View {
    private let core = DeveloperFileActionCoreFixture()

    var body: some View {
        ClassifierImpactPreviewSheet(
            repoPath: fixture.repoPath,
            handoff: fixture.classifierHandoff,
            previewer: core,
            errorMapper: CoreErrorSnapshotMapper(),
            onCancel: {},
            onBack: { _ in }
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperDeleteFileScenario: View {
    var body: some View {
        DeleteFileConfirmSheet(
            file: fixture.primaryFile,
            operation: .moveToTrash,
            state: .idle,
            isTrashAvailable: true,
            onCancel: {},
            onConfirm: { _, _ in },
            onCollectDiagnostics: {}
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperRenameFileScenario: View {
    var body: some View {
        RenameFileSheet(
            file: fixture.primaryFile,
            candidateFiles: fixture.selectedFiles,
            state: .idle,
            onCancel: {},
            onRename: { _, _ in },
            onShowExistingFile: { _ in }
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperReplaceScenario: View {
    var body: some View {
        ReplaceConfirmSheet(
            context: fixture.replaceContext,
            errorMessage: nil,
            diagnosticsMessage: nil,
            onCancel: {},
            onRetry: {},
            onCollectDiagnostics: {},
            onConfirm: { _ in }
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperTagSuggestionsScenario: View {
    @State private var state = fixture.tagSuggestionState

    var body: some View {
        TagSuggestionsPanel(
            file: fixture.primaryFile,
            state: state,
            disabledReason: nil,
            onRetry: reset,
            onToggleSuggestion: toggle,
            onSelectAll: { state = DetailTagSuggestionAction.selectingAll(in: state) },
            onClearSelection: { state = DetailTagSuggestionAction.clearingSelection(in: state) },
            onStartEditing: startEditing,
            onCancelEditing: { state = DetailTagSuggestionAction.cancelingEdit(in: state) },
            onEditDisplayName: updateDisplayName,
            onEditSlug: updateSlug,
            onRegenerateSlug: regenerateSlug,
            onApplySelected: applySelected,
            onApplyEdited: applyEdited,
            onRetryFailed: reset,
            onAddManually: {},
            onClose: {}
        )
        .background(.background)
    }

    private func reset() {
        state = fixture.tagSuggestionState
    }

    private func toggle(_ suggestionID: String) {
        state = DetailTagSuggestionAction.togglingSelection(suggestionID: suggestionID, in: state)
    }

    private func startEditing() {
        state = DetailTagSuggestionAction.startingEdit(in: state, disabledReason: nil)
    }

    private func updateDisplayName(_ suggestionID: String, _ displayName: String) {
        state = DetailTagSuggestionAction.updatingDisplayName(
            suggestionID: suggestionID,
            displayName: displayName,
            in: state,
            disabledReason: nil
        )
    }

    private func updateSlug(_ suggestionID: String, _ slug: String) {
        state = DetailTagSuggestionAction.updatingSlug(
            suggestionID: suggestionID,
            slug: slug,
            in: state,
            disabledReason: nil
        )
    }

    private func regenerateSlug(_ suggestionID: String) {
        state = DetailTagSuggestionAction.regeneratingSlug(
            suggestionID: suggestionID,
            in: state,
            disabledReason: nil
        )
    }

    private func applySelected() {
        guard let report = state.report else { return }
        state = .applied(fileID: report.fileID, report, fixture.tagApplyReport, state.selectedIDs)
    }

    private func applyEdited() {
        guard let report = state.report, let session = state.editSession else { return }
        state = .editApplied(fileID: report.fileID, report, fixture.tagApplyReport, session)
    }
}

@MainActor
private struct DeveloperUndoHistoryScenario: View {
    private let core = DeveloperFileActionCoreFixture()

    var body: some View {
        UndoHistoryPanel(
            repoPath: fixture.repoPath,
            focusedActionID: fixture.undoActions.first?.actionID,
            initialFailure: nil,
            undoStore: core,
            redoStore: core,
            errorMapper: CoreErrorSnapshotMapper(),
            onClose: {},
            onUndoCompleted: { _ in },
            onRedoCompleted: { _ in }
        )
        .background(.background)
    }
}

private let fixture = DeveloperFileActionScenarioFixture.self
private var fileIDs: [Int64] {
    fixture.selectedFiles.map(\.id)
}
#endif
