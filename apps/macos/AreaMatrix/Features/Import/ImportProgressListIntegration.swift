import SwiftUI

struct ImportProgressListRow: Identifiable, Equatable {
    let item: ImportBatchProgressSnapshot.Item

    var id: String {
        item.id
    }

    var displayName: String {
        let name = (item.targetPath as NSString).lastPathComponent
        return name.isEmpty ? item.targetPath : name
    }

    var categoryPathDisplay: String {
        let directory = (item.targetPath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? item.targetPath : directory
    }

    var sourcePath: String {
        item.sourcePath
    }

    var targetPath: String {
        item.targetPath
    }

    var statusText: String {
        item.phase.displayText
    }

    var errorMessage: String? {
        item.errorMessage
    }
}

struct ImportProgressTableView: View {
    let rows: [ImportProgressListRow]
    @Binding var selection: Set<String>

    var body: some View {
        if !rows.isEmpty {
            Table(rows, selection: $selection) {
                TableColumn("Importing") { row in
                    Text(row.displayName)
                        .lineLimit(1)
                }
                TableColumn("Target") { row in
                    Text(row.categoryPathDisplay)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                TableColumn("Status") { row in
                    Text(row.statusText)
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 96, idealHeight: tableHeight, maxHeight: tableHeight)
        }
    }

    private var tableHeight: CGFloat {
        CGFloat(min(max(rows.count, 1), 4)) * 34 + 34
    }
}

struct ImportProgressDetailPane: View {
    let row: ImportProgressListRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Import details", systemImage: row.systemImage)
                    .font(.headline)
                metadataRows
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow("Status", row.statusText)
            metadataRow("Target", row.targetPath)
            metadataRow("Source", row.sourcePath)
            if let errorMessage = row.errorMessage {
                metadataRow("Error", errorMessage)
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }
}

extension MainRepositoryContentView {
    var selectedImportProgressRow: ImportProgressListRow? {
        guard let id = selectedImportProgressIDs.first else { return nil }
        return importProgressRows.first { $0.id == id }
    }
}

struct CommandPaletteSmartListTarget: Equatable, Identifiable {
    let savedSearch: SavedSearchSnapshot

    var id: Int64 {
        savedSearch.id
    }

    var title: String {
        savedSearch.name
    }

    var systemImage: String {
        savedSearch.icon ?? "line.3.horizontal.decrease.circle"
    }

    var helpText: String {
        "Open Smart List"
    }

    var accessibilityIdentifier: String {
        "command-palette-smart-list-smart-list-\(savedSearch.id)"
    }

    static func matching(_ savedSearches: [SavedSearchSnapshot], query: String) -> [CommandPaletteSmartListTarget] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = savedSearches.filter { saved in
            trimmed.isEmpty ||
                saved.name.localizedCaseInsensitiveContains(trimmed) ||
                saved.query.query.localizedCaseInsensitiveContains(trimmed)
        }
        return filtered.map(CommandPaletteSmartListTarget.init(savedSearch:))
    }
}

struct SearchCommandPaletteRouteView: View {
    @Binding var query: String
    let state: CommandPaletteLoadState
    var smartLists: [SavedSearchSnapshot] = []
    let onLoad: () -> Void
    var onOpenSmartList: (SavedSearchSnapshot) -> Void = { _ in }
    let onExecuteTarget: (CommandTargetSnapshot) -> Void
    let onClose: () -> Void

    var body: some View {
        CommandPaletteView(
            query: $query,
            state: state,
            smartLists: smartLists,
            onLoad: onLoad,
            onOpenSmartList: onOpenSmartList,
            onExecuteTarget: onExecuteTarget,
            onClose: onClose
        )
        .accessibilityIdentifier("command-palette-search-route")
    }
}

extension MainRepositoryContentView {
    func commandPaletteBatchDeleteRoute() -> BatchDeleteRoute {
        CommandPaletteBatchRouteBuilder.batchDeleteRoute(
            selectedFileIDs: selectedFileIDs,
            visibleFiles: visibleFiles,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    func commandPaletteBatchRenameRoute() -> BatchRenameRoute {
        CommandPaletteBatchRouteBuilder.batchRenameRoute(
            selectedFileIDs: selectedFileIDs,
            visibleFiles: visibleFiles,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }
}

private extension ImportProgressListRow {
    var systemImage: String {
        switch item.phase {
        case .done:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .pending:
            "clock"
        case .copying, .moving, .hashing, .classifying, .writingIndex:
            "arrow.triangle.2.circlepath"
        }
    }
}
