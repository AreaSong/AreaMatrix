import SwiftUI

struct DetailLogTabView: View {
    let selection: MainFileSelectionState
    let detailLogState: MainDetailLogState
    let diagnosticsState: MainDetailLogDiagnosticsState
    let externalCreateSyncState: MainDetailExternalCreateSyncState
    let onRefreshChangeLog: () -> Void
    let onRequestDiagnostics: () -> Void
    let onConfirmDiagnostics: () -> Void
    let onCancelDiagnostics: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            DetailExternalCreateSyncStatusView(state: externalCreateSyncState)
            content
        }
        .task(id: selection.singleFileID) {
            onRefreshChangeLog()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Change Log")
                    .font(.headline)
                Text("该文件的导入、移动、重命名和外部修改都会记录在这里。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Refresh", action: onRefreshChangeLog)
                .disabled(detailLogState.isLoading || externalCreateSyncState.isSyncing)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch detailLogState {
        case .notLoaded, .loading:
            loadingState
        case let .loaded(_, entries):
            loadedState(entries)
        case let .failed(fileID, mapping):
            errorState(fileID: fileID, mapping)
        }
    }

    private var isCollectingDiagnostics: Bool {
        diagnosticsState.isCollecting
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading change log")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func loadedState(_ entries: [ChangeLogEntrySnapshot]) -> some View {
        if entries.isEmpty {
            Text("暂无改动记录")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    ChangeTimelineRow(entry: entry)
                }
            }
        }
    }

    private func errorState(fileID: Int64, _ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("无法加载改动记录", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(mapping.userMessage)
                .foregroundStyle(.secondary)
            Text(mapping.suggestedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Retry", action: onRefreshChangeLog)
                Button("Collect Diagnostics...", action: onRequestDiagnostics)
                    .disabled(isCollectingDiagnostics)
            }
            Text("Diagnostics redact paths and usernames, exclude user file contents, and are not uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            diagnosticsStatus(fileID: fileID)
            DisclosureGroup("Technical Details") {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12))
    }

    @ViewBuilder
    private func diagnosticsStatus(fileID: Int64) -> some View {
        switch diagnosticsState {
        case .idle:
            EmptyView()
        case let .confirmingPrivacy(stateFileID) where stateFileID == fileID:
            VStack(alignment: .leading, spacing: 6) {
                Text("Create a redacted diagnostics package for this change log error?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Create diagnostics", action: onConfirmDiagnostics)
                    Button("Cancel", action: onCancelDiagnostics)
                }
            }
        case let .collecting(stateFileID) where stateFileID == fileID:
            Label("Preparing redacted diagnostics...", systemImage: "arrow.clockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
        case let .collected(stateFileID, snapshot) where stateFileID == fileID:
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.caption)
        case let .failed(stateFileID, mapping) where stateFileID == fileID:
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics could not be collected", systemImage: "exclamationmark.triangle")
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        case .confirmingPrivacy, .collecting, .collected, .failed:
            EmptyView()
        }
    }
}

