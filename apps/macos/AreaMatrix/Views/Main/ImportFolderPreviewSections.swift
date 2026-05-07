import SwiftUI

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
            Text("导入目标：\(model.selectedDestination.title)")
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
        Picker("导入到", selection: $selectedDestination) {
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
            Text("文件夹信息")
                .font(.headline)
            LabeledContent("文件夹", value: folderPath)
            HStack(spacing: 16) {
                LabeledContent("已发现", value: "\(fileCount) 个文件")
                LabeledContent("总大小", value: totalSizeDescription ?? "计算中")
                LabeledContent("子文件夹", value: "\(folderCount) 个")
                LabeledContent("iCloud", value: "\(iCloudPlaceholderCount) 个")
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
            Text("默认排除")
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
        [".DS_Store", ".git/", ".areamatrix/", "node_modules/", "隐藏文件", "符号链接"]
    }

    private func ruleLabel(_ rule: String) -> String {
        guard let skipped = skippedRules.first(where: { $0.label == rule }) else {
            return rule
        }
        return "\(rule) · \(skipped.count)"
    }
}

struct ImportFolderAdvancedOptionsSection: View {
    @Binding var includeHiddenFiles: Bool
    @Binding var followSymlinks: Bool
    let isDisabled: Bool

    var body: some View {
        DisclosureGroup("高级选项") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("包含隐藏文件", isOn: $includeHiddenFiles)
                Toggle("跟随符号链接", isOn: $followSymlinks)
                Text("选项变化后会重新预扫描；确认前不会复制、移动或写入文件。")
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
            Picker("存储模式", selection: $selectedStorageMode) {
                ForEach(ImportSingleFileStorageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
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
                Text("预扫描错误")
                    .font(.headline)
                Text("\(firstError.path)：\(firstError.message)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}

struct ImportFolderICloudSummarySection: View {
    let iCloudPlaceholderCount: Int
    let isDownloading: Bool
    let downloadErrorMessage: String?
    let onDownloadAndRetry: () -> Void
    let onSwitchToLocalRepo: () -> Void

    var body: some View {
        if iCloudPlaceholderCount > 0 || isDownloading || downloadErrorMessage != nil {
            VStack(alignment: .leading, spacing: 6) {
                if iCloudPlaceholderCount > 0 {
                    Text("\(iCloudPlaceholderCount) files are still in iCloud")
                        .font(.headline)
                }
                if let downloadErrorMessage {
                    Text(downloadErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 10) {
                    Button("Download & retry scan", action: onDownloadAndRetry)
                        .disabled(isDownloading)
                    Button("Switch to local repo...", action: onSwitchToLocalRepo)
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
    let rows: [ImportFolderPreviewRow]

    var body: some View {
        DisclosureGroup("View files...") {
            Table(rows) {
                TableColumn("File") { row in
                    Text(row.originalName)
                }
                TableColumn("Relative path") { row in
                    Text(row.relativePath)
                }
                TableColumn("Suggested category") { row in
                    Text(row.predictedCategory ?? "未生成")
                }
                TableColumn("Suggested name") { row in
                    Text(row.suggestedName)
                }
                TableColumn("Status") { row in
                    statusCell(for: row)
                }
            }
            .frame(minHeight: 240)
        }
        .disabled(rows.isEmpty)
    }

    private func statusCell(for row: ImportFolderPreviewRow) -> some View {
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

struct ImportFolderFooterSection: View {
    let request: ImportEntryRequest
    let model: ImportFolderPreviewModel
    let importDisabledReason: String?
    let onCancel: () -> Void
    let onImportProgress: ImportBatchProgressHandler
    let onImportFailed: ImportBatchFailureHandler
    let onImportResults: ImportBatchProgressHandler
    let importProgressControlState: ImportProgressControlState
    let onImported: (String, FileEntrySnapshot) -> Void
    let onRetryScan: () -> Void

    var body: some View {
        HStack {
            if let importDisabledReason {
                Text(importDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry scan", action: onRetryScan)
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Import Folder") {
                Task { await importFolder() }
            }
                .keyboardShortcut(.defaultAction)
                .disabled(importDisabledReason != nil)
        }
    }

    @MainActor
    private func importFolder() async {
        importProgressControlState.reset()
        if let initialProgress = initialProgressSnapshot() {
            onImportProgress(initialProgress)
        }

        var lastProgress: ImportBatchProgressSnapshot?
        let outcome = await model.importReadyFiles(controlState: importProgressControlState) { progress in
            lastProgress = progress
            if progress.completed > 0 || progress.failed > 0 {
                onImportProgress(progress)
            }
        }

        guard let outcome else { return }
        if let retryContext = outcome.fatalRetryContext,
           let failure = model.lastFailureMapping,
           let progress = lastProgress {
            onImportFailed(progress, failure, retryContext, .checking)
            importProgressControlState.registerQueueContinuation(model)
            return
        }
        if outcome.didStopAfterCurrentFile {
            onImportResults(
                outcome.progressSnapshot(currentPath: model.currentImportPath ?? request.sheetTitle)
                    .withItems(model.progressItems())
            )
            return
        }
        if outcome.needsResultSummary {
            onImportResults(
                outcome.progressSnapshot(currentPath: model.currentImportPath ?? request.sheetTitle)
                    .withItems(model.progressItems())
            )
            return
        }
        guard outcome.failedCount == 0 else { return }
        guard let importedEntry = outcome.succeededEntries.last else {
            onCancel()
            return
        }

        onImported(request.repoPath, importedEntry)
    }

    private func initialProgressSnapshot() -> ImportBatchProgressSnapshot? {
        guard importDisabledReason == nil else { return nil }
        let total = model.importableRows.count
        guard total > 0 else { return nil }
        return ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: total,
            remaining: total,
            currentPath: model.currentImportPath ?? request.sheetTitle,
            items: model.progressItems()
        )
    }
}
