import SwiftUI

extension MainRepositoryContentView {
    var actionDestinationBinding: Binding<MainFileActionDestination?> {
        Binding(
            get: { fileListModel.pendingActionDestination },
            set: { value in
                if value == nil {
                    fileListModel.clearPendingActionDestination()
                }
            }
        )
    }

    func actionRoutingSheet(_ destination: MainFileActionDestination) -> some View {
        MainFileActionRoutingSheet(
            destination: destination,
            file: file(for: destination.fileID),
            candidateFiles: fileListModel.files,
            categoryRows: repositoryTree.sidebarRows,
            renameState: fileListModel.renameState,
            deleteState: fileListModel.deleteState,
            changeCategoryState: fileListModel.changeCategoryState,
            iCloudConflictResolutionState: fileListModel.iCloudConflictResolutionState,
            iCloudConflictResolutionCapability: fileListModel.iCloudConflictResolver.iCloudConflictResolutionCapability,
            repoPath: opening.config.repoPath,
            isTrashAvailable: OnboardingModel.isSystemTrashAvailable(),
            iCloudConflictPathValidator: CoreBridge(),
            iCloudConflictErrorMapper: fileListModel.errorMapper,
            onDismiss: fileListModel.clearPendingActionDestination,
            onRename: submitRename,
            onShowExistingFile: showExistingFile,
            onPreviewChangeCategory: previewChangeCategory,
            onChangeCategory: submitChangeCategory,
            onRenameFirstFromChangeCategory: { fileID, targetCategory in
                fileListModel.beginRenameFromChangeCategory(fileID: fileID, targetCategory: targetCategory)
            },
            onOpenChangeCategoryPermissionRecovery: onOpenChangeCategoryPermissionRecovery,
            onDelete: submitDelete,
            onApplyICloudConflict: applyICloudConflict,
            onCollectDiagnostics: { Task { await fileListModel.collectCurrentListDiagnostics() } }
        )
    }

    var searchDestinationBinding: Binding<MainSearchDestination?> {
        Binding(
            get: {
                guard fileListModel.pendingSearchDestination?.isSheetRoute == true else { return nil }
                return fileListModel.pendingSearchDestination
            },
            set: { value in
                if value == nil {
                    fileListModel.clearPendingSearchDestination()
                }
            }
        )
    }

    @ViewBuilder
    func searchRoutingSheet(_ destination: MainSearchDestination) -> some View {
        switch destination {
        case let .savedSearchSheet(request):
            SavedSearchSheetRouteView(
                request: request,
                repoPath: opening.config.repoPath,
                resultCountState: savedSearchResultCountState,
                savedSearchStore: savedSearchStore,
                errorMapper: errorMapper,
                onCancel: fileListModel.clearPendingSearchDestination,
                onSaved: saveAndCloseSearchSheet,
                onEditFilters: {
                    fileListModel.clearPendingSearchDestination()
                    isSearchFiltersPresented = true
                }
            )
        case let .indexingStatus(request):
            SearchIndexingStatusRouteView(
                request: request,
                indexStatus: fileListModel.searchState.indexStatus,
                onRetry: { Task { await fileListModel.retrySearch() } },
                onClose: fileListModel.clearPendingSearchDestination
            )
        case .commandPalette:
            SearchCommandPaletteRouteView(
                query: filterText,
                batchAddTagsRoute: commandPaletteBatchAddTagsRoute(),
                batchChangeCategoryRoute: commandPaletteBatchChangeCategoryRoute(),
                onOpenBatchAddTags: { route in
                    pendingBatchAddTagsRoute = route
                    fileListModel.clearPendingSearchDestination()
                },
                onOpenBatchChangeCategory: { route in
                    pendingBatchChangeCategoryRoute = route
                    fileListModel.clearPendingSearchDestination()
                },
                onClose: fileListModel.clearPendingSearchDestination
            )
        case .classifierRuleEditor:
            ClassifierSettingsPane(repoPath: opening.config.repoPath)
        case .searchEmpty, .queryError:
            EmptyView()
        }
    }

