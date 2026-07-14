import SwiftUI

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
        commandPaletteFocusRoutingState.prepareForPresentation(
            searchFieldWasFocused: isSearchFieldFocused
        )
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
        isSearchFieldFocused = commandPaletteFocusRoutingState.consumeSearchFieldFocusRestoration()
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
        if state == .empty, fileListModel.commandPaletteState.snapshot == nil {
            return .loaded(.noRepositoryCommands())
        }
        return fileListModel.commandPaletteState
    }

    func routeLinkedCommandPaletteTarget(_ route: CommandPaletteLinkedPageRoute) -> Bool {
        switch route {
        case .redo:
            Task { await executeLatestRedoAction(entryPoint: .commandPalette) }
            return false
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
            importConflictBatchRelayState.enqueue(route)
            return true
        case .classifierImpactPreview:
            fileListModel.commandPaletteState = .failed(
                commandPaletteContext(),
                fileListModel.commandPaletteState.snapshot ?? .commandRegistryRecovery(
                    query: fileListModel.commandPaletteQuery
                ),
                route.blockedMapping
            )
            return false
        case .tagSuggestions:
            return routeSelectedFileTagSuggestions(source: route)
        }
    }

    func commandPaletteContext() -> CommandIndexContext {
        CommandIndexContext.commandPalette(
            query: fileListModel.commandPaletteQuery,
            selectedFileIDs: selectedFileIDs,
            currentPath: selectedSidebarRow.pathFilterPrefix
        )
    }

    private func routeSelectedFileTagSuggestions(source: CommandPaletteLinkedPageRoute) -> Bool {
        guard let fileID = selectedFileIDs.first, selectedFileIDs.count == 1 else {
            fileListModel.commandPaletteState = .failed(
                commandPaletteContext(),
                fileListModel.commandPaletteState.snapshot ?? .commandRegistryRecovery(
                    query: fileListModel.commandPaletteQuery
                ),
                source.blockedMapping
            )
            return false
        }
        selectedFileIDs = [fileID]
        Task {
            await fileListModel.selectFiles([fileID])
            fileListModel.presentSelectedFileTagSuggestions(source: .commandPalette)
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
