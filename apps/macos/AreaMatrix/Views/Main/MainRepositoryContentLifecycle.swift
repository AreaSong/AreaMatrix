import SwiftUI

extension View {
    func mainRepositoryContentLifecycle(_ contentView: MainRepositoryContentView) -> some View {
        mainRepositoryContentLoadTasks(contentView)
            .mainRepositoryContentSearchTasks(contentView)
            .mainRepositoryContentDialogs(contentView)
            .mainRepositoryContentSheets(contentView)
            .mainRepositoryContentCommands(contentView)
    }

    func mainRepositoryContentLoadTasks(_ contentView: MainRepositoryContentView) -> some View {
        contentView.applyMainRepositoryContentLoadTasks(to: self)
    }

    func mainRepositoryContentSearchTasks(_ contentView: MainRepositoryContentView) -> some View {
        contentView.applyMainRepositoryContentSearchTasks(to: self)
    }

    func mainRepositoryContentDialogs(_ contentView: MainRepositoryContentView) -> some View {
        contentView.applyMainRepositoryContentDialogs(to: self)
    }

    func mainRepositoryContentSheets(_ contentView: MainRepositoryContentView) -> some View {
        contentView.applyMainRepositoryContentSheets(to: self)
    }

    func mainRepositoryContentCommands(_ contentView: MainRepositoryContentView) -> some View {
        contentView.applyMainRepositoryContentCommands(to: self)
    }
}

extension MainRepositoryContentView {
    func applyMainRepositoryContentLoadTasks(to content: some View) -> some View {
        content
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
                selectedFileIDs = focusedFileID.map { [$0] } ?? []
                await fileListModel.loadCurrentCategory(
                    selectedSidebarRow.categoryForFileList,
                    focusingOn: focusedFileID
                )
                if pendingMovedFileFocusID == focusedFileID { pendingMovedFileFocusID = nil }
            }
            .task(id: opening.config.repoPath) {
                guard state == .list else { return }
                await loadSmartLists()
            }
            .task(id: opening.config.repoPath) {
                guard state == .list else { return }
                await syncConflictEntryModel.loadIfNeeded()
            }
            .task(id: externalCreatedEvent?.id) {
                guard let externalCreatedEvent else { return }
                await fileListModel.syncExternalCreated(externalCreatedEvent)
                onExternalCreatedEventHandled(externalCreatedEvent)
            }
            .task(id: pendingTagSuggestionFocus?.id) {
                await applyPendingTagSuggestionFocus()
            }
            .onChange(of: selectedFileIDs) { previousIDs, ids in
                handleSelectedFileIDsChange(previousIDs: previousIDs, ids: ids)
            }
            .onChange(of: selectedImportProgressIDs) { _, ids in
                guard !ids.isEmpty else { return }
                selectedFileIDs = []
            }
    }

    func applyMainRepositoryContentSearchTasks(to content: some View) -> some View {
        content
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
                    filters: effectiveSearchFilters,
                    mode: searchMode
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
    }

    func applyMainRepositoryContentDialogs(to content: some View) -> some View {
        applyMainRepositorySemanticIndexDialogs(
            to: applyMainRepositorySummaryDialog(to: content)
        )
    }

    func applyMainRepositorySummaryDialog(to content: some View) -> some View {
        content
            .confirmationDialog(
                "Save AI summary changes?",
                isPresented: Binding(
                    get: { summarySelectionExitState.pendingRequest != nil },
                    set: { if !$0 { cancelPendingSummarySelectionExit() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel, action: cancelPendingSummarySelectionExit)
                Button("Discard changes", role: .destructive) {
                    summaryExitController.discardChanges()
                    finishPendingSummarySelectionExit()
                }
                Button("Save changes") {
                    Task { await saveAndFinishPendingSummarySelectionExit() }
                }
            } message: {
                Text("Save or discard the AI summary draft before switching files.")
            }
    }

    func applyMainRepositorySemanticIndexDialogs(to content: some View) -> some View {
        content
            .confirmationDialog(
                "Build semantic index?",
                isPresented: $isSemanticIndexConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Start index build") {
                    Task { await fileListModel.buildSemanticIndexForCurrentSearch() }
                }
                .disabled(!fileListModel.semanticPrivacyGateState.allowsIndexBuild)
                semanticIndexRecoveryActions
                Button("Back") {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(semanticIndexConfirmationMessage)
            }
            .confirmationDialog(
                "Cancel semantic index build?",
                isPresented: Binding(
                    get: {
                        if case .cancelConfirm = fileListModel.semanticIndexControlState { return true }
                        return false
                    },
                    set: { if !$0 { fileListModel.keepBuildingSemanticIndexForCurrentSearch() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Cancel index build", role: .destructive) {
                    Task { await fileListModel.cancelSemanticIndexBuildForCurrentSearch() }
                }
                Button("Keep building", role: .cancel) {
                    fileListModel.keepBuildingSemanticIndexForCurrentSearch()
                }
            } message: {
                Text(semanticIndexCancelConfirmationMessage)
            }
    }

    func applyMainRepositoryContentSheets(to content: some View) -> some View {
        content
            .sheet(item: actionDestinationBinding, content: actionRoutingSheet)
            .sheet(item: searchDestinationBinding, content: searchRoutingSheet)
            .sheet(item: $semanticPrivacyRuleRoute, content: semanticPrivacyRuleSheet)
            .sheet(item: $semanticCallLogRoute, content: semanticCallLogSheet)
            .sheet(item: $pendingBatchAddTagsRoute, content: batchAddTagsRoutingSheet)
            .sheet(item: $pendingBatchChangeCategoryRoute, content: batchChangeCategoryRoutingSheet)
            .sheet(item: $pendingBatchDeleteRoute, content: batchDeleteRoutingSheet)
            .sheet(item: $pendingBatchRenameRoute, content: batchRenameRoutingSheet)
            .sheet(item: $pendingUndoHistoryRequest, content: undoHistorySheet)
            .sheet(item: $smartListManagementRoute, content: smartListManagementSheet)
            .sheet(item: $pendingSyncConflictReviewRoute, content: syncConflictReviewSheet)
            .onChange(of: pendingImportConflictBatchRoute) { _, route in
                guard let route else { return }
                pendingImportConflictBatchRoute = nil
                onOpenImportConflictBatch(route)
            }
            .onChange(of: isSearchFiltersPresented) { _, presented in
                guard !presented else { return }
                reopenSmartListEditorFromDraftIfNeeded()
            }
    }

    func applyMainRepositoryContentCommands(to content: some View) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: AreaMatrixUndoHistoryCommandRelay.notification)) { _ in
                openUndoHistoryFromMenu()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: AreaMatrixCommandPaletteCommandRelay.notification
            )) { _ in
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

    private func applyPendingTagSuggestionFocus() async {
        guard state == .list, let focus = pendingTagSuggestionFocus else { return }
        selectedFileIDs = [focus.fileID]
        await fileListModel.selectFiles([focus.fileID])
        fileListModel.presentSelectedFileTagSuggestions(source: focus.source)
        onPendingTagSuggestionFocusConsumed(focus)
    }
}
