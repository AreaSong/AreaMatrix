import SwiftUI

extension ImportBatchConflictSection {
    @ViewBuilder
    func incomingResolutionView(for row: ImportBatchCopyImportRow) -> some View {
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
    func strategyView(for row: ImportBatchCopyImportRow) -> some View {
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

    func duplicateStrategyPicker(for row: ImportBatchCopyImportRow) -> some View {
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

    func conflictBatchStrategyPicker(
        _ title: String,
        strategies: [ImportConflictBatchStrategySnapshot],
        selection: Binding<ImportConflictBatchStrategySnapshot>
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(strategies, id: \.self) { strategy in
                Text(strategy.title).tag(strategy)
            }
        }
        .frame(maxWidth: 240)
        .disabled(batchImportModel.status.isImporting || batchImportModel.isConflictBatchApplying)
    }

    func nameConflictStrategyPicker(for row: ImportBatchCopyImportRow) -> some View {
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
    func actionView(for row: ImportBatchCopyImportRow) -> some View {
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
            iCloudActionButtons(for: row)
        case .blocked:
            Text("Resolve required")
        case .loading, .ready, .importing, .skippedDuplicate, .skippedICloud, .imported, .error:
            Text("-")
        }
    }

    func iCloudActionButtons(for row: ImportBatchCopyImportRow) -> some View {
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
    }

    func replaceButton(row: ImportBatchCopyImportRow, isConfirmed: Bool) -> some View {
        Button(isConfirmed ? "Replace confirmed" : "Confirm Replace...") {
            guard let context = batchImportModel.beginReplaceConfirmation(for: row.id) else { return }
            pendingReplaceConfirmation = ImportBatchReplaceConfirmation(rowID: row.id, context: context)
        }
        .disabled(isConfirmed || batchImportModel.status.isImporting)
    }

    var duplicateStrategies: [ImportBatchDuplicateResolutionStrategy] {
        showsReplaceOption ? ImportBatchDuplicateResolutionStrategy.allCases : [.skip, .keepBoth]
    }

    var showsReplaceOption: Bool {
        batchImportModel.replaceOptionVisibility == .enabled
    }
}
