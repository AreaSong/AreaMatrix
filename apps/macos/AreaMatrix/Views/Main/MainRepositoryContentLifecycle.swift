import SwiftUI

extension View {
    func mainRepositoryContentLifecycle(_ contentView: MainRepositoryContentView) -> some View {
        mainRepositoryContentLoadTasks(contentView)
            .mainRepositoryContentImportProgressSelection(contentView)
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

    func mainRepositoryContentImportProgressSelection(_ contentView: MainRepositoryContentView) -> some View {
        contentView.applyMainRepositoryImportProgressSelectionRelay(to: self)
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
            .task(id: localizer.resourceLocaleIdentifier) {
                await refreshTreeForInterfaceLocaleChange(
                    localizer.resourceLocaleIdentifier
                )
            }
            .task(id: externalSyncQueueRevision) {
                fileListModel.scheduleExternalSyncDrain(
                    windows: externalSyncWindows,
                    onWindowCompleted: onExternalSyncWindowCompleted
                )
            }
            .task(id: fileListModel.pendingExternalSelectionUpdate?.id) {
                await applyPendingExternalSelectionUpdate()
            }
            .task(id: pendingTagSuggestionFocus?.id) {
                await applyPendingTagSuggestionFocus()
            }
            .onChange(of: selectedFileIDs) { previousIDs, ids in
                handleSelectedFileIDsChange(previousIDs: previousIDs, ids: ids)
            }
    }

    private func refreshTreeForInterfaceLocaleChange(_ localeIdentifier: String) async {
        defer { observedInterfaceLocaleIdentifier = localeIdentifier }
        guard let previousLocale = observedInterfaceLocaleIdentifier,
              previousLocale != localeIdentifier,
              RepositoryContentLanguage(snapshotValue: opening.config.locale) == .followInterface
        else { return }

        do {
            let refreshedTree = try await treeLister.listTree(
                repoPath: opening.config.repoPath,
                locale: opening.config.locale
            )
            guard !Task.isCancelled,
                  localizer.resourceLocaleIdentifier == localeIdentifier
            else { return }
            let plan = InterfaceLocaleTreeRefreshPlan.make(
                refreshedTree: refreshedTree,
                savedSearches: Array(savedSearchesBySidebarID.values),
                selectedSidebarID: selectedSidebarID
            )
            repositoryTree = plan.tree
            selectedSidebarID = plan.selectedSidebarID
        } catch {
            // Presentation refresh is best-effort; keep the stable current tree and all user state.
        }
    }

    private var externalSyncQueueRevision: String {
        "\(externalSyncWindows.first?.id ?? "empty"):\(fileListModel.externalSyncAttemptRevision)"
    }

    private func applyPendingExternalSelectionUpdate() async {
        guard let update = fileListModel.pendingExternalSelectionUpdate else { return }
        switch update {
        case let .moved(file):
            await refreshTreeAndFocusMovedFile(file)
        case .cleared:
            selectedFileIDs = []
        }
        fileListModel.consumeExternalSelectionUpdate(update)
    }

    func applyMainRepositoryContentDialogs(to content: some View) -> some View {
        applyMainRepositorySemanticIndexDialogs(
            to: applyMainRepositoryDiagnosticsDialog(
                to: applyMainRepositorySummaryDialog(to: content)
            )
        )
    }

    func applyMainRepositoryDiagnosticsDialog(to content: some View) -> some View {
        content.confirmationDialog(
            "Collect repository diagnostics?",
            isPresented: Binding(
                get: { fileListModel.diagnosticsState == .confirmingPrivacy },
                set: { if !$0 { fileListModel.cancelCurrentListDiagnostics() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel, action: fileListModel.cancelCurrentListDiagnostics)
            Button("Collect diagnostics") {
                Task { await fileListModel.collectCurrentListDiagnostics() }
            }
        } message: {
            Text(L10n.string("diagnostics.repositoryPrivacyDetail"))
        }
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

    func applyMainRepositoryContentSheets(to content: some View) -> some View {
        let primaryActionHost = applyMainRepositoryPrimaryFileActionSheet(to: content)
        let searchHost = applyMainRepositorySearchSheets(to: primaryActionHost)
        let batchActionHost = applyMainRepositoryBatchFileActionSheets(to: searchHost)
        let smartListHost = applyMainRepositorySmartListSheet(to: batchActionHost)
        let syncConflictHost = applyMainRepositorySyncConflictSheet(to: smartListHost)
        let importRelay = applyMainRepositoryImportConflictBatchRelay(to: syncConflictHost)
        return applyMainRepositorySearchFilterDismissRelay(to: importRelay)
    }

    func applyMainRepositoryContentCommands(to content: some View) -> some View {
        let undoMenuHost = applyMainRepositoryUndoHistoryMenuCommandRelay(to: content)
        let commandPaletteMenuHost = applyMainRepositoryCommandPaletteMenuCommandRelay(to: undoMenuHost)
        return applyMainRepositoryUndoRedoKeyCommands(to: commandPaletteMenuHost)
    }

    private func applyPendingTagSuggestionFocus() async {
        guard state == .list, let focus = pendingTagSuggestionFocus else { return }
        selectedFileIDs = [focus.fileID]
        await fileListModel.selectFiles([focus.fileID])
        fileListModel.presentSelectedFileTagSuggestions(source: focus.source)
        onPendingTagSuggestionFocusConsumed(focus)
    }
}

struct InterfaceLocaleTreeRefreshPlan: Equatable {
    var tree: RepositoryTreeNodeSnapshot
    var selectedSidebarID: String

    static func make(
        refreshedTree: RepositoryTreeNodeSnapshot,
        savedSearches: [SavedSearchSnapshot],
        selectedSidebarID: String
    ) -> InterfaceLocaleTreeRefreshPlan {
        let tree = savedSearches.reduce(refreshedTree) { tree, savedSearch in
            tree.insertingSavedSearch(savedSearch)
        }
        let retainedSelection = tree.sidebarRow(id: selectedSidebarID)?.id
            ?? MainRepositoryContentView.defaultSelectedSidebarID(from: tree.sidebarRows)
        return InterfaceLocaleTreeRefreshPlan(tree: tree, selectedSidebarID: retainedSelection)
    }
}
