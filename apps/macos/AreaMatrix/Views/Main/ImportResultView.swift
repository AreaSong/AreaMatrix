import SwiftUI

struct ImportResultView: View {
    let state: ImportResultRouteState
    let onDone: () -> Void
    let onRetryFailed: () -> Void
    let onLoadChangeLog: () -> Void
    let onShowExistingFile: (ImportResultRouteState.Item.ID) -> Void
    let onRequestExport: () -> Void
    let onConfirmExport: () -> Void
    let onCancelExport: () -> Void

    @State private var filter: ImportResultRouteState.Item.Status?
    @State private var selectedItemID: ImportResultRouteState.Item.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入结果")
                .font(.title2.weight(.semibold))
            Text(state.summaryText)
                .font(.headline)
                .accessibilityLabel(state.summaryText)

            Picker("Filter", selection: $filter) {
                Text("All").tag(ImportResultRouteState.Item.Status?.none)
                Text("Imported").tag(ImportResultRouteState.Item.Status?.some(.imported))
                Text("Skipped").tag(ImportResultRouteState.Item.Status?.some(.skipped))
                Text("Failed").tag(ImportResultRouteState.Item.Status?.some(.failed))
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Table(filteredItems, selection: $selectedItemID) {
                TableColumn("文件名") { item in
                    Text(displayName(for: item.targetPath))
                }
                TableColumn("目标分类") { item in
                    Text(displayCategory(for: item.targetPath))
                }
                TableColumn("状态") { item in
                    Text(item.status.rawValue)
                }
                TableColumn("原因") { item in
                    Text(item.reason)
                }
                TableColumn("动作") { item in
                    if item.canShowExistingFile {
                        Button("Show existing file") {
                            onShowExistingFile(item.id)
                        }
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 220)
            .accessibilityLabel(state.summaryText)

            if let selectedItem {
                ImportErrorDetailView(item: selectedItem)
            }
            changeLogSection

            HStack {
                Text("当前：\(state.currentPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                if state.isRetryingFailedItems {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Export Details...", action: onRequestExport)
                Button(state.retryButtonTitle, action: onRetryFailed)
                    .disabled(!state.canRetryFailedItems)
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            exportStatus
        }
        .padding(24)
        .confirmationDialog(
            "Export import result details?",
            isPresented: exportConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Export Details...", action: onConfirmExport)
            Button("Cancel", role: .cancel, action: onCancelExport)
        } message: {
            Text("The export contains result rows, error codes, and redacted paths. It does not include user file contents or upload data.")
        }
        .task(id: state.sourceOpening.config.repoPath) {
            onLoadChangeLog()
        }
    }

    private var filteredItems: [ImportResultRouteState.Item] {
        guard let filter else { return state.items }
        return state.items.filter { $0.status == filter }
    }

    private var selectedItem: ImportResultRouteState.Item? {
        if let selectedItemID,
           let item = state.items.first(where: { $0.id == selectedItemID }) {
            return item
        }
        return state.items.first(where: { $0.status == .failed })
    }

    private var exportConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirmingPrivacy = state.exportState { return true }
                return false
            },
            set: { isPresented in
                if !isPresented {
                    onCancelExport()
                }
            }
        )
    }

    @ViewBuilder
    private var exportStatus: some View {
        switch state.exportState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .exported(let path):
            Text("Exported details to \(path)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func displayName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? path : name
    }

    private func displayCategory(for path: String) -> String {
        let category = (path as NSString).deletingLastPathComponent
        return category.isEmpty ? "repo root" : category
    }

    @ViewBuilder
    private var changeLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Core change log")
                    .font(.headline)
                Spacer()
                Button("Refresh", action: onLoadChangeLog)
                    .disabled(changeLogIsLoading)
            }
            changeLogContent
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var changeLogContent: some View {
        switch state.changeLog {
        case .notLoaded, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading import log from Core...")
                    .foregroundStyle(.secondary)
            }
        case .loaded(let entries):
            if entries.isEmpty {
                Text("No imported change_log rows returned for this repository.")
                    .foregroundStyle(.secondary)
            } else {
                Table(entries) {
                    TableColumn("时间") { entry in
                        Text(entry.occurredAtDisplay)
                    }
                    TableColumn("文件") { entry in
                        Text(entry.filename)
                    }
                    TableColumn("分类") { entry in
                        Text(entry.category.isEmpty ? "repo root" : entry.category)
                    }
                    TableColumn("动作") { entry in
                        Text(entry.actionDisplayName)
                    }
                    TableColumn("详情") { entry in
                        Text(entry.detailSummary)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: 150, idealHeight: 180)
            }
        case .failed(let mapping):
            VStack(alignment: .leading, spacing: 4) {
                Label(mapping.userMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(mapping.suggestedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var changeLogIsLoading: Bool {
        if case .loading = state.changeLog { return true }
        return false
    }
}

private struct ImportErrorDetailView: View {
    let item: ImportResultRouteState.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Result details", systemImage: item.status.detailSystemImage)
                .font(.headline)
            detailRow("Status", item.status.rawValue)
            detailRow("Source", item.sanitizedSourcePath)
            detailRow("Target", item.sanitizedTargetPath)
            detailRow("Reason", item.reason)
            if let existingRelativePath = item.existingRelativePath {
                detailRow("Existing file", ImportResultRouteState.sanitizedPathDisplay(existingRelativePath))
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

private extension ImportResultRouteState.Item.Status {
    var detailSystemImage: String {
        switch self {
        case .imported:
            return "checkmark.circle"
        case .skipped, .pending:
            return "clock"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
}
