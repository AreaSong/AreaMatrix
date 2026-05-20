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
            onOpenChangeCategoryPermissionRecovery: {
                onOpenChangeCategoryPermissionRecovery()
            },
            onDelete: submitDelete,
            onApplyICloudConflict: applyICloudConflict,
            onCollectDiagnostics: {
                Task {
                    await fileListModel.collectCurrentListDiagnostics()
                }
            }
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
                onCancel: fileListModel.clearPendingSearchDestination,
                onSaved: { saved in
                    selectSavedSearch(saved)
                    fileListModel.clearPendingSearchDestination()
                },
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
                onClose: fileListModel.clearPendingSearchDestination
            )
        case .searchEmpty, .queryError:
            EmptyView()
        }
    }

    private func file(for fileID: Int64) -> FileEntrySnapshot? {
        fileListModel.files.first { $0.id == fileID } ??
            fileListModel.selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil }
    }

    private func submitRename(fileID: Int64, newName: String) {
        Task { await fileListModel.submitRename(fileID: fileID, newName: newName) }
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

    private func selectSavedSearch(_ saved: SavedSearchSnapshot) {
        filterText = saved.query.query
        searchScope = saved.query.scope
        searchSort = saved.query.sort
        searchFilters = saved.query.filter
        savedSearchesBySidebarID[RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)] = saved
        fileListModel.cancelSmartListFilterDraft()
        fileListModel.enterSearch(context: .smartList(id: saved.id, name: saved.name))
        repositoryTree = repositoryTree.insertingSavedSearch(saved)
        selectedSidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        selectedFileIDs = []
    }

    func restoreSelectedSavedSearchIfNeeded() async -> Bool {
        guard let saved = savedSearchesBySidebarID[selectedSidebarID] else {
            return selectedSidebarRow.isSmartList
        }

        filterText = saved.query.query
        searchScope = saved.query.scope
        searchSort = saved.query.sort
        searchFilters = saved.query.filter
        await fileListModel.restoreSavedSearch(saved)
        return true
    }

    private func previewChangeCategory(fileID: Int64, targetCategory: String) {
        Task { await fileListModel.loadMoveToCategoryPreview(fileID: fileID, targetCategory: targetCategory) }
    }

    private func submitChangeCategory(fileID: Int64, targetCategory: String) {
        Task {
            await fileListModel.submitMoveToCategory(fileID: fileID, targetCategory: targetCategory) { movedFile in
                refreshAfterCategoryMove(movedFile)
            }
        }
    }

    private func submitDelete(fileID: Int64, operation: MainFileDeleteOperation) {
        Task { await fileListModel.submitDelete(fileID: fileID, operation: operation) }
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
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Label("No results for \"\(request.query)\"", systemImage: "magnifyingglass")
                .font(.headline)
            Text("S2-04 search-empty")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(searchContextText(request))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Clear search", action: onClear)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("S2-04-search-empty")
    }
}

struct QueryErrorRouteView: View {
    let request: SearchQueryRequestSnapshot
    let diagnostic: SearchQueryDiagnosticSnapshot
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Label("Query error", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text("S2-05 query-error")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(diagnostic.message)
                .font(.callout)
                .multilineTextAlignment(.center)
            if let suggestion = diagnostic.suggestion, !suggestion.isEmpty {
                Text(suggestion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(searchContextText(request))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Clear search", action: onClear)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("S2-05-query-error")
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

struct SearchCommandPaletteRouteView: View {
    let query: String
    let onClose: () -> Void

    var body: some View {
        MainFileActionSheetContainer(title: "Command Palette", pageID: "S2-15") {
            TextField("Search commands", text: .constant(query))
                .textFieldStyle(.roundedBorder)
            Text("Search related commands")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .accessibilityIdentifier("S2-15-search-route")
    }
}

private func searchContextText(_ request: SearchQueryRequestSnapshot) -> String {
    "Scope: \(request.scope.displayName) | Sort: \(request.sort.displayName)"
}
