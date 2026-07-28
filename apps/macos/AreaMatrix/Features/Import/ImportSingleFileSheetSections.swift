import SwiftUI

struct ImportSingleFileStorageModeSection: View {
    @Binding var selectedMode: ImportSingleFileStorageMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(L10n.string("存储模式"), selection: $selectedMode) {
                ForEach(ImportSingleFileStorageMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
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
            .orange
        case .idle, .checking, .ready:
            .secondary
        }
    }
}

struct ImportSingleFileICloudActionsSection: View {
    let isDownloading: Bool
    let onDownloadAndRetry: () -> Void
    let onSwitchToLocalRepo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(L10n.string("Download & retry"), action: onDownloadAndRetry)
                .disabled(isDownloading)

            Button(L10n.string("Switch to local repo..."), action: onSwitchToLocalRepo)
        }
    }
}

struct ImportSingleFileRetryPreviewSection: View {
    let onRetryPreview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(L10n.string("Retry preview"), action: onRetryPreview)
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
                    Text(status.message ?? L10n.string("import.progress.importing"))
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
            .red
        case let .imported(entry) where entry.importCommitState.isDegraded:
            .orange
        case .imported, .skippedDuplicate:
            .green
        case .idle, .importing:
            .secondary
        }
    }
}

struct ImportSingleFileConflictSection: View {
    let result: ImportSingleFilePreflightResult
    let activePage: ImportSingleFileConflictPage?
    let sourceFilename: String?
    let sourcePath: String?
    let replaceOptionVisibility: ImportSingleFileReplaceOptionVisibility
    @Binding var duplicateResolution: SingleFileDuplicateResolutionStrategy
    @Binding var nameConflictResolution: ImportSingleFileNameConflictResolution
    let resolvedNameConflictFilename: String
    let resolvedNameConflictPath: String
    let nameConflictBlockingReason: String?
    let existingFile: FileEntrySnapshot?
    let duplicateReplaceActionTitle: String
    let isReplaceConfirmed: Bool
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
                Text(L10n.string("冲突状态"))
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
            Picker(L10n.string("重复处理策略"), selection: $duplicateResolution) {
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
                    Text(L10n.format("import.single.keep-both-name", keepBothPath))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.string("无法生成可用文件名"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if duplicateResolution == .replace {
                replaceAction
            }

            if case let .duplicate(existingPath) = result.conflict {
                Button(L10n.string("Show existing file")) {
                    onShowExistingFile(existingPath)
                }
                .help(existingPath)
            }
        }
    }

    private var nameConflictResolutionOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.string("处理选项"), selection: $nameConflictResolution) {
                Text(ImportSingleFileNameConflictResolution.keepBoth.title)
                    .tag(ImportSingleFileNameConflictResolution.keepBoth)
                Text(ImportSingleFileNameConflictResolution.renameIncoming(resolvedNameConflictFilename).title)
                    .tag(ImportSingleFileNameConflictResolution.renameIncoming(resolvedNameConflictFilename))
                if replaceOptionVisibility == .enabled {
                    Text(ImportSingleFileNameConflictResolution.replace.title)
                        .tag(ImportSingleFileNameConflictResolution.replace)
                } else if replaceOptionVisibility == .disabled {
                    Text(L10n.string("Replace requires system Trash"))
                        .tag(ImportSingleFileNameConflictResolution.replace)
                }
            }
            .pickerStyle(.radioGroup)

            Text(nameConflictResolution.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            nameConflictResolutionDetails

            if case let .name(existingPath) = result.conflict {
                Button(L10n.string("Show existing file")) {
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
                Text(L10n.format("import.single.resolved-filename", resolvedNameConflictFilename))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("无法生成可用文件名"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        case let .renameIncoming(name):
            TextField(L10n.string("新文件名"), text: Binding(
                get: { name },
                set: onRenameNameConflictFile
            ))
            .textFieldStyle(.roundedBorder)
            if let nameConflictBlockingReason {
                Text(nameConflictBlockingReason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text(L10n.format("import.single.resolved-path", resolvedNameConflictPath))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .replace:
            nameReplaceAction
        }
    }

    private var duplicateStrategies: [SingleFileDuplicateResolutionStrategy] {
        switch replaceOptionVisibility {
        case .hidden:
            [.skip, .keepBoth]
        case .enabled, .disabled:
            [.skip, .keepBoth, .replace]
        }
    }

    @ViewBuilder
    private var replaceAction: some View {
        switch replaceOptionVisibility {
        case .hidden:
            EmptyView()
        case .enabled:
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("替换操作需要二次确认。旧文件不会直接删除，会移到废纸篓。"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(duplicateReplaceActionTitle, action: onBeginReplaceConfirmation)
                    .disabled(isReplaceConfirmed)
                    .help(L10n.string("Replace 每次必须先二次确认"))
            }
        case .disabled:
            Text(L10n.string("Replace requires system Trash"))
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
                Text(L10n.string("替换操作需要二次确认。旧文件不会直接删除，会移到废纸篓。"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button(duplicateReplaceActionTitle, action: onBeginReplaceConfirmation)
                    .disabled(isReplaceConfirmed)
                    .help(L10n.string("Replace 每次必须先二次确认"))
            }
        case .disabled:
            Text(L10n.string("Replace requires system Trash"))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var conflictDetails: some View {
        switch result.conflict {
        case let .duplicate(existingPath):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(L10n.string("已有文件"), value: existingPath)
                if let sourceFilename {
                    LabeledContent(L10n.string("当前文件"), value: sourceFilename)
                }
                if let sourcePath {
                    LabeledContent(L10n.string("来源"), value: sourcePath)
                }
            }
            .font(.caption)
        case let .name(path):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(L10n.string("已存在"), value: path)
                if let size = existingFile?.sizeBytes {
                    LabeledContent(L10n.string("已有文件大小"), value: ByteCountFormatter.string(
                        fromByteCount: size,
                        countStyle: .file
                    ))
                }
                if let updatedAt = existingFile?.updatedAt {
                    LabeledContent(L10n.string("已有文件修改时间"), value: DateFormatter.localizedString(
                        from: Date(timeIntervalSince1970: TimeInterval(updatedAt)),
                        dateStyle: .medium,
                        timeStyle: .short
                    ))
                }
                if let sourceFilename {
                    LabeledContent(L10n.string("当前文件"), value: sourceFilename)
                }
                if let sourcePath {
                    LabeledContent(L10n.string("来源"), value: sourcePath)
                }
                if let sourceSize = result.sourceSizeBytes {
                    LabeledContent(L10n.string("当前文件大小"), value: ByteCountFormatter.string(
                        fromByteCount: sourceSize,
                        countStyle: .file
                    ))
                }
                LabeledContent(L10n.string("hash 结论"), value: L10n.string("import.conflict.sameNameDifferentContent"))
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
            .secondary
        case .invalidFilename, .name, .duplicate, .iCloudPlaceholder, .iCloudDownloadFailed,
             .corePreviewUnavailable, .sourceUnavailable, .error:
            .orange
        }
    }
}

struct ImportSingleFileReplaceConfirmation: Identifiable, Equatable {
    var context: SingleFileReplaceConfirmationContext

    var id: String {
        context.id
    }
}
