import SwiftUI

struct ImportEntrySheetView: View {
    let request: ImportEntryRequest
    let onCancel: () -> Void
    let onSwitchToLocalRepo: () -> Void
    let onImportStarted: (String) -> Void
    let onImportFailed: (String, CoreErrorMappingSnapshot) -> Void
    let onImported: (String, FileEntrySnapshot) -> Void

    @StateObject private var previewModel: ImportSingleFilePreviewModel
    @StateObject private var batchPreviewModel: ImportBatchPreviewModel
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
        _batchPreviewModel = StateObject(wrappedValue: ImportBatchPreviewModel(
            predictor: categoryPredictor
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
                genericImportSummary
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
            case .folder:
                break
            }
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

    private var batchPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            batchSummary
            batchDestinationSection
            batchStatusSection
            batchRowsSection
            if batchPreviewModel.showsRetryPreview {
                HStack(spacing: 10) {
                    Button("Retry preview") {
                        Task { await batchPreviewModel.retryPreview() }
                    }
                }
            }
            batchBoundarySection
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

    private var batchSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("批量导入摘要")
                .font(.headline)
            HStack(spacing: 16) {
                if let totalSizeDescription = batchPreviewModel.totalSizeDescription {
                    LabeledContent("总大小", value: totalSizeDescription)
                }
                LabeledContent("来源", value: batchPreviewModel.sourceLabel)
                LabeledContent("预计重复", value: "待后续重复检测任务接入")
                LabeledContent("重名冲突", value: "待后续冲突任务接入")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var batchDestinationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("导入到", selection: $batchPreviewModel.selectedDestination) {
                ForEach(batchPreviewModel.destinationOptions, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if let helperMessage = batchPreviewModel.destinationHelperMessage {
                Text(helperMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var batchStatusSection: some View {
        HStack(spacing: 8) {
            if batchPreviewModel.status.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let message = batchPreviewModel.status.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(batchPreviewStatusStyle)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var batchRowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup("查看 \(request.urls.count) 个项目") {
                Table(batchPreviewModel.rows) {
                    TableColumn("原文件名") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.originalName)
                            Text(row.sourcePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    TableColumn("建议分类") { row in
                        Text(row.displayCategory(for: batchPreviewModel.selectedDestination))
                    }
                    TableColumn("建议新名称") { row in
                        Text(row.suggestedName)
                    }
                    TableColumn("状态") { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.status.tag)
                                .font(.caption.weight(.semibold))
                            if let detail = row.status.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(minHeight: 240)
            }
            .disabled(batchPreviewModel.rows.isEmpty)
        }
    }

    private var batchBoundarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("当前任务边界")
                .font(.headline)
            Text("已接入真实 predict_category 批量分类预览、加载态和 classify 错误映射。")
                .font(.callout)
            Text("批量导入执行、重复检测和冲突处理留给后续 S1-18 任务。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
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
            } else if case .multipleItems = request.kind {
                Button("Import") {}
                    .keyboardShortcut(.defaultAction)
                    .disabled(true)
                    .help(batchPreviewModel.importDisabledReason)
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

    private var batchPreviewStatusStyle: Color {
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
        guard let firstURL = request.urls.first else {
            return "No valid file URL"
        }

        if request.urls.count == 1 {
            return firstURL.path
        }

        return "\(firstURL.path) and \(request.urls.count - 1) more"
    }
}
