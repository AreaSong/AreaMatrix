import SwiftUI

struct ImportEntrySheetView: View {
    let request: ImportEntryRequest
    let onCancel: () -> Void
    let onSwitchToLocalRepo: () -> Void
    let onImportStarted: (String, ImportSingleFileStorageMode) -> Void
    let onImportStartedWithRetryContext: (
        String,
        String,
        ImportSingleFileStorageMode,
        String,
        String,
        DuplicateStrategy
    ) -> Void
    let onImportFailed: (String, CoreErrorMappingSnapshot) -> Void
    let onBatchImportProgress: ImportBatchProgressHandler
    let onBatchImportFailed: ImportBatchFailureHandler
    let onBatchImportResults: ImportBatchProgressHandler
    let importProgressControlState: ImportProgressControlState
    let onImported: (String, FileEntrySnapshot) -> Void
    let onShowExistingFile: (String) -> Void

    @StateObject var previewModel: ImportSingleFilePreviewModel
    @StateObject private var batchPreviewModel: ImportBatchPreviewModel
    @StateObject private var batchImportModel: ImportBatchCopyImportModel
    @StateObject private var folderPreviewModel: ImportFolderPreviewModel
    @State var isReasonPopoverPresented = false
    @State private var showsBatchConflictReview = false
    @State private var pendingBatchReplaceConfirmation: ImportBatchReplaceConfirmation?
    @State var pendingSingleFileReplaceConfirmation: ImportSingleFileReplaceConfirmation?
    @State private var showsFolderConflictReview = false
    @State private var pendingFolderReplaceConfirmation: ImportFolderReplaceConfirmation?

    init(
        request: ImportEntryRequest,
        onCancel: @escaping () -> Void,
        onSwitchToLocalRepo: (() -> Void)? = nil,
        onImportStarted: @escaping (String, ImportSingleFileStorageMode) -> Void = { _, _ in },
        onImportStartedWithRetryContext: @escaping (
            String,
            String,
            ImportSingleFileStorageMode,
            String,
            String,
            DuplicateStrategy
        ) -> Void = { _, _, _, _, _, _ in },
        onImportFailed: @escaping (String, CoreErrorMappingSnapshot) -> Void = { _, _ in },
        onBatchImportProgress: @escaping ImportBatchProgressHandler = { _ in },
        onBatchImportFailed: @escaping ImportBatchFailureHandler = { _, _, _, _ in },
        onBatchImportResults: @escaping ImportBatchProgressHandler = { _ in },
        importProgressControlState: ImportProgressControlState = ImportProgressControlState(),
        onImported: @escaping (String, FileEntrySnapshot) -> Void = { _, _ in },
        onShowExistingFile: @escaping (String) -> Void = { _ in },
        categoryPredictor: any CoreCategoryPredicting = AppCoreServices.categoryPredictor,
        fileImporter: any CoreFileImporting = CoreBridge(),
        batchFileImporter: any CoreBatchCopyImporting = CoreBridge(),
        batchConflictBatcher: any CoreImportConflictBatching = CoreBridge(),
        batchDuplicatePrechecker: any ImportBatchDuplicatePrechecking = CoreImportBatchDuplicatePrechecker(),
        batchNameConflictPrechecker: any ImportBatchNameConflictPrechecking = CoreImportBatchNameConflictPrechecker(),
        folderScanner: any ImportFolderScanning = ImportPlatformServices.folderScanner,
        preflight: any ImportSingleFilePreflighting = CoreImportSingleFilePreflight(),
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader(),
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        batchSessionStore: any ImportBatchSessionPersisting = AppPlatformServices.importBatchSessionStore
    ) {
        self.request = request
        self.onCancel = onCancel
        self.onSwitchToLocalRepo = onSwitchToLocalRepo ?? onCancel
        self.onImportStarted = onImportStarted
        self.onImportStartedWithRetryContext = onImportStartedWithRetryContext
        self.onImportFailed = onImportFailed
        self.onBatchImportProgress = onBatchImportProgress
        self.onBatchImportFailed = onBatchImportFailed
        self.onBatchImportResults = onBatchImportResults
        self.importProgressControlState = importProgressControlState
        self.onImported = onImported
        self.onShowExistingFile = onShowExistingFile
        _previewModel = StateObject(wrappedValue: ImportSingleFilePreviewModel(
            predictor: categoryPredictor,
            importer: fileImporter,
            preflight: preflight,
            placeholderDownloader: placeholderDownloader,
            errorMapper: errorMapper
        ))
        _batchPreviewModel = StateObject(wrappedValue: ImportBatchPreviewModel(
            predictor: categoryPredictor,
            duplicatePrechecker: batchDuplicatePrechecker,
            nameConflictPrechecker: batchNameConflictPrechecker
        ))
        _batchImportModel = StateObject(wrappedValue: ImportBatchCopyImportModel(
            importer: batchFileImporter,
            errorMapper: errorMapper,
            conflictBatcher: batchConflictBatcher,
            sessionStore: batchSessionStore,
            placeholderDownloader: placeholderDownloader
        ))
        _folderPreviewModel = StateObject(wrappedValue: ImportFolderPreviewModel(
            predictor: categoryPredictor,
            importer: batchFileImporter,
            errorMapper: errorMapper,
            scanner: folderScanner,
            placeholderDownloader: placeholderDownloader
        ))
    }
}

