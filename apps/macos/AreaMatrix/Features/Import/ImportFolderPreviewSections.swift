import SwiftUI

@MainActor
struct ImportFolderPreviewView: View {
    @ObservedObject var model: ImportFolderPreviewModel
    let request: ImportEntryRequest
    @Binding var showsConflictReview: Bool
    @Binding var pendingReplaceConfirmation: ImportFolderReplaceConfirmation?
    let onSwitchToLocalRepo: () -> Void
    let onShowExistingFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ImportFolderSummarySection(
                folderPath: model.folderPathLabel,
                fileCount: model.rows.count,
                totalSizeDescription: model.totalSizeDescription,
                folderCount: model.folderCount,
                iCloudPlaceholderCount: model.iCloudPlaceholderCount
            )
            ImportFolderExclusionSection(skippedRules: model.skippedRules)
            ImportFolderAdvancedOptionsSection(
                includeHiddenFiles: includeHiddenFilesBinding,
                followSymlinks: followSymlinksBinding,
                isDisabled: model.status.isScanning
            )
            ImportFolderDestinationSection(
                selectedDestination: $model.selectedDestination,
                destinationOptions: model.destinationOptions,
                isDisabled: model.status.isScanning || model.rows.contains { $0.status.isImporting }
            )
            ImportFolderStorageModeSection(
                selectedStorageMode: $model.selectedStorageMode,
                riskMessage: model.storageModeRiskMessage,
                isDisabled: model.status.isScanning || model.rows.contains { $0.status.isImporting }
            )
            ImportFolderPreviewStatusSection(status: model.status)
            ImportFolderICloudSummarySection(
                iCloudPlaceholderCount: model.iCloudPlaceholderCount,
                isDownloading: model.isICloudDownloading,
                downloadErrorMessage: model.iCloudDownloadErrorMessage,
                onDownloadAndRetry: {
                    Task { _ = await model.downloadICloudPlaceholdersAndRetry() }
                },
                onSwitchToLocalRepo: onSwitchToLocalRepo
            )
            ImportFolderErrorSummary(errors: model.scanErrors)
            ImportFolderRowsSection(rows: model.rows)
            if model.duplicateCount > 0
                || model.nameConflictCount > 0
                || model.iCloudPlaceholderCount > 0
                || model.blockedCount > 0
                || showsConflictReview {
                ImportFolderConflictSection(
                    model: model,
                    isExpanded: $showsConflictReview,
                    pendingReplaceConfirmation: $pendingReplaceConfirmation,
                    onRetryScan: {
                        Task { await model.retryScan() }
                    },
                    onSwitchToLocalRepo: onSwitchToLocalRepo,
                    onShowExistingFile: onShowExistingFile
                )
            }
            Text(L10n.format("import.folder.destination", model.selectedDestination.title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var includeHiddenFilesBinding: Binding<Bool> {
        Binding(
            get: { model.includeHiddenFiles },
            set: { model.updateIncludeHiddenFiles($0) }
        )
    }

    private var followSymlinksBinding: Binding<Bool> {
        Binding(
            get: { model.followSymlinks },
            set: { model.updateFollowSymlinks($0) }
        )
    }
}

struct ImportFolderDestinationSection: View {
    @Binding var selectedDestination: ImportBatchDestinationOption
    let destinationOptions: [ImportBatchDestinationOption]
    let isDisabled: Bool

    var body: some View {
        Picker(L10n.string("导入到"), selection: $selectedDestination) {
            ForEach(destinationOptions, id: \.self) { destination in
                Text(destination.title).tag(destination)
            }
        }
        .frame(maxWidth: 320)
        .disabled(isDisabled)
    }
}

struct ImportFolderSummarySection: View {
    let folderPath: String
    let fileCount: Int
    let totalSizeDescription: String?
    let folderCount: Int
    let iCloudPlaceholderCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("文件夹信息"))
                .font(.headline)
            LabeledContent(L10n.string("文件夹"), value: folderPath)
            HStack(spacing: 16) {
                LabeledContent(L10n.string("已发现"), value: L10n.plural("import.folder.file-count", count: fileCount))
                LabeledContent(L10n.string("总大小"), value: totalSizeDescription ?? L10n.string("import.folder.calculating"))
                LabeledContent(L10n.string("子文件夹"), value: L10n.plural("import.folder.subfolder-count", count: folderCount))
                LabeledContent(
                    L10n.string("iCloud"),
                    value: L10n.plural("import.folder.icloud-placeholder-count", count: iCloudPlaceholderCount)
                )
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

struct ImportFolderExclusionSection: View {
    let skippedRules: [ImportFolderSkippedRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("默认排除"))
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(defaultRules, id: \.self) { rule in
                    Text(ruleLabel(rule))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var defaultRules: [String] {
        [
            ".DS_Store", ".git/", ".areamatrix/", "node_modules/",
            L10n.string("import.folder.hiddenFiles"),
            L10n.string("import.folder.symbolicLinks")
        ]
    }

    private func ruleLabel(_ rule: String) -> String {
        guard let skipped = skippedRules.first(where: { $0.label == rule }) else {
            return rule
        }
        return L10n.format("import.folder.rule-skip-count", rule, Int64(skipped.count))
    }
}

struct ImportFolderAdvancedOptionsSection: View {
    @Binding var includeHiddenFiles: Bool
    @Binding var followSymlinks: Bool
    let isDisabled: Bool

    var body: some View {
        DisclosureGroup(L10n.string("高级选项")) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(L10n.string("包含隐藏文件"), isOn: $includeHiddenFiles)
                Toggle(L10n.string("跟随符号链接"), isOn: $followSymlinks)
                Text(L10n.string("选项变化后会重新预扫描；确认前不会复制、移动或写入文件。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
        .disabled(isDisabled)
    }
}

struct ImportFolderStorageModeSection: View {
    @Binding var selectedStorageMode: ImportSingleFileStorageMode
    let riskMessage: String?
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(L10n.string("存储模式"), selection: $selectedStorageMode) {
                ForEach(ImportSingleFileStorageMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .disabled(isDisabled)

            Text(selectedStorageMode.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let riskMessage {
                Text(riskMessage)
                    .font(.caption)
                    .foregroundStyle(selectedStorageMode == .move ? Color.orange : Color.secondary)
            }
        }
    }
}

struct ImportFolderPreviewStatusSection: View {
    let status: ImportFolderPreviewStatus

    var body: some View {
        HStack(spacing: 8) {
            if status.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            if let message = status.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        if case .failed = status {
            return .red
        }
        return .secondary
    }
}

struct ImportFolderErrorSummary: View {
    let errors: [ImportFolderScanError]

    var body: some View {
        if let firstError = errors.first {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("预扫描错误"))
                    .font(.headline)
                Text(L10n.format("import.folder.scan-error", firstError.path, firstError.message))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}

struct ImportFolderICloudSummarySection: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let iCloudPlaceholderCount: Int
    let isDownloading: Bool
    let downloadErrorMessage: LocalizedMessage?
    let onDownloadAndRetry: () -> Void
    let onSwitchToLocalRepo: () -> Void

    var body: some View {
        if iCloudPlaceholderCount > 0 || isDownloading || downloadErrorMessage != nil {
            VStack(alignment: .leading, spacing: 6) {
                if iCloudPlaceholderCount > 0 {
                    Text(L10n.plural("import.folder.files-still-in-icloud", count: iCloudPlaceholderCount))
                        .font(.headline)
                }
                if let downloadErrorMessage {
                    Text(localizer.resolve(downloadErrorMessage))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    Button(L10n.string("Download & retry scan"), action: onDownloadAndRetry)
                        .disabled(isDownloading)
                    Button(L10n.string("Switch to local repo..."), action: onSwitchToLocalRepo)
                        .disabled(isDownloading)
                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

struct ImportFolderRowsSection: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let rows: [ImportFolderPreviewRow]

    var body: some View {
        DisclosureGroup(L10n.string("View files...")) {
            Table(rows) {
                TableColumn(L10n.string("File")) { row in
                    Text(row.originalName)
                }
                TableColumn(L10n.string("Relative path")) { row in
                    Text(row.relativePath)
                }
                TableColumn(L10n.string("Suggested category")) { row in
                    Text(row.predictedCategory ?? L10n.string("未生成"))
                }
                TableColumn(L10n.string("Suggested name")) { row in
                    Text(row.suggestedName)
                }
                TableColumn(L10n.string("Status")) { row in
                    statusCell(for: row)
                }
            }
            .frame(minHeight: 240)
        }
        .disabled(rows.isEmpty)
    }

    private func statusCell(for row: ImportFolderPreviewRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localizer.resolve(row.status.tagMessage))
                .font(.caption.weight(.semibold))
            if let detail = row.status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
