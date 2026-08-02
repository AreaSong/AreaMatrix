import SwiftUI

#if DEBUG
@MainActor
struct DeveloperImportScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .importEntry:
            DeveloperImportEntryScenario()
        case .importFolderPreview:
            DeveloperImportFolderPreviewScenario()
        case .importProgress:
            DeveloperImportProgressScenario()
        case .importResult:
            DeveloperImportResultScenario()
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct DeveloperImportEntryScenario: View {
    private let services = DeveloperImportScenarioServices()
    private let sessionStore = DeveloperImportScenarioSessionStore()

    var body: some View {
        ImportEntrySheetView(
            request: DeveloperImportScenarioFixture.singleFileRequest,
            onCancel: {},
            categoryPredictor: services,
            batchFileLoader: services,
            fileImporter: services,
            batchFileImporter: services,
            batchConflictBatcher: services,
            undoActionStore: services,
            batchDuplicatePrechecker: services,
            batchNameConflictPrechecker: services,
            folderScanner: services,
            preflight: services,
            placeholderDownloader: services,
            errorMapper: CoreErrorSnapshotMapper(),
            batchSessionStore: sessionStore
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperImportFolderPreviewScenario: View {
    @StateObject private var model: ImportFolderPreviewModel
    @State private var showsConflictReview = false
    @State private var pendingReplaceConfirmation: ImportFolderReplaceConfirmation?

    init() {
        let services = DeveloperImportScenarioServices()
        _model = StateObject(wrappedValue: ImportFolderPreviewModel(
            predictor: services,
            importer: services,
            errorMapper: CoreErrorSnapshotMapper(),
            conflictPrechecker: services,
            scanner: services,
            placeholderDownloader: services
        ))
    }

    var body: some View {
        ImportFolderPreviewView(
            model: model,
            request: DeveloperImportScenarioFixture.folderRequest,
            showsConflictReview: $showsConflictReview,
            pendingReplaceConfirmation: $pendingReplaceConfirmation,
            onSwitchToLocalRepo: {},
            onShowExistingFile: { _ in }
        )
        .background(.background)
        .task {
            await model.load(request: DeveloperImportScenarioFixture.folderRequest)
        }
    }
}

private struct DeveloperImportProgressScenario: View {
    var body: some View {
        ImportProgressView(
            state: DeveloperImportScenarioFixture.progressState,
            onStopAfterCurrentFile: {},
            onViewDetails: {},
            onRetryCurrentItem: {},
            onStopAndViewResults: {},
            onRequestDiagnostics: {},
            onConfirmDiagnostics: {},
            onCancelDiagnostics: {},
            onOpenRepositoryInFinder: {}
        )
        .background(.background)
    }
}

private struct DeveloperImportResultScenario: View {
    var body: some View {
        ImportResultView(
            state: DeveloperImportScenarioFixture.resultState,
            onDone: {},
            onRetryFailed: {},
            onLoadChangeLog: {},
            onShowExistingFile: { _ in },
            onReviewTagSuggestions: { _ in },
            onRequestExport: {},
            onConfirmExport: {},
            onCancelExport: {}
        )
        .background(.background)
    }
}
#endif
