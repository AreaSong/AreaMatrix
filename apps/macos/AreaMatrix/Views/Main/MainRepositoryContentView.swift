import AreaMatrixFeatureIngestion
import AreaMatrixFeatureLibrary
import AreaMatrixUIFoundation
import SwiftUI
import UniformTypeIdentifiers

struct MainRepositoryContentView: View {
    @EnvironmentObject var localizer: AppLocalizer
    @ObservedObject var commandRouter: AppCommandRouter
    @State var session: RepositorySession
    let opening: RepositoryOpeningResult
    let state: AreaMatrixFeatureLibrary.MainRepositoryContentState
    let onImport: () -> Void
    let onDropImport: ([URL], ImportEntryDestination) -> Void
    let onOpenSettings: () -> Void
    let onOpenAISettings: () -> Void
    let onOpenRepository: () -> Void
    let onOpenHelp: () -> Void
    let onOpenImportConflictBatch: (ImportConflictBatchRoute) -> Void
    let mainListErrorRecoveryActions: MainListErrorRecoveryActions
    let onShowInFinder: (String) -> Void
    let onCopyPath: (String) -> Void
    let onCopyPaths: ([String]) -> Void
    let onOpenNoteFile: (String) -> Void
    let onOpenChangeCategoryPermissionRecovery: () -> Void
    let treeLister: any CoreRepositoryTreeListing
    let savedSearchStore: any CoreSavedSearchCRUD
    let batchRenamer: any CoreBatchRenaming
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let errorMapper: any CoreErrorMapping
    let aiDependencies: AIFeatureDependencies
    let fileActionsDependencies: FileActionsFeatureDependencies
    let settingsDependencies: SettingsFeatureDependencies
    let syncConflictsDependencies: SyncConflictsFeatureDependencies
    let externalSyncWindows: [MainExternalSyncWindow]
    let onExternalSyncWindowCompleted: (MainExternalSyncWindow) -> Void
    let pendingTagSuggestionFocus: TagSuggestionPresentationRequest?
    let onPendingTagSuggestionFocusConsumed: (TagSuggestionPresentationRequest) -> Void
    let importProgressPresentation: ImportProgressListPresentation
    @StateObject var fileListModel: MainFileListModel
    @StateObject var searchModel: SearchModel
    @StateObject var detailTagModel: DetailTagModel
    @StateObject var syncConflictCoordinator: SyncConflictCoordinator
    @StateObject var fileActionCoordinator: FileActionCoordinator
    @StateObject var commandPaletteModel: CommandPaletteModel
    @StateObject var syncConflictEntryModel: SyncConflictEntryModel
    @State var repositoryTree: RepositoryTreeNodeSnapshot
    @StateObject var sidebarSelectionModel: MainSidebarSelectionModel
    @StateObject var selectionModel: MainSelectionModel
    @StateObject var searchInputModel: MainRepositorySearchInputModel
    @State var importProgressSelectionState = ImportProgressListSelectionState()
    @FocusState var isSearchFieldFocused: Bool
    @StateObject var dropPreviewModel: ImportDropPreviewModel
    @StateObject var detailNoteModel: DetailNoteModel
    @StateObject var summaryExitController: AISummaryEditorExitController
    @State var tableSortOrder: [KeyPathComparator<FileEntrySnapshot>] = [
        .init(\FileEntrySnapshot.importedAt, order: .reverse)
    ]
    @State var observedInterfaceLocaleIdentifier: String?

