import SwiftUI

struct ImportResultView: View {
    let state: ImportResultRouteState
    let onDone: () -> Void
    let onRetryFailed: () -> Void
    let onLoadChangeLog: () -> Void

    @State private var filter: ImportResultRouteState.Item.Status?

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

            Table(filteredItems) {
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
            }
            .frame(minHeight: 220)

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
                Button(state.retryButtonTitle, action: onRetryFailed)
                    .disabled(!state.canRetryFailedItems)
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .task(id: state.sourceOpening.config.repoPath) {
            onLoadChangeLog()
        }
    }

    private var filteredItems: [ImportResultRouteState.Item] {
        guard let filter else { return state.items }
        return state.items.filter { $0.status == filter }
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
