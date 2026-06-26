import Foundation
import SwiftUI

private enum MainSidebarTagFilterEntry {
    static let id = "tag-filters-sidebar-tags-filter"
    static let title = "Tags"
    static let accessibilityLabel = "Tags filter"
    static let accessibilityHint = "Open tag filters for the current search scope."
}

extension MainRepositoryContentView {
    var detailTagActions: MainRepositoryDetailPaneTagActions {
        MainRepositoryDetailPaneTagActions(
            aiSuggestionState: fileListModel.aiTagSuggestionState,
            aiBatchSuggestionState: fileListModel.aiTagBatchSuggestionState,
            onLoadTags: { Task { await fileListModel.loadSelectedFileTags() } },
            onRetryTags: { Task { await fileListModel.retrySelectedFileTags() } },
            onAddTag: { tag in Task { await fileListModel.addSelectedFileTag(tag) } },
            onRemoveTag: { tag in Task { await fileListModel.removeSelectedFileTag(tag) } },
            onLoadSuggestions: { Task { await fileListModel.loadSelectedFileTagSuggestions() } },
            onRetrySuggestions: { Task { await fileListModel.retrySelectedFileTagSuggestions() } },
            onToggleSuggestion: fileListModel.toggleSelectedFileTagSuggestion,
            onSelectAllSuggestions: fileListModel.selectAllSelectedFileTagSuggestions,
            onClearSuggestions: fileListModel.clearSelectedFileTagSuggestions,
            onStartEditingSuggestions: fileListModel.startEditingSelectedFileTagSuggestions,
            onCancelEditingSuggestions: fileListModel.cancelEditingSelectedFileTagSuggestions,
            onEditSuggestionDisplayName: fileListModel.updateSelectedFileTagSuggestionDisplayName,
            onEditSuggestionSlug: fileListModel.updateSelectedFileTagSuggestionSlug,
            onRegenerateSuggestionSlug: fileListModel.regenerateSelectedFileTagSuggestionSlug,
            onApplySuggestions: {
                applyTagSuggestionUndo { await fileListModel.applySelectedFileTagSuggestions() }
            },
            onApplyEditedSuggestions: {
                applyTagSuggestionUndo { await fileListModel.applyEditedSelectedFileTagSuggestions() }
            },
            onRetryFailedSuggestions: {
                applyTagSuggestionUndo { await fileListModel.retryFailedSelectedFileTagSuggestions() }
            },
            onLoadAISuggestions: { Task { await fileListModel.loadSelectedFileAITagSuggestions() } },
            onRetryAISuggestions: { Task { await fileListModel.retrySelectedFileAITagSuggestions() } },
            onToggleAISuggestion: fileListModel.toggleSelectedFileAITagSuggestion,
            onApplySingleAISuggestion: { suggestionID in
                applyTagSuggestionUndo { await fileListModel.applySelectedFileAITagSuggestion(suggestionID) }
            },
            onSelectHighConfidenceAISuggestions: fileListModel.selectHighConfidenceAITagSuggestions,
            onClearAISuggestions: fileListModel.clearSelectedFileAITagSuggestions,
            onStartEditingAISuggestions: fileListModel.startEditingSelectedFileAITagSuggestions,
            onCancelEditingAISuggestions: fileListModel.cancelEditingSelectedFileAITagSuggestions,
            onEditAISuggestionDisplayName: fileListModel.updateSelectedFileAITagSuggestionDisplayName,
            onEditAISuggestionSlug: fileListModel.updateSelectedFileAITagSuggestionSlug,
            onRegenerateAISuggestionSlug: fileListModel.regenerateSelectedFileAITagSuggestionSlug,
            onApplyAISuggestions: {
                applyTagSuggestionUndo { await fileListModel.applySelectedFileAITagSuggestions() }
            },
            onApplyEditedAISuggestions: {
                applyTagSuggestionUndo { await fileListModel.applyEditedSelectedFileAITagSuggestions() }
            },
            onRetryFailedAISuggestions: {
                applyTagSuggestionUndo { await fileListModel.retryFailedSelectedFileAITagSuggestions() }
            },
            aiBatchActions: fileListModel.aiTagBatchSuggestionActions,
            onOpenAISettings: onOpenAISettings,
            onSuggestionPresentationConsumed: fileListModel.consumeTagSuggestionPresentationRequest,
            onUndoTagChange: { Task { await fileListModel.undoLastDetailTagChange() } },
            onDismissTagUndoToast: fileListModel.dismissDetailTagUndoToast,
            onBatchTagUndoStateChange: updateBatchTagUndoState
        )
    }

    func applyTagSuggestionUndo(_ action: @escaping () async -> BatchTagUndoState?) {
        Task {
            if let state = await action() { updateBatchTagUndoState(state) }
        }
    }

    var regularSidebarRows: [RepositorySidebarRowSnapshot] {
        repositoryTree.sidebarRows.filter { !$0.isSmartList }
    }

    var smartListRows: [RepositorySidebarRowSnapshot] {
        repositoryTree.sidebarRows.filter(\.isSmartList)
    }

