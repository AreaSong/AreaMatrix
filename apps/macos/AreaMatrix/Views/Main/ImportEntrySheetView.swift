import SwiftUI

struct ImportEntrySheetView: View {
    let request: ImportEntryRequest
    let onCancel: () -> Void
    let onSwitchToLocalRepo: () -> Void
    let onImportStarted: (String) -> Void
    let onImportFailed: (String, CoreErrorMappingSnapshot) -> Void
    let onImported: (String, FileEntrySnapshot) -> Void

    @StateObject private var previewModel: ImportSingleFilePreviewModel
    @State private var isReasonPopoverPresented = false

    init(
        request: ImportEntryRequest,
        onCancel: @escaping () -> Void,
        onSwitchToLocalRepo: (() -> Void)? = nil,
        onImportStarted: @escaping (String) -> Void = { _ in },
        onImportFailed: @escaping (String, CoreErrorMappingSnapshot) -> Void = { _, _ in },
        onImported: @escaping (String, FileEntrySnapshot) -> Void = { _, _ in },
        categoryPredictor: any CoreCategoryPredicting = CoreBridge(),
        fileImporter: any CoreFileImporting = CoreBridge(),
        preflight: any ImportSingleFilePreflighting = CoreImportSingleFilePreflight(),
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.request = request
        self.onCancel = onCancel
        self.onSwitchToLocalRepo = onSwitchToLocalRepo ?? onCancel
        self.onImportStarted = onImportStarted
        self.onImportFailed = onImportFailed
        self.onImported = onImported
        _previewModel = StateObject(wrappedValue: ImportSingleFilePreviewModel(
            predictor: categoryPredictor,
            importer: fileImporter,
            preflight: preflight,
            placeholderDownloader: placeholderDownloader,
            errorMapper: errorMapper
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.sheetTitle)
                .font(.title2.weight(.semibold))

            if request.kind == .singleFile {
                singleFilePreview
            } else {
                genericImportSummary
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 480)
        .task(id: request.id) {
            await previewModel.load(request: request)
        }
        .sheet(item: Binding(
            get: { previewModel.pendingReplaceConfirmation },
            set: { if $0 == nil { previewModel.cancelReplaceConfirmation() } }
        )) { context in
            ReplaceConfirmSheet(
                context: context,
                onCancel: previewModel.cancelReplaceConfirmation,
                onConfirm: previewModel.applyReplaceConfirmation
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
                    isReplaceConfirmed: previewModel.isReplaceConfirmed,
                    onOpenReplaceConfirm: previewModel.beginReplaceConfirmation
                )
            }
            ImportSingleFileImportStatusSection(
                status: previewModel.importStatus,
                disabledReason: previewModel.importDisabledReason
            )
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

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            if request.kind == .singleFile {
                Button("Import") {
                    Task {
                        onImportStarted(previewModel.progressCurrentPath)
                        if let entry = await previewModel.importSelectedFile() {
                            onImported(request.repoPath, entry)
                        } else if let mapping = previewModel.importFailureMapping {
                            onImportFailed(previewModel.progressCurrentPath, mapping)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(previewModel.importDisabledReason != nil)
            }
        }
    }

    private var genericImportSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(primaryFileLabel)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
            LabeledContent("Destination", value: request.destinationLabel)
        }
    }

    private var categoryOptions: [String] {
        let values = request.availableCategories + [previewModel.selectedCategory, previewModel.prediction?.category, "inbox"]
        var uniqueValues: [String] = []
        for value in values.compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if !uniqueValues.contains(value) {
                uniqueValues.append(value)
            }
        }
        return uniqueValues
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

    private var primaryFileLabel: String {
        guard let firstURL = request.urls.first else {
            return "No valid file URL"
        }

        if request.urls.count == 1 {
            return firstURL.path
        }

        return "\(firstURL.path) and \(request.urls.count - 1) more"
    }
}
