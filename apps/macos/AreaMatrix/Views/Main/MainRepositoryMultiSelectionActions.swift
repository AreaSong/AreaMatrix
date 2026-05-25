import SwiftUI

struct MainRepositoryMultiSelectionActions: View {
    let selection: MainFileSelectionState
    let summary: MultiSelectionDetailSummary
    let detailErrorMapping: CoreErrorMappingSnapshot?
    let repoPath: String
    let categoryRows: [RepositorySidebarRowSnapshot]
    let batchTagStore: any CoreTagCRUD
    let batchTagUndoStore: any CoreUndoActionLogging
    let batchTagErrorMapper: any CoreErrorMapping
    let batchDeleter: any CoreBatchDeleting
    let batchCategoryChanger: any CoreBatchCategoryChanging
    let batchRenamer: any CoreBatchRenaming
    let tagActions: MainRepositoryDetailPaneTagActions
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    let onCopyPaths: ([String]) -> Void
    let onRetrySelectedFileDetail: () -> Void
    let onRefreshChangeLog: () -> Void
    let onBatchCategoryApplied: (BatchCategoryChangeReportSnapshot) -> Void
    let onBatchDeleteApplied: (BatchDeleteReportSnapshot) -> Void
    let onBatchRenameApplied: (BatchRenameReportSnapshot) -> Void
    let onBatchCategoryCreateNewCategory: (BatchChangeCategoryNewCategoryHandoff) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Show in Finder") {}
                .disabled(true)
                .help("Open one file at a time")
            Text("Open one file at a time")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Copy Paths") {
                onCopyPaths(summary.paths)
            }
            .disabled(summary.paths.isEmpty)
            BatchAddTagsTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedCount: summary.selectedCount,
                disabledReason: batchAddTagsDisabledReason,
                tagStore: batchTagStore,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onRefreshSelection: onRetrySelectedFileDetail,
                onRefreshChangeLog: onRefreshChangeLog,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            BatchChangeCategoryTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchChangeCategoryDisabledReason,
                categoryRows: categoryRows,
                changer: batchCategoryChanger,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchCategoryApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange,
                onCreateNewCategory: onBatchCategoryCreateNewCategory
            )
            BatchRenameTrigger(
                repoPath: repoPath,
                fileIDs: BatchRenameEntryPolicy.fileIDsForPreview(summary: summary),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchRenameDisabledReason,
                renamer: batchRenamer,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchRenameApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            BatchDeleteTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchDeleteDisabledReason,
                deleter: batchDeleter,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchDeleteApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            if detailErrorMapping != nil {
                Button("Retry Metadata", action: onRetrySelectedFileDetail)
            }
        }
    }

    private var batchAddTagsDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if let reason = summary.files.compactMap({ writeActionDisabledReason($0.id) }).first {
            return reason.rawValue
        }
        return nil
    }

    private var batchChangeCategoryDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if let reason = summary.files.compactMap({ writeActionDisabledReason($0.id) }).first {
            return reason.rawValue
        }
        return nil
    }

    private var batchDeleteDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if summary.isUpdating { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        if let reason = summary.files.compactMap({ writeActionDisabledReason($0.id) }).first {
            return reason.rawValue
        }
        return nil
    }

    private var batchRenameDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if summary.isUpdating { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        if let reason = summary.files.compactMap({ writeActionDisabledReason($0.id) }).first {
            return reason.rawValue
        }
        return nil
    }
}

extension MainRepositoryContentView {
    func commandPaletteRouteView() -> some View {
        SearchCommandPaletteRouteView(
            query: $fileListModel.commandPaletteQuery,
            state: visibleCommandPaletteState,
            smartLists: state == .list ? sortedSavedSearches : [],
            onLoad: loadCommandPaletteIndex,
            onOpenSmartList: openCommandPaletteSmartList,
            onExecuteTarget: executeCommandPaletteTarget,
            onClose: closeCommandPalette
        )
    }

    func loadCommandPaletteIndex() {
        guard state == .list else {
            fileListModel.commandPaletteState = .loaded(.noRepositoryCommands())
            return
        }
        Task { await loadCommandPaletteIndexFromCurrentState() }
    }

    func loadCommandPaletteIndexFromCurrentState() async {
        await fileListModel.loadCommandIndex(
            query: fileListModel.commandPaletteQuery,
            selectedFileIDs: selectedFileIDs,
            currentPath: selectedSidebarRow.pathFilterPrefix
        )
    }

    func openCommandPalette() {
        shouldRestoreSearchFocusAfterCommandPalette = isSearchFieldFocused
        isSearchFieldFocused = false
        fileListModel.commandPaletteQuery = ""
        if state == .list {
            fileListModel.openCommandPaletteForSearch()
        } else {
            fileListModel.pendingSearchDestination = .commandPalette
            fileListModel.commandPaletteState = .loaded(.noRepositoryCommands())
        }
    }

