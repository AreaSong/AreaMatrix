import SwiftUI
import UniformTypeIdentifiers

enum MainRepositoryContentState: Equatable { case empty, list }

struct MainRepositoryContentView: View {
    let opening: RepositoryOpeningResult
    let state: MainRepositoryContentState
    let onImport: () -> Void
    let onDropImport: ([URL], ImportEntryDestination) -> Void
    let onOpenSettings: () -> Void
    let onOpenRepository: () -> Void
    let onOpenHelp: () -> Void
    let onOpenImportConflictBatch: (ImportConflictBatchRoute) -> Void
    let onRetryCurrentList: () -> Void
    let onCollectDiagnostics: () async -> Void
    let onShowInFinder: (String) -> Void
    let onCopyPath: (String) -> Void
    let onCopyPaths: ([String]) -> Void
    let onOpenNoteFile: (String) -> Void
    let onOpenChangeCategoryPermissionRecovery: () -> Void
    let treeLister: any CoreRepositoryTreeListing
    let savedSearchStore: any CoreSavedSearchCRUD
    let batchRenamer: any CoreBatchRenaming
    let errorMapper: any CoreErrorMapping
    let externalCreatedEvent: MainExternalCreatedFileEvent?
    let onExternalCreatedEventHandled: (MainExternalCreatedFileEvent) -> Void
    let pendingTagSuggestionFocus: TagSuggestionPresentationRequest?
    let onPendingTagSuggestionFocusConsumed: (TagSuggestionPresentationRequest) -> Void
    let importProgressItems: [ImportBatchProgressSnapshot.Item]
    @StateObject var fileListModel: MainFileListModel
    @State var repositoryTree: RepositoryTreeNodeSnapshot
    @State var selectedSidebarID: String = "inbox"
    @State var selectedFileIDs: Set<Int64> = []
    @State var pendingMovedFileFocusID: Int64?
    @State var selectedImportProgressIDs: Set<String> = []
    @State var pendingBatchAddTagsRoute: BatchAddTagsRoute?
    @State var pendingBatchChangeCategoryRoute: BatchChangeCategoryRoute?
    @State var pendingBatchDeleteRoute: BatchDeleteRoute?
    @State var pendingBatchRenameRoute: BatchRenameRoute?
    @State var pendingImportConflictBatchRoute: ImportConflictBatchRoute?
    @State var pendingUndoHistoryRequest: UndoToastHistoryRequest?
    @State var batchTagUndoState: BatchTagUndoState = .idle
    @State var batchTagActionLogRefreshFailure: CoreErrorMappingSnapshot?
    @State var restoreSearchFocusAfterPalette = false
    @State var filterText: String = ""
    @State var searchScope: SearchScopeSnapshot = .all
    @State var searchSort: SearchSortSnapshot = .newestImported
    @State var searchFilters: SearchFilterStateSnapshot = .empty
    @State var isSearchFiltersPresented = false
    @State var isSidebarTagsFilterPresented = false
    @State var savedSearchesBySidebarID: [String: SavedSearchSnapshot] = [:]
    @State var smartListLoadError: CoreErrorMappingSnapshot?
    @State var smartListManagementRoute: SmartListManagementRoute?
    @FocusState var isSearchFieldFocused: Bool
    @StateObject var dropPreviewModel: ImportDropPreviewModel
    @StateObject var detailNoteModel: DetailNoteModel
    @State var tableSortOrder: [KeyPathComparator<FileEntrySnapshot>] = [
        .init(\FileEntrySnapshot.importedAt, order: .reverse)
    ]