    func smartListManagementSheet(_ route: SmartListManagementRoute) -> some View {
        SmartListManagementSheet(
            route: route,
            repoPath: opening.config.repoPath,
            savedSearches: sortedSavedSearches,
            resultCountState: savedSearchResultCountState,
            savedSearchStore: savedSearchStore,
            searchQuerying: fileListModel.searchQuerying,
            errorMapper: errorMapper,
            onCancel: { cancelSmartListManagement(route) },
            onSaved: applyManagedSmartList,
            onDeleted: deleteManagedSmartList,
            onEditFilters: beginSmartListFilterEditing
        )
    }

    private func file(for fileID: Int64) -> FileEntrySnapshot? {
        fileListModel.files.first { $0.id == fileID } ??
            fileListModel.selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
    }

    private func submitRename(fileID: Int64, newName: String) {
        Task {
            let didRename = await fileListModel.submitRename(fileID: fileID, newName: newName)
            if didRename { refreshLatestUndoToast() }
        }
    }

    private func showExistingFile(fileID: Int64) {
        selectedFileIDs = [fileID]
        fileListModel.clearPendingActionDestination()
        Task { await fileListModel.selectFiles([fileID]) }
    }

    private var savedSearchResultCountState: SavedSearchResultCountState {
        switch fileListModel.searchState {
        case let .loaded(_, page):
            .loaded(page.totalCount)
        case .failed:
            .failed
        case .idle, .loading:
            .loading
        }
    }

    private func saveAndCloseSearchSheet(_ saved: SavedSearchSnapshot) {
        selectSavedSearch(saved)
        fileListModel.clearPendingSearchDestination()
    }

    private func selectSavedSearch(_ saved: SavedSearchSnapshot) {
        applySavedSearchToSidebar(saved)
        selectAppliedSavedSearch(saved)
    }

    var selectedSmartList: SavedSearchSnapshot? {
        savedSearchesBySidebarID[selectedSidebarID]
    }

    func openSelectedSmartListEditor() {
        guard let saved = selectedSmartList else { return }
        openSmartListManagement(.editQuery, saved: saved)
    }