    func toggleCommandPalette() {
        if fileListModel.pendingSearchDestination == .commandPalette {
            closeCommandPalette()
            return
        }
        openCommandPalette()
    }

    func closeCommandPalette() {
        fileListModel.commandPaletteQuery = ""
        fileListModel.clearCommandPaletteState()
        fileListModel.clearPendingSearchDestination()
        isSearchFieldFocused = shouldRestoreSearchFocusAfterCommandPalette
        shouldRestoreSearchFocusAfterCommandPalette = false
    }

    func executeCommandPaletteTarget(_ target: CommandTargetSnapshot) {
        guard target.isExecutable else { return }
        switch target.executionRoute {
        case .importFiles:
            closeCommandPalette()
            onImport()
        case .settings:
            closeCommandPalette()
            onOpenSettings()
        case .beginSearch:
            closeCommandPalette()
            beginCommandFindSearch()
        case .batchAddTags:
            pendingBatchAddTagsRoute = commandPaletteBatchAddTagsRoute()
            closeCommandPalette()
        case .batchChangeCategory:
            pendingBatchChangeCategoryRoute = commandPaletteBatchChangeCategoryRoute()
            closeCommandPalette()
        case .batchDelete:
            pendingBatchDeleteRoute = commandPaletteBatchDeleteRoute()
            closeCommandPalette()
        case .batchRename:
            pendingBatchRenameRoute = commandPaletteBatchRenameRoute()
            closeCommandPalette()
        case let .runSmartList(savedSearchID):
            executeCommandPaletteSmartList(savedSearchID: savedSearchID)
        case let .focusFile(fileID):
            selectedFileIDs = [fileID]
            closeCommandPalette()
            Task { await fileListModel.selectFiles([fileID]) }
        case .openRepository:
            closeCommandPalette()
            onOpenRepository()
        case .help:
            closeCommandPalette()
            onOpenHelp()
        case .classifierRuleEditor:
            fileListModel.clearCommandPaletteState()
            fileListModel.commandPaletteQuery = ""
            fileListModel.pendingSearchDestination = .classifierRuleEditor(context: nil)
        case let .linkedPage(route):
            if routeLinkedCommandPaletteTarget(route) { closeCommandPalette() }
        case .unsupported:
            return
        }
    }

    var visibleCommandPaletteState: CommandPaletteLoadState {
        if state == .empty, fileListModel.commandPaletteState.snapshot == nil {
            return .loaded(.noRepositoryCommands())
        }
        return fileListModel.commandPaletteState
    }

    func routeLinkedCommandPaletteTarget(_ route: CommandPaletteLinkedPageRoute) -> Bool {
        switch route {
        case .redo:
            pendingUndoHistoryRequest = UndoHistoryActionLog.redoShortcutRequest(
                state: batchTagUndoState,
                failure: batchTagActionLogRefreshFailure
            )
            return true
        case .importConflictBatch:
            guard let route = activeImportConflictBatchRoute(source: route) else {
                fileListModel.commandPaletteState = .failed(
                    commandPaletteContext(),
                    fileListModel.commandPaletteState.snapshot ?? .commandRegistryRecovery(
                        query: fileListModel.commandPaletteQuery
                    ),
                    route.blockedMapping
                )
                return false
            }
            pendingImportConflictBatchRoute = route
            return true
        case .classifierImpactPreview, .tagSuggestions:
            fileListModel.commandPaletteState = .failed(
                commandPaletteContext(),
                fileListModel.commandPaletteState.snapshot ?? .commandRegistryRecovery(
                    query: fileListModel.commandPaletteQuery
                ),
                route.blockedMapping
            )
            return false
        }
    }

    private func activeImportConflictBatchRoute(
        source: CommandPaletteLinkedPageRoute
    ) -> ImportConflictBatchRoute? {
        ImportConflictBatchRoute(
            metadata: importProgressItems.compactMap(\.importConflictBatch),
            source: source
        )
    }

    private func commandPaletteContext() -> CommandIndexContext {
        CommandIndexContext.commandPalette(
            query: fileListModel.commandPaletteQuery,
            selectedFileIDs: selectedFileIDs,
            currentPath: selectedSidebarRow.pathFilterPrefix
        )
    }

    private func openCommandPaletteSmartList(_ saved: SavedSearchSnapshot) {
        closeCommandPalette()
        selectedSidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        selectedFileIDs = []
        Task { await restoreSavedSearch(saved) }
    }

    private func executeCommandPaletteSmartList(savedSearchID: Int64) {
        guard let saved = CommandPaletteSmartListRouting.savedSearch(
            savedSearchID: savedSearchID,
            in: sortedSavedSearches
        ) else { return }
        openCommandPaletteSmartList(saved)
    }

