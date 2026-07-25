import SwiftUI

extension ImportEntrySheetView {
    var singleFilePreview: some View {
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
                    nameConflictResolution: Binding(
                        get: { previewModel.nameConflictResolution },
                        set: { previewModel.updateNameConflictResolution($0) }
                    ),
                    resolvedNameConflictFilename: previewModel.resolvedNameConflictFilename,
                    resolvedNameConflictPath: previewModel.resolvedConflictImportPath,
                    nameConflictBlockingReason: previewModel.nameConflictResolutionBlockingReason,
                    existingFile: result.existingFile,
                    duplicateReplaceActionTitle: previewModel.duplicateReplaceConfirmationActionTitle,
                    isReplaceConfirmed: previewModel.isReplaceConfirmed,
                    onBeginReplaceConfirmation: {
                        previewModel.beginReplaceConfirmation()
                        if let context = previewModel.pendingReplaceConfirmation {
                            pendingSingleFileReplaceConfirmation = ImportSingleFileReplaceConfirmation(context: context)
                        }
                    },
                    onShowExistingFile: onShowExistingFile,
                    onRenameNameConflictFile: previewModel.renameIncomingNameConflictFile
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
                    Text(L10n.format("import.single.source-size", sourceSizeDescription))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text(
                    L10n.format(
                        "import.single.source-path",
                        previewModel.source?.sourcePath ?? request.destinationLabel
                    )
                )
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
                Picker(L10n.string("建议分类"), selection: $previewModel.selectedCategory) {
                    ForEach(categoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .frame(maxWidth: 240)

                reasonButton
            }

            TextField(L10n.string("建议命名"), text: $previewModel.suggestedName)
                .textFieldStyle(.roundedBorder)
            if let filenameValidationMessage = previewModel.filenameValidationMessage {
                Text(filenameValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var reasonButton: some View {
        Button(L10n.string("为什么？")) {
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

    private var primaryFileLabel: String {
        ImportEntrySheetHelper.primaryFileLabel(urls: request.urls)
    }
}