    private func applyManagedSmartList(_ saved: SavedSearchSnapshot) {
        fileListModel.cancelSmartListFilterDraft()
        applySavedSearchToSidebar(saved)
        if selectedSidebarID == RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id) {
            Task { await restoreSavedSearch(saved) }
        }
        smartListManagementRoute = nil
    }

    private func applySavedSearchToSidebar(_ saved: SavedSearchSnapshot) {
        let sidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        savedSearchesBySidebarID[sidebarID] = saved
        rebuildSmartListSidebar()
    }

    private func selectAppliedSavedSearch(_ saved: SavedSearchSnapshot) {
        filterText = saved.query.query
        searchScope = saved.query.scope
        searchSort = saved.query.sort
        searchFilters = saved.query.filter
        fileListModel.cancelSmartListFilterDraft()
        fileListModel.enterSearch(context: .smartList(id: saved.id, name: saved.name))
        selectedSidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        selectedFileIDs = []
    }

    func restoreSelectedSavedSearchIfNeeded() async -> Bool {
        guard let saved = savedSearchesBySidebarID[selectedSidebarID] else {
            return selectedSidebarRow.isSmartList
        }

        await restoreSavedSearch(saved)
        return true
    }

    func restoreSavedSearch(_ saved: SavedSearchSnapshot) async {
        filterText = saved.query.query
        searchScope = saved.query.scope
        searchSort = saved.query.sort
        searchFilters = saved.query.filter
        await fileListModel.restoreSavedSearch(saved)
    }

    func loadSmartLists() async {
        do {
            let saved = try await savedSearchStore.listSavedSearches(repoPath: opening.config.repoPath)
            await MainActor.run {
                smartListLoadError = nil
                savedSearchesBySidebarID = Dictionary(
                    uniqueKeysWithValues: saved.map {
                        (RepositoryTreeNodeSnapshot.savedSearchSidebarID($0.id), $0)
                    }
                )
                rebuildSmartListSidebar()
            }
        } catch {
            let mapped = await mapSmartListError(error)
            await MainActor.run {
                smartListLoadError = mapped
            }
        }
    }

    func openSmartListManagement(
        _ mode: SmartListManagementMode,
        saved: SavedSearchSnapshot,
        draftFilters: SearchFilterStateSnapshot? = nil
    ) {
        smartListManagementRoute = SmartListManagementRoute(mode: mode, savedSearch: saved, draftFilters: draftFilters)
    }

    private func cancelSmartListManagement(_ route: SmartListManagementRoute) {
        if route.mode == .editQuery {
            fileListModel.cancelSmartListFilterDraft()
        }
        smartListManagementRoute = nil
    }

    private func deleteManagedSmartList(_ saved: SavedSearchSnapshot) {
        let sidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        savedSearchesBySidebarID.removeValue(forKey: sidebarID)
        repositoryTree = repositoryTree.removingSavedSearch(id: saved.id)
        if selectedSidebarID == sidebarID {
            selectedSidebarID = Self.defaultSelectedSidebarID(from: regularSidebarRows)
            clearSearch()
        }
        smartListManagementRoute = nil
    }

    private func beginSmartListFilterEditing(_ saved: SavedSearchSnapshot, filters: SearchFilterStateSnapshot) {
        fileListModel.beginSmartListFilterDraft(id: saved.id, name: saved.name, filters: filters)
        smartListManagementRoute = nil
        isSearchFiltersPresented = true
    }

    private func rebuildSmartListSidebar() {
        var tree = repositoryTree
        for row in smartListRows {
            if let id = row.savedSearchID {
                tree = tree.removingSavedSearch(id: id)
            }
        }
        for saved in sortedSavedSearches {
            tree = tree.insertingSavedSearch(saved)
        }
        repositoryTree = tree
    }

    private func mapSmartListError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func previewChangeCategory(fileID: Int64, targetCategory: String) {
        Task { await fileListModel.loadMoveToCategoryPreview(fileID: fileID, targetCategory: targetCategory) }
    }

    private func submitChangeCategory(fileID: Int64, targetCategory: String) {
        Task {
            let didMove = await fileListModel.submitMoveToCategory(fileID: fileID, targetCategory: targetCategory) { movedFile in
                refreshAfterCategoryMove(movedFile)
            }
            if didMove { refreshLatestUndoToast() }
        }
    }

    private func submitDelete(fileID: Int64, operation: MainFileDeleteOperation) {
        Task {
            let didDelete = await fileListModel.submitDelete(fileID: fileID, operation: operation)
            if didDelete { refreshLatestUndoToast() }
        }
    }

    private func applyICloudConflict(
        fileID: Int64,
        strategy: ICloudConflictResolutionStrategy,
        originalPath: String?,
        conflictedCopyPath: String?
    ) {
        Task {
            await fileListModel.applyICloudConflictResolution(
                fileID: fileID,
                strategy: strategy,
                originalPath: originalPath,
                conflictedCopyPath: conflictedCopyPath
            )
        }
    }
}

struct SearchEmptyRouteView: View {
    let request: SearchQueryRequestSnapshot
    var indexStatus: SearchIndexStatusSnapshot? = .ready
    let onClearSearch: () -> Void
    let onClearFilters: () -> Void
    let onRemoveFilter: (SearchFilterChipKind) -> Void
    let onSearchAllFileTypes: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Label("No files found", systemImage: "magnifyingglass")
                .font(.title3.weight(.semibold))
            Text(reasonText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            conditionSummary
            actionButtons
            if shouldShowFilterShortcuts {
                filterShortcutButtons
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S2-04-search-empty")
    }

    private var conditionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Query: \(querySummary)")
            Text("Filters: \(filterSummary)")
            Text(searchContextText(request))
            if indexStatus == .indexing {
                Text("Indexing...")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 360, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search conditions. Query \(querySummary). Filters \(filterSummary).")
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            if request.filters.isEmpty {
                Button("Clear search", action: onClearSearch)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Clear filters", action: onClearFilters)
                    .keyboardShortcut(.defaultAction)
                Button("Clear search", action: onClearSearch)
            }
        }
    }

