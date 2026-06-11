import SwiftUI

@MainActor
struct ImportFolderConflictSection: View {
    let model: ImportFolderPreviewModel
    @Binding var isExpanded: Bool
    @Binding var pendingReplaceConfirmation: ImportFolderReplaceConfirmation?
    let onRetryScan: () -> Void
    let onSwitchToLocalRepo: () -> Void
    let onShowExistingFile: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if model.iCloudPlaceholderCount > 0 {
                iCloudActions
            }
            if isExpanded || !model.rows.filter(\.isConflictReviewRow).isEmpty {
                conflictsTable
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review folder conflicts")
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
            Button("Download & retry scan") {
                Task {
                    let didRetry = await model.downloadICloudPlaceholdersAndRetry()
                    if didRetry {
                        onRetryScan()
                    }
                }
            }
            .disabled(model.isICloudDownloading || model.rows.contains { $0.status.isImporting })
            Button("Switch to local repo...", action: onSwitchToLocalRepo)
                .disabled(model.rows.contains { $0.status.isImporting })
            if model.isICloudDownloading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var conflictsTable: some View {
        Table(model.rows.filter(\.isConflictReviewRow)) {
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
        "\(model.duplicateCount) duplicates · \(model.nameConflictCount) name conflicts · \(model.blockedCount) blocked"
    }

    @ViewBuilder
    private func incomingResolutionView(for row: ImportFolderPreviewRow) -> some View {
        switch row.status {
        case let .nameConflict(_, resolution):
            switch resolution {
            case let .renameIncoming(name):
                TextField("Incoming filename", text: Binding(
                    get: { name },
                    set: { model.renameIncomingFile(for: row.id, to: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(model.rows.contains { $0.status.isImporting })
            case .keepBoth, .replace:
                Text(row.resolvedIncomingName)
            }
        default:
            Text(row.resolvedIncomingName)
        }
    }

    @ViewBuilder
    private func strategyView(for row: ImportFolderPreviewRow) -> some View {
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

    private func duplicateStrategyPicker(for row: ImportFolderPreviewRow) -> some View {
        Picker("Strategy", selection: Binding(
            get: { row.duplicateResolution ?? .skip },
            set: { model.updateDuplicateStrategy(for: row.id, strategy: $0) }
        )) {
            ForEach(duplicateStrategies, id: \.self) { strategy in
                Text(strategy.title).tag(strategy)
            }
            if model.replaceOptionVisibility == .disabled {
                Text("Replace requires system Trash").tag(ImportBatchDuplicateResolutionStrategy.replace)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 150)
        .disabled(model.rows.contains { $0.status.isImporting })
    }

    private func nameConflictStrategyPicker(for row: ImportFolderPreviewRow) -> some View {
        Picker("Strategy", selection: Binding(
            get: { row.nameConflictResolution ?? .keepBoth },
            set: { model.updateNameConflictResolution(for: row.id, resolution: $0) }
        )) {
            Text("Keep both (auto-number)").tag(ImportBatchNameConflictResolution.keepBoth)
            Text("Rename incoming").tag(ImportBatchNameConflictResolution.renameIncoming(row.resolvedIncomingName))
            if showsReplaceOption {
                Text("Replace").tag(ImportBatchNameConflictResolution.replace(isConfirmed: false))
            } else if model.replaceOptionVisibility == .disabled {
                Text("Replace requires system Trash").tag(ImportBatchNameConflictResolution.replace(isConfirmed: false))
            }
        }
        .labelsHidden()
        .frame(maxWidth: 180)
        .disabled(model.rows.contains { $0.status.isImporting })
    }

    @ViewBuilder
    private func actionView(for row: ImportFolderPreviewRow) -> some View {
        switch row.status {
        case let .duplicate(existingPath, strategy, isReplaceConfirmed):
            if strategy == .replace {
                replaceButton(row: row, isConfirmed: isReplaceConfirmed)
            } else {
                Button("Show existing file") {
                    onShowExistingFile(existingPath)
                }
                .disabled(model.rows.contains { $0.status.isImporting })
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
            Button("Import ready only") {
                model.markICloudPlaceholderPending(rowID: row.id)
            }
            .disabled(model.rows.contains { $0.status.isImporting })
        case .blocked:
            Text("Resolve required")
        case .loading, .ready, .importing, .skippedDuplicate, .skippedICloud, .imported, .error:
            Text("-")
        }
    }

    private func replaceButton(row: ImportFolderPreviewRow, isConfirmed: Bool) -> some View {
        Button(isConfirmed ? "Replace confirmed" : "Confirm Replace...") {
            guard let context = model.beginReplaceConfirmation(for: row.id) else { return }
            pendingReplaceConfirmation = ImportFolderReplaceConfirmation(rowID: row.id, context: context)
        }
        .disabled(isConfirmed || model.rows.contains { $0.status.isImporting })
    }

    private var duplicateStrategies: [ImportBatchDuplicateResolutionStrategy] {
        showsReplaceOption ? ImportBatchDuplicateResolutionStrategy.allCases : [.skip, .keepBoth]
    }

    private var showsReplaceOption: Bool {
        model.replaceOptionVisibility == .enabled
    }
}

struct ImportFolderReplaceConfirmation: Identifiable, Equatable {
    var rowID: ImportFolderPreviewRow.ID
    var context: SingleFileReplaceConfirmationContext

    var id: String {
        "\(rowID)|\(context.id)"
    }
}
