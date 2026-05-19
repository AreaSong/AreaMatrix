import SwiftUI
import UniformTypeIdentifiers

enum MainRepositoryContentState: Equatable {
    case empty
    case list
}

struct MainRepositoryContentView: View {
    let opening: RepositoryOpeningResult
    let state: MainRepositoryContentState
    let onImport: () -> Void
    let onDropImport: ([URL], ImportEntryDestination) -> Void
    let onOpenSettings: () -> Void
    let onRetryCurrentList: () -> Void
    let onCollectDiagnostics: () async -> Void
    let onShowInFinder: (String) -> Void
    let onCopyPath: (String) -> Void
    let onCopyPaths: ([String]) -> Void
    let onOpenNoteFile: (String) -> Void
    let onOpenChangeCategoryPermissionRecovery: () -> Void
    let treeLister: any CoreRepositoryTreeListing
    let externalCreatedEvent: MainExternalCreatedFileEvent?
    let onExternalCreatedEventHandled: (MainExternalCreatedFileEvent) -> Void
    let importProgressItems: [ImportBatchProgressSnapshot.Item]
    @StateObject var fileListModel: MainFileListModel
    @State var repositoryTree: RepositoryTreeNodeSnapshot
    @State var selectedSidebarID: String = "inbox"
    @State var selectedFileIDs: Set<Int64> = []
    @State var pendingMovedFileFocusID: Int64?
    @State var selectedImportProgressIDs: Set<String> = []
    @State var filterText: String = ""
    @State var searchScope: SearchScopeSnapshot = .all
    @State var searchSort: SearchSortSnapshot = .newestImported
    @StateObject var dropPreviewModel: ImportDropPreviewModel
    @StateObject var detailNoteModel: DetailNoteModel
    @State var tableSortOrder: [KeyPathComparator<FileEntrySnapshot>] = [
        KeyPathComparator(\FileEntrySnapshot.importedAt, order: .reverse)
    ]
}

