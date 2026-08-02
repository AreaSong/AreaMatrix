import SwiftUI

#if DEBUG
@MainActor
struct DeveloperLibraryScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .commandPalette:
            DeveloperCommandPaletteScenario()
        case .detailLog:
            DeveloperDetailLogScenario()
        case .detailNote:
            DeveloperDetailNoteScenario()
        case .detailPane:
            DeveloperDetailPaneScenario(selection: .single(fixture.primaryFile.id))
        case .detailMultiSelection:
            DeveloperDetailPaneScenario(selection: .multiple(Set(fixture.files.map(\.id))))
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct DeveloperCommandPaletteScenario: View {
    @State private var query = ""

    var body: some View {
        CommandPaletteView(
            query: $query,
            state: .loaded(fixture.commandPaletteSnapshot),
            onLoad: {},
            onExecuteTarget: { _ in },
            onClose: {}
        )
        .background(.background)
    }
}

private struct DeveloperDetailLogScenario: View {
    var body: some View {
        DetailLogTabView(
            selection: .single(fixture.primaryFile.id),
            detailLogState: .loaded(
                fileID: fixture.primaryFile.id,
                entries: fixture.changeLogEntries
            ),
            diagnosticsState: .idle,
            externalCreateSyncState: .idle,
            onRetryExternalSync: {},
            onRefreshChangeLog: {},
            onRequestDiagnostics: {},
            onConfirmDiagnostics: {},
            onCancelDiagnostics: {}
        )
        .padding(24)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }
}

@MainActor
private struct DeveloperDetailNoteScenario: View {
    @StateObject private var model: DetailNoteModel

    init() {
        _model = StateObject(wrappedValue: DetailNoteModel(
            repoPath: fixture.repoPath,
            noteStore: DeveloperDetailNoteStore(),
            errorMapper: CoreErrorSnapshotMapper()
        ))
    }

    var body: some View {
        DetailNoteTabView(
            model: model,
            file: fixture.primaryFile,
            writeBlock: nil,
            onOpenNoteFile: { _ in }
        )
        .padding(24)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }
}

@MainActor
private struct DeveloperDetailPaneScenario: View {
    let selection: MainFileSelectionState

    private let core = DeveloperFileActionCoreFixture()
    @StateObject private var noteModel: DetailNoteModel
    @StateObject private var summaryExitController = AISummaryEditorExitController()

    init(selection: MainFileSelectionState) {
        self.selection = selection
        _noteModel = StateObject(wrappedValue: DetailNoteModel(
            repoPath: fixture.repoPath,
            noteStore: DeveloperDetailNoteStore(),
            errorMapper: CoreErrorSnapshotMapper()
        ))
    }

    var body: some View {
        MainRepositoryDetailPane(
            selection: selection,
            multiSelectionSummary: MultiSelectionDetailSummary(selection: selection, files: fixture.files),
            detailErrorMapping: nil,
            syncConflict: nil,
            isDetailLoading: false,
            selectedFileDetail: selection.singleFileID == nil ? nil : fixture.primaryFile,
            noteWriteBlock: nil,
            detailLogState: .loaded(
                fileID: fixture.primaryFile.id,
                entries: fixture.changeLogEntries
            ),
            detailLogDiagnosticsState: .idle,
            detailExternalCreateSyncState: .idle,
            detailTagEditorState: .loaded(
                fileID: fixture.primaryFile.id,
                DeveloperFileActionScenarioFixture.tagSet
            ),
            detailTagSuggestionState: .idle,
            missingFileRelinkState: .idle,
            tagSuggestionPresentationRequest: nil,
            detailTagUndoToast: nil,
            detailTabRequest: nil,
            selectedImportProgressRow: nil,
            semanticDetail: nil,
            repoPath: fixture.repoPath,
            aiDependencies: AppDependencyContainer.live.feature.ai,
            batchTagStore: core,
            batchTagUndoStore: core,
            batchTagErrorMapper: CoreErrorSnapshotMapper(),
            batchDeleter: core,
            batchCategoryChanger: core,
            batchRenamer: core,
            categoryRows: DeveloperFileActionScenarioFixture.categoryRows,
            onBatchCategoryApplied: { _ in },
            onBatchDeleteApplied: { _ in },
            onBatchRenameApplied: { _ in },
            onBatchCategoryCreateNewCategory: { _ in },
            onRetrySelectedFileDetail: {},
            onRetryExternalSync: {},
            tagActions: fixture.tagActions,
            onCopyPaths: { _ in },
            onOpenNoteFile: { _ in },
            onLocateMissingFile: { _ in },
            onRefreshChangeLog: {},
            onRequestDetailLogDiagnostics: {},
            onConfirmDetailLogDiagnostics: {},
            onCancelDetailLogDiagnostics: {},
            onDetailTabRequestConsumed: { _ in },
            onBeginRenameFile: { _ in },
            onBeginChangeCategoryFile: { _ in },
            onBeginClassifierCorrectionFile: { _ in },
            onBeginAIClassificationSuggestionFile: { _ in },
            onBeginDeleteFile: { _ in },
            onBeginICloudConflictResolution: { _ in },
            onBeginSyncConflictReview: { _ in },
            onOpenAISettings: {},
            writeActionDisabledReason: { _ in nil },
            canPerformWriteAction: { _ in true },
            summaryExitController: summaryExitController,
            noteModel: noteModel
        )
        .frame(maxWidth: 620, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }
}

private let fixture = DeveloperLibraryScenarioFixture.self
#endif
