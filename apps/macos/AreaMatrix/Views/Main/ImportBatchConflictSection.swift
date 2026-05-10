import SwiftUI

struct ImportBatchConflictSection: View {
    let batchImportModel: ImportBatchCopyImportModel
    @Binding var isExpanded: Bool
    @Binding var pendingReplaceConfirmation: ImportBatchReplaceConfirmation?
    let onRetryPreview: () -> Void
    let onSwitchToLocalRepo: () -> Void
    let onShowExistingFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if batchImportModel.iCloudPlaceholderCount > 0 {
                iCloudActions
            }
            if isExpanded
                || batchImportModel.duplicateCount > 0
                || batchImportModel.nameConflictCount > 0
                || batchImportModel.iCloudPlaceholderCount > 0
                || batchImportModel.blockedCount > 0 {
                conflictsTable
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review conflicts")
                    .font(.headline)
                Text(conflictSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isExpanded ? "Hide" : "Review conflicts") {
                isExpanded.toggle()
            }
        }
    }

    private var iCloudActions: some View {
        HStack(spacing: 10) {
            Button("Download all & retry preview") {
                Task {
                    let didDownload = await batchImportModel.downloadAllICloudPlaceholdersAndRetry()
                    if didDownload {
                        onRetryPreview()
                    }
                }
            }
            .disabled(batchImportModel.isICloudDownloading || batchImportModel.status.isImporting)
            Button("Switch to local repo...", action: onSwitchToLocalRepo)
                .disabled(batchImportModel.status.isImporting)
            if batchImportModel.isICloudDownloading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var conflictsTable: some View {
        Table(batchImportModel.rows.filter(\.isConflictReviewRow)) {
            TableColumn("File") { row in
                Text(row.originalName)
            }
            TableColumn("Conflict") { row in
                Text(row.conflictLabel)
            }
            TableColumn("Existing item") { row in
                Text(row.existingConflictPath ?? "-")
            }
            TableColumn("Incoming resolution") { row in
                incomingResolutionView(for: row)
            }
            TableColumn("Strategy") { row in
                strategyView(for: row)
            }
            TableColumn("Status") { row in
                Text(row.status.detail ?? row.status.tag)
            }
            TableColumn("Action") { row in
                actionView(for: row)
            }
        }
        .frame(minHeight: 120)
    }

    private var conflictSummary: String {
        [
            "\(batchImportModel.duplicateCount) duplicates",
            "\(batchImportModel.nameConflictCount) name conflict",
            "\(batchImportModel.iCloudPlaceholderCount) iCloud",
            "\(batchImportModel.blockedCount) blocked"
        ].joined(separator: " · ")
    }

    @ViewBuilder
    private func incomingResolutionView(for row: ImportBatchCopyImportRow) -> some View {
        switch row.status {
        case let .nameConflict(_, resolution):
            switch resolution {
            case let .renameIncoming(name):
                TextField("Incoming filename", text: Binding(
                    get: { name },
                    set: { batchImportModel.renameIncomingFile(for: row.id, to: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(batchImportModel.status.isImporting)
            case .keepBoth, .replace:
                Text(row.resolvedIncomingName)
            }
        default:
            Text(row.resolvedIncomingName)
        }
    }

    @ViewBuilder
    private func strategyView(for row: ImportBatchCopyImportRow) -> some View {
        switch row.status {
        case .duplicate:
            duplicateStrategyPicker(for: row)
        case .nameConflict:
            nameConflictStrategyPicker(for: row)
        case .iCloudPlaceholder, .skippedICloud:
            Text("Download required")
        case .blocked:
            Text("Resolve required")
        case .loading, .ready, .importing, .skippedDuplicate, .imported, .error:
            Text("-")
        }
    }

    private func duplicateStrategyPicker(for row: ImportBatchCopyImportRow) -> some View {
        Picker("Strategy", selection: Binding(
            get: { row.duplicateResolution ?? .skip },
            set: { batchImportModel.updateDuplicateStrategy(for: row.id, strategy: $0) }
        )) {
            ForEach(duplicateStrategies, id: \.self) { strategy in
                Text(strategy.title).tag(strategy)
            }
            if batchImportModel.replaceOptionVisibility == .disabled {
                Text("Replace requires system Trash").tag(ImportBatchDuplicateResolutionStrategy.replace)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 150)
        .disabled(batchImportModel.status.isImporting)
    }

    private func nameConflictStrategyPicker(for row: ImportBatchCopyImportRow) -> some View {
        Picker("Strategy", selection: Binding(
            get: { row.nameConflictResolution ?? .keepBoth },
            set: { batchImportModel.updateNameConflictResolution(for: row.id, resolution: $0) }
        )) {
            Text("Keep both (auto-number)").tag(ImportBatchNameConflictResolution.keepBoth)
            Text("Rename incoming").tag(ImportBatchNameConflictResolution.renameIncoming(row.resolvedIncomingName))
            if showsReplaceOption {
                Text("Replace").tag(ImportBatchNameConflictResolution.replace(isConfirmed: false))
            } else if batchImportModel.replaceOptionVisibility == .disabled {
                Text("Replace requires system Trash").tag(ImportBatchNameConflictResolution.replace(isConfirmed: false))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
        .disabled(batchImportModel.status.isImporting)
    }

    @ViewBuilder
    private func actionView(for row: ImportBatchCopyImportRow) -> some View {
        switch row.status {
        case let .duplicate(existingPath, strategy, isReplaceConfirmed):
            if strategy == .replace {
                replaceButton(row: row, isConfirmed: isReplaceConfirmed)
            } else {
                Button("Show existing file") {
                    onShowExistingFile(existingPath)
                }
                .disabled(batchImportModel.status.isImporting)
                .help(existingPath)
            }
        case let .nameConflict(_, resolution):
            switch resolution {
            case let .replace(isConfirmed):
                replaceButton(row: row, isConfirmed: isConfirmed)
            case .renameIncoming:
                Text("Rename incoming...")
            case .keepBoth:
                Text("Auto-number incoming")
            }
        case .iCloudPlaceholder:
            HStack(spacing: 6) {
                Button("Download & retry") {
                    Task {
                        let didDownload = await batchImportModel.downloadICloudPlaceholderAndRetry(rowID: row.id)
                        if didDownload {
                            onRetryPreview()
                        }
                    }
                }
                .disabled(batchImportModel.isICloudDownloading || batchImportModel.status.isImporting)
                Button("Import ready only") {
                    batchImportModel.markICloudPlaceholderPending(rowID: row.id)
                }
                .disabled(batchImportModel.status.isImporting)
            }
        case .blocked:
            Text("Resolve required")
        case .loading, .ready, .importing, .skippedDuplicate, .skippedICloud, .imported, .error:
            Text("-")
        }
    }

    private func replaceButton(row: ImportBatchCopyImportRow, isConfirmed: Bool) -> some View {
        Button(isConfirmed ? "Replace confirmed" : "Confirm Replace...") {
            guard let context = batchImportModel.beginReplaceConfirmation(for: row.id) else { return }
            pendingReplaceConfirmation = ImportBatchReplaceConfirmation(rowID: row.id, context: context)
        }
        .disabled(isConfirmed || batchImportModel.status.isImporting)
    }

    private var duplicateStrategies: [ImportBatchDuplicateResolutionStrategy] {
        showsReplaceOption ? ImportBatchDuplicateResolutionStrategy.allCases : [.skip, .keepBoth]
    }

    private var showsReplaceOption: Bool {
        batchImportModel.replaceOptionVisibility == .enabled
    }
}

struct ImportBatchReplaceConfirmation: Identifiable, Equatable {
    var rowID: ImportBatchCopyImportRow.ID
    var context: SingleFileReplaceConfirmationContext

    var id: String {
        "\(rowID)|\(context.id)"
    }
}
