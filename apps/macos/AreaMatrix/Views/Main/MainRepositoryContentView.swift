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
    let onCollectDiagnostics: () async -> Void
    let onShowInFinder: (String) -> Void
    let onCopyPath: (String) -> Void
    @StateObject private var fileListModel: MainFileListModel
    @State private var selectedSidebarID: String = "inbox"
    @State private var selectedFileIDs: Set<Int64> = []
    @State private var filterText: String = ""
    @State private var isDropTargeted = false
    @State private var tableSortOrder: [KeyPathComparator<FileEntrySnapshot>] = [
        KeyPathComparator(\FileEntrySnapshot.importedAt, order: .reverse),
    ]

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
            selectedFileIDs = []
            await fileListModel.loadCurrentCategory(selectedSidebarRow.categoryForFileList)
        }
        .onChange(of: selectedFileIDs) { _, ids in
            Task {
                await fileListModel.selectFiles(ids)
            }
        }
        .sheet(item: actionDestinationBinding) { destination in
            actionRoutingSheet(destination)
        }
    }

    private var actionDestinationBinding: Binding<MainFileActionDestination?> {
        Binding(
            get: { fileListModel.pendingActionDestination },
            set: { value in
                if value == nil {
                    fileListModel.clearPendingActionDestination()
                }
            }
        )
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
        onCollectDiagnostics: @escaping () async -> Void = {},
        onShowInFinder: @escaping (String) -> Void = { _ in },
        onCopyPath: @escaping (String) -> Void = { _ in },
        fileLister: any CoreFileListing = CoreBridge(),
        fileDetailer: any CoreFileDetailing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge()
    ) {
        self.opening = opening
        self.state = state
        self.onImport = onImport
        self.onDropImport = onDropImport
        self.onOpenSettings = onOpenSettings
        self.onRetryCurrentList = onRetryCurrentList
        self.onCollectDiagnostics = onCollectDiagnostics
        self.onShowInFinder = onShowInFinder
        self.onCopyPath = onCopyPath
        _fileListModel = StateObject(wrappedValue: MainFileListModel(
            opening: opening,
            fileLister: fileLister,
            fileDetailer: fileDetailer,
            errorMapper: errorMapper,
            diagnosticsCollector: diagnosticsCollector
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
                statusBanner
                fileTable
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var fileTable: some View {
        Table(visibleFiles, selection: $selectedFileIDs, sortOrder: $tableSortOrder) {
            TableColumn("Name", sortUsing: KeyPathComparator(\FileEntrySnapshot.currentName)) { file in
                Text(file.currentName)
                    .lineLimit(1)
            }
            TableColumn("Category / Path", sortUsing: KeyPathComparator(\FileEntrySnapshot.path)) { file in
                Text(file.categoryPathDisplay)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Size", sortUsing: KeyPathComparator(\FileEntrySnapshot.sizeBytes)) { file in
                Text(file.sizeDisplay)
                    .monospacedDigit()
            }
            TableColumn("Modified", sortUsing: KeyPathComparator(\FileEntrySnapshot.updatedAt)) { file in
                Text(file.updatedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn("Imported", sortUsing: KeyPathComparator(\FileEntrySnapshot.importedAt)) { file in
                Text(file.importedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn("Status", sortUsing: KeyPathComparator(\FileEntrySnapshot.statusDisplay)) { file in
                Text(file.statusDisplay)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { selection in
            contextMenu(for: selection)
        } primaryAction: { selection in
            selectedFileIDs = selection
        }
        .overlay {
            if !fileListModel.isLoading && visibleFiles.isEmpty {
                Text("No files in this category")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleFiles: [FileEntrySnapshot] {
        MainListVisibleFileFiltering.visibleFiles(
            from: fileListModel.files,
            sidebarRow: selectedSidebarRow,
            filterText: filterText
        )
        .sorted(using: tableSortOrder)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let banner = fileListModel.statusBanner {
            HStack(spacing: 10) {
                Label(banner.message, systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                Spacer()
                Button("Retry") {
                    Task {
                        await fileListModel.retryCurrentCategory()
                    }
                }
                Button("Dismiss") {
                    fileListModel.clearStatusBanner()
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.12))
        }
    }

    @ViewBuilder
    private func contextMenu(for selection: Set<Int64>) -> some View {
        let selectedFiles = files(for: selection)
        if selectedFiles.count == 1, let file = selectedFiles.first {
            Button("Show in Finder") {
                onShowInFinder(file.path)
            }
            Button("Rename...") {
                fileListModel.beginRename(fileID: file.id)
            }
            .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
            Button("Change Category...") {
                fileListModel.beginChangeCategory(fileID: file.id)
            }
            .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
            Button("Delete...", role: .destructive) {
                fileListModel.beginDelete(fileID: file.id)
            }
            .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
            Divider()
            Button("Copy Path") {
                onCopyPath(file.path)
            }
        } else {
            Button("Copy Paths") {
                onCopyPath(selectedFiles.map(\.path).joined(separator: "\n"))
            }
            .disabled(selectedFiles.isEmpty)
        }
    }

    private func files(for selection: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { selection.contains($0.id) }
    }

    private func actionRoutingSheet(_ destination: MainFileActionDestination) -> some View {
        let file = file(for: destination.fileID)
        return MainFileActionRoutingSheet(
            destination: destination,
            file: file,
            categoryRows: opening.tree.sidebarRows,
            onDismiss: fileListModel.clearPendingActionDestination
        )
    }

    private func file(for fileID: Int64) -> FileEntrySnapshot? {
        fileListModel.files.first { $0.id == fileID } ??
            fileListModel.selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
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
                Button("Collect Diagnostics...") {
                    if state == .list {
                        Task {
                            await fileListModel.collectCurrentListDiagnostics()
                        }
                    } else {
                        Task {
                            await onCollectDiagnostics()
                        }
                    }
                }
                .disabled(isCollectingCurrentListDiagnostics)
                DisclosureGroup("Technical Details") {
                    Text(error.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            currentListDiagnosticsStatus
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var isCollectingCurrentListDiagnostics: Bool {
        if case .collecting = fileListModel.diagnosticsState {
            return true
        }
        return false
    }

    @ViewBuilder
    private var currentListDiagnosticsStatus: some View {
        switch fileListModel.diagnosticsState {
        case .idle:
            EmptyView()
        case .collecting:
            Label("Preparing diagnostics...", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .collected(let snapshot):
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.callout)
        case .failed(let mapping):
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics could not be collected", systemImage: "exclamationmark.triangle")
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var detailPane: some View {
        MainRepositoryDetailPane(
            selection: fileListModel.selection,
            detailErrorMapping: fileListModel.detailErrorMapping,
            isDetailLoading: fileListModel.isDetailLoading,
            selectedFileDetail: fileListModel.selectedFileDetail,
            onRetrySelectedFileDetail: {
                Task {
                    await fileListModel.retrySelectedFileDetail()
                }
            }
        )
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
    }
}