    @ViewBuilder
    private var filterShortcutButtons: some View {
        VStack(alignment: .center, spacing: 8) {
            if request.filters.fileKind != nil {
                Button("Search all file types", action: onSearchAllFileTypes)
            }
            ForEach(SearchFilterChips.items(for: request.filters)) { chip in
                Button("Remove \(chip.label)") {
                    onRemoveFilter(chip.kind)
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .accessibilityElement(children: .contain)
    }

    private var reasonText: String {
        if indexStatus == .indexing {
            return "Search is still indexing. Results may appear in a moment."
        }
        if !request.query.isEmpty, request.filters.activeFilterCount > 0 {
            return "No files match this query and \(activeFilterText)."
        }
        if !request.query.isEmpty {
            return "No files match \"\(request.query)\"."
        }
        return "No files match \(activeFilterText)."
    }

    private var shouldShowFilterShortcuts: Bool { request.filters.activeFilterCount > 0 && indexStatus != .indexing }

    private var querySummary: String { request.query.isEmpty ? "None" : request.query }

    private var filterSummary: String {
        let chips = SearchFilterChips.items(for: request.filters).map(\.label)
        return chips.isEmpty ? "None" : chips.joined(separator: ", ")
    }

    private var activeFilterText: String {
        let count = request.filters.activeFilterCount
        return count == 1 ? "1 active filter" : "\(count) active filters"
    }
}

extension MainRepositoryContentView {
    func clearSearchQuery() {
        guard !effectiveSearchFilters.isEmpty else {
            clearSearch()
            return
        }
        filterText = ""
        selectedFileIDs = []
        fileListModel.enterSearch(context: .toolbar)
    }

    func clearSearchFiltersFromEmptyState() {
        SearchFilterStateRouting.assign(.empty, searchFilters: &searchFilters, fileListModel: fileListModel)
        selectedFileIDs = []
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearSearch()
        }
    }

    func removeSearchFilterFromEmptyState(_ kind: SearchFilterChipKind) {
        let updated = SearchFilterEditing.removing(kind, from: effectiveSearchFilters)
        SearchFilterStateRouting.assign(updated, searchFilters: &searchFilters, fileListModel: fileListModel)
    }

    func searchAllFileTypesFromEmptyState() { removeSearchFilterFromEmptyState(.fileKind) }

    func applyQuerySuggestion(_ query: String) {
        filterText = query
        selectedFileIDs = []
        fileListModel.enterSearch(context: .toolbar)
        isSearchFieldFocused = true
    }
}

struct SearchIndexingStatusRouteView: View {
    let request: SearchQueryRequestSnapshot
    let indexStatus: SearchIndexStatusSnapshot?
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        MainFileActionSheetContainer(title: "Search Index Status", pageID: "S2-01-indexing-status") {
            Label(statusText, systemImage: "exclamationmark.triangle")
                .font(.callout)
            metadataRow("Query", request.query)
            metadataRow("Scope", request.scope.displayName)
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Retry", action: onRetry)
            }
        }
        .accessibilityIdentifier("S2-01-indexing-status-search-route")
    }

    private var statusText: String {
        switch indexStatus {
        case .unavailable:
            "Search index unavailable"
        case .indexing:
            "Search index is updating"
        case .ready:
            "Search index ready"
        case nil:
            "Search index status unavailable"
        }
    }
}

private func searchContextText(_ request: SearchQueryRequestSnapshot) -> String {
    "Scope: \(request.scope.displayName) | Sort: \(request.sort.displayName)"
}
