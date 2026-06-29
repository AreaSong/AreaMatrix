import SwiftUI
import UniformTypeIdentifiers

enum MainRepositoryContentState: Equatable { case empty, list }
struct MainRepositoryContentView: View {
    let opening: RepositoryOpeningResult
    let state: MainRepositoryContentState
    let onImport: () -> Void
    let onDropImport: ([URL], ImportEntryDestination) -> Void
    let onOpenSettings: () -> Void
    let onOpenAISettings: () -> Void
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
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let errorMapper: any CoreErrorMapping
    let externalCreatedEvent: MainExternalCreatedFileEvent?
    let onExternalCreatedEventHandled: (MainExternalCreatedFileEvent) -> Void
    let pendingTagSuggestionFocus: TagSuggestionPresentationRequest?
    let onPendingTagSuggestionFocusConsumed: (TagSuggestionPresentationRequest) -> Void
    let importProgressItems: [ImportBatchProgressSnapshot.Item]
    @StateObject var fileListModel: MainFileListModel
    @StateObject var syncConflictEntryModel: SyncConflictEntryModel
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
    @State var searchMode: SearchModeSnapshot = .normal
    @State var searchSort: SearchSortSnapshot = .newestImported
    @State var searchFilters: SearchFilterStateSnapshot = .empty
    @State var isSearchFiltersPresented = false
    @State var isSidebarTagsFilterPresented = false
    @State var isSemanticIndexConfirmationPresented = false
    @State var semanticPrivacyRuleRoute: AIClassificationPrivacyRuleRoute?
    @State var semanticCallLogRoute: SemanticSearchCallLogRoute?
    @State var savedSearchesBySidebarID: [String: SavedSearchSnapshot] = [:]
    @State var smartListLoadError: CoreErrorMappingSnapshot?
    @State var smartListManagementRoute: SmartListManagementRoute?
    @State var pendingSyncConflictReviewRoute: SyncConflictReviewRoute?
    @FocusState var isSearchFieldFocused: Bool
    @StateObject var dropPreviewModel: ImportDropPreviewModel
    @StateObject var detailNoteModel: DetailNoteModel
    @StateObject var summaryExitController: AISummaryEditorExitController
    @State var tableSortOrder: [KeyPathComparator<FileEntrySnapshot>] = [
        .init(\FileEntrySnapshot.importedAt, order: .reverse)
    ]
    @State var summarySelectionExitState = AISummarySelectionExitState()

    // swiftlint:disable:next function_body_length
    init(
        opening: RepositoryOpeningResult,
        state: MainRepositoryContentState,
        onImport: @escaping () -> Void,
        onDropImport: @escaping ([URL], ImportEntryDestination) -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onOpenAISettings: @escaping () -> Void = {},
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
        semanticSearching: any CoreSemanticSearching = CoreBridge(),
        searchFiltering: any CoreSearchFiltering = CoreBridge(),
        commandIndexer: any CoreCommandIndexing = CoreBridge(),
        fileCategoryMover: any CoreFileCategoryMoving = CoreBridge(),
        batchDeleter: any CoreBatchDeleting = CoreBridge(),
        batchCategoryChanger: any CoreBatchCategoryChanging = CoreBridge(),
        batchRenamer: any CoreBatchRenaming = CoreBridge(),
        systemCapabilityChecker: any OnboardingSystemCapabilityChecking = LocalOnboardingCapabilities(),
        syncConflictDetector: any CoreSyncConflictDetecting = CoreBridge(),
        iCloudConflictResolver: any ICloudConflictResolving = CoreBridge(),
        tagStore: any CoreTagCRUD = CoreBridge(),
        aiPrivacyRules: any CoreAIPrivacyEvaluating = CoreBridge(),
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
        self.onOpenSettings = onOpenSettings; self.onOpenAISettings = onOpenAISettings
        self.onOpenRepository = onOpenRepository; self.onOpenHelp = onOpenHelp
        self.onOpenImportConflictBatch = onOpenImportConflictBatch
        self.onRetryCurrentList = onRetryCurrentList; self.onCollectDiagnostics = onCollectDiagnostics
        self.onShowInFinder = onShowInFinder; self.onCopyPath = onCopyPath; self.onCopyPaths = onCopyPaths
        self.onOpenNoteFile = onOpenNoteFile
        self.onOpenChangeCategoryPermissionRecovery = onOpenChangeCategoryPermissionRecovery
        self.treeLister = treeLister; self.savedSearchStore = savedSearchStore; self.batchRenamer = batchRenamer
        self.systemCapabilityChecker = systemCapabilityChecker
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
        _summaryExitController = StateObject(wrappedValue: AISummaryEditorExitController())
        _fileListModel = StateObject(wrappedValue: MainFileListModel(
            opening: opening,
            fileLister: fileLister,
            fileDetailer: fileDetailer,
            searchQuerying: searchQuerying,
            semanticSearching: semanticSearching,
            searchFiltering: searchFiltering,
            commandIndexer: commandIndexer,
            fileCategoryMover: fileCategoryMover,
            batchDeleter: batchDeleter,
            batchCategoryChanger: batchCategoryChanger,
            iCloudConflictResolver: iCloudConflictResolver,
            tagStore: tagStore,
            aiPrivacyRules: aiPrivacyRules,
            undoActionStore: undoActionStore,
            redoActionStore: redoActionStore,
            changeLogLister: changeLogLister,
            externalChangesSyncer: externalChangesSyncer,
            errorMapper: errorMapper,
            diagnosticsCollector: diagnosticsCollector
        ))
        _syncConflictEntryModel = StateObject(wrappedValue: SyncConflictEntryModel(
            repoPath: opening.config.repoPath,
            conflictDetector: syncConflictDetector,
            errorMapper: errorMapper
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
        .overlay(alignment: .center) { dropOverlay }
        .overlay(alignment: .bottomTrailing) { batchTagUndoToastOverlay.padding(18) }
        .mainRepositoryContentLifecycle(self)
    }

    static func defaultSelectedSidebarID(from rows: [RepositorySidebarRowSnapshot]) -> String {
        rows.first { $0.node.slug == "inbox" }?.id ?? rows.first?.id ?? "__root__"
    }

    var selectedSidebarRow: RepositorySidebarRowSnapshot {
        repositoryTree.sidebarRow(id: selectedSidebarID) ??
            repositoryTree.sidebarRows.first ??
            RepositorySidebarRowSnapshot(node: repositoryTree, depth: 0)
    }
}
