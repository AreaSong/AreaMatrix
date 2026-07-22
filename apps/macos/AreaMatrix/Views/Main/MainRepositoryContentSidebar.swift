import SwiftUI

private enum MainSidebarTagFilterEntry {
    static let id = "tag-filters-sidebar-tags-filter"
    static var title: String {
        L10n.string("Tags")
    }

    static var accessibilityLabel: String {
        L10n.string("Tags filter")
    }

    static var accessibilityHint: String {
        L10n.string("Open tag filters for the current search scope.")
    }
}

extension MainRepositoryContentView {
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
        .popover(isPresented: $searchRoutingState.isSidebarTagsFilterPresented) {
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
                    searchRoutingState.isSidebarTagsFilterPresented = false
                    fileListModel.openSavedSearchSheet()
                }
            )
        }
    }

    func openSidebarTagFilter() {
        searchScope = selectedSidebarRow.categoryForFileList == nil ? .all : .current
        fileListModel.enterSearch(context: .sidebar(MainSidebarTagFilterEntry.id))
        searchRoutingState.isSidebarTagsFilterPresented = true
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
        return L10n.format(
            "Smart List %@, %@",
            row.displayName,
            smartListStatus(for: row).accessibilityValue
        )
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