    func openBatchChangeCategoryRoute(_ ids: Set<Int64>, source: BatchChangeCategoryRouteSource) {
        let selectedFiles = filesForBatchChangeCategory(ids)
        pendingBatchChangeCategoryRoute = BatchChangeCategoryRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchChangeCategoryDisabledReason(for: selectedFiles)
        )
    }

    func openBatchDeleteRoute(_ ids: Set<Int64>, source: BatchDeleteRouteSource) {
        let selectedFiles = filesForBatchDelete(ids)
        pendingBatchDeleteRoute = BatchDeleteRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchDeleteDisabledReason(for: selectedFiles)
        )
    }

    func openBatchRenameRoute(_ ids: Set<Int64>, source: BatchRenameRouteSource) {
        let selectedFiles = filesForBatchRename(ids)
        pendingBatchRenameRoute = BatchRenameRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchRenameDisabledReason(for: selectedFiles)
        )
    }

    func commandPaletteBatchChangeCategoryRoute() -> BatchChangeCategoryRoute {
        let selectedFiles = filesForBatchChangeCategory(selectedFileIDs)
        return BatchChangeCategoryRoute(
            source: .commandPalette,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchChangeCategoryDisabledReason(for: selectedFiles)
        )
    }

    private func filesForBatchChangeCategory(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { ids.contains($0.id) }
    }

    func filesForBatchDelete(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { ids.contains($0.id) }
    }

    func filesForBatchRename(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { ids.contains($0.id) }
    }

    private func batchChangeCategoryDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchChangeCategoryEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    func batchDeleteDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchDeleteEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    func batchRenameDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchRenameEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    func batchRenameRoutingSheet(_ route: BatchRenameRoute) -> some View {
        BatchRenameSheet(
            repoPath: opening.config.repoPath,
            fileIDs: route.fileIDs,
            selectedFiles: route.selectedFiles,
            selectedCount: route.selectedCount,
            disabledReason: route.disabledReason,
            renamer: batchRenamer,
            undoStore: fileListModel.undoActionStore,
            errorMapper: fileListModel.errorMapper,
            onApplied: applyBatchRenameResult,
            onUndoStateChange: updateBatchTagUndoState,
            onClose: { pendingBatchRenameRoute = nil }
        )
    }

    func applyBatchRenameResult(_ report: BatchRenameReportSnapshot) {
        Task {
            if !report.updatedFiles.isEmpty {
                fileListModel.files = fileListModel.files.map { current in
                    report.updatedFiles.first { $0.id == current.id } ?? current
                }
            }
            await fileListModel.retryCurrentCategory()
            await fileListModel.retrySelectedFileDetail()
        }
    }
}

enum CommandPaletteBatchRouteBuilder {
    static func batchDeleteRoute(
        selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> BatchDeleteRoute {
        let files = selectedFiles(selectedFileIDs, visibleFiles: visibleFiles)
        return BatchDeleteRoute(
            source: .commandPalette,
            fileIDs: files.map(\.id),
            selectedFiles: files,
            selectedCount: files.count,
            disabledReason: BatchDeleteEntryPolicy.disabledReason(
                selectedFiles: files,
                isReadOnly: isReadOnly,
                isLoading: isLoading,
                writeLockedFileIDs: writeLockedFileIDs
            )
        )
    }

    static func batchRenameRoute(
        selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> BatchRenameRoute {
        let files = selectedFiles(selectedFileIDs, visibleFiles: visibleFiles)
        return BatchRenameRoute(
            source: .commandPalette,
            fileIDs: files.map(\.id),
            selectedFiles: files,
            selectedCount: files.count,
            disabledReason: BatchRenameEntryPolicy.disabledReason(
                selectedFiles: files,
                isReadOnly: isReadOnly,
                isLoading: isLoading,
                writeLockedFileIDs: writeLockedFileIDs
            )
        )
    }

    private static func selectedFiles(
        _ selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot]
    ) -> [FileEntrySnapshot] {
        visibleFiles.filter { selectedFileIDs.contains($0.id) }
    }
}

enum CommandPaletteSelectionRouting {
    static func nextSelectedID(
        currentID: String?,
        targets: [CommandTargetSnapshot],
        offset: Int
    ) -> String? {
        let executableTargets = targets.filter(\.isExecutable)
        guard !executableTargets.isEmpty else { return nil }
        guard let currentID,
              let currentIndex = executableTargets.firstIndex(where: { $0.id == currentID })
        else {
            return executableTargets.first?.id
        }

        let nextIndex = wrappedIndex(currentIndex + offset, count: executableTargets.count)
        return executableTargets[nextIndex].id
    }

    private static func wrappedIndex(_ index: Int, count: Int) -> Int {
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }
}