    init(
        opening: RepositoryOpeningResult,
        state: MainRepositoryContentState,
        onImport: @escaping () -> Void,
        onDropImport: @escaping ([URL], ImportEntryDestination) -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onOpenRepository: @escaping () -> Void = {},
        onOpenHelp: @escaping () -> Void = {},
        onOpenImportConflictBatch: @escaping (ImportConflictBatchRoute) -> Void = { _ in },
        onRetryCurrentList: @escaping () -> Void = {},
        onCollectDiagnostics: @escaping () async -> Void = {},
        onShowInFinder: @escaping (String) -> Void = { _ in },
        onCopyPath: @escaping (String) -> Void = { _ in },
        onCopyPaths: @escaping ([String]) -> Void = { _ in },
        onOpenNoteFile: @escaping (String) -> Void = { _ in },
        onOpenChangeCategoryPermissionRecovery: @escaping () -> Void = {},
        treeLister: any CoreRepositoryTreeListing = CoreBridge(),
        savedSearchStore: any CoreSavedSearchCRUD = CoreBridge(),
        externalCreatedEvent: MainExternalCreatedFileEvent? = nil,
        onExternalCreatedEventHandled: @escaping (MainExternalCreatedFileEvent) -> Void = { _ in },
        pendingTagSuggestionFocus: TagSuggestionPresentationRequest? = nil,
        onPendingTagSuggestionFocusConsumed: @escaping (TagSuggestionPresentationRequest) -> Void = { _ in },
        importProgressItems: [ImportBatchProgressSnapshot.Item] = [],
        fileLister: any CoreFileListing = CoreBridge(),
        fileDetailer: any CoreFileDetailing = CoreBridge(),
        searchQuerying: any CoreSearchQuerying = CoreBridge(),
        searchFiltering: any CoreSearchFiltering = CoreBridge(),
        commandIndexer: any CoreCommandIndexing = CoreBridge(),
        fileCategoryMover: any CoreFileCategoryMoving = CoreBridge(),
        batchDeleter: any CoreBatchDeleting = CoreBridge(),
        batchCategoryChanger: any CoreBatchCategoryChanging = CoreBridge(),
        batchRenamer: any CoreBatchRenaming = CoreBridge(),
        iCloudConflictResolver: any ICloudConflictResolving = CoreBridge(),
        tagStore: any CoreTagCRUD = CoreBridge(),
        undoActionStore: any CoreUndoActionLogging = CoreBridge(),
        redoActionStore: any CoreRedoActionLogging = CoreBridge(),
        changeLogLister: any CoreChangeLogListing = CoreBridge(),
        externalChangesSyncer: any CoreExternalChangesSyncing = CoreBridge(),
        noteStore: any CoreNoteReadingWriting = CoreBridge(),
        categoryPredictor: any CoreCategoryPredicting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge()
    ) {
        self.opening = opening; self.state = state
        self.onImport = onImport; self.onDropImport = onDropImport
        self.onOpenSettings = onOpenSettings; self.onOpenRepository = onOpenRepository; self.onOpenHelp = onOpenHelp
        self.onOpenImportConflictBatch = onOpenImportConflictBatch
        self.onRetryCurrentList = onRetryCurrentList; self.onCollectDiagnostics = onCollectDiagnostics
        self.onShowInFinder = onShowInFinder; self.onCopyPath = onCopyPath; self.onCopyPaths = onCopyPaths
        self.onOpenNoteFile = onOpenNoteFile
        self.onOpenChangeCategoryPermissionRecovery = onOpenChangeCategoryPermissionRecovery
        self.treeLister = treeLister; self.savedSearchStore = savedSearchStore; self.batchRenamer = batchRenamer
        self.errorMapper = errorMapper; self.externalCreatedEvent = externalCreatedEvent
        self.onExternalCreatedEventHandled = onExternalCreatedEventHandled
        self.pendingTagSuggestionFocus = pendingTagSuggestionFocus
        self.onPendingTagSuggestionFocusConsumed = onPendingTagSuggestionFocusConsumed
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
            searchFiltering: searchFiltering,
            commandIndexer: commandIndexer,
            fileCategoryMover: fileCategoryMover,
            batchDeleter: batchDeleter,
            batchCategoryChanger: batchCategoryChanger,
            iCloudConflictResolver: iCloudConflictResolver,
            tagStore: tagStore,
            undoActionStore: undoActionStore,
            redoActionStore: redoActionStore,
            changeLogLister: changeLogLister,
            externalChangesSyncer: externalChangesSyncer,
            errorMapper: errorMapper,
            diagnosticsCollector: diagnosticsCollector
        ))
        _repositoryTree = State(initialValue: opening.tree)
        _selectedSidebarID = State(initialValue: Self.defaultSelectedSidebarID(from: opening.tree.sidebarRows))
        let defaultSidebarID = Self.defaultSelectedSidebarID(from: opening.tree.sidebarRows)
        let defaultRow = opening.tree.sidebarRows.first { $0.id == defaultSidebarID }
        _searchScope = State(initialValue: defaultRow?.categoryForFileList == nil ? .all : .current)
    }
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
        .overlay(alignment: .bottomTrailing) {
            batchTagUndoToastOverlay.padding(18)
        }
        .task(id: selectedSidebarID) {
            guard state == .list else { return }
            if await restoreSelectedSavedSearchIfNeeded() {
                selectedFileIDs = []
                return
            }
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
        .task(id: opening.config.repoPath) {
            guard state == .list else { return }
            await loadSmartLists()
        }
        .task(id: externalCreatedEvent?.id) {
            guard let externalCreatedEvent else { return }
            await fileListModel.syncExternalCreated(externalCreatedEvent)
            onExternalCreatedEventHandled(externalCreatedEvent)
        }
        .task(id: pendingTagSuggestionFocus?.id) {
            await applyPendingTagSuggestionFocus()
        }
        .task(id: searchTaskKey) {
            guard state == .list else { return }
            guard savedSearchesBySidebarID[selectedSidebarID] == nil else { return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await fileListModel.runSearch(
                query: filterText,
                scope: searchScope,
                sort: searchSort,
                sidebarRow: selectedSidebarRow,
                filters: effectiveSearchFilters
            )
        }
        .task(id: searchFacetsTaskKey) {
            guard state == .list else { return }
            guard savedSearchesBySidebarID[selectedSidebarID] == nil else { return }
            await fileListModel.loadSearchFacets(
                query: filterText,
                scope: searchScope,
                sidebarRow: selectedSidebarRow,
                filters: effectiveSearchFilters
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
        .sheet(item: actionDestinationBinding, content: actionRoutingSheet)
        .sheet(item: searchDestinationBinding, content: searchRoutingSheet)
        .sheet(item: $pendingBatchAddTagsRoute, content: batchAddTagsRoutingSheet)
        .sheet(item: $pendingBatchChangeCategoryRoute, content: batchChangeCategoryRoutingSheet)
        .sheet(item: $pendingBatchDeleteRoute, content: batchDeleteRoutingSheet)
        .sheet(item: $pendingBatchRenameRoute, content: batchRenameRoutingSheet)
        .sheet(item: $pendingUndoHistoryRequest, content: undoHistorySheet)
        .sheet(item: $smartListManagementRoute, content: smartListManagementSheet)
        .onChange(of: pendingImportConflictBatchRoute) { _, route in
            guard let route else { return }; pendingImportConflictBatchRoute = nil
            onOpenImportConflictBatch(route)
        }
        .onChange(of: isSearchFiltersPresented) { _, presented in
            guard !presented else { return }
            reopenSmartListEditorFromDraftIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: AreaMatrixUndoHistoryCommandRelay.notification)) { _ in
            openUndoHistoryFromMenu()
        }
        .onReceive(NotificationCenter.default.publisher(for: AreaMatrixCommandPaletteCommandRelay.notification)) { _ in
            toggleCommandPalette()
        }
        .onKeyPress("z", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            if event.modifiers.contains(.shift) {
                openUndoHistoryFromRedoShortcut()
                return .handled
            }
            openUndoHistoryFromShortcut()
            return .handled
        }
    }

    func reopenSmartListEditorFromDraftIfNeeded() {
        guard let draft = fileListModel.smartListFilterDraft else { return }
        let sidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(draft.id)
        guard let saved = savedSearchesBySidebarID[sidebarID] else { return }
        smartListManagementRoute = SmartListManagementRoute(
            mode: .editQuery,
            savedSearch: saved,
            draftFilters: draft.filters
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
            TextField("Search files", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($isSearchFieldFocused)
                .onExitCommand {
                    handleSearchEscape()
                }
                .onSubmit {
                    fileListModel.enterSearch(context: .toolbar)
                }
                .accessibilityIdentifier("S2-01-search-field")
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
            searchFiltersButton
            Button(action: openUndoHistoryFromToolbar) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Undo History")
            .accessibilityLabel("Undo History")
            .accessibilityIdentifier("S2-11-C2-07-toolbar-open-history")
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
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
        .onKeyPress("f", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            beginCommandFindSearch()
            return .handled
        }
        .onKeyPress("k", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            toggleCommandPalette()
            return .handled
        }
    }

    static func defaultSelectedSidebarID(from rows: [RepositorySidebarRowSnapshot]) -> String {
        rows.first { $0.node.slug == "inbox" }?.id ?? rows.first?.id ?? "__root__"
    }

    private var statusText: String { state == .empty ? "Idle" : "Synced" }

    private func applyPendingTagSuggestionFocus() async {
        guard state == .list, let focus = pendingTagSuggestionFocus else { return }
        selectedFileIDs = [focus.fileID]
        await fileListModel.selectFiles([focus.fileID])
        fileListModel.presentSelectedFileTagSuggestions(source: focus.source)
        onPendingTagSuggestionFocusConsumed(focus)
    }

    private var selectedListTitle: String {
        selectedSidebarRow.displayName
    }

    var selectedSidebarRow: RepositorySidebarRowSnapshot {
        repositoryTree.sidebarRow(id: selectedSidebarID) ??
            repositoryTree.sidebarRows.first ??
            RepositorySidebarRowSnapshot(node: repositoryTree, depth: 0)
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

}