    @MainActor
    init(
        session: RepositorySession,
        opening: RepositoryOpeningResult,
        state: AreaMatrixFeatureLibrary.MainRepositoryContentState,
        assembly: MainRepositoryContentAssembly,
        commandRouter: AppCommandRouter,
        onImport: @escaping () -> Void,
        onDropImport: @escaping ([URL], ImportEntryDestination) -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onOpenAISettings: @escaping () -> Void = {},
        onOpenRepository: @escaping () -> Void = {},
        onOpenHelp: @escaping () -> Void = {},
        onOpenImportConflictBatch: @escaping (ImportConflictBatchRoute) -> Void = { _ in },
        mainListErrorRecoveryActions: MainListErrorRecoveryActions = .none,
        onShowInFinder: @escaping (String) -> Void = { _ in },
        onCopyPath: @escaping (String) -> Void = { _ in },
        onCopyPaths: @escaping ([String]) -> Void = { _ in },
        onOpenNoteFile: @escaping (String) -> Void = { _ in },
        onOpenChangeCategoryPermissionRecovery: @escaping () -> Void = {},
        externalSyncWindows: [MainExternalSyncWindow] = [],
        onExternalSyncWindowCompleted: @escaping (MainExternalSyncWindow) -> Void = { _ in },
        pendingTagSuggestionFocus: TagSuggestionPresentationRequest? = nil,
        onPendingTagSuggestionFocusConsumed: @escaping (TagSuggestionPresentationRequest) -> Void = { _ in },
        importProgressPresentation: ImportProgressListPresentation = .empty
    ) {
        _session = State(initialValue: session); self.opening = opening; self.state = state
        _commandRouter = ObservedObject(wrappedValue: commandRouter)
        self.onImport = onImport; self.onDropImport = onDropImport
        self.onOpenSettings = onOpenSettings; self.onOpenAISettings = onOpenAISettings
        self.onOpenRepository = onOpenRepository; self.onOpenHelp = onOpenHelp
        self.onOpenImportConflictBatch = onOpenImportConflictBatch
        self.mainListErrorRecoveryActions = mainListErrorRecoveryActions
        self.onShowInFinder = onShowInFinder; self.onCopyPath = onCopyPath; self.onCopyPaths = onCopyPaths
        self.onOpenNoteFile = onOpenNoteFile
        self.onOpenChangeCategoryPermissionRecovery = onOpenChangeCategoryPermissionRecovery
        treeLister = assembly.treeLister
        savedSearchStore = assembly.savedSearchStore
        batchRenamer = assembly.batchRenamer
        systemCapabilityChecker = assembly.systemCapabilityChecker
        errorMapper = assembly.errorMapper
        aiDependencies = assembly.aiDependencies
        fileActionsDependencies = assembly.fileActionsDependencies
        settingsDependencies = assembly.settingsDependencies
        syncConflictsDependencies = assembly.syncConflictsDependencies
        self.externalSyncWindows = externalSyncWindows
        self.onExternalSyncWindowCompleted = onExternalSyncWindowCompleted
        self.pendingTagSuggestionFocus = pendingTagSuggestionFocus
        self.onPendingTagSuggestionFocusConsumed = onPendingTagSuggestionFocusConsumed
        self.importProgressPresentation = importProgressPresentation
        _dropPreviewModel = StateObject(wrappedValue: assembly.makeDropPreviewModel())
        _detailNoteModel = StateObject(wrappedValue: assembly.makeDetailNoteModel())
        _summaryExitController = StateObject(wrappedValue: assembly.makeSummaryExitController())
        _selectionModel = StateObject(wrappedValue: MainSelectionModel())
        let fileListModel = assembly.makeFileListModel()
        _fileListModel = StateObject(wrappedValue: fileListModel)
        _searchModel = StateObject(wrappedValue: fileListModel.searchModel)
        _detailTagModel = StateObject(wrappedValue: fileListModel.detailTagModel)
        _syncConflictCoordinator = StateObject(wrappedValue: fileListModel.syncConflictCoordinator)
        _fileActionCoordinator = StateObject(wrappedValue: fileListModel.fileActionCoordinator)
        _commandPaletteModel = StateObject(wrappedValue: assembly.makeCommandPaletteModel())
        _syncConflictEntryModel = StateObject(wrappedValue: assembly.makeSyncConflictEntryModel())
        let defaultSidebarID = Self.defaultSelectedSidebarID(from: opening.tree.sidebarRows)
        _repositoryTree = State(initialValue: opening.tree)
        _sidebarSelectionModel = StateObject(
            wrappedValue: MainSidebarSelectionModel(selectedID: defaultSidebarID)
        )
        let defaultRow = opening.tree.sidebarRows.first { $0.id == defaultSidebarID }
        let searchInputModel = MainRepositorySearchInputModel()
        searchInputModel.searchScope = defaultRow?.categoryForFileList == nil ? .all : .current
        _searchInputModel = StateObject(wrappedValue: searchInputModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            MainRepositoryToolbar(
                repoPath: opening.config.repoPath,
                isReadOnly: opening.isReadOnly,
                isEmpty: state == .empty,
                filterText: $searchInputModel.filterText,
                searchMode: $searchInputModel.searchMode,
                searchScope: $searchInputModel.searchScope,
                searchSort: $searchInputModel.searchSort,
                isSearchFieldFocused: $isSearchFieldFocused,
                searchFiltersButton: AnyView(searchFiltersButton),
                onImport: onImport,
                onOpenSettings: onOpenSettings,
                onSearchExit: handleSearchEscape,
                onSearchSubmit: { searchModel.enterSearch(context: .toolbar) },
                onCommandFind: beginCommandFindSearch,
                onCommandPalette: toggleCommandPalette,
                onOpenUndoHistory: openUndoHistoryFromToolbar
            )
            Divider()
            if let error = fileListModel.externalSyncErrorMapping {
                MainExternalSyncErrorBanner(
                    error: error,
                    fileListModel: fileListModel,
                    recoveryActions: mainListErrorRecoveryActions
                )
            }
            HStack(spacing: 0) {
                sidebar
                    .areaMatrixWorkspaceRegionShell(cornerRadius: 0)
                Divider()
                listPane
                Divider()
                detailPane
                    .areaMatrixWorkspaceRegionShell(cornerRadius: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .center) {
            MainRepositoryDropOverlay(presentation: dropPreviewModel.presentation)
        }
        .overlay(alignment: .bottomTrailing) { batchTagUndoToastOverlay.padding(18) }
        .mainRepositoryContentLifecycle(self)
        .animation(.areaMatrixSceneFlow, value: state)
    }

    static func defaultSelectedSidebarID(from rows: [RepositorySidebarRowSnapshot]) -> String {
        rows.first { $0.node.slug == "inbox" }?.id ?? rows.first?.id ?? "__root__"
    }

    var filterText: String {
        get { searchInputModel.filterText }
        nonmutating set { searchInputModel.filterText = newValue }
    }

    var searchScope: SearchScopeSnapshot {
        get { searchInputModel.searchScope }
        nonmutating set { searchInputModel.searchScope = newValue }
    }

    var searchMode: SearchModeSnapshot {
        get { searchInputModel.searchMode }
        nonmutating set { searchInputModel.searchMode = newValue }
    }

    var searchSort: SearchSortSnapshot {
        get { searchInputModel.searchSort }
        nonmutating set { searchInputModel.searchSort = newValue }
    }

    var searchFilters: SearchFilterStateSnapshot {
        get { searchInputModel.searchFilters }
        nonmutating set { searchInputModel.searchFilters = newValue }
    }

    var selectedSidebarID: String {
        get { sidebarSelectionModel.selectedID }
        nonmutating set { sidebarSelectionModel.selectedID = newValue }
    }

    var selectedSidebarIDBinding: Binding<String> {
        Binding(
            get: { sidebarSelectionModel.selectedID },
            set: { sidebarSelectionModel.selectedID = $0 }
        )
    }

    var selectedSidebarRow: RepositorySidebarRowSnapshot {
        repositoryTree.sidebarRow(id: selectedSidebarID) ??
            repositoryTree.sidebarRows.first ??
            RepositorySidebarRowSnapshot(node: repositoryTree, depth: 0)
    }

    var mainListPresentation: MainListPresentationProjection {
        MainListPresentationProjection.make(
            files: fileListModel.files,
            sidebarRow: selectedSidebarRow,
            filterText: filterText,
            sortOrder: tableSortOrder,
            search: MainListSearchPresentation(
                isActive: searchModel.searchState.isActive,
                resultCount: searchModel.searchState.page?.totalCount
            )
        )
    }

    func searchMatchText(for fileID: Int64) -> String {
        guard let result = searchModel.searchState.page?.results.first(where: { $0.file.id == fileID }) else {
            return "-"
        }
        if let semantic = searchModel.searchState.page?.semanticPage?.result(for: fileID) {
            return semanticMatchText(semantic)
        }
        if let noteSnippet = result.noteSnippet, !noteSnippet.isEmpty {
            return L10n.format("mainList.searchMatch.note", noteSnippet)
        }
        guard let match = result.matches.first else { return L10n.string("Match") }
        return L10n.format(
            "mainList.searchMatch.summary",
            match.kindDisplayName,
            match.fieldDisplayName,
            match.snippet
        )
    }
}