extension MainRepositoryContentView {
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
        .overlay(alignment: .center) {
            dropOverlay
        }
        .task(id: selectedSidebarID) {
            guard state == .list else { return }
            if fileListModel.searchState.isActive {
                selectedFileIDs = []
                return
            }
            searchScope = selectedSidebarRow.categoryForFileList == nil ? .all : .current
            let focusedFileID = pendingMovedFileFocusID
            if let focusedFileID {
                selectedFileIDs = [focusedFileID]
            } else {
                selectedFileIDs = []
            }
            await fileListModel.loadCurrentCategory(selectedSidebarRow.categoryForFileList, focusingOn: focusedFileID)
            if pendingMovedFileFocusID == focusedFileID {
                pendingMovedFileFocusID = nil
            }
        }
        .task(id: externalCreatedEvent?.id) {
            guard let externalCreatedEvent else { return }
            await fileListModel.syncExternalCreated(externalCreatedEvent)
            onExternalCreatedEventHandled(externalCreatedEvent)
        }
        .task(id: searchTaskKey) {
            guard state == .list else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await fileListModel.runSearch(
                query: filterText,
                scope: searchScope,
                sort: searchSort,
                sidebarRow: selectedSidebarRow
            )
        }
        .onChange(of: selectedFileIDs) { previousIDs, ids in
            showFailedNoteDraftBannerIfNeeded(leaving: previousIDs)
            if !ids.isEmpty {
                selectedImportProgressIDs = []
            }
            Task {
                await fileListModel.selectFiles(ids)
            }
        }
        .onChange(of: selectedImportProgressIDs) { _, ids in
            guard !ids.isEmpty else { return }
            selectedFileIDs = []
        }
        .sheet(item: actionDestinationBinding) { destination in
            actionRoutingSheet(destination)
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
            TextField("Search files", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onExitCommand {
                    clearSearch()
                }
            Picker("Scope", selection: $searchScope) {
                ForEach(SearchScopeSnapshot.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            Picker("Sort", selection: $searchSort) {
                ForEach(SearchSortSnapshot.allCases) { sort in
                    Text(sort.displayName).tag(sort)
                }
            }
            .frame(width: 170)
            Button("Import...", action: onImport)
                .disabled(opening.isReadOnly)
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
            ForEach(repositoryTree.sidebarRows) { row in
                sidebarRow(row)
                    .tag(row.id)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
    }

    private func sidebarRow(_ row: RepositorySidebarRowSnapshot) -> some View {
        HStack(spacing: 6) {
            Text(row.displayName)
                .padding(.leading, CGFloat(row.depth) * 14)
            Spacer()
            Text("\(row.totalFileCount)")
                .foregroundStyle(.secondary)
        }
        .modifier(ImportDropTargetModifier(
            target: row.importDropTarget,
            dropPreviewModel: dropPreviewModel,
            onDropImport: { urls, target in
                onDropImport(urls, target.entryDestination)
            },
            isEnabled: !opening.isReadOnly
        ))
        .help(row.importDropTarget.sidebarHelp)
        .accessibilityLabel("\(row.displayName) \(row.totalFileCount)")
        .accessibilityHint(row.importDropTarget.sidebarHelp)
    }

    static func defaultSelectedSidebarID(from rows: [RepositorySidebarRowSnapshot]) -> String {
        rows.first { $0.node.slug == "inbox" }?.id ?? rows.first?.id ?? "__root__"
    }

    private var statusText: String {
        state == .empty ? "Idle" : "Synced"
    }

    private var selectedListTitle: String {
        selectedSidebarRow.displayName
    }

    var selectedSidebarRow: RepositorySidebarRowSnapshot {
        repositoryTree.sidebarRow(id: selectedSidebarID) ??
            repositoryTree.sidebarRows.first ??
            RepositorySidebarRowSnapshot(node: repositoryTree, depth: 0)
    }

    init(
        opening: RepositoryOpeningResult,
        state: MainRepositoryContentState,
        onImport: @escaping () -> Void,
        onDropImport: @escaping ([URL], ImportEntryDestination) -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onRetryCurrentList: @escaping () -> Void = {},
        onCollectDiagnostics: @escaping () async -> Void = {},
        onShowInFinder: @escaping (String) -> Void = { _ in },
        onCopyPath: @escaping (String) -> Void = { _ in },
        onCopyPaths: @escaping ([String]) -> Void = { _ in },
        onOpenNoteFile: @escaping (String) -> Void = { _ in },
        onOpenChangeCategoryPermissionRecovery: @escaping () -> Void = {},
        treeLister: any CoreRepositoryTreeListing = CoreBridge(),
        externalCreatedEvent: MainExternalCreatedFileEvent? = nil,
        onExternalCreatedEventHandled: @escaping (MainExternalCreatedFileEvent) -> Void = { _ in },
        importProgressItems: [ImportBatchProgressSnapshot.Item] = [],
        fileLister: any CoreFileListing = CoreBridge(),
        fileDetailer: any CoreFileDetailing = CoreBridge(),
        searchQuerying: any CoreSearchQuerying = CoreBridge(),
        fileCategoryMover: any CoreFileCategoryMoving = CoreBridge(),
        iCloudConflictResolver: any ICloudConflictResolving = CoreBridge(),
        changeLogLister: any CoreChangeLogListing = CoreBridge(),
        externalChangesSyncer: any CoreExternalChangesSyncing = CoreBridge(),
        noteStore: any CoreNoteReadingWriting = CoreBridge(),
        categoryPredictor: any CoreCategoryPredicting = CoreBridge(),
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
        self.onCopyPaths = onCopyPaths
        self.onOpenNoteFile = onOpenNoteFile
        self.onOpenChangeCategoryPermissionRecovery = onOpenChangeCategoryPermissionRecovery
        self.treeLister = treeLister
        self.externalCreatedEvent = externalCreatedEvent
        self.onExternalCreatedEventHandled = onExternalCreatedEventHandled
        self.importProgressItems = importProgressItems
        _dropPreviewModel = StateObject(wrappedValue: ImportDropPreviewModel(
            repoPath: opening.config.repoPath,
            predictor: categoryPredictor
        ))
        _detailNoteModel = StateObject(wrappedValue: DetailNoteModel(
            repoPath: opening.config.repoPath,
            noteStore: noteStore,
            errorMapper: errorMapper
        ))
        _fileListModel = StateObject(wrappedValue: MainFileListModel(
            opening: opening,
            fileLister: fileLister,
            fileDetailer: fileDetailer,
            searchQuerying: searchQuerying,
            fileCategoryMover: fileCategoryMover,
            iCloudConflictResolver: iCloudConflictResolver,
            changeLogLister: changeLogLister,
            externalChangesSyncer: externalChangesSyncer,
            errorMapper: errorMapper,
            diagnosticsCollector: diagnosticsCollector
        ))
        _repositoryTree = State(initialValue: opening.tree)
        _selectedSidebarID = State(initialValue: Self.defaultSelectedSidebarID(from: opening.tree.sidebarRows))
        let defaultRow = opening.tree.sidebarRows.first {
            $0.id == Self.defaultSelectedSidebarID(from: opening.tree.sidebarRows)
        }
        _searchScope = State(initialValue: defaultRow?.categoryForFileList == nil ? .all : .current)
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
                    .disabled(opening.isReadOnly)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(ImportDropTargetModifier(
                target: .autoClassify,
                dropPreviewModel: dropPreviewModel,
                onDropImport: { urls, target in
                    onDropImport(urls, target.entryDestination)
                },
                isEnabled: !opening.isReadOnly
            ))
            .accessibilityElement(children: .contain)
        case .list:
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedListTitle)
                        .font(.title3.weight(.semibold))
                    Text(listCountText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    listLoadingIndicator
                }
                Divider()
                statusBanner
                fileTable
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(ImportDropTargetModifier(
                target: selectedSidebarRow.importDropTarget,
                dropPreviewModel: dropPreviewModel,
                onDropImport: { urls, target in
                    onDropImport(urls, target.entryDestination)
                },
                isEnabled: !opening.isReadOnly
            ))
        }
    }

    @ViewBuilder
    private var listLoadingIndicator: some View {
        if let loadingStatus = fileListModel.loadingStatusText {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(loadingStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(fileListModel.loadingAccessibilityText ?? "Loading files")
        }
    }

    private var fileTable: some View {
        VStack(spacing: 8) {
            ImportProgressTableView(rows: importProgressRows, selection: $selectedImportProgressIDs)
            fileTableContent
        }
        .overlay { emptyListOverlay }
    }

    private var fileTableContent: some View {
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
            TableColumn("Match") { file in
                Text(searchMatchText(for: file.id))
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
                onCopyPaths(selectedFiles.map(\.path))
            }
            .disabled(selectedFiles.isEmpty)
        }
    }

    private func files(for selection: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { selection.contains($0.id) }
    }

    private func currentListErrorPane(_ error: CoreErrorMappingSnapshot) -> some View {
        MainCurrentListErrorPane(
            error: error,
            state: state,
            fileListModel: fileListModel,
            onRetryCurrentList: onRetryCurrentList,
            onCollectDiagnostics: onCollectDiagnostics
        )
    }

    var dropOverlay: some View {
        Group {
            if let presentation = dropPreviewModel.presentation {
                DropZoneOverlay(presentation: presentation)
                    .padding(24)
            }
        }
    }

    var selectedImportProgressRow: ImportProgressListRow? {
        guard let id = selectedImportProgressIDs.first else { return nil }
        return importProgressRows.first { $0.id == id }
    }
}
