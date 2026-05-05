import SwiftUI
import UniformTypeIdentifiers

enum MainRepositoryContentState: Equatable, Sendable {
    case empty
    case list
}

struct MainRepositoryContentView: View {
    let opening: RepositoryOpeningResult
    let state: MainRepositoryContentState
    let onImport: () -> Void
    let onDropImport: ([URL]) -> Void
    let onOpenSettings: () -> Void
    let onRetryCurrentList: () -> Void
    @StateObject private var fileListModel: MainFileListModel
    @State private var selectedSidebarID: String = "inbox"
    @State private var selectedFileID: Int64?
    @State private var filterText: String = ""
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                listPane
                Divider()
                detailPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: selectedSidebarID) {
            guard state == .list else { return }
            selectedFileID = nil
            await fileListModel.loadCurrentCategory(selectedSidebarRow.categoryForFileList)
        }
        .onChange(of: selectedFileID) { _, fileID in
            Task {
                await fileListModel.selectFile(id: fileID)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Menu {
                Text(opening.config.repoPath)
                Button("Settings", action: onOpenSettings)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text("AreaMatrix")
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.headline)
            }
            .accessibilityLabel("Repository AreaMatrix")
            Spacer()
            TextField("Filter current list", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button("Import...", action: onImport)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Settings")
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarID) {
            ForEach(opening.tree.sidebarRows) { row in
                sidebarRow(row)
                    .tag(row.id)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
        .onChange(of: opening.tree.sidebarRows) { _, rows in
            selectedSidebarID = Self.defaultSelectedSidebarID(from: rows)
        }
    }

    private func sidebarRow(_ row: RepositorySidebarRowSnapshot) -> some View {
        HStack(spacing: 6) {
            Text(row.displayName)
                .padding(.leading, CGFloat(row.depth) * 14)
            Spacer()
            Text("\(row.totalFileCount)")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(row.displayName) \(row.totalFileCount)")
    }

    private static func defaultSelectedSidebarID(from rows: [RepositorySidebarRowSnapshot]) -> String {
        rows.first { $0.node.slug == "inbox" }?.id ?? rows.first?.id ?? "__root__"
    }

    private var statusText: String {
        state == .empty ? "Idle" : "Synced"
    }

    private var selectedListTitle: String {
        selectedSidebarRow.displayName
    }

    private var selectedSidebarRow: RepositorySidebarRowSnapshot {
        opening.tree.sidebarRow(id: selectedSidebarID) ??
            opening.tree.sidebarRows.first ??
            RepositorySidebarRowSnapshot(node: opening.tree, depth: 0)
    }

    init(
        opening: RepositoryOpeningResult,
        state: MainRepositoryContentState,
        onImport: @escaping () -> Void,
        onDropImport: @escaping ([URL]) -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onRetryCurrentList: @escaping () -> Void = {},
        fileLister: any CoreFileListing = CoreBridge(),
        fileDetailer: any CoreFileDetailing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.opening = opening
        self.state = state
        self.onImport = onImport
        self.onDropImport = onDropImport
        self.onOpenSettings = onOpenSettings
        self.onRetryCurrentList = onRetryCurrentList
        _fileListModel = StateObject(wrappedValue: MainFileListModel(
            opening: opening,
            fileLister: fileLister,
            fileDetailer: fileDetailer,
            errorMapper: errorMapper
        ))
        _selectedSidebarID = State(initialValue: Self.defaultSelectedSidebarID(from: opening.tree.sidebarRows))
    }

    @ViewBuilder
    private var listPane: some View {
        if let error = currentListError {
            currentListErrorPane(error)
        } else {
            listContentPane
        }
    }

    private var currentListError: CoreErrorMappingSnapshot? {
        state == .list ? fileListModel.errorMapping : opening.currentCategoryListError
    }

    @ViewBuilder
    private var listContentPane: some View {
        switch state {
        case .empty:
            VStack(spacing: 14) {
                Text("这里还没有文件")
                    .font(.title2.weight(.semibold))
                Text("把文件拖到这里，AreaMatrix 会自动分类、命名并记录改动。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Import...", action: onImport)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                FileDropAdapter(onDrop: onDropImport).handle(providers)
            }
            .accessibilityElement(children: .contain)
        case .list:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedListTitle)
                        .font(.title3.weight(.semibold))
                    Text("\(visibleFiles.count) files")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if fileListModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Divider()
                fileTable
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var fileTable: some View {
        Table(visibleFiles, selection: $selectedFileID) {
            TableColumn("Name") { file in
                Text(file.currentName)
                    .lineLimit(1)
            }
            TableColumn("Category / Path") { file in
                Text(file.categoryPathDisplay)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Size") { file in
                Text(file.sizeDisplay)
                    .monospacedDigit()
            }
            TableColumn("Modified") { file in
                Text(file.updatedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn("Imported") { file in
                Text(file.importedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn("Status") { file in
                Text(file.statusDisplay)
            }
        }
        .overlay {
            if !fileListModel.isLoading && visibleFiles.isEmpty {
                Text("No files in this category")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleFiles: [FileEntrySnapshot] {
        fileListModel.files.filter { selectedSidebarRow.contains($0) }
    }

    private func currentListErrorPane(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current list cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Retry") {
                    if state == .list {
                        Task {
                            await fileListModel.retryCurrentCategory()
                        }
                    } else {
                        onRetryCurrentList()
                    }
                }
                DisclosureGroup("Technical Details") {
                    Text(error.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var detailPane: some View {
        Group {
            if let error = fileListModel.detailErrorMapping {
                detailErrorPane(error)
            } else if fileListModel.isDetailLoading {
                detailLoadingPane
            } else if let detail = fileListModel.selectedFileDetail {
                detailMetadataPane(detail)
            } else {
                emptyDetailPane
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyDetailPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择一个文件查看详情")
                .font(.headline)
            Text("文件的元数据、改动时间线和伴生笔记会显示在这里。")
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private var detailLoadingPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading file details")
                .font(.headline)
        }
        .padding(18)
    }

    private func detailErrorPane(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("File details cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task {
                    await fileListModel.retrySelectedFileDetail()
                }
            }
            DisclosureGroup("Technical Details") {
                Text(error.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .accessibilityElement(children: .contain)
    }

    private func detailMetadataPane(_ detail: FileEntrySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(detail.currentName)
                    .font(.headline)
                    .textSelection(.enabled)
                metadataRows(for: detail)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func metadataRows(for detail: FileEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow("Category", detail.category)
            metadataRow("Path", detail.path)
            metadataRow("Size", detail.sizeDisplay)
            metadataRow("Storage", detail.storageMode)
            metadataRow("Origin", detail.origin)
            metadataRow("Imported", detail.importedAtDisplay)
            metadataRow("Modified", detail.updatedAtDisplay)
            metadataRow("SHA-256", detail.hashSha256)
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
                .lineLimit(3)
        }
    }
}

private extension FileEntrySnapshot {
    var categoryPathDisplay: String {
        let pathPrefix = path.split(separator: "/").dropLast().joined(separator: "/")
        return pathPrefix.isEmpty ? category : pathPrefix
    }

    var sizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var importedAtDisplay: String {
        Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(importedAt)))
    }

    var updatedAtDisplay: String {
        Self.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(updatedAt)))
    }

    var statusDisplay: String {
        storageMode == "Indexed" ? "Index-only" : "OK"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