private struct ChangeTimelineRow: View {
    let entry: ChangeLogEntrySnapshot
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(entry.detailJSON)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.actionDisplayName)
                    .font(.callout.weight(.semibold))
                Text(entry.occurredAtDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.detailSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension MainFileListModel {
    var loadingStatusText: String? {
        guard isLoading else { return nil }
        if searchState.isActive { return "Searching..." }
        return "正在加载 \(currentCategoryDisplayName)..."
    }

    var loadingAccessibilityText: String? {
        guard let loadingStatusText else { return nil }
        return "Loading files. \(loadingStatusText)"
    }

    func canApplyDetailLogDiagnosticsResult(fileID: Int64) -> Bool {
        guard selection.singleFileID == fileID,
              case let .failed(failedFileID, _) = detailLogState else { return false }
        return failedFileID == fileID
    }

    func canApplyMultiSelectionDetailResult(generation: Int, ids: Set<Int64>) -> Bool {
        generation == detailGeneration && selection.multipleFileIDs == ids
    }
}

struct MultiSelectionDetailSummary: Equatable {
    var selectedCount: Int
    var files: [FileEntrySnapshot]
    var listOrderedFileIDs: [Int64]
    var unresolvedMetadataCount: Int
    var isUpdating: Bool

    init(selection: MainFileSelectionState, files: [FileEntrySnapshot], isUpdating: Bool = false) {
        let selectedIDs = selection.multipleFileIDs
        selectedCount = selectedIDs.count
        listOrderedFileIDs = files.filter { selectedIDs.contains($0.id) }.map(\.id)
        self.files = Self.orderedSelectedFiles(from: files, selectedIDs: selectedIDs)
        unresolvedMetadataCount = max(0, selectedIDs.count - self.files.count)
        self.isUpdating = isUpdating
    }

    var title: String {
        "\(selectedCount) 个文件已选中"
    }

    var subtitle: String {
        if categories.count == 1, let category = categories.first {
            return "\(category) 中的 \(selectedCount) 个项目"
        }
        if categories.count > 1 {
            return "跨 \(categories.count) 个分类的 \(selectedCount) 个项目"
        }
        return "\(selectedCount) 个项目"
    }

    var paths: [String] {
        files.map(\.path)
    }

    var warningMessages: [String] {
        var warnings: [String] = []
        if unresolvedMetadataCount > 0 { warnings.append("部分选中项无法读取元数据") }
        if missingCount > 0 { warnings.append("选中的文件中有 \(missingCount) 个缺失条目") }
        if indexOnlyCount > 0 { warnings.append("某些条目的来源路径可能在资料库外") }
        return warnings
    }

    var statisticRows: [MultiSelectionSummaryRow] {
        [
            MultiSelectionSummaryRow(label: "Total size", value: totalSizeDisplay),
            MultiSelectionSummaryRow(label: "Categories", value: categoriesDisplay),
            MultiSelectionSummaryRow(label: "Storage modes", value: storageModesDisplay),
            MultiSelectionSummaryRow(label: "Earliest imported", value: importedDateDisplay { $0.min() }),
            MultiSelectionSummaryRow(label: "Latest imported", value: importedDateDisplay { $0.max() })
        ]
    }

    var fileTypeRows: [MultiSelectionSummaryRow] {
        let groupedTypes = Dictionary(grouping: files.map(Self.fileTypeLabel), by: { $0 })
        return groupedTypes.map { label, values in
            (label: label, count: values.count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.label < rhs.label
        }
        .map { MultiSelectionSummaryRow(label: $0.label, value: "\($0.count)") }
    }

    private var categories: [String] {
        uniqueSorted(files.map(\.category))
    }

    private var categoriesDisplay: String {
        displayList(categories)
    }

    private var storageModesDisplay: String {
        displayList(uniqueSorted(files.map(\.storageMode)))
    }

    private var totalSizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file)
    }

    private var missingCount: Int {
        files.filter { $0.availability == .missing }.count
    }

    private var indexOnlyCount: Int {
        files.filter { $0.storageMode == "Indexed" }.count
    }

    private func importedDateDisplay(_ valueSelector: ([Int64]) -> Int64?) -> String {
        let importedValues = files.map(\.importedAt)
        guard let timestamp = valueSelector(importedValues) else { return "Not available" }
        return FileEntrySnapshot.mainDisplayDateFormatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(timestamp))
        )
    }

    private static func orderedSelectedFiles(
        from files: [FileEntrySnapshot],
        selectedIDs: Set<Int64>
    ) -> [FileEntrySnapshot] {
        files.filter { selectedIDs.contains($0.id) }
            .sorted { $0.currentName.localizedStandardCompare($1.currentName) == .orderedAscending }
    }

    private static func fileTypeLabel(for file: FileEntrySnapshot) -> String {
        let fileExtension = (file.currentName as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            return "PDF"
        case "md", "markdown":
            return "Markdown"
        case "png", "jpg", "jpeg", "gif", "heic", "webp":
            return "Image"
        case "":
            return "No Extension"
        default:
            return fileExtension.uppercased()
        }
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private func displayList(_ values: [String]) -> String {
        values.isEmpty ? "Not available" : values.joined(separator: ", ")
    }
}

struct MultiSelectionSummaryRow: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String {
        label
    }
}