extension ImportEntrySheetView {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.sheetTitle)
                .font(.title2.weight(.semibold))

            switch request.kind {
            case .singleFile:
                singleFilePreview
            case .multipleItems:
                batchPreview
            case .folder:
                folderPreview
            }

            footer
        }
        .padding(24)
        .frame(minWidth: request.urls.count > 1 ? 720 : 480)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.immediate)
        .task(id: request.id) {
            switch request.kind {
            case .singleFile:
                await previewModel.load(request: request)
            case .multipleItems:
                await batchPreviewModel.load(request: request)
                batchImportModel.applyPreviewRows(
                    batchPreviewModel.rows,
                    request: request,
                    selectedDestination: batchPreviewModel.selectedDestination
                )
                if batchImportModel.showsCoreConflictBatchReview {
                    showsBatchConflictReview = true
                    await batchImportModel.loadImportConflictBatchPreview()
                }
            case .folder:
                await folderPreviewModel.load(request: request)
            }
        }
        .onChange(of: batchPreviewModel.rows) { _, rows in
            if case .multipleItems = request.kind {
                batchImportModel.applyPreviewRows(
                    rows,
                    request: request,
                    selectedDestination: batchPreviewModel.selectedDestination
                )
                if batchImportModel.showsCoreConflictBatchReview {
                    showsBatchConflictReview = true
                    Task { await batchImportModel.loadImportConflictBatchPreview() }
                }
            }
        }
        .onChange(of: batchPreviewModel.selectedDestination) { _, selectedDestination in
            if case .multipleItems = request.kind {
                batchImportModel.applyPreviewRows(
                    batchPreviewModel.rows,
                    request: request,
                    selectedDestination: selectedDestination
                )
            }
        }
        .sheet(item: $pendingBatchReplaceConfirmation) { item in
            ImportEntryReplaceConfirmationSheets.batch(
                item: item,
                model: batchImportModel,
                pending: $pendingBatchReplaceConfirmation
            )
        }
        .sheet(item: $pendingSingleFileReplaceConfirmation) { item in
            ImportEntryReplaceConfirmationSheets.singleFile(
                item: item,
                model: previewModel,
                pending: $pendingSingleFileReplaceConfirmation
            )
        }
        .sheet(item: $pendingFolderReplaceConfirmation) { item in
            ImportEntryReplaceConfirmationSheets.folder(
                item: item,
                model: folderPreviewModel,
                pending: $pendingFolderReplaceConfirmation
            )
        }
    }

    private var batchPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            ImportBatchSummarySection(
                totalSizeDescription: batchPreviewModel.totalSizeDescription,
                sourceLabel: batchPreviewModel.sourceLabel,
                duplicateCount: batchImportModel.duplicateCount,
                nameConflictCount: batchImportModel.nameConflictCount,
                iCloudPlaceholderCount: batchImportModel.iCloudPlaceholderCount
            )
            ImportBatchDestinationSection(
                selectedDestination: $batchPreviewModel.selectedDestination,
                destinationOptions: batchPreviewModel.destinationOptions,
                selectedStorageMode: $batchImportModel.selectedStorageMode,
                selectedNamingStrategy: Binding(
                    get: { batchImportModel.selectedNamingStrategy },
                    set: { batchImportModel.updateNamingStrategy($0) }
                ),
                namingPrefix: $batchImportModel.namingPrefix,
                isImporting: batchImportModel.status.isImporting,
                destinationHelperMessage: batchPreviewModel.destinationHelperMessage,
                storageModeRiskMessage: batchImportModel.storageModeRiskMessage
            )
            batchStatusSection
            ImportBatchRowsSection(
                itemCount: request.urls.count,
                rows: batchImportModel.rows,
                selectedDestination: batchPreviewModel.selectedDestination,
                isImporting: batchImportModel.status.isImporting,
                categoryOptions: batchCategoryOptions,
                onUpdateCategory: batchImportModel.updateCategoryOverride
            )
            if batchImportModel.duplicateCount > 0
                || batchImportModel.nameConflictCount > 0
                || batchImportModel.iCloudPlaceholderCount > 0
                || batchImportModel.blockedCount > 0
                || showsBatchConflictReview {
                ImportBatchConflictSection(
                    batchImportModel: batchImportModel,
                    isExpanded: $showsBatchConflictReview,
                    pendingReplaceConfirmation: $pendingBatchReplaceConfirmation,
                    onRetryPreview: {
                        Task { await batchPreviewModel.retryPreview() }
                    },
                    onSwitchToLocalRepo: onSwitchToLocalRepo,
                    onShowExistingFile: onShowExistingFile
                )
            }
            if batchPreviewModel.showsRetryPreview {
                HStack(spacing: 10) {
                    Button("Retry preview") {
                        Task { await batchPreviewModel.retryPreview() }
                    }
                }
            }
        }
    }

    private var batchStatusSection: some View {
        HStack(spacing: 8) {
            if batchPreviewModel.status.isLoading || batchImportModel.status.isImporting {
                ProgressView()
                    .controlSize(.small)
            }

            if let message = batchImportModel.status.message ?? batchPreviewModel.status.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(batchPreviewStatusStyle)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        Group {
            if request.kind == .singleFile {
                singleFileFooter
            } else if case .multipleItems = request.kind {
                ImportBatchCopyFooterSection(
                    request: request,
                    batchPreviewModel: batchPreviewModel,
                    batchImportModel: batchImportModel,
                    onCancel: onCancel,
                    onImportProgress: onBatchImportProgress,
                    onImportFailed: onBatchImportFailed,
                    onImportResults: onBatchImportResults,
                    importProgressControlState: importProgressControlState,
                    onImported: onImported
                )
            } else if case .folder = request.kind {
                ImportFolderFooterSection(
                    request: request,
                    model: folderPreviewModel,
                    importDisabledReason: folderPreviewModel.importDisabledReason,
                    onCancel: onCancel,
                    onImportProgress: onBatchImportProgress,
                    onImportFailed: onBatchImportFailed,
                    onImportResults: onBatchImportResults,
                    importProgressControlState: importProgressControlState,
                    onImported: onImported,
                    onRetryScan: {
                        Task { await folderPreviewModel.retryScan() }
                    }
                )
            }
        }
    }

    private var folderPreview: some View {
        ImportFolderPreviewView(
            model: folderPreviewModel,
            request: request,
            showsConflictReview: $showsFolderConflictReview,
            pendingReplaceConfirmation: $pendingFolderReplaceConfirmation,
            onSwitchToLocalRepo: onSwitchToLocalRepo,
            onShowExistingFile: onShowExistingFile
        )
    }

    private var batchPreviewStatusStyle: Color {
        if case let .imported(_, failed) = batchImportModel.status, failed > 0 {
            return .orange
        }
        switch batchImportModel.status {
        case .importing, .imported:
            return .secondary
        case .idle:
            break
        }

        switch batchPreviewModel.status {
        case let .loaded(_, _, failed) where failed > 0:
            return .orange
        case .unsupported:
            return .red
        case .idle, .loading, .loaded:
            return .secondary
        }
    }
}
