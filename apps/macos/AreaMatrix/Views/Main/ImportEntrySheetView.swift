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
    @State private var isReasonPopoverPresented = false
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
        categoryPredictor: any CoreCategoryPredicting = CoreBridge(),
        fileImporter: any CoreFileImporting = CoreBridge(),
        batchFileImporter: any CoreBatchCopyImporting = CoreBridge(),
        batchDuplicatePrechecker: any ImportBatchDuplicatePrechecking = CoreImportBatchDuplicatePrechecker(),
        batchNameConflictPrechecker: any ImportBatchNameConflictPrechecking = CoreImportBatchNameConflictPrechecker(),
        folderScanner: any ImportFolderScanning = LocalImportFolderScanner(),
        preflight: any ImportSingleFilePreflighting = CoreImportSingleFilePreflight(),
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader(),
        errorMapper: any CoreErrorMapping = CoreBridge()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.sheetTitle)
                .font(.title2.weight(.semibold))

            switch request.kind {
            case .singleFile:
                singleFilePreview
            case .multipleItems(_):
                batchPreview
            case .folder:
                folderPreview
            }

            footer
        }
        .padding(24)
        .frame(minWidth: request.urls.count > 1 ? 720 : 480)
        .task(id: request.id) {
            switch request.kind {
            case .singleFile:
                await previewModel.load(request: request)
            case .multipleItems(_):
                await batchPreviewModel.load(request: request)
                batchImportModel.applyPreviewRows(
                    batchPreviewModel.rows,
                    request: request,
                    selectedDestination: batchPreviewModel.selectedDestination
                )
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
            ReplaceConfirmSheet(
                context: item.context,
                onCancel: { pendingBatchReplaceConfirmation = nil },
                onConfirm: { decision in
                    batchImportModel.applyReplaceConfirmation(for: item.rowID, decision: decision)
                    pendingBatchReplaceConfirmation = nil
                }
            )
        }
        .sheet(item: $pendingSingleFileReplaceConfirmation) { item in
            ReplaceConfirmSheet(
                context: item.context,
                onCancel: {
                    previewModel.cancelReplaceConfirmation()
                    pendingSingleFileReplaceConfirmation = nil
                },
                onConfirm: { decision in
                    previewModel.applyReplaceConfirmation(decision)
                    pendingSingleFileReplaceConfirmation = nil
                }
            )
        }
        .sheet(item: $pendingFolderReplaceConfirmation) { item in
            ReplaceConfirmSheet(
                context: item.context,
                onCancel: { pendingFolderReplaceConfirmation = nil },
                onConfirm: { decision in
                    folderPreviewModel.applyReplaceConfirmation(for: item.rowID, decision: decision)
                    pendingFolderReplaceConfirmation = nil
                }
            )
        }
    }

    private var singleFilePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            fileInformation
            classifyControls
            ImportSingleFileStorageModeSection(selectedMode: $previewModel.selectedStorageMode)
            previewStatus
            ImportSingleFilePreflightStatusSection(
                status: previewModel.preflightStatus,
                message: previewModel.preflightMessage,
                isICloudDownloading: previewModel.isICloudDownloading
            )
            if previewModel.showsICloudActions {
                ImportSingleFileICloudActionsSection(
                    isDownloading: previewModel.isICloudDownloading,
                    onDownloadAndRetry: {
                        Task { await previewModel.downloadICloudPlaceholderAndRetry() }
                    },
                    onSwitchToLocalRepo: onSwitchToLocalRepo
                )
            }
            if previewModel.showsRetryPreviewAction {
                ImportSingleFileRetryPreviewSection(
                    onRetryPreview: {
                        Task { await previewModel.retryPreview() }
                    }
                )
            }
            if let result = previewModel.currentPreflightResult, previewModel.showsConflictSection {
                ImportSingleFileConflictSection(
                    result: result,
                    activePage: previewModel.activeConflictPage,
                    sourceFilename: previewModel.source?.fileName,
                    sourcePath: previewModel.source?.sourcePath,
                    replaceOptionVisibility: previewModel.replaceOptionVisibility,
                    duplicateResolution: Binding(
                        get: { previewModel.duplicateResolution },
                        set: { previewModel.updateDuplicateResolution($0) }
                    ),
                    onBeginReplaceConfirmation: {
                        previewModel.beginReplaceConfirmation()
                        if let context = previewModel.pendingReplaceConfirmation {
                            pendingSingleFileReplaceConfirmation = ImportSingleFileReplaceConfirmation(context: context)
                        }
                    },
                    onShowExistingFile: onShowExistingFile
                )
            }
            ImportSingleFileImportStatusSection(
                status: previewModel.importStatus,
                disabledReason: previewModel.importDisabledReason
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

    private var fileInformation: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc")
                .font(.title2)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(previewModel.source?.fileName ?? primaryFileLabel)
                    .font(.headline)
                    .lineLimit(2)
                if let sourceSizeDescription = previewModel.sourceSizeDescription {
                    Text("大小：\(sourceSizeDescription)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("来源：\(previewModel.source?.sourcePath ?? request.destinationLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private var classifyControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Picker("建议分类", selection: $previewModel.selectedCategory) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .frame(maxWidth: 240)

                reasonButton
            }

            TextField("建议命名", text: $previewModel.suggestedName)
                .textFieldStyle(.roundedBorder)
            if let filenameValidationMessage = previewModel.filenameValidationMessage {
                Text(filenameValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var reasonButton: some View {
        Button("为什么？") {
            isReasonPopoverPresented.toggle()
        }
        .disabled(previewModel.prediction == nil)
        .popover(isPresented: $isReasonPopoverPresented) {
            Text(previewModel.reasonSummary)
                .padding()
                .frame(minWidth: 180)
        }
    }

    private var previewStatus: some View {
        HStack(spacing: 8) {
            if previewModel.status.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let message = previewModel.status.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(previewStatusStyle)
            }
        }
        .accessibilityElement(children: .combine)
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

    private var categoryOptions: [String] {
        ImportEntrySheetHelper.categoryOptions(
            availableCategories: request.availableCategories,
            selectedCategory: previewModel.selectedCategory,
            predictedCategory: previewModel.prediction?.category
        )
    }

    private var previewStatusStyle: Color {
        if case .failed = previewModel.status {
            return .red
        }
        if case .unsupported = previewModel.status {
            return .secondary
        }
        return .secondary
    }

    private var batchPreviewStatusStyle: Color {
        if case .imported(_, let failed) = batchImportModel.status, failed > 0 {
            return .orange
        }
        switch batchImportModel.status {
        case .importing, .imported:
            return .secondary
        case .idle:
            break
        }

        switch batchPreviewModel.status {
        case .loaded(_, _, let failed) where failed > 0:
            return .orange
        case .unsupported:
            return .red
        case .idle, .loading, .loaded:
            return .secondary
        }
    }

    private var primaryFileLabel: String {
        ImportEntrySheetHelper.primaryFileLabel(urls: request.urls)
    }

}
