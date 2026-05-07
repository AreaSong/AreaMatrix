import SwiftUI

struct ImportSingleFileStorageModeSection: View {
    @Binding var selectedMode: ImportSingleFileStorageMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("存储模式", selection: $selectedMode) {
                ForEach(ImportSingleFileStorageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            Text(selectedMode.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct ImportSingleFilePreflightStatusSection: View {
    let status: ImportSingleFilePreflightStatus
    let message: String?
    let isICloudDownloading: Bool

    var body: some View {
        HStack(spacing: 8) {
            if status.isChecking || isICloudDownloading {
                ProgressView()
                    .controlSize(.small)
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(statusStyle)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusStyle: Color {
        switch status {
        case .blocked:
            return .orange
        case .idle, .checking, .ready:
            return .secondary
        }
    }
}

struct ImportSingleFileICloudActionsSection: View {
    let isDownloading: Bool
    let onDownloadAndRetry: () -> Void
    let onSwitchToLocalRepo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Download & retry", action: onDownloadAndRetry)
                .disabled(isDownloading)

            Button("Switch to local repo...", action: onSwitchToLocalRepo)
        }
    }
}

struct ImportSingleFileRetryPreviewSection: View {
    let onRetryPreview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Retry preview", action: onRetryPreview)
        }
    }
}

struct ImportSingleFileImportStatusSection: View {
    let status: ImportSingleFileImportStatus
    let disabledReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if status.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(status.message ?? "正在导入...")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if let message = status.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(statusStyle)
            }

            if let disabledReason {
                Text(disabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusStyle: Color {
        switch status {
        case .failed, .blocked:
            return .red
        case .imported, .skippedDuplicate:
            return .green
        case .idle, .importing:
            return .secondary
        }
    }
}

struct ImportSingleFileConflictSection: View {
    let result: ImportSingleFilePreflightResult
    let activePage: ImportSingleFileConflictPage?
    let sourceFilename: String?
    let sourcePath: String?
    let replaceOptionVisibility: ImportSingleFileReplaceOptionVisibility
    @Binding var duplicateResolution: ImportSingleFileDuplicateResolutionStrategy
    @Binding var nameConflictResolution: ImportSingleFileNameConflictResolution
    let resolvedNameConflictFilename: String
    let resolvedNameConflictPath: String
    let nameConflictBlockingReason: String?
    let existingFile: FileEntrySnapshot?
    let onBeginReplaceConfirmation: () -> Void
    let onShowExistingFile: (String) -> Void
    let onRenameNameConflictFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let activePage {
                Text(activePage.routeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(activePage.title)
                    .font(.headline)
                Text(activePage.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                conflictDetails
            } else {
                Text("冲突状态")
                    .font(.headline)
            }

            Text(result.statusMessage)
                .font(.callout)
                .foregroundStyle(statusColor)

            if case .duplicate = result.conflict {
                duplicateResolutionOptions
            }
            if case .name = result.conflict {
                nameConflictResolutionOptions
            }

        }
        .accessibilityElement(children: .combine)
    }

    private var duplicateResolutionOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("重复处理策略", selection: $duplicateResolution) {
                ForEach(duplicateStrategies) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            .pickerStyle(.radioGroup)

            Text(duplicateResolution.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if duplicateResolution == .keepBoth {
                if let keepBothPath = result.keepBothTargetRelativePath {
                    Text("新文件名：\(keepBothPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("无法生成可用文件名")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if duplicateResolution == .replace {
                replaceAction
            }

            if case .duplicate(let existingPath) = result.conflict {
                Button("Show existing file") {
                    onShowExistingFile(existingPath)
                }
                .help(existingPath)
            }
        }
    }

    private var nameConflictResolutionOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("处理选项", selection: $nameConflictResolution) {
                Text(ImportSingleFileNameConflictResolution.keepBoth.title)
                    .tag(ImportSingleFileNameConflictResolution.keepBoth)
                Text(ImportSingleFileNameConflictResolution.renameIncoming(resolvedNameConflictFilename).title)
                    .tag(ImportSingleFileNameConflictResolution.renameIncoming(resolvedNameConflictFilename))
                if replaceOptionVisibility == .enabled {
                    Text(ImportSingleFileNameConflictResolution.replace.title)
                        .tag(ImportSingleFileNameConflictResolution.replace)
                } else if replaceOptionVisibility == .disabled {
                    Text("Replace requires system Trash")
                        .tag(ImportSingleFileNameConflictResolution.replace)
                }
            }
            .pickerStyle(.radioGroup)

            Text(nameConflictResolution.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            nameConflictResolutionDetails

            if case .name(let existingPath) = result.conflict {
                Button("Show existing file") {
                    onShowExistingFile(existingPath)
                }
                .help(existingPath)
            }
        }
    }

    @ViewBuilder
    private var nameConflictResolutionDetails: some View {
        switch nameConflictResolution {
        case .keepBoth:
            if result.keepBothTargetRelativePath != nil {
                Text("最终文件名：\(resolvedNameConflictFilename)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("无法生成可用文件名")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case .renameIncoming(let name):
            TextField("新文件名", text: Binding(
                get: { name },
                set: onRenameNameConflictFile
            ))
            .textFieldStyle(.roundedBorder)
            if let nameConflictBlockingReason {
                Text(nameConflictBlockingReason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("最终路径：\(resolvedNameConflictPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .replace:
            nameReplaceAction
        }
    }

    private var duplicateStrategies: [ImportSingleFileDuplicateResolutionStrategy] {
        switch replaceOptionVisibility {
        case .hidden:
            return [.skip, .keepBoth]
        case .enabled, .disabled:
            return [.skip, .keepBoth, .replace]
        }
    }

    @ViewBuilder
    private var replaceAction: some View {
        switch replaceOptionVisibility {
        case .hidden:
            EmptyView()
        case .enabled:
            VStack(alignment: .leading, spacing: 6) {
                Text("替换操作需要二次确认。旧文件不会直接删除，会移到废纸篓。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Confirm Replace...", action: onBeginReplaceConfirmation)
                    .help("Replace 每次必须先二次确认")
            }
        case .disabled:
            Text("Replace requires system Trash")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var nameReplaceAction: some View {
        switch replaceOptionVisibility {
        case .hidden:
            EmptyView()
        case .enabled:
            VStack(alignment: .leading, spacing: 6) {
                Text("替换操作需要二次确认。旧文件不会直接删除，会移到废纸篓。")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Confirm Replace...", action: onBeginReplaceConfirmation)
                    .help("Replace 每次必须先二次确认")
            }
        case .disabled:
            Text("Replace requires system Trash")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var conflictDetails: some View {
        switch result.conflict {
        case .duplicate(let existingPath):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("已有文件", value: existingPath)
                if let sourceFilename {
                    LabeledContent("当前文件", value: sourceFilename)
                }
                if let sourcePath {
                    LabeledContent("来源", value: sourcePath)
                }
            }
            .font(.caption)
        case .name(let path):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("已存在", value: path)
                if let size = existingFile?.sizeBytes {
                    LabeledContent("已有文件大小", value: ByteCountFormatter.string(
                        fromByteCount: size,
                        countStyle: .file
                    ))
                }
                if let updatedAt = existingFile?.updatedAt {
                    LabeledContent("已有文件修改时间", value: DateFormatter.localizedString(
                        from: Date(timeIntervalSince1970: TimeInterval(updatedAt)),
                        dateStyle: .medium,
                        timeStyle: .short
                    ))
                }
                if let sourceFilename {
                    LabeledContent("当前文件", value: sourceFilename)
                }
                if let sourcePath {
                    LabeledContent("来源", value: sourcePath)
                }
                if let sourceSize = result.sourceSizeBytes {
                    LabeledContent("当前文件大小", value: ByteCountFormatter.string(
                        fromByteCount: sourceSize,
                        countStyle: .file
                    ))
                }
                LabeledContent("hash 结论", value: "同名但内容不同")
            }
            .font(.caption)
        case .none, .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            EmptyView()
        }
    }

    private var statusColor: Color {
        switch result.conflict {
        case .none:
            return .secondary
        case .invalidFilename, .name, .duplicate, .iCloudPlaceholder, .iCloudDownloadFailed,
             .corePreviewUnavailable, .sourceUnavailable, .error:
            return .orange
        }
    }
}

struct ImportSingleFileReplaceConfirmation: Identifiable, Equatable {
    var context: ImportSingleFileReplaceConfirmationContext

    var id: String {
        context.id
    }
}

struct ReplaceConfirmSheet: View {
    let context: ImportSingleFileReplaceConfirmationContext
    let onCancel: () -> Void
    let onConfirm: (ImportSingleFileReplaceConfirmationDecision) -> Void

    @State private var understandsReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认替换？")
                .font(.title2.weight(.semibold))
            Text("你将用新文件替换资料库中的已有文件。")
                .font(.callout)

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("将被替换", value: context.existingPath)
                LabeledContent("替换为", value: context.incomingPath)
                if let incomingSizeBytes = context.incomingSizeBytes {
                    LabeledContent("新文件大小", value: ByteCountFormatter.string(
                        fromByteCount: incomingSizeBytes,
                        countStyle: .file
                    ))
                }
                LabeledContent("目标位置", value: context.targetRelativePath)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("旧文件将移到系统废纸篓。")
                Text("新文件将写入原目标位置。")
                Text("这次操作会记录到改动日志。")
                Text("如果导入失败，AreaMatrix 会保持原文件不变或恢复到安全状态。")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Toggle("我理解这是替换操作", isOn: $understandsReplace)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Replace", role: .destructive) {
                    onConfirm(context.decision(understandsReplace: understandsReplace))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!understandsReplace || !context.isTrashAvailable)
            }
        }
        .padding(24)
        .frame(minWidth: 460)
    }
}
