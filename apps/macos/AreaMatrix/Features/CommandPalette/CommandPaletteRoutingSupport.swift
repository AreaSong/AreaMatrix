import SwiftUI

extension MainRepositoryContentView {
    func commandPaletteRouteView() -> some View {
        SearchCommandPaletteRouteView(
            query: $commandPaletteModel.query,
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
            commandPaletteModel.state = .loaded(.noRepositoryCommands())
            return
        }
        Task { await loadCommandPaletteIndexFromCurrentState() }
    }

    func loadCommandPaletteIndexFromCurrentState() async {
        await commandPaletteModel.load(
            query: commandPaletteModel.query,
            selectedFileIDs: selectionModel.fileIDs,
            currentPath: selectedSidebarRow.pathFilterPrefix
        )
    }

    func openCommandPalette() {
        commandPaletteModel.focusRoutingState.prepareForPresentation(
            searchFieldWasFocused: isSearchFieldFocused
        )
        isSearchFieldFocused = false
        commandPaletteModel.query = ""
        if state == .list {
            searchModel.openCommandPaletteForSearch()
        } else {
            searchModel.pendingSearchDestination = .commandPalette
            commandPaletteModel.state = .loaded(.noRepositoryCommands())
        }
    }

    func toggleCommandPalette() {
        if searchModel.pendingSearchDestination == .commandPalette {
            closeCommandPalette()
            return
        }
        openCommandPalette()
    }

    func closeCommandPalette() {
        commandPaletteModel.query = ""
        commandPaletteModel.clear()
        searchModel.clearPendingSearchDestination()
        isSearchFieldFocused = commandPaletteModel.focusRoutingState.consumeSearchFieldFocusRestoration()
    }

    // swiftlint:disable:next cyclomatic_complexity
    func executeCommandPaletteTarget(_ target: CommandTargetSnapshot) {
        guard target.isExecutable else { return }
        switch target.executionRoute {
        case .importFiles:
            openImportFromCommandPalette()
        case .settings:
            openSettingsFromCommandPalette()
        case .beginSearch:
            beginSearchFromCommandPalette()
        case .batchAddTags:
            openBatchAddTagsFromCommandPalette()
        case .batchChangeCategory:
            openBatchChangeCategoryFromCommandPalette()
        case .batchDelete:
            openBatchDeleteFromCommandPalette()
        case .batchRename:
            openBatchRenameFromCommandPalette()
        case let .runSmartList(savedSearchID):
            executeCommandPaletteSmartList(savedSearchID: savedSearchID)
        case let .focusFile(fileID):
            focusFileFromCommandPalette(fileID)
        case .openRepository:
            openRepositoryFromCommandPalette()
        case .help:
            openHelpFromCommandPalette()
        case .classifierRuleEditor:
            openClassifierRuleEditorFromCommandPalette()
        case let .linkedPage(route):
            if routeLinkedCommandPaletteTarget(route) { closeCommandPalette() }
        case .unsupported:
            return
        }
    }

    var visibleCommandPaletteState: CommandPaletteLoadState {
        if state == .empty, commandPaletteModel.state.snapshot == nil {
            return .loaded(.noRepositoryCommands())
        }
        return commandPaletteModel.state
    }

    func routeLinkedCommandPaletteTarget(_ route: CommandPaletteLinkedPageRoute) -> Bool {
        switch route {
        case .redo:
            Task { await executeLatestRedoAction(entryPoint: .commandPalette) }
            return false
        case .importConflictBatch:
            guard let route = activeImportConflictBatchRoute(source: route) else {
                commandPaletteModel.state = .failed(
                    commandPaletteContext(),
                    commandPaletteModel.state.snapshot ?? .commandRegistryRecovery(
                        query: commandPaletteModel.query
                    ),
                    route.blockedMapping
                )
                return false
            }
            commandPaletteModel.importConflictBatchRelayState.enqueue(route)
            return true
        case .classifierImpactPreview:
            commandPaletteModel.state = .failed(
                commandPaletteContext(),
                commandPaletteModel.state.snapshot ?? .commandRegistryRecovery(
                    query: commandPaletteModel.query
                ),
                route.blockedMapping
            )
            return false
        case .tagSuggestions:
            return routeSelectedFileTagSuggestions(source: route)
        }
    }

    func commandPaletteContext() -> CommandIndexRequestSnapshot {
        CommandIndexRequestSnapshot.commandPalette(
            query: commandPaletteModel.query,
            selectedFileIDs: selectionModel.fileIDs,
            currentPath: selectedSidebarRow.pathFilterPrefix
        )
    }

    private func routeSelectedFileTagSuggestions(source: CommandPaletteLinkedPageRoute) -> Bool {
        guard let fileID = selectionModel.fileIDs.first, selectionModel.fileIDs.count == 1 else {
            commandPaletteModel.state = .failed(
                commandPaletteContext(),
                commandPaletteModel.state.snapshot ?? .commandRegistryRecovery(
                    query: commandPaletteModel.query
                ),
                source.blockedMapping
            )
            return false
        }
        selectionModel.fileIDs = [fileID]
        Task {
            await fileListModel.selectFiles([fileID])
            detailTagModel.presentSelectedFileTagSuggestions(source: .commandPalette)
        }
        return true
    }

    private func activeImportConflictBatchRoute(
        source: CommandPaletteLinkedPageRoute
    ) -> ImportConflictBatchRoute? {
        ImportConflictBatchRoute(
            metadata: importProgressPresentation.items.compactMap(\.importConflictBatch),
            source: source
        )
    }

    private func openCommandPaletteSmartList(_ saved: SavedSearchSnapshot) {
        closeCommandPalette()
        selectedSidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        selectionModel.fileIDs = []
        Task { await restoreSavedSearch(saved) }
    }

    private func executeCommandPaletteSmartList(savedSearchID: Int64) {
        guard let saved = CommandPaletteSmartListRouting.savedSearch(
            savedSearchID: savedSearchID,
            in: sortedSavedSearches
        ) else { return }
        openCommandPaletteSmartList(saved)
    }
}

struct CommandPaletteFocusRoutingState: Equatable {
    private(set) var shouldRestoreSearchFieldFocus = false

    mutating func prepareForPresentation(searchFieldWasFocused: Bool) {
        shouldRestoreSearchFieldFocus = searchFieldWasFocused
    }

    mutating func consumeSearchFieldFocusRestoration() -> Bool {
        defer { shouldRestoreSearchFieldFocus = false }
        return shouldRestoreSearchFieldFocus
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