    var sortedSavedSearches: [SavedSearchSnapshot] {
        savedSearchesBySidebarID.values.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            if lhs.pinned { return lhs.updatedAt > rhs.updatedAt }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var sidebar: some View {
        List(selection: $selectedSidebarID) {
            ForEach(regularSidebarRows) { row in
                sidebarRow(row)
                    .tag(row.id)
            }
            sidebarTagsFilterRow
            if !smartListRows.isEmpty || smartListLoadError != nil {
                Section("Smart Lists") {
                    ForEach(smartListRows) { row in
                        sidebarRow(row)
                            .tag(row.id)
                            .contextMenu {
                                smartListContextMenu(for: row)
                            }
                    }
                    smartListErrorRow
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)
    }

    var sidebarTagsFilterRow: some View {
        Button(action: openSidebarTagFilter) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(Color.secondary)
                Text(MainSidebarTagFilterEntry.title)
                Spacer()
                Text(searchFilters.tags.isEmpty ? "" : "\(searchFilters.tags.count)")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(MainSidebarTagFilterEntry.id)
        .accessibilityLabel(MainSidebarTagFilterEntry.accessibilityLabel)
        .accessibilityHint(MainSidebarTagFilterEntry.accessibilityHint)
        .popover(isPresented: $isSidebarTagsFilterPresented) {
            SearchFiltersPopover(
                filters: searchFiltersBinding,
                facetsState: fileListModel.searchFacetsState,
                tagRegistryState: fileListModel.tagFilterRegistryState,
                tagRegistryAnchorFileID: tagRegistryAnchorFileID,
                canSaveAsSmartList: !fileListModel.isEditingSmartListFilterDraft && fileListModel.canSaveCurrentSearch,
                isEditingSmartListDraft: fileListModel.isEditingSmartListFilterDraft,
                saveDisabledReason: searchSaveDisabledReason,
                onReset: {
                    resetSearchFilters()
                },
                onRetry: {
                    Task { await fileListModel.retrySearchFacets() }
                },
                onLoadTagRegistry: { fileID in
                    Task { await fileListModel.loadTagFilterRegistry(activeFileID: fileID) }
                },
                onRetryTagRegistry: {
                    Task { await fileListModel.retryTagFilterRegistry() }
                },
                onSaveAsSmartList: {
                    isSidebarTagsFilterPresented = false
                    fileListModel.openSavedSearchSheet()
                }
            )
        }
    }

    func openSidebarTagFilter() {
        searchScope = selectedSidebarRow.categoryForFileList == nil ? .all : .current
        fileListModel.enterSearch(context: .sidebar(MainSidebarTagFilterEntry.id))
        isSidebarTagsFilterPresented = true
    }

    @MainActor
    func refreshAfterCategoryMove(_ movedFile: FileEntrySnapshot) {
        Task {
            await refreshTreeAndFocusMovedFile(movedFile)
        }
    }

    @MainActor
    func refreshAfterClassifierCorrection(_ correctedFile: FileEntrySnapshot) async {
        await fileListModel.retryCurrentCategory()
        selectedFileIDs = [correctedFile.id]
        await fileListModel.selectFiles([correctedFile.id])
        fileListModel.statusBanner = .correctedClassification(
            fileID: correctedFile.id,
            category: correctedFile.category,
            ruleConfirmationRequired: fileListModel.classifierCorrectionResult?.ruleConfirmationRequired ?? false
        )
    }

    @MainActor
    func refreshTreeAndFocusMovedFile(_ movedFile: FileEntrySnapshot) async {
        let refreshedTree = await refreshedTreeAfterCategoryMove()
        let plan = CategoryMoveRefreshPlan.make(
            movedFile: movedFile,
            currentSidebarID: selectedSidebarID,
            currentTree: repositoryTree,
            refreshedTree: refreshedTree
        )

        repositoryTree = plan.tree
        pendingMovedFileFocusID = movedFile.id
        selectedSidebarID = plan.selectedSidebarID
        selectedFileIDs = [movedFile.id]
        await fileListModel.loadCurrentCategory(plan.categoryForFileList, focusingOn: movedFile.id)
        selectedFileIDs = [movedFile.id]
        if refreshedTree == nil {
            fileListModel.statusBanner = .changedCategoryTreeRefreshFailed(
                fileID: movedFile.id,
                category: movedFile.category
            )
        } else if fileListModel.errorMapping == nil {
            fileListModel.statusBanner = .changedCategory(fileID: movedFile.id, category: movedFile.category)
        }
    }

    private func refreshedTreeAfterCategoryMove() async -> RepositoryTreeNodeSnapshot? {
        do {
            return try await treeLister.listTree(repoPath: opening.config.repoPath, locale: opening.config.locale)
        } catch {
            return nil
        }
    }

    private func sidebarRow(_ row: RepositorySidebarRowSnapshot) -> some View {
        HStack(spacing: 6) {
            Image(systemName: row.isSmartList ? "folder.badge.gearshape" : "folder")
                .foregroundStyle(row.isSmartList ? Color.accentColor : Color.secondary)
            Text(row.displayName)
                .padding(.leading, CGFloat(row.depth) * 14)
            Spacer()
            if row.isSmartList {
                smartListRowStatus(for: row)
            } else {
                Text("\(row.totalFileCount)")
                    .foregroundStyle(.secondary)
            }
        }
        .modifier(ImportDropTargetModifier(
            target: row.importDropTarget,
            dropPreviewModel: dropPreviewModel,
            onDropImport: { urls, target in
                onDropImport(urls, target.entryDestination)
            },
            isEnabled: !opening.isReadOnly
        ))
        .help(row.importDropTarget.sidebarHelp)
        .accessibilityLabel(sidebarAccessibilityLabel(row))
        .accessibilityHint(row.importDropTarget.sidebarHelp)
    }

    @ViewBuilder
    private var smartListErrorRow: some View {
        if let smartListLoadError {
            HStack(spacing: 8) {
                Label("Could not load Smart Lists", systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Retry") {
                    Task { await loadSmartLists() }
                }
            }
            .font(.callout)
            .foregroundStyle(.red)
            .accessibilityIdentifier("smart-list-management-smart-list-load-error")
            .accessibilityHint(smartListLoadError.suggestedAction)
        }
    }

    @ViewBuilder
    var smartListBannerEditButton: some View {
        if selectedSmartList != nil {
            Button("Edit", action: openSelectedSmartListEditor)
        }
    }

    @ViewBuilder
    private func smartListContextMenu(for row: RepositorySidebarRowSnapshot) -> some View {
        if let saved = savedSearchesBySidebarID[row.id] {
            Button("Open") {
                selectedSidebarID = row.id
            }
            Button("Rename...") {
                openSmartListManagement(.rename, saved: saved)
            }
            Button("Duplicate...") {
                openSmartListManagement(.duplicate, saved: saved)
            }
            Button("Edit query...") {
                openSmartListManagement(.editQuery, saved: saved)
            }
            Button("Delete...", role: .destructive) {
                openSmartListManagement(.delete, saved: saved)
            }
        }
    }

    private func sidebarAccessibilityLabel(_ row: RepositorySidebarRowSnapshot) -> String {
        guard row.isSmartList else { return "\(row.displayName) \(row.totalFileCount)" }
        return "Smart List \(row.displayName), \(smartListStatus(for: row).accessibilityValue)"
    }

    @ViewBuilder
    private func smartListRowStatus(for row: RepositorySidebarRowSnapshot) -> some View {
        let status = smartListStatus(for: row)
        HStack(spacing: 4) {
            if let warningMessage = status.warningMessage {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(warningMessage)
                    .accessibilityLabel("Warning: \(warningMessage)")
            }
            Text(status.badgeText)
                .font(.caption)
                .foregroundStyle(status.warningMessage == nil ? Color.secondary : Color.orange)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityValue)
        .help(status.warningMessage ?? status.badgeAccessibilityText)
    }

    private func smartListStatus(for row: RepositorySidebarRowSnapshot) -> SmartListSidebarRowStatus {
        let savedSearch = savedSearchesBySidebarID[row.id]
        return SmartListSidebarRowStatus.make(
            savedSearch: savedSearch,
            isCurrent: selectedSidebarID == row.id,
            searchState: fileListModel.searchState
        )
    }
}

struct CategoryMoveRefreshPlan: Equatable {
    var tree: RepositoryTreeNodeSnapshot
    var selectedSidebarID: String
    var focusedFileID: Int64
    var categoryForFileList: String?

    static func make(
        movedFile: FileEntrySnapshot,
        currentSidebarID: String,
        currentTree: RepositoryTreeNodeSnapshot,
        refreshedTree: RepositoryTreeNodeSnapshot?
    ) -> CategoryMoveRefreshPlan {
        let tree = refreshedTree ?? currentTree
        let fallbackSidebarID = sidebarID(forMovedFile: movedFile, in: currentTree) ?? currentSidebarID
        let selectedSidebarID = sidebarID(forMovedFile: movedFile, in: tree) ?? fallbackSidebarID
        let selectedRow = tree.sidebarRow(id: selectedSidebarID) ??
            tree.sidebarRows.first ??
            RepositorySidebarRowSnapshot(node: tree, depth: 0)
        return CategoryMoveRefreshPlan(
            tree: tree,
            selectedSidebarID: selectedSidebarID,
            focusedFileID: movedFile.id,
            categoryForFileList: selectedRow.categoryForFileList
        )
    }

    private static func sidebarID(forMovedFile file: FileEntrySnapshot,
                                  in tree: RepositoryTreeNodeSnapshot) -> String? {
        tree.sidebarRows.first { row in
            row.categoryForFileList == file.category && row.contains(file)
        }?.id ?? tree.sidebarRows.first { row in
            row.categoryForFileList == file.category && row.pathFilterPrefix == nil
        }?.id
    }
}
